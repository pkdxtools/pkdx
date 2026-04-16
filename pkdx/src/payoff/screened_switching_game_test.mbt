///|
/// Integration tests for the `team_payoff_matrix_screened` 2-stage pipeline.
/// Focuses on structural / contractual properties only — per-phase behaviour
/// (team MC rollout, SwitchingGame value recursion) is covered elsewhere.

///|
fn build_screen_team(label : String) -> Array[Combatant] {
  let mv = mk_move("のしかかり", "ノーマル", @model.Physical, 85)
  let team = Array::make(4, mk_combatant(
    mk_pokemon("dummy", "ノーマル", "", 100, 100, 80, 80, 80, 100),
    [mv],
  ))
  for i in 0..<4 {
    team[i] = mk_combatant(
      mk_pokemon(
        label + i.to_string(),
        "ノーマル",
        "",
        100,
        100 + i * 5,
        80,
        80,
        80,
        100 + i * 3,
      ),
      [mv],
    )
  }
  team
}

///|
test "team_payoff_matrix_screened_bit_exact_when_keep_top_one" {
  // keep_top >= 1.0 は short-circuit 経路で team_payoff_matrix_switching に
  // フォールスルーする。値・形状の両方で bit-exact 一致を要求する。
  let team = build_screen_team("A")
  let opp = build_screen_team("B")
  let (screened, rows, cols) = team_payoff_matrix_screened(
    team, opp, Single, 10, 42UL, 1.0, refine_turn_limit=1, mc_turn_limit=1,
  )
  let oracle = team_payoff_matrix_with_team_model(
    team, opp, Single, SwitchingGame(1),
  )
  assert_eq(screened.rows(), oracle.rows())
  assert_eq(screened.cols(), oracle.cols())
  for i in 0..<screened.rows() {
    for j in 0..<screened.cols() {
      assert_eq(screened.at(i, j), oracle.at(i, j))
    }
  }
  // Full retention: retained indices are the identity.
  assert_eq(rows.length(), oracle.rows())
  assert_eq(cols.length(), oracle.cols())
  for i in 0..<rows.length() {
    assert_eq(rows[i], i)
  }
  for j in 0..<cols.length() {
    assert_eq(cols[j], j)
  }
}

///|
test "team_payoff_matrix_screened_retained_count_matches_ceil_of_quantile" {
  let team = build_screen_team("A")
  let opp = build_screen_team("B")
  // C(4, 3) = 4 selections on each side. keep_top = 0.5 → ceil(4 * 0.5) = 2.
  let (_, rows, cols) = team_payoff_matrix_screened(
    team, opp, Single, 10, 11UL, 0.5, refine_turn_limit=1, mc_turn_limit=1,
  )
  assert_eq(rows.length(), 2)
  assert_eq(cols.length(), 2)
}

///|
test "team_payoff_matrix_screened_retained_indices_are_sorted_ascending" {
  let team = build_screen_team("A")
  let opp = build_screen_team("B")
  let (_, rows, cols) = team_payoff_matrix_screened(
    team, opp, Single, 10, 11UL, 0.5, refine_turn_limit=1, mc_turn_limit=1,
  )
  for i in 1..<rows.length() {
    assert_true(rows[i - 1] < rows[i])
  }
  for j in 1..<cols.length() {
    assert_true(cols[j - 1] < cols[j])
  }
}

///|
test "team_payoff_matrix_screened_retained_count_is_monotonic_in_keep_top" {
  let team = build_screen_team("A")
  let opp = build_screen_team("B")
  let (_, rows_low, _) = team_payoff_matrix_screened(
    team, opp, Single, 10, 11UL, 0.3, refine_turn_limit=1, mc_turn_limit=1,
  )
  let (_, rows_high, _) = team_payoff_matrix_screened(
    team, opp, Single, 10, 11UL, 0.8, refine_turn_limit=1, mc_turn_limit=1,
  )
  assert_true(rows_low.length() < rows_high.length())
}

///|
test "team_payoff_matrix_screened_keeps_nash_weighted_rows" {
  let team = build_screen_team("A")
  let opp = build_screen_team("B")
  let (_, retained_rows, _) = team_payoff_matrix_screened(
    team, opp, Single, 10, 11UL, 0.5, refine_turn_limit=1, mc_turn_limit=1,
  )
  assert_eq(retained_rows.length(), 2)
}

///|
test "screen_nash_scores_preserves_support_that_mean_would_drop" {
  // RPS-like 3x3 matrix where row 0 is a specialist: low mean but in Nash
  // support. Mean-based keep_top=2/3 would drop r0 (mean ≈ 0.033, lowest).
  // Nash-weighted scoring assigns equal scores to all support rows (= game
  // value), so all 3 survive any quantile ≥ 1/3.
  let screen = [
    [0.9, -0.4, -0.4],
    [-0.2, 0.6, 0.0],
    [-0.2, 0.0, 0.6],
  ]
  let (row_scores, _) = screen_nash_scores(screen, 3, 3)
  let tol = 1.0e-4
  // All Nash-support rows must have equal score (= game value).
  assert_true((row_scores[0] - row_scores[1]).abs() < tol)
  assert_true((row_scores[0] - row_scores[2]).abs() < tol)
  // Verify mean-based would have been different: r0 mean < r1 mean.
  let mean_r0 = (0.9 + -0.4 + -0.4) / 3.0
  let mean_r1 = (-0.2 + 0.6 + 0.0) / 3.0
  assert_true(mean_r0 < mean_r1)
}
