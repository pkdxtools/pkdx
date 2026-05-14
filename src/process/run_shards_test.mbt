/// Tests for `run_parallel_shards`. These use the host shell instead
/// of the pkdx binary so we can exercise the spawn / wait / timeout
/// logic without depending on Task 5's `__select-shard` subcommand.
///
/// `PKDX_SELF_EXEC` is set to `/bin/sh` (POSIX) or `cmd.exe` (Windows)
/// so the public wrapper picks the shell instead of pkdx itself. The
/// argv passed to each shard is the shell-specific invocation that
/// runs an inline script.

///|
extern "C" fn pkdx_monotonic_ns() -> Int64 = "pkdx_monotonic_ns"

///|
fn monotonic_ms() -> Int64 {
  pkdx_monotonic_ns() / 1_000_000
}

///|
/// Find a shell that exists on this host and set PKDX_SELF_EXEC so the
/// public wrapper picks it up. Returns the shell kind ("sh" or "cmd").
/// Tests that depend on Unix-shell idioms should skip if the host is
/// Windows.
fn setup_shell() -> String {
  let sh_candidates = ["/bin/sh", "/bin/bash"]
  for cand in sh_candidates {
    if @db.file_exists(cand) {
      @sys.set_env_var("PKDX_SELF_EXEC", cand)
      return "sh"
    }
  }
  let cmd_path = "C:\\Windows\\System32\\cmd.exe"
  if @db.file_exists(cmd_path) {
    @sys.set_env_var("PKDX_SELF_EXEC", cmd_path)
    return "cmd"
  }
  abort("No shell found for testing run_parallel_shards")
}

///|
test "run_parallel_shards single shard exit 0" {
  let kind = setup_shell()
  if kind != "sh" {
    return
  }
  let argvs = [["sh", "-c", "true"]]
  let results = run_parallel_shards(argvs, timeout_ms=10_000)
  @debug.assert_eq(results.length(), 1)
  @debug.assert_eq(results[0], Ok)
}

///|
test "run_parallel_shards mixed exit codes are reported per shard" {
  let kind = setup_shell()
  if kind != "sh" {
    return
  }
  let argvs = [
    ["sh", "-c", "exit 0"],
    ["sh", "-c", "exit 1"],
    ["sh", "-c", "exit 2"],
    ["sh", "-c", "exit 0"],
  ]
  let results = run_parallel_shards(argvs, timeout_ms=10_000)
  @debug.assert_eq(results.length(), 4)
  @debug.assert_eq(results[0], Ok)
  @debug.assert_eq(results[1], Exit(1))
  @debug.assert_eq(results[2], Exit(2))
  @debug.assert_eq(results[3], Ok)
}

///|
test "run_parallel_shards times out long-running shards" {
  let kind = setup_shell()
  if kind != "sh" {
    return
  }
  // 1 child finishes immediately, the rest sleep past the timeout. The
  // parent must SIGTERM / SIGKILL the survivors and return without
  // leaving zombies.
  let argvs = [
    ["sh", "-c", "true"],
    ["sh", "-c", "sleep 30"],
    ["sh", "-c", "sleep 30"],
    ["sh", "-c", "sleep 30"],
  ]
  let start_ms = monotonic_ms()
  let results = run_parallel_shards(argvs, timeout_ms=1_500)
  let elapsed_ms = monotonic_ms() - start_ms
  @debug.assert_eq(results.length(), 4)
  @debug.assert_eq(results[0], Ok)
  // The survivors should have been killed; result is Failed (signal /
  // -1 exit) — never Ok and never Exit(positive).
  for i in [1, 2, 3] {
    let r = results[i]
    match r {
      Failed => ()
      _ =>
        abort(
          "expected Failed for shard " +
          i.to_string() +
          ", got " +
          @debug.to_string(r),
        )
    }
  }
  // 2-second grace + ~50ms polling slack; should be comfortably under 8s.
  assert_true(elapsed_ms < 8_000L)
}
