///|
/// Whitebox tests for `solve_with_fallback`. Stage 1a covers the primary
/// simplex path only — the fallback chain (fictitious_play / mwu) is wired in
/// later commits.

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
