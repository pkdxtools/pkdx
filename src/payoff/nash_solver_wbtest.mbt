///|
/// Whitebox tests for `solve_with_fallback`. Stage 1a covers the primary
/// simplex path; Stage 1b adds the fictitious_play fallback wired below.

///|
test "primary simplex on rock-paper-scissors returns Simplex path + expl=0" {
  let m = match
    @nash.FiniteMatrix::new([
      [0.0, -1.0, 1.0],
      [1.0, 0.0, -1.0],
      [-1.0, 1.0, 0.0],
    ]) {
    Ok(mat) => mat
    Err(_) => {
      assert_true(false)
      abort("matrix construction failed")
    }
  }
  let result = solve_with_fallback(m)
  inspect(result.solver_path, content="Simplex")
  inspect(result.value, content="0")
  inspect(result.exploitability, content="0")
  // RPS Nash equilibrium is uniform (1/3, 1/3, 1/3) on each side.
  let row = result.row_strategy.to_array()
  let col = result.col_strategy.to_array()
  assert_eq(row.length(), 3)
  assert_eq(col.length(), 3)
  let third = 1.0 / 3.0
  for i in 0..<3 {
    assert_true((row[i] - third).abs() < 1.0e-6)
    assert_true((col[i] - third).abs() < 1.0e-6)
  }
}

///|
/// Load the pinned 60x60 degenerate payoff matrix from
/// `tests/fixtures/nash_simplex_failure_60x60.json`. This matrix was produced
/// by running `bin/pkdx select` on the 6v6 turn_limit=3 smoke fixture
/// observed to raise `SimplexFailure(IterationLimit)` on PR #143 smoke. We
/// reuse the same matrix here so that the regression guard is exactly the
/// case the fallback chain must handle.
fn load_degenerate_fixture_60x60() -> @nash.FiniteMatrix {
  let raw = match @db.read_file(
      "tests/fixtures/nash_simplex_failure_60x60.json",
    ) {
    Some(s) => s
    None => abort("missing tests/fixtures/nash_simplex_failure_60x60.json")
  }
  let parsed = try @json.parse(raw) catch {
    _ => abort("fixture JSON parse failed")
  } noraise {
    j => j
  }
  let rows : Array[Array[Double]] = match parsed {
    Array(rs) => {
      let out = Array::make(rs.length(), ([] : Array[Double]))
      for i in 0..<rs.length() {
        match rs[i] {
          Array(cs) => {
            let row = Array::make(cs.length(), 0.0)
            for j in 0..<cs.length() {
              row[j] = match cs[j] {
                Number(n, ..) => n
                _ => abort("fixture cell not a number")
              }
            }
            out[i] = row
          }
          _ => abort("fixture row not an array")
        }
      }
      out
    }
    _ => abort("fixture root not an array")
  }
  match @nash.FiniteMatrix::new(rows) {
    Ok(m) => m
    Err(_) => abort("fixture matrix construction failed")
  }
}

///|
/// Baseline regression guard: `@nash.solve_zero_sum` on its own is still
/// expected to raise `SimplexFailure(_)` for this fixture. If a future
/// upstream change makes the primary simplex succeed here, this assertion
/// will fail and we should reconsider whether the fallback chain is still
/// needed (or replace the fixture with a still-failing matrix).
test "fixture baseline: solve_zero_sum raises SimplexFailure on degenerate 60x60 matrix" {
  let m = load_degenerate_fixture_60x60()
  assert_true(m.rows() == 60)
  assert_true(m.cols() == 60)
  let raised_simplex_failure = try {
    let _ = @nash.solve_zero_sum(m)
    false
  } catch {
    @nash.SimplexFailure(_) => true
    _ => false
  }
  assert_true(raised_simplex_failure)
}

///|
/// Stage 1c red→green: when both `fictitious_play` and `mwu` exceed `tol` on a
/// pathologically tight tolerance (1e-10) with a tight iteration budget, the
/// fallback chain raises `NashFallbackExhausted` carrying the original simplex
/// error message plus the observed exploitabilities from both iterative
/// solvers. Users can inspect how close each approximate solver came.
test "all-fallback fail raises NashFallbackExhausted on pathological tol" {
  let m = load_degenerate_fixture_60x60()
  let pathological : NashSolverConfig = { tol: 1.0e-10, iterations: 100 }
  try solve_with_fallback(m, config=pathological) catch {
    NashFallbackExhausted(simplex_err~, fp_expl~, mwu_expl~) => {
      // Observed exploitabilities from both iterative solvers must be at or
      // above the impossible tol — i.e. neither succeeded.
      assert_true(fp_expl >= 1.0e-10)
      assert_true(mwu_expl >= 1.0e-10)
      // Simplex error message is non-empty (carries the original failure).
      assert_true(simplex_err.length() > 0)
    }
    _ => fail("expected NashFallbackExhausted, got a different NashCliError")
  } noraise {
    _ => fail("expected NashFallbackExhausted but solver returned a strategy")
  }
}

///|
/// Stage 1b green: `solve_with_fallback` retries via `@nash.fictitious_play`
/// when the primary simplex raises. The iterative result is accepted only
/// when `@nash.exploitability` < `config.tol` (default 0.05 winrate units).
test "fictitious_play fallback succeeds on degenerate 60x60 matrix" {
  let m = load_degenerate_fixture_60x60()
  let result = solve_with_fallback(m)
  inspect(result.solver_path, content="FictitiousPlay")
  // exploitability must be strictly below the default tolerance.
  assert_true(result.exploitability < 0.05)
  // value lives in [-1, +1] (winrate units).
  assert_true(result.value >= -1.0 && result.value <= 1.0)
  // Strategies are valid probability simplex points.
  let row = result.row_strategy.to_array()
  let col = result.col_strategy.to_array()
  assert_eq(row.length(), 60)
  assert_eq(col.length(), 60)
  let mut row_sum = 0.0
  for x in row {
    assert_true(x >= 0.0)
    row_sum += x
  }
  assert_true((row_sum - 1.0).abs() < 1.0e-6)
  let mut col_sum = 0.0
  for x in col {
    assert_true(x >= 0.0)
    col_sum += x
  }
  assert_true((col_sum - 1.0).abs() < 1.0e-6)
}
