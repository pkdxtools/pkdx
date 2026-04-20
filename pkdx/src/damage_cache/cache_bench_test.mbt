///|
/// `now_ns()` must return a positive clock reading (nanoseconds since the
/// kernel boot epoch on Linux / since an arbitrary epoch on macOS). A stub
/// returning 0 fails this — Red phase.
test "now_ns returns positive clock reading" {
  assert_true(now_ns() > 0L)
}

///|
/// `now_ns()` must be monotonically non-decreasing across consecutive calls.
test "now_ns monotonically non-decreasing" {
  let t1 = now_ns()
  let t2 = now_ns()
  assert_true(t2 >= t1)
}

///|
/// `elapsed_ms(start)` is non-negative when `start` was taken before.
test "elapsed_ms non-negative interval" {
  let start = now_ns()
  let ms = elapsed_ms(start)
  assert_true(ms >= 0.0)
}
