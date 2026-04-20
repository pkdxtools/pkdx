///|
/// CLOCK_MONOTONIC nanosecond reading. The C stub lives in `src/db/cwrap.c`
/// alongside the other `pkdx_*` FFI symbols; the cross-package link is safe
/// because moon builds all native stubs into a single translation unit.
extern "C" fn pkdx_monotonic_ns() -> Int64 = "pkdx_monotonic_ns"

///|
/// Monotonic clock in nanoseconds. Opaque epoch; only differences are meaningful.
pub fn now_ns() -> Int64 {
  pkdx_monotonic_ns()
}

///|
/// Elapsed time in milliseconds since `start`.
pub fn elapsed_ms(start : Int64) -> Double {
  (now_ns() - start).to_double() / 1_000_000.0
}
