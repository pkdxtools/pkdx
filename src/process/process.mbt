///|
/// Logical processor count for the current host. Always >= 1.
pub fn nproc() -> Int {
  let n = pkdx_nproc()
  if n < 1 {
    1
  } else {
    n
  }
}

///|
/// Platform-specific hard cap on parallel shard count. 64 on Windows
/// (`MAXIMUM_WAIT_OBJECTS`), effectively unbounded (`INT32_MAX`) on
/// POSIX. Use as `min(nproc(), max_parallel_shards())` when sizing
/// `auto`-resolved parallelism.
pub fn max_parallel_shards() -> Int {
  pkdx_max_parallel_shards()
}

///|
/// Absolute path of the binary the parent orchestrator should re-exec
/// for parallel shards. `PKDX_SELF_EXEC`, if set, takes precedence
/// over the OS-level lookup. Returns `None` when both the env override
/// and every OS lookup fail.
pub fn self_exec_path() -> String? {
  let s = pkdx_self_exec_path()
  if s.length() == 0 {
    None
  } else {
    Some(s)
  }
}

///|
/// Create a temp file with the given filename prefix in the OS-default
/// temp dir. Returns `None` on failure. The caller owns the file and
/// must delete it with `@db.unlink_file` when finished.
pub fn mkstemp_file(prefix : String) -> String? {
  let bytes = pkdx_string_to_utf8(prefix, prefix.length())
  let path = pkdx_mkstemp_file(bytes)
  if path.length() == 0 {
    None
  } else {
    Some(path)
  }
}

///|
/// Outcome of a single shard. A non-`Ok` value means the child either
/// failed to spawn, exited non-zero, or was killed by a signal /
/// TerminateProcess on timeout.
pub(all) enum ShardResult {
  Ok
  Exit(Int)     // non-zero exit code
  Failed       // spawn / signal / timeout
} derive(Debug, Eq)

///|
pub suberror RunShardsError {
  InvalidInput(String)
} derive(Debug)

///|
/// Spawn `argvs.length()` child processes, each invoking the running
/// pkdx native binary (resolved via `self_exec_path`) with the given
/// argv. Waits for all children to finish or `timeout_ms` to elapse.
///
/// Each child's stdin / stdout is redirected to /dev/null (NUL on
/// Windows); stderr is inherited so panics surface. Output collection
/// is the caller's responsibility (typically via per-shard temp files
/// referenced from each shard's argv).
///
/// `timeout_ms <= 0` waits indefinitely. On expiry the parent SIGTERMs
/// (or TerminateProcesses) every survivor, allows a 2-second grace,
/// then SIGKILLs.
pub fn run_parallel_shards(
  argvs : Array[Array[String]],
  timeout_ms~ : Int = 600_000,
) -> Array[ShardResult] raise RunShardsError {
  let n_shards = argvs.length()
  if n_shards <= 0 {
    raise InvalidInput("argvs must contain at least one shard")
  }
  let exe = match self_exec_path() {
    Some(p) => p
    None =>
      raise InvalidInput(
        "could not resolve self executable path; set PKDX_SELF_EXEC",
      )
  }
  let exe_bytes = pkdx_string_to_utf8(exe, exe.length())

  // Flatten argv: concatenate every argument's UTF-8 bytes, each
  // NUL-terminated. The C side walks the buffer with `strlen + 1`
  // strides to recover the individual argv slots.
  let buf = @buffer.new()
  let shard_argc = FixedArray::make(n_shards, 0)
  for i in 0..<n_shards {
    let args = argvs[i]
    if args.length() <= 0 {
      raise InvalidInput("shard " + i.to_string() + " has no argv (need at least argv[0])")
    }
    shard_argc[i] = args.length()
    for arg in args {
      let arg_bytes = pkdx_string_to_utf8(arg, arg.length())
      buf.write_bytes(arg_bytes)
    }
  }
  let flat_bytes = buf.to_bytes()

  let exit_codes = FixedArray::make(n_shards, -1)
  let _ = pkdx_run_parallel_shards(
    exe_bytes,
    flat_bytes,
    shard_argc,
    n_shards,
    timeout_ms,
    exit_codes,
  )

  let out = Array::make(n_shards, Ok)
  for i in 0..<n_shards {
    let code = exit_codes[i]
    out[i] = if code == 0 {
      Ok
    } else if code < 0 {
      Failed
    } else {
      Exit(code)
    }
  }
  out
}
