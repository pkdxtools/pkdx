///|
/// Mock env lookup: returns the value for a single configured key,
/// `None` for everything else.
fn mock_env(key_match : String, value : String?) -> (String) -> String? {
  fn lookup(key : String) -> String? {
    if key == key_match {
      value
    } else {
      None
    }
  }
  lookup
}

///|
test "parallel_count: \"1\" returns 1 regardless of nproc" {
  let n = parallel_count_from_env_and_flag(
    "1", fn() { 16 }, fn() { 0x7FFFFFFF }, mock_env("", None),
  )
  @debug.assert_eq(n, 1)
}

///|
test "parallel_count: \"auto\" returns nproc on POSIX (no cap)" {
  let n = parallel_count_from_env_and_flag(
    "auto", fn() { 12 }, fn() { 0x7FFFFFFF }, mock_env("", None),
  )
  @debug.assert_eq(n, 12)
}

///|
test "parallel_count: \"auto\" clamps to Windows MAXIMUM_WAIT_OBJECTS (64)" {
  let n = parallel_count_from_env_and_flag(
    "auto", fn() { 128 }, fn() { 64 }, mock_env("", None),
  )
  @debug.assert_eq(n, 64)
}

///|
test "parallel_count: \"auto\" with PKDX_NO_PARALLEL=1 forces 1" {
  let n = parallel_count_from_env_and_flag(
    "auto", fn() { 16 }, fn() { 0x7FFFFFFF },
    mock_env("PKDX_NO_PARALLEL", Some("1")),
  )
  @debug.assert_eq(n, 1)
}

///|
test "parallel_count: explicit positive integer passes through (POSIX)" {
  let n = parallel_count_from_env_and_flag(
    "4", fn() { 16 }, fn() { 0x7FFFFFFF }, mock_env("", None),
  )
  @debug.assert_eq(n, 4)
}

///|
test "parallel_count: explicit N > Windows cap errors out" {
  let raised = try {
    let _ = parallel_count_from_env_and_flag(
      "128", fn() { 16 }, fn() { 64 }, mock_env("", None),
    )
    false
  } catch {
    InvalidJson(_) => true
    _ => false
  }
  assert_true(raised)
}

///|
test "parallel_count: explicit 0 errors out (must be positive)" {
  let raised = try {
    let _ = parallel_count_from_env_and_flag(
      "0", fn() { 16 }, fn() { 0x7FFFFFFF }, mock_env("", None),
    )
    false
  } catch {
    InvalidJson(_) => true
    _ => false
  }
  assert_true(raised)
}

///|
test "parallel_count: malformed flag errors out" {
  let raised = try {
    let _ = parallel_count_from_env_and_flag(
      "yes", fn() { 16 }, fn() { 0x7FFFFFFF }, mock_env("", None),
    )
    false
  } catch {
    InvalidJson(_) => true
    _ => false
  }
  assert_true(raised)
}

///|
test "parallel_count: nproc returning 0 still gives >= 1" {
  let n = parallel_count_from_env_and_flag(
    "auto", fn() { 0 }, fn() { 0x7FFFFFFF }, mock_env("", None),
  )
  assert_true(n >= 1)
}
