#include "sqlite3.h"
#include <moonbit.h>
#include <string.h>
#include <stdlib.h>

/* ---- UTF-8 -> UTF-16 conversion for Japanese text ---- */

static moonbit_string_t utf8_to_moonbit_string(const char *ptr) {
    if (ptr == NULL) {
        return moonbit_make_string(0, 0);
    }

    /* First pass: count UTF-16 code units */
    int32_t u16_len = 0;
    const uint8_t *s = (const uint8_t *)ptr;
    while (*s) {
        uint32_t cp;
        if (*s < 0x80) {
            cp = *s++;
        } else if ((*s & 0xE0) == 0xC0) {
            cp = (*s++ & 0x1F) << 6;
            if ((*s & 0xC0) == 0x80) cp |= (*s++ & 0x3F);
        } else if ((*s & 0xF0) == 0xE0) {
            cp = (*s++ & 0x0F) << 12;
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F) << 6; }
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F); }
        } else if ((*s & 0xF8) == 0xF0) {
            cp = (*s++ & 0x07) << 18;
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F) << 12; }
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F) << 6; }
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F); }
        } else {
            s++;
            cp = 0xFFFD;
        }
        u16_len += (cp >= 0x10000) ? 2 : 1;
    }

    moonbit_string_t ms = moonbit_make_string_raw(u16_len);

    /* Second pass: encode UTF-16 */
    s = (const uint8_t *)ptr;
    int32_t idx = 0;
    while (*s) {
        uint32_t cp;
        if (*s < 0x80) {
            cp = *s++;
        } else if ((*s & 0xE0) == 0xC0) {
            cp = (*s++ & 0x1F) << 6;
            if ((*s & 0xC0) == 0x80) cp |= (*s++ & 0x3F);
        } else if ((*s & 0xF0) == 0xE0) {
            cp = (*s++ & 0x0F) << 12;
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F) << 6; }
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F); }
        } else if ((*s & 0xF8) == 0xF0) {
            cp = (*s++ & 0x07) << 18;
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F) << 12; }
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F) << 6; }
            if ((*s & 0xC0) == 0x80) { cp |= (*s++ & 0x3F); }
        } else {
            s++;
            cp = 0xFFFD;
        }

        if (cp >= 0x10000) {
            cp -= 0x10000;
            ms[idx++] = (uint16_t)(0xD800 + (cp >> 10));
            ms[idx++] = (uint16_t)(0xDC00 + (cp & 0x3FF));
        } else {
            ms[idx++] = (uint16_t)cp;
        }
    }
    return ms;
}

/* ---- SQLite result set ---- */

typedef struct {
    int32_t row_count;
    int32_t col_count;
    char **cells;  /* row_count * col_count owned strings */
} PkdxResultSet;

/* ---- DB open/close ---- */

typedef struct {
    sqlite3 *db;
} PkdxDb;

static void pkdx_db_destructor(void *self) {
    PkdxDb *wrapper = (PkdxDb *)self;
    if (wrapper->db) {
        sqlite3_close(wrapper->db);
        wrapper->db = NULL;
    }
}

/* Placeholder values for FixedArray initialization */
MOONBIT_FFI_EXPORT
PkdxDb *pkdx_null_db(void) {
    PkdxDb *wrapper = moonbit_make_external_object(
        &pkdx_db_destructor, sizeof(PkdxDb));
    wrapper->db = NULL;
    return wrapper;
}

MOONBIT_FFI_EXPORT
int32_t pkdx_db_open(const uint8_t *path, PkdxDb **out) {
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2((const char *)path, &db,
                             SQLITE_OPEN_READONLY, NULL);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return rc;
    }
    PkdxDb *wrapper = moonbit_make_external_object(
        &pkdx_db_destructor, sizeof(PkdxDb));
    wrapper->db = db;
    out[0] = wrapper;
    return 0;
}

MOONBIT_FFI_EXPORT
void pkdx_db_close(PkdxDb *wrapper) {
    if (wrapper && wrapper->db) {
        sqlite3_close(wrapper->db);
        wrapper->db = NULL;
    }
}

MOONBIT_FFI_EXPORT
PkdxResultSet *pkdx_null_rs(void) {
    PkdxResultSet *rs = (PkdxResultSet *)libc_malloc(sizeof(PkdxResultSet));
    rs->row_count = 0;
    rs->col_count = 0;
    rs->cells = NULL;
    return rs;
}

/* ---- High-level query execution ---- */

MOONBIT_FFI_EXPORT
int32_t pkdx_exec_query(
    PkdxDb *db_wrapper,
    const uint8_t *sql,
    int32_t bind_count,
    const uint8_t **bind_values,
    PkdxResultSet **out
) {
    if (!db_wrapper || !db_wrapper->db) return -1;

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db_wrapper->db, (const char *)sql, -1,
                                &stmt, NULL);
    if (rc != SQLITE_OK || !stmt) return rc ? rc : -1;

    for (int32_t i = 0; i < bind_count; i++) {
        sqlite3_bind_text(stmt, i + 1, (const char *)bind_values[i],
                         -1, SQLITE_TRANSIENT);
    }

    int32_t col_count = sqlite3_column_count(stmt);

    /* Collect rows into a dynamic array */
    int32_t capacity = 64;
    int32_t row_count = 0;
    char **cells = (char **)libc_malloc(sizeof(char *) * capacity * col_count);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (row_count >= capacity) {
            capacity *= 2;
            cells = (char **)realloc(cells, sizeof(char *) * capacity * col_count);
        }
        for (int32_t c = 0; c < col_count; c++) {
            const char *text = (const char *)sqlite3_column_text(stmt, c);
            if (text) {
                size_t len = strlen(text);
                char *copy = (char *)libc_malloc(len + 1);
                memcpy(copy, text, len + 1);
                cells[row_count * col_count + c] = copy;
            } else {
                cells[row_count * col_count + c] = NULL;
            }
        }
        row_count++;
    }

    sqlite3_finalize(stmt);

    PkdxResultSet *rs = (PkdxResultSet *)libc_malloc(sizeof(PkdxResultSet));
    rs->row_count = row_count;
    rs->col_count = col_count;
    rs->cells = cells;
    out[0] = rs;
    return 0;
}

MOONBIT_FFI_EXPORT
int32_t pkdx_result_row_count(PkdxResultSet *rs) {
    return rs ? rs->row_count : 0;
}

MOONBIT_FFI_EXPORT
int32_t pkdx_result_col_count(PkdxResultSet *rs) {
    return rs ? rs->col_count : 0;
}

MOONBIT_FFI_EXPORT
moonbit_string_t pkdx_result_get(PkdxResultSet *rs, int32_t row, int32_t col) {
    if (!rs || row < 0 || row >= rs->row_count ||
        col < 0 || col >= rs->col_count) {
        return moonbit_make_string(0, 0);
    }
    char *cell = rs->cells[row * rs->col_count + col];
    return utf8_to_moonbit_string(cell);
}

MOONBIT_FFI_EXPORT
void pkdx_result_free(PkdxResultSet *rs) {
    if (!rs) return;
    int32_t total = rs->row_count * rs->col_count;
    for (int32_t i = 0; i < total; i++) {
        if (rs->cells[i]) libc_free(rs->cells[i]);
    }
    libc_free(rs->cells);
    libc_free(rs);
}

/* ---- Schema check ---- */

MOONBIT_FFI_EXPORT
int32_t pkdx_table_exists(PkdxDb *db_wrapper, const uint8_t *table_name) {
    if (!db_wrapper || !db_wrapper->db) return 0;

    const char *sql =
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db_wrapper->db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK || !stmt) return 0;

    sqlite3_bind_text(stmt, 1, (const char *)table_name, -1, SQLITE_TRANSIENT);

    int32_t exists = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        exists = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    return exists;
}

/* ---- MoonBit String (UTF-16) -> null-terminated UTF-8 Bytes ---- */

MOONBIT_FFI_EXPORT
moonbit_bytes_t pkdx_string_to_utf8(moonbit_string_t str, int32_t str_len) {
    /* First pass: calculate UTF-8 byte length */
    int32_t byte_len = 0;
    for (int32_t i = 0; i < str_len; i++) {
        uint32_t cp = str[i];
        /* Handle surrogate pairs */
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < str_len) {
            uint16_t lo = str[i + 1];
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                i++;
            }
        }
        if (cp < 0x80) byte_len += 1;
        else if (cp < 0x800) byte_len += 2;
        else if (cp < 0x10000) byte_len += 3;
        else byte_len += 4;
    }

    /* Allocate MoonBit Bytes with null terminator */
    moonbit_bytes_t out = moonbit_make_bytes(byte_len + 1, 0);

    /* Second pass: encode UTF-8 */
    int32_t pos = 0;
    for (int32_t i = 0; i < str_len; i++) {
        uint32_t cp = str[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < str_len) {
            uint16_t lo = str[i + 1];
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                i++;
            }
        }
        if (cp < 0x80) {
            out[pos++] = (uint8_t)cp;
        } else if (cp < 0x800) {
            out[pos++] = (uint8_t)(0xC0 | (cp >> 6));
            out[pos++] = (uint8_t)(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            out[pos++] = (uint8_t)(0xE0 | (cp >> 12));
            out[pos++] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));
            out[pos++] = (uint8_t)(0x80 | (cp & 0x3F));
        } else {
            out[pos++] = (uint8_t)(0xF0 | (cp >> 18));
            out[pos++] = (uint8_t)(0x80 | ((cp >> 12) & 0x3F));
            out[pos++] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));
            out[pos++] = (uint8_t)(0x80 | (cp & 0x3F));
        }
    }
    out[pos] = 0;
    return out;
}
