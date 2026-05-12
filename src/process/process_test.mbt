///|
test "nproc returns at least 1" {
  let n = nproc()
  assert_true(n >= 1)
}

///|
test "self_exec_path returns Some when the process is launched normally" {
  // Under `moon test` the test runner is the host pkdx binary (or a
  // moonbit-run helper). Either way the OS call should succeed.
  // We only assert presence + non-empty path; the exact suffix differs
  // between macOS / Linux / Windows.
  let path = self_exec_path()
  match path {
    Some(p) => assert_true(p.length() > 0)
    None => abort("self_exec_path returned None — OS lookup failed")
  }
}

///|
test "mkstemp_file creates a unique writable temp file" {
  let p1 = mkstemp_file("pkdx_process_test")
  let p2 = mkstemp_file("pkdx_process_test")
  match (p1, p2) {
    (Some(a), Some(b)) => {
      assert_true(a.length() > 0)
      assert_true(b.length() > 0)
      // Templates are unique — two consecutive calls must not collide.
      assert_true(a != b)
      // Clean up after ourselves so /tmp does not accumulate orphans.
      let _ = @db.unlink_file(a)
      let _ = @db.unlink_file(b)
    }
    _ => abort("mkstemp_file returned None")
  }
}
