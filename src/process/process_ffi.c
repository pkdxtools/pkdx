/*
 * pkdx process FFI — cross-platform helpers for the parallel select
 * orchestrator. Lives in its own package so both src/main (CLI entry)
 * and src/payoff (orchestrator) can depend on it without back-references.
 *
 * Functions:
 *   - pkdx_nproc:                CPU core count
 *   - pkdx_self_exec_path:       absolute path to the running native binary
 *   - pkdx_mkstemp_file:         create a per-user temp file, return its path
 *   - pkdx_run_parallel_shards:  fan out N children, wait for all, with timeout
 */

#include <moonbit.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#endif

#if defined(__APPLE__)
#include <crt_externs.h>
#include <limits.h>
#include <mach-o/dyld.h>
#define PKDX_ENVIRON (*_NSGetEnviron())
#elif !defined(_WIN32)
extern char **environ;
#define PKDX_ENVIRON environ
#endif

/*
 * UTF-8 → moonbit_string_t (UTF-16). Surrogate-pair correct.
 *
 * Duplicated from src/db/cwrap.c because the original is `static` and
 * the routine is short enough that header-sharing would add more
 * indirection than it saves. Keep the two copies in lock-step if either
 * is touched.
 */
static moonbit_string_t pkdx_proc_utf8_to_ms(const char *ptr) {
    if (ptr == NULL) {
        return moonbit_make_string(0, 0);
    }
    int32_t u16_len = 0;
    const uint8_t *s = (const uint8_t *)ptr;
    while (*s) {
        uint32_t cp;
        if (*s < 0x80) {
            cp = *s++;
        } else if ((*s & 0xE0) == 0xC0) {
            cp = (uint32_t)(*s++ & 0x1F) << 6;
            if ((*s & 0xC0) == 0x80) cp |= (uint32_t)(*s++ & 0x3F);
        } else if ((*s & 0xF0) == 0xE0) {
            cp = (uint32_t)(*s++ & 0x0F) << 12;
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F) << 6; }
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F); }
        } else if ((*s & 0xF8) == 0xF0) {
            cp = (uint32_t)(*s++ & 0x07) << 18;
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F) << 12; }
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F) << 6; }
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F); }
        } else {
            s++;
            cp = 0xFFFD;
        }
        u16_len += (cp >= 0x10000) ? 2 : 1;
    }
    moonbit_string_t ms = moonbit_make_string_raw(u16_len);
    s = (const uint8_t *)ptr;
    int32_t idx = 0;
    while (*s) {
        uint32_t cp;
        if (*s < 0x80) {
            cp = *s++;
        } else if ((*s & 0xE0) == 0xC0) {
            cp = (uint32_t)(*s++ & 0x1F) << 6;
            if ((*s & 0xC0) == 0x80) cp |= (uint32_t)(*s++ & 0x3F);
        } else if ((*s & 0xF0) == 0xE0) {
            cp = (uint32_t)(*s++ & 0x0F) << 12;
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F) << 6; }
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F); }
        } else if ((*s & 0xF8) == 0xF0) {
            cp = (uint32_t)(*s++ & 0x07) << 18;
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F) << 12; }
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F) << 6; }
            if ((*s & 0xC0) == 0x80) { cp |= (uint32_t)(*s++ & 0x3F); }
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

/* ===== pkdx_max_parallel_shards =======================================
 *
 * Platform-specific hard cap on the number of children that can be
 * awaited concurrently. On Windows this is `MAXIMUM_WAIT_OBJECTS` (64)
 * because `WaitForMultipleObjects` cannot handle more in a single call.
 * On POSIX there is no equivalent fixed limit; we return a large
 * sentinel that effectively means "no cap" so user-specified parallel
 * counts pass through unchanged.
 */
MOONBIT_FFI_EXPORT
int32_t pkdx_max_parallel_shards(void) {
#if defined(_WIN32)
    return (int32_t)MAXIMUM_WAIT_OBJECTS;
#else
    return 0x7FFFFFFF;
#endif
}

/* ===== pkdx_nproc =====================================================
 *
 * Returns the count of logical processors. Used to default --parallel=auto.
 * Always >= 1; falls back to 1 if the OS query fails so callers never
 * see 0.
 */
MOONBIT_FFI_EXPORT
int32_t pkdx_nproc(void) {
#if defined(_WIN32)
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    DWORD n = si.dwNumberOfProcessors;
    return (n > 0) ? (int32_t)n : 1;
#else
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return (n > 0) ? (int32_t)n : 1;
#endif
}

/* ===== pkdx_self_exec_path ============================================
 *
 * Absolute path of the running pkdx native binary. Used by the parent
 * orchestrator to fork-and-exec itself with the __select-shard
 * subcommand. The wrapper scripts (bin/pkdx, bin/pkdx.cmd) hand off to
 * the native binary via exec / direct invocation, so the path returned
 * here is always the native binary itself (not the wrapper) — children
 * therefore run with the same code as the parent.
 *
 * The PKDX_SELF_EXEC environment variable, if set, takes precedence over
 * the OS lookup. This lets tests inject a substitute binary (e.g. /bin/sh)
 * and lets users with unusual installs override the runtime detection.
 * Returns an empty string only when both the env var and every OS-level
 * lookup fail.
 */
MOONBIT_FFI_EXPORT
moonbit_string_t pkdx_self_exec_path(void) {
    const char *env = getenv("PKDX_SELF_EXEC");
    if (env && *env) {
        return pkdx_proc_utf8_to_ms(env);
    }

    char buf[4096];

#if defined(__APPLE__)
    uint32_t size = (uint32_t)sizeof(buf);
    if (_NSGetExecutablePath(buf, &size) == 0) {
        char resolved[PATH_MAX];
        if (realpath(buf, resolved) != NULL) {
            return pkdx_proc_utf8_to_ms(resolved);
        }
        return pkdx_proc_utf8_to_ms(buf);
    }
#elif defined(__linux__)
    ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n > 0) {
        buf[n] = '\0';
        return pkdx_proc_utf8_to_ms(buf);
    }
#elif defined(_WIN32)
    wchar_t wbuf[4096];
    DWORD wn = GetModuleFileNameW(NULL, wbuf,
                                  (DWORD)(sizeof(wbuf) / sizeof(wbuf[0])));
    if (wn > 0 && wn < (DWORD)(sizeof(wbuf) / sizeof(wbuf[0]))) {
        int ubytes = WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, NULL, 0,
                                         NULL, NULL);
        if (ubytes > 0 && ubytes <= (int)sizeof(buf)) {
            WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, buf, ubytes,
                                NULL, NULL);
            return pkdx_proc_utf8_to_ms(buf);
        }
    }
#endif

    return moonbit_make_string(0, 0);
}

/* ===== pkdx_mkstemp_file ==============================================
 *
 * Creates a per-user temp file in the OS-default temp directory and
 * returns its absolute path. POSIX uses mkstemp (mode 0600 by default).
 * Windows uses GetTempFileNameW; the resulting file inherits the
 * default per-user ACL.
 *
 * `prefix` is a UTF-8 fragment included in the resulting filename
 * (e.g., "pkdx_select_input"). On Windows only the first three chars
 * survive due to the GetTempFileNameW contract; the suffix is OS-
 * generated.
 *
 * Returns an empty string on failure. The created file is empty and
 * closed; the caller is responsible for opening it for writing /
 * reading and ultimately deleting it via @db.unlink_file.
 */
MOONBIT_FFI_EXPORT
moonbit_string_t pkdx_mkstemp_file(const uint8_t *prefix) {
    const char *pfx = (const char *)prefix;
    if (!pfx || !*pfx) pfx = "pkdx";

#if defined(_WIN32)
    wchar_t wtempdir[MAX_PATH];
    DWORD wn = GetTempPathW(MAX_PATH, wtempdir);
    if (wn == 0 || wn > MAX_PATH) {
        return moonbit_make_string(0, 0);
    }

    /* Windows GetTempFileNameW uses only the first three chars of the
       prefix. Convert and truncate. */
    wchar_t wpfx[4] = {0, 0, 0, 0};
    int wn_pfx = MultiByteToWideChar(CP_UTF8, 0, pfx, -1, NULL, 0);
    if (wn_pfx > 0) {
        wchar_t *wpfx_full = (wchar_t *)malloc(sizeof(wchar_t) *
                                               (size_t)wn_pfx);
        if (wpfx_full) {
            MultiByteToWideChar(CP_UTF8, 0, pfx, -1, wpfx_full, wn_pfx);
            for (int i = 0; i < 3 && wpfx_full[i] != L'\0'; i++) {
                wpfx[i] = wpfx_full[i];
            }
            free(wpfx_full);
        }
    }
    if (wpfx[0] == L'\0') wpfx[0] = L'p';

    wchar_t wout[MAX_PATH];
    UINT uniq = GetTempFileNameW(wtempdir, wpfx, 0, wout);
    if (uniq == 0) {
        return moonbit_make_string(0, 0);
    }

    char out_u8[MAX_PATH * 4];
    int ubytes = WideCharToMultiByte(CP_UTF8, 0, wout, -1, out_u8,
                                     (int)sizeof(out_u8), NULL, NULL);
    if (ubytes <= 0) {
        return moonbit_make_string(0, 0);
    }
    return pkdx_proc_utf8_to_ms(out_u8);
#else
    const char *tmpdir = getenv("TMPDIR");
    if (!tmpdir || !*tmpdir) tmpdir = "/tmp";

    size_t tlen = strlen(tmpdir);
    size_t plen = strlen(pfx);
    /* template: "<tmpdir>/<prefix>_XXXXXX\0" */
    size_t bufsize = tlen + 1 + plen + 1 + 6 + 1;
    char *tmpl = (char *)malloc(bufsize);
    if (!tmpl) {
        return moonbit_make_string(0, 0);
    }
    memcpy(tmpl, tmpdir, tlen);
    tmpl[tlen] = '/';
    memcpy(tmpl + tlen + 1, pfx, plen);
    memcpy(tmpl + tlen + 1 + plen, "_XXXXXX", 7);
    tmpl[bufsize - 1] = '\0';

    int fd = mkstemp(tmpl);
    if (fd < 0) {
        free(tmpl);
        return moonbit_make_string(0, 0);
    }
    close(fd);
    moonbit_string_t result = pkdx_proc_utf8_to_ms(tmpl);
    free(tmpl);
    return result;
#endif
}

/* ===== pkdx_run_parallel_shards =======================================
 *
 * Spawn N child processes, each running `exe_path` with its own argv,
 * and wait for all to finish (or for `timeout_ms` to elapse).
 *
 * argvs_flat layout:
 *   For shard i (0..n_shards-1), shard_argc[i] consecutive NUL-terminated
 *   UTF-8 strings, packed back-to-back. The strings are passed to
 *   `posix_spawn` / `CreateProcessW` verbatim — including argv[0]. The
 *   caller decides what argv[0] should be (typically the same path as
 *   `exe_path`).
 *
 * Child stdio:
 *   stdin and stdout are redirected to /dev/null (Windows: NUL device).
 *   stderr is inherited from the parent so the child can surface panics
 *   / OOMs.
 *
 * Timeout semantics:
 *   - `timeout_ms <= 0` means "wait indefinitely".
 *   - On expiry the parent sends SIGTERM (POSIX) or TerminateProcess
 *     (Windows) to every still-running child, waits another 2 seconds,
 *     then sends SIGKILL (POSIX) / a second TerminateProcess attempt
 *     (Windows) to whatever is still alive. All children are then reaped.
 *
 * Exit codes:
 *   - 0..255: normal exit code
 *   - -1: spawn / wait failure, or the child was killed by a signal /
 *     TerminateProcess (treat as "abnormal" for the caller).
 *
 * Return value: 0 if every shard exited 0; otherwise the count of
 * non-zero shards (clipped to INT_MAX-ish — never < 1 in the failure
 * case).
 */

#if defined(_WIN32)

/* Append a single argv element to `buf` (size `cap`, current length
 * `*len`), following Microsoft's command-line parsing rules:
 *   - backslashes preceding a `"` are doubled
 *   - trailing backslashes before the closing quote are doubled too
 *   - args containing space / tab / `"` are wrapped in `"..."`
 *   - empty args become `""`
 * `buf` is grown via realloc as needed. Returns 0 on success.
 */
static int pkdx_win_append_quoted(char **buf, size_t *cap, size_t *len,
                                  const char *arg) {
    size_t arg_len = strlen(arg);
    int needs_quote = (arg_len == 0) ||
                      (strpbrk(arg, " \t\"") != NULL);
    /* Worst case: every char doubles → 2x + 2 quotes + space. */
    size_t needed = arg_len * 2 + 4;
    if (*len + needed >= *cap) {
        size_t new_cap = (*cap + needed) * 2;
        char *nb = (char *)realloc(*buf, new_cap);
        if (!nb) return -1;
        *buf = nb;
        *cap = new_cap;
    }

    if (needs_quote) (*buf)[(*len)++] = '"';

    int backslashes = 0;
    for (size_t i = 0; i < arg_len; i++) {
        char c = arg[i];
        if (c == '\\') {
            backslashes++;
        } else if (c == '"') {
            /* Double the run of backslashes then escape the quote. */
            for (int k = 0; k < 2 * backslashes; k++) {
                (*buf)[(*len)++] = '\\';
            }
            (*buf)[(*len)++] = '\\';
            (*buf)[(*len)++] = '"';
            backslashes = 0;
        } else {
            for (int k = 0; k < backslashes; k++) {
                (*buf)[(*len)++] = '\\';
            }
            (*buf)[(*len)++] = c;
            backslashes = 0;
        }
    }

    if (needs_quote) {
        /* Trailing backslashes inside quotes get doubled. */
        for (int k = 0; k < 2 * backslashes; k++) {
            (*buf)[(*len)++] = '\\';
        }
        (*buf)[(*len)++] = '"';
    } else {
        for (int k = 0; k < backslashes; k++) {
            (*buf)[(*len)++] = '\\';
        }
    }
    return 0;
}

/* Build a UTF-16 command line from the argv elements `argv[0..argc)`.
 * Returns malloc'd buffer (caller frees) or NULL on failure. */
static wchar_t *pkdx_win_build_cmdline(const char *const *argv, int argc) {
    size_t cap = 256;
    size_t len = 0;
    char *u8 = (char *)malloc(cap);
    if (!u8) return NULL;

    for (int i = 0; i < argc; i++) {
        if (i > 0) {
            if (len + 1 >= cap) {
                cap *= 2;
                char *nb = (char *)realloc(u8, cap);
                if (!nb) { free(u8); return NULL; }
                u8 = nb;
            }
            u8[len++] = ' ';
        }
        if (pkdx_win_append_quoted(&u8, &cap, &len, argv[i]) != 0) {
            free(u8);
            return NULL;
        }
    }
    if (len + 1 >= cap) {
        char *nb = (char *)realloc(u8, len + 1);
        if (!nb) { free(u8); return NULL; }
        u8 = nb;
    }
    u8[len] = '\0';

    int wn = MultiByteToWideChar(CP_UTF8, 0, u8, -1, NULL, 0);
    if (wn <= 0) { free(u8); return NULL; }
    wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)wn);
    if (!w) { free(u8); return NULL; }
    MultiByteToWideChar(CP_UTF8, 0, u8, -1, w, wn);
    free(u8);
    return w;
}

#else /* POSIX */

/* Cross-platform monotonic wall-clock in milliseconds. */
static int64_t pkdx_monotonic_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)ts.tv_nsec / 1000000;
}

#endif /* _WIN32 */

MOONBIT_FFI_EXPORT
int32_t pkdx_run_parallel_shards(
    const uint8_t *exe_path,
    const uint8_t *argvs_flat,
    const int32_t *shard_argc,
    int32_t n_shards,
    int32_t timeout_ms,
    int32_t *exit_codes
) {
    if (!exe_path || !argvs_flat || !shard_argc || !exit_codes ||
        n_shards <= 0) {
        return -1;
    }

    /* Pre-fill exit_codes with -1 so caller-visible state is consistent
       even on early failure paths. */
    for (int32_t i = 0; i < n_shards; i++) exit_codes[i] = -1;

    /* Walk argvs_flat once, building per-shard pointer arrays. */
    const char **arg_ptrs = (const char **)malloc(sizeof(const char *) *
        ((size_t)n_shards));
    if (!arg_ptrs) return -1;

    /* Count total args to allocate the flat pointer table. */
    int32_t total_args = 0;
    for (int32_t i = 0; i < n_shards; i++) {
        if (shard_argc[i] <= 0) {
            free(arg_ptrs);
            return -1;
        }
        total_args += shard_argc[i];
    }

    const char **all_ptrs = (const char **)malloc(sizeof(const char *) *
        ((size_t)total_args));
    if (!all_ptrs) { free(arg_ptrs); return -1; }

    const char *cursor = (const char *)argvs_flat;
    int32_t off = 0;
    for (int32_t i = 0; i < n_shards; i++) {
        arg_ptrs[i] = (const char *)&all_ptrs[off];
        for (int32_t j = 0; j < shard_argc[i]; j++) {
            all_ptrs[off++] = cursor;
            cursor += strlen(cursor) + 1;
        }
    }

#if defined(_WIN32)

    HANDLE *handles = (HANDLE *)calloc((size_t)n_shards, sizeof(HANDLE));
    if (!handles) { free(all_ptrs); free(arg_ptrs); return -1; }

    /* exe_path: UTF-8 → UTF-16 */
    int wn = MultiByteToWideChar(CP_UTF8, 0, (const char *)exe_path, -1,
                                 NULL, 0);
    wchar_t *exe_w = NULL;
    if (wn > 0) {
        exe_w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)wn);
        if (exe_w) MultiByteToWideChar(CP_UTF8, 0, (const char *)exe_path,
                                       -1, exe_w, wn);
    }
    if (!exe_w) {
        free(handles); free(all_ptrs); free(arg_ptrs);
        return -1;
    }

    /* NUL device for stdin/stdout. Single shared handle is fine because
       we mark it inheritable and the child treats it as read-only /
       discarded output. */
    SECURITY_ATTRIBUTES sa = {0};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE nul_in = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ,
                                &sa, OPEN_EXISTING, 0, NULL);
    HANDLE nul_out = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_WRITE,
                                 &sa, OPEN_EXISTING, 0, NULL);
    HANDLE std_err = GetStdHandle(STD_ERROR_HANDLE);

    int32_t spawn_failures = 0;

    for (int32_t i = 0; i < n_shards; i++) {
        const char *const *child_argv =
            (const char *const *)arg_ptrs[i];
        wchar_t *cmdline_w = pkdx_win_build_cmdline(
            child_argv, shard_argc[i]);
        if (!cmdline_w) {
            spawn_failures++;
            handles[i] = NULL;
            continue;
        }

        STARTUPINFOW si = {0};
        si.cb = sizeof(si);
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdInput = nul_in;
        si.hStdOutput = nul_out;
        si.hStdError = std_err;

        PROCESS_INFORMATION pi = {0};

        BOOL ok = CreateProcessW(exe_w, cmdline_w, NULL, NULL,
                                 TRUE, 0, NULL, NULL, &si, &pi);
        free(cmdline_w);
        if (!ok) {
            spawn_failures++;
            handles[i] = NULL;
            continue;
        }
        CloseHandle(pi.hThread);
        handles[i] = pi.hProcess;
    }

    /* Compact handles array for WaitForMultipleObjects (which rejects
       NULL entries). Keep a mapping back to the original shard index. */
    HANDLE wait_set[MAXIMUM_WAIT_OBJECTS];
    int32_t wait_to_shard[MAXIMUM_WAIT_OBJECTS];
    DWORD n_wait = 0;
    for (int32_t i = 0; i < n_shards && n_wait < MAXIMUM_WAIT_OBJECTS;
         i++) {
        if (handles[i] != NULL) {
            wait_set[n_wait] = handles[i];
            wait_to_shard[n_wait] = i;
            n_wait++;
        }
    }

    DWORD wait_ms = (timeout_ms > 0) ? (DWORD)timeout_ms : INFINITE;

    if (n_wait > 0) {
        DWORD r = WaitForMultipleObjects(n_wait, wait_set, TRUE, wait_ms);
        if (r == WAIT_TIMEOUT) {
            /* Kill everyone still running, then wait briefly for
               cleanup. The second WFMO uses a short grace window so we
               do not wedge the parent forever on a stubborn child. */
            for (DWORD k = 0; k < n_wait; k++) {
                TerminateProcess(wait_set[k], 1);
            }
            WaitForMultipleObjects(n_wait, wait_set, TRUE, 2000);
            /* If anyone is still up at this point, force a second
               TerminateProcess; GetExitCodeProcess below tolerates
               STILL_ACTIVE by recording -1 for that shard. */
            for (DWORD k = 0; k < n_wait; k++) {
                DWORD code = 0;
                if (GetExitCodeProcess(wait_set[k], &code) &&
                    code == STILL_ACTIVE) {
                    TerminateProcess(wait_set[k], 1);
                }
            }
        }
    }

    /* Collect exit codes + close handles. */
    for (int32_t i = 0; i < n_shards; i++) {
        if (handles[i] == NULL) {
            exit_codes[i] = -1;
            continue;
        }
        DWORD code = 0;
        if (GetExitCodeProcess(handles[i], &code) &&
            code != STILL_ACTIVE) {
            exit_codes[i] = (int32_t)code;
        } else {
            exit_codes[i] = -1;
        }
        CloseHandle(handles[i]);
    }

    if (nul_in != INVALID_HANDLE_VALUE) CloseHandle(nul_in);
    if (nul_out != INVALID_HANDLE_VALUE) CloseHandle(nul_out);

    free(exe_w);
    free(handles);
    free(all_ptrs);
    free(arg_ptrs);

    (void)spawn_failures;

#else /* POSIX */

    pid_t *pids = (pid_t *)calloc((size_t)n_shards, sizeof(pid_t));
    if (!pids) { free(all_ptrs); free(arg_ptrs); return -1; }

    posix_spawn_file_actions_t fa;
    if (posix_spawn_file_actions_init(&fa) != 0) {
        free(pids); free(all_ptrs); free(arg_ptrs);
        return -1;
    }
    posix_spawn_file_actions_addopen(&fa, STDIN_FILENO, "/dev/null",
                                     O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&fa, STDOUT_FILENO, "/dev/null",
                                     O_WRONLY, 0);
    /* stderr is inherited by default. */

    int32_t spawn_failures = 0;

    for (int32_t i = 0; i < n_shards; i++) {
        const char *const *child_argv =
            (const char *const *)arg_ptrs[i];
        /* posix_spawn wants a NULL-terminated argv. We have to build
           one with the null sentinel; allocate argc+1 slots. */
        const char **argv_nl = (const char **)malloc(
            sizeof(const char *) * ((size_t)shard_argc[i] + 1));
        if (!argv_nl) {
            spawn_failures++;
            continue;
        }
        for (int32_t j = 0; j < shard_argc[i]; j++) {
            argv_nl[j] = child_argv[j];
        }
        argv_nl[shard_argc[i]] = NULL;

        pid_t pid = 0;
        int rc = posix_spawn(&pid, (const char *)exe_path, &fa, NULL,
                             (char *const *)argv_nl, PKDX_ENVIRON);
        free(argv_nl);
        if (rc != 0) {
            spawn_failures++;
            pids[i] = 0;
            continue;
        }
        pids[i] = pid;
    }

    posix_spawn_file_actions_destroy(&fa);

    /* Wait loop with optional deadline. */
    int64_t start_ms = pkdx_monotonic_ms();
    int64_t deadline_ms = (timeout_ms > 0) ?
        (start_ms + (int64_t)timeout_ms) : -1;
    int64_t kill_deadline_ms = -1;  /* set after SIGTERM */
    int alive = 0;
    for (int32_t i = 0; i < n_shards; i++) {
        if (pids[i] > 0) alive++;
    }

    while (alive > 0) {
        for (int32_t i = 0; i < n_shards; i++) {
            if (pids[i] <= 0) continue;
            int status = 0;
            pid_t r = waitpid(pids[i], &status, WNOHANG);
            if (r == 0) continue;  /* still running */
            if (r < 0) {
                if (errno == ECHILD) {
                    /* Already reaped (shouldn't happen but be safe). */
                    pids[i] = 0;
                    alive--;
                    continue;
                }
                continue;
            }
            /* Reaped successfully. */
            if (WIFEXITED(status)) {
                exit_codes[i] = WEXITSTATUS(status);
            } else {
                exit_codes[i] = -1;
            }
            pids[i] = 0;
            alive--;
        }
        if (alive == 0) break;

        int64_t now_ms = pkdx_monotonic_ms();
        if (deadline_ms > 0 && now_ms > deadline_ms &&
            kill_deadline_ms < 0) {
            /* First timeout: SIGTERM the survivors, give them 2s grace. */
            for (int32_t i = 0; i < n_shards; i++) {
                if (pids[i] > 0) kill(pids[i], SIGTERM);
            }
            kill_deadline_ms = now_ms + 2000;
        }
        if (kill_deadline_ms > 0 && now_ms > kill_deadline_ms) {
            /* Grace expired: SIGKILL. */
            for (int32_t i = 0; i < n_shards; i++) {
                if (pids[i] > 0) kill(pids[i], SIGKILL);
            }
            /* Reset so we do not re-fire forever. */
            kill_deadline_ms = now_ms + 60000;
        }
        /* Tiny sleep so we do not busy-loop. */
        struct timespec slp = {0, 50 * 1000 * 1000};
        nanosleep(&slp, NULL);
    }

    free(pids);
    free(all_ptrs);
    free(arg_ptrs);

    (void)spawn_failures;

#endif /* _WIN32 */

    int32_t failures = 0;
    for (int32_t i = 0; i < n_shards; i++) {
        if (exit_codes[i] != 0) failures++;
    }
    return failures;
}
