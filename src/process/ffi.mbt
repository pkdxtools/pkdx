///|
/// Logical processor count (1 on OS query failure).
extern "C" fn pkdx_nproc() -> Int = "pkdx_nproc"

///|
/// Platform-specific hard cap on the number of children awaitable at
/// once. 64 on Windows (`MAXIMUM_WAIT_OBJECTS`); effectively unbounded
/// (`INT32_MAX`) on POSIX.
extern "C" fn pkdx_max_parallel_shards() -> Int = "pkdx_max_parallel_shards"

///|
/// Absolute path of the binary the parent orchestrator should re-exec
/// for parallel shards. `PKDX_SELF_EXEC`, if set, takes precedence over
/// the OS-level lookup so tests can inject a substitute binary
/// (e.g. /bin/sh) and unusual installs can override runtime detection.
/// Returns an empty string when both the env override and every OS
/// lookup fail.
extern "C" fn pkdx_self_exec_path() -> String = "pkdx_self_exec_path"

///|
/// Create a per-user temp file in the OS-default temp directory and
/// return its absolute path. `prefix` is a UTF-8 NUL-terminated byte
/// fragment used in the filename (Windows keeps only the first three
/// chars due to GetTempFileNameW). Empty string on failure.
#borrow(prefix)
extern "C" fn pkdx_mkstemp_file(prefix : Bytes) -> String = "pkdx_mkstemp_file"

///|
/// MoonBit `String` (UTF-16) to NUL-terminated UTF-8 `Bytes`. The symbol
/// is implemented in `src/db/cwrap.c` and linked globally; re-declared
/// here so `@process` does not need to import `@db`.
#borrow(s)
extern "C" fn pkdx_string_to_utf8(s : String, len : Int) -> Bytes = "pkdx_string_to_utf8"

///|
/// Spawn `n_shards` children, each running `exe` with its own argv,
/// and wait for all of them (or for `timeout_ms` to elapse).
///
/// `argvs_flat`: every child's argv flattened with `\0` separators.
/// `shard_argc`: how many args each shard owns (sum == total args).
/// `exit_codes`: filled with each shard's exit code; -1 on spawn /
///   signal / timeout / kill.
///
/// Return value: 0 = every shard exited 0; otherwise the count of
/// failing shards (a positive integer).
#borrow(exe, argvs_flat, shard_argc, exit_codes)
extern "C" fn pkdx_run_parallel_shards(
  exe : Bytes,
  argvs_flat : Bytes,
  shard_argc : FixedArray[Int],
  n_shards : Int,
  timeout_ms : Int,
  exit_codes : FixedArray[Int],
) -> Int = "pkdx_run_parallel_shards"
