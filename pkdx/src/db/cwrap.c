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

/* Open the database in read-write mode for migrations. Unlike pkdx_db_open,
   this does not pass SQLITE_OPEN_CREATE: the DB file must already exist
   (pokedex submodule's import_db.rb is responsible for generating it). */
MOONBIT_FFI_EXPORT
int32_t pkdx_db_open_rw(const uint8_t *path, PkdxDb **out) {
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2((const char *)path, &db,
                             SQLITE_OPEN_READWRITE, NULL);
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

/* Execute a SQL statement (or statement list) that returns no rows.
   Accepts semicolon-separated DDL/DML via sqlite3_exec. Used for
   CREATE TABLE, ALTER TABLE, BEGIN/COMMIT, etc. */
MOONBIT_FFI_EXPORT
int32_t pkdx_exec_sql(PkdxDb *db_wrapper, const uint8_t *sql) {
    if (!db_wrapper || !db_wrapper->db) return -1;
    return sqlite3_exec(db_wrapper->db, (const char *)sql, NULL, NULL, NULL);
}

/* Number of rows modified by the most recent INSERT/UPDATE/DELETE on the
   connection. Used by 002 to branch UPDATE vs INSERT on pokedex rows. */
MOONBIT_FFI_EXPORT
int32_t pkdx_db_changes(PkdxDb *db_wrapper) {
    if (!db_wrapper || !db_wrapper->db) return 0;
    return sqlite3_changes(db_wrapper->db);
}

/* PkdxResultSet を MoonBit の external_object として確保することで、
   MoonBit 側の incref/decref がダミーながら整合する。
   destructor はセル本体（libc_malloc 済み）を解放する。
   この対応をしないと、MoonBit が `void* rs` を refcounted オブジェクトと
   見なして関数末尾で moonbit_decref(rs) を挿入し、`(rs - 8)` に rc-1 を
   書き込むことで隣接する String バッファ先頭バイトを破壊する。 */
static void pkdx_rs_destructor(void *self) {
    PkdxResultSet *rs = (PkdxResultSet *)self;
    if (!rs->cells) return;
    int32_t total = rs->row_count * rs->col_count;
    for (int32_t i = 0; i < total; i++) {
        if (rs->cells[i]) libc_free(rs->cells[i]);
    }
    libc_free(rs->cells);
    rs->cells = NULL;
}

MOONBIT_FFI_EXPORT
PkdxResultSet *pkdx_null_rs(void) {
    PkdxResultSet *rs = (PkdxResultSet *)moonbit_make_external_object(
        &pkdx_rs_destructor, sizeof(PkdxResultSet));
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

    int step_rc;
    while ((step_rc = sqlite3_step(stmt)) == SQLITE_ROW) {
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

    /* Only SQLITE_DONE signals clean completion. Anything else (including
       SQLITE_CONSTRAINT / SQLITE_BUSY for non-SELECT statements whose loop
       body never ran) must propagate so the caller can abort the
       transaction instead of committing a partially-applied migration. */
    if (step_rc != SQLITE_DONE) {
        sqlite3_finalize(stmt);
        int32_t total = row_count * col_count;
        for (int32_t i = 0; i < total; i++) {
            if (cells[i]) libc_free(cells[i]);
        }
        libc_free(cells);
        return step_rc;
    }

    sqlite3_finalize(stmt);

    /* moonbit_make_external_object でラップ。
       null 用にすでに `out[0]` に渡された rs があるはずだが、それは
       捨てて新規に作る（destructor が cells=NULL を見て何もしない）。 */
    PkdxResultSet *rs = (PkdxResultSet *)moonbit_make_external_object(
        &pkdx_rs_destructor, sizeof(PkdxResultSet));
    rs->row_count = row_count;
    rs->col_count = col_count;
    rs->cells = cells;
    out[0] = rs;
    return 0;
}

/* Bind with per-parameter type tags. Needed for migration SQL that must
   distinguish NULL from empty string (e.g. COALESCE patterns in 001/002).
   tags[i]: 0 = NULL, 1 = TEXT (values[i] is null-terminated utf-8),
            2 = INTEGER (values[i] is ASCII decimal). */
MOONBIT_FFI_EXPORT
int32_t pkdx_exec_query_typed(
    PkdxDb *db_wrapper,
    const uint8_t *sql,
    int32_t bind_count,
    const int32_t *tags,
    const uint8_t **bind_values,
    PkdxResultSet **out
) {
    if (!db_wrapper || !db_wrapper->db) return -1;

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db_wrapper->db, (const char *)sql, -1,
                                &stmt, NULL);
    if (rc != SQLITE_OK || !stmt) return rc ? rc : -1;

    for (int32_t i = 0; i < bind_count; i++) {
        int32_t tag = tags[i];
        if (tag == 0) {
            sqlite3_bind_null(stmt, i + 1);
        } else if (tag == 2) {
            long long v = strtoll((const char *)bind_values[i], NULL, 10);
            sqlite3_bind_int64(stmt, i + 1, v);
        } else {
            sqlite3_bind_text(stmt, i + 1, (const char *)bind_values[i],
                             -1, SQLITE_TRANSIENT);
        }
    }

    int32_t col_count = sqlite3_column_count(stmt);

    /* Two allocations per cell: marker + (optional) text. Markers encode
       NULL by storing a sentinel cell pointer == NULL. Callers use
       pkdx_result_is_null / pkdx_result_get to discriminate. */
    int32_t capacity = 64;
    int32_t row_count = 0;
    char **cells = (char **)libc_malloc(sizeof(char *) * capacity * col_count);

    int step_rc;
    while ((step_rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (row_count >= capacity) {
            capacity *= 2;
            cells = (char **)realloc(cells, sizeof(char *) * capacity * col_count);
        }
        for (int32_t c = 0; c < col_count; c++) {
            if (sqlite3_column_type(stmt, c) == SQLITE_NULL) {
                cells[row_count * col_count + c] = NULL;
            } else {
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
        }
        row_count++;
    }

    /* DML routed through this path (INSERT/UPDATE/DELETE via exec_binds →
       query_binds_impl) must surface SQLITE_CONSTRAINT / SQLITE_BUSY etc.
       so runner.mbt rolls back the transaction instead of committing a
       partially-applied migration. */
    if (step_rc != SQLITE_DONE) {
        sqlite3_finalize(stmt);
        int32_t total = row_count * col_count;
        for (int32_t i = 0; i < total; i++) {
            if (cells[i]) libc_free(cells[i]);
        }
        libc_free(cells);
        return step_rc;
    }

    sqlite3_finalize(stmt);

    PkdxResultSet *rs = (PkdxResultSet *)moonbit_make_external_object(
        &pkdx_rs_destructor, sizeof(PkdxResultSet));
    rs->row_count = row_count;
    rs->col_count = col_count;
    rs->cells = cells;
    out[0] = rs;
    return 0;
}

MOONBIT_FFI_EXPORT
int32_t pkdx_result_is_null(PkdxResultSet *rs, int32_t row, int32_t col) {
    if (!rs || row < 0 || row >= rs->row_count ||
        col < 0 || col >= rs->col_count) {
        return 1;
    }
    return rs->cells[row * rs->col_count + col] == NULL ? 1 : 0;
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

/* moonbit_make_external_object 化した今、解放は destructor 経由で行われる。
   既存の呼び出し元（旧 query 経路）からの明示解放にも対応するため、
   セルだけ早期解放してオブジェクト本体は GC に任せる no-op に近い形にする。 */
MOONBIT_FFI_EXPORT
void pkdx_result_free(PkdxResultSet *rs) {
    if (!rs) return;
    /* セル配列だけ解放。rs 本体は moonbit_make_external_object 由来なので
       MoonBit ランタイム側の rc=0 で destructor が再呼び出しされても
       cells == NULL を見て早抜けするので二重 free にはならない。 */
    pkdx_rs_destructor(rs);
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

#include <stdio.h>
#include <sys/stat.h>
#include <errno.h>

#define PKDX_STDIN_MAX (4 * 1024 * 1024)

MOONBIT_FFI_EXPORT
moonbit_string_t pkdx_read_stdin(void) {
    size_t capacity = 4096;
    size_t len = 0;
    char *buf = (char *)malloc(capacity);
    if (!buf) return moonbit_make_string(0, 0);
    int c;
    while ((c = fgetc(stdin)) != EOF) {
        if (len + 1 >= capacity) {
            if (capacity * 2 > PKDX_STDIN_MAX) { free(buf); return moonbit_make_string(0, 0); }
            capacity *= 2;
            char *newbuf = (char *)realloc(buf, capacity);
            if (!newbuf) { free(buf); return moonbit_make_string(0, 0); }
            buf = newbuf;
        }
        buf[len++] = (char)c;
    }
    buf[len] = '\0';
    moonbit_string_t result = utf8_to_moonbit_string(buf);
    free(buf);
    return result;
}

#ifdef _WIN32
#define PKDX_MKDIR(p) mkdir(p)
#define PKDX_IS_SEP(c) ((c) == '/' || (c) == '\\')
#else
#define PKDX_MKDIR(p) mkdir(p, 0755)
#define PKDX_IS_SEP(c) ((c) == '/')
#endif

static int pkdx_mkdirs(const char *path) {
    size_t plen = strlen(path);
    char *tmp = (char *)malloc(plen + 1);
    if (!tmp) return -1;
    memcpy(tmp, path, plen + 1);
    for (char *p = tmp + 1; *p; p++) {
        if (PKDX_IS_SEP(*p)) { *p = '\0'; PKDX_MKDIR(tmp); *p = '/'; }
    }
    int rc = PKDX_MKDIR(tmp);
    free(tmp);
    return rc;
}

MOONBIT_FFI_EXPORT
int32_t pkdx_write_file(const uint8_t *path, const uint8_t *content) {
    const char *p = (const char *)path;
    const char *last_slash = NULL;
    for (const char *ch = p; *ch; ch++) { if (*ch == '/') last_slash = ch; }
    if (last_slash) {
        size_t dir_len = (size_t)(last_slash - p);
        char *dir = (char *)malloc(dir_len + 1);
        if (!dir) return ENOMEM;
        memcpy(dir, p, dir_len);
        dir[dir_len] = '\0';
        pkdx_mkdirs(dir);
        free(dir);
    }
    FILE *f = fopen(p, "w");
    if (!f) return errno;
    fputs((const char *)content, f);
    fclose(f);
    return 0;
}

MOONBIT_FFI_EXPORT
void pkdx_exit(int32_t code) {
    exit(code);
}

MOONBIT_FFI_EXPORT
void pkdx_eprintln(const uint8_t *msg) {
    fprintf(stderr, "%s\n", (const char *)msg);
}

/* 8 MiB is a safety cap for migration JSON inputs. LegendsZA.json is
   currently <1 MiB and the largest data.json is ~300 KiB, so this is
   comfortable headroom while still bounding memory. */
#define PKDX_READ_FILE_MAX (8 * 1024 * 1024)

MOONBIT_FFI_EXPORT
moonbit_string_t pkdx_read_file(const uint8_t *path) {
    FILE *f = fopen((const char *)path, "rb");
    if (!f) return moonbit_make_string(0, 0);
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return moonbit_make_string(0, 0); }
    long sz = ftell(f);
    if (sz < 0 || sz > PKDX_READ_FILE_MAX) { fclose(f); return moonbit_make_string(0, 0); }
    rewind(f);
    char *buf = (char *)malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return moonbit_make_string(0, 0); }
    size_t n = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[n] = '\0';
    moonbit_string_t result = utf8_to_moonbit_string(buf);
    free(buf);
    return result;
}

MOONBIT_FFI_EXPORT
int32_t pkdx_file_exists(const uint8_t *path) {
    struct stat st;
    return stat((const char *)path, &st) == 0 ? 1 : 0;
}

MOONBIT_FFI_EXPORT
void pkdx_println(const uint8_t *msg) {
    fputs((const char *)msg, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}
