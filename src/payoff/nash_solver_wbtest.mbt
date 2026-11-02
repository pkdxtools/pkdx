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
  let raw = match
    @db.read_file("tests/fixtures/nash_simplex_failure_60x60.json") {
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

///|
/// Deterministic value in [-1, 1]. The multipliers stay inside 32-bit `Int`.
fn det_unit(i : Int, j : Int, seed : Int) -> Double {
  let mut x = i * 37 + j * 91 + seed * 17 + 123
  x = x % 997
  if x < 0 {
    x = x + 997
  }
  x = (x * 131 + seed + 17) % 1000
  if x < 0 {
    x = x + 1000
  }
  (x - 500).to_double() / 500.0
}

///|
/// 16×16 matrix whose entries are `scale * det_unit(i, j, seed)`.
///
/// Seed 20 at `scale = 1e-10` is a zero matrix plus 1e-10 noise. The same
/// pattern at `scale = 1` is an ordinary mixed game that simplex solves, so
/// the LP failure is the noise scale (entries sit between the simplex pivot
/// epsilon and the optimality epsilon), not a missing equilibrium.
fn scaled_noise_matrix(
  n : Int,
  seed : Int,
  scale : Double,
) -> @nash.FiniteMatrix {
  let rows = Array::make(n, ([] : Array[Double]))
  for i in 0..<n {
    let row = Array::make(n, 0.0)
    for j in 0..<n {
      row[j] = scale * det_unit(i, j, seed)
    }
    rows[i] = row
  }
  match @nash.FiniteMatrix::new(rows) {
    Ok(m) => m
    Err(_) => abort("scaled noise matrix was rejected")
  }
}

///|
/// The 16×16 / 1e-10 case `solve_zero_sum` currently reports as
/// `InconsistentGame("col LP unbounded")`.
fn inconsistent_noise_matrix_16() -> @nash.FiniteMatrix {
  scaled_noise_matrix(16, 20, 1.0e-10)
}

///|
fn matrix_json(m : @nash.FiniteMatrix, extra : String) -> String {
  let mut s = "{\"matrix\":["
  for i in 0..<m.rows() {
    if i > 0 {
      s = s + ","
    }
    s = s + "["
    for j in 0..<m.cols() {
      if j > 0 {
        s = s + ","
      }
      s = s + m.at(i, j).to_string()
    }
    s = s + "]"
  }
  s + "]" + extra + "}"
}

///|
fn assert_prob(xs : Array[Double], n : Int) -> Unit raise {
  assert_eq(xs.length(), n)
  let mut sum = 0.0
  for x in xs {
    assert_true(x >= 0.0)
    sum = sum + x
  }
  assert_true((sum - 1.0).abs() < 1.0e-6)
}

///|
test "scaled noise at O(1) still takes the simplex path" {
  // Same generator as the InconsistentGame fixture, without the 1e-10 scale.
  // Locks the claim that this pattern has an equilibrium simplex can return,
  // and that a successful simplex is still reported as Simplex / expl 0.
  let m = scaled_noise_matrix(16, 20, 1.0)
  let result = solve_with_fallback(m)
  inspect(result.solver_path, content="Simplex")
  inspect(result.exploitability, content="0")
  assert_true(!result.value.is_nan())
  assert_prob(result.row_strategy.to_array(), 16)
  assert_prob(result.col_strategy.to_array(), 16)
}

///|
test "16x16 1e-10 noise: solve_zero_sum raises InconsistentGame col LP unbounded" {
  let m = inconsistent_noise_matrix_16()
  assert_eq(m.rows(), 16)
  assert_eq(m.cols(), 16)
  try {
    let _ = @nash.solve_zero_sum(m)
    fail("expected InconsistentGame")
  } catch {
    @nash.InconsistentGame(msg) =>
      assert_true(msg.contains("col LP unbounded"))
    other => fail("expected InconsistentGame, got " + other.to_string())
  }
}

///|
test "16x16 1e-10 noise: solve_with_fallback accepts fictitious play under tol" {
  let m = inconsistent_noise_matrix_16()
  let result = solve_with_fallback(m)
  inspect(result.solver_path, content="FictitiousPlay")
  // Default tol is 0.05. Payoffs are O(1e-10), so a real equilibrium is far
  // below that; require a tight residual so a uniform guess cannot pass.
  assert_true(result.exploitability < 0.05)
  assert_true(result.exploitability < 1.0e-9)
  assert_true(!result.value.is_nan())
  assert_true(result.value.abs() < 1.0e-8)
  assert_prob(result.row_strategy.to_array(), 16)
  assert_prob(result.col_strategy.to_array(), 16)
}

///|
/// Payoffs are O(1e-10), and 100 iterations of either learner land near
/// 1e-11. `tol = 1e-12` is below both, so the chain must raise rather than
/// return a strategy. The carried error is the original `InconsistentGame`,
/// not a `SimplexFailure`.
test "16x16 1e-10 noise: tight tol raises NashFallbackExhausted" {
  let m = inconsistent_noise_matrix_16()
  let tight : NashSolverConfig = { tol: 1.0e-12, iterations: 100 }
  try solve_with_fallback(m, config=tight) catch {
    NashFallbackExhausted(simplex_err~, fp_expl~, mwu_expl~) => {
      assert_true(simplex_err.contains("InconsistentGame"))
      assert_true(simplex_err.contains("col LP unbounded"))
      assert_true(fp_expl >= 1.0e-12)
      assert_true(mwu_expl >= 1.0e-12)
    }
    _ => fail("expected NashFallbackExhausted, got a different NashCliError")
  } noraise {
    _ => fail("expected NashFallbackExhausted but solver returned a strategy")
  }
}

///|
test "nash solve path: 16x16 1e-10 noise falls back with expl < tol" {
  let input = matrix_json(inconsistent_noise_matrix_16(), "")
  let out = run_nash_solve(input)
  let parsed = @json.parse(out) catch {
    _ => abort("nash solve output is not json")
  }
  match parsed {
    Object(obj) => {
      match obj.get("nash_solver") {
        Some(String(s)) => assert_eq(s, "fictitious_play")
        _ => fail("nash_solver missing")
      }
      match obj.get("exploitability") {
        Some(Number(expl, ..)) => {
          assert_true(expl < 0.05)
          assert_true(expl < 1.0e-9)
        }
        _ => fail("exploitability missing")
      }
      match obj.get("row_strategy") {
        Some(Array(arr)) => assert_eq(arr.length(), 16)
        _ => fail("row_strategy missing")
      }
      match obj.get("col_strategy") {
        Some(Array(arr)) => assert_eq(arr.length(), 16)
        _ => fail("col_strategy missing")
      }
    }
    _ => fail("nash solve output is not an object")
  }
}

///|
test "nash solve path: 16x16 1e-10 noise tight tol raises NashFallbackExhausted" {
  let input = matrix_json(
    inconsistent_noise_matrix_16(),
    ",\"nash_solver_config\":{\"tol\":1e-12,\"iterations\":100}",
  )
  try run_nash_solve(input) catch {
    NashFallbackExhausted(simplex_err~, fp_expl~, mwu_expl~) => {
      assert_true(simplex_err.contains("col LP unbounded"))
      assert_true(fp_expl >= 1.0e-12)
      assert_true(mwu_expl >= 1.0e-12)
    }
    _ => fail("expected NashFallbackExhausted, got a different NashCliError")
  } noraise {
    _ => fail("expected run_nash_solve to raise")
  }
}

///|
/// `build_select_result` is the select boundary that calls
/// `solve_with_fallback`. select's public JSON API builds the payoff from
/// teams, so the noisy matrix is injected here with an empty roster; the
/// solver still runs on that matrix and the serialized `nash_solver` tag is
/// the one `pkdx select` prints.
test "select path: 16x16 1e-10 noise falls back with expl < tol" {
  let m = inconsistent_noise_matrix_16()
  let result = build_select_result(Single, [], [], m, None, None)
  inspect(result.solver_path, content="FictitiousPlay")
  assert_true(result.exploitability < 0.05)
  assert_true(result.exploitability < 1.0e-9)
  assert_prob(result.row_strategy, 16)
  assert_prob(result.col_strategy, 16)
  let json = serialize_select_result(result)
  assert_true(json.contains("\"nash_solver\":\"fictitious_play\""))
}

///|
test "select path: 16x16 1e-10 noise tight tol raises NashFallbackExhausted" {
  let m = inconsistent_noise_matrix_16()
  let tight : NashSolverConfig = { tol: 1.0e-12, iterations: 100 }
  try build_select_result(Single, [], [], m, None, None, nash_config=tight) catch {
    NashFallbackExhausted(simplex_err~, fp_expl~, mwu_expl~) => {
      assert_true(simplex_err.contains("col LP unbounded"))
      assert_true(fp_expl >= 1.0e-12)
      assert_true(mwu_expl >= 1.0e-12)
    }
    _ => fail("expected NashFallbackExhausted, got a different NashCliError")
  } noraise {
    _ => fail("expected build_select_result to raise")
  }
}

///|
/// Invalid matrices never become a fallback. `FiniteMatrix::new` rejects
/// empty input and non-finite entries; the CLI rejects an empty matrix as
/// `InvalidJson` before `solve_with_fallback`.
test "empty and non-finite matrices stay hard errors" {
  match @nash.FiniteMatrix::new([]) {
    Err(@nash.Empty) => ()
    Ok(_) => fail("empty matrix was accepted")
    Err(other) => fail("expected Empty, got " + other.to_string())
  }
  // 0/0 and 1/0 are the non-finite values FiniteMatrix::new must reject.
  // They never reach the fallback chain.
  let nan_row = [0.0 / 0.0, 0.0]
  match @nash.FiniteMatrix::new([nan_row, [0.0, 0.0]]) {
    Err(@nash.NonFinite) => ()
    Ok(_) => fail("NaN matrix was accepted")
    Err(_) => fail("expected NonFinite for NaN")
  }
  let inf_row = [1.0 / 0.0, 0.0]
  match @nash.FiniteMatrix::new([inf_row, [0.0, 0.0]]) {
    Err(@nash.NonFinite) => ()
    Ok(_) => fail("Inf matrix was accepted")
    Err(_) => fail("expected NonFinite for Inf")
  }
  try run_nash_solve("{\"matrix\":[]}") catch {
    InvalidJson(msg) => assert_true(msg.contains("non-empty"))
    NashFallbackExhausted(_) =>
      fail("empty matrix must not enter the fallback")
    _ => fail("expected InvalidJson for an empty matrix")
  } noraise {
    _ => fail("expected run_nash_solve to raise on an empty matrix")
  }
}
