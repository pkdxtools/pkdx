///|
/// Cross-cutting E2E tests: build 6v6 combatants → team payoff matrix → Nash
/// → selection distribution. After the removal of pairwise `PayoffModel`
/// only `SwitchingGame(1)` / `ScreenedSwitchingGame(1)` exercise this path.

///|
/// Build a deterministic 6-member test team keyed by the given speeds.
fn build_6_team(label_prefix : String, speeds : Array[Int]) -> Array[Combatant] {
  let mv = mk_move("のしかかり", "ノーマル", @model.Physical, 85)
  let team = Array::make(6, mk_combatant(
    mk_pokemon("dummy", "ノーマル", "", 100, 100, 80, 80, 80, 100),
    [mv],
  ))
  for i in 0..<6 {
    team[i] = mk_combatant(
      mk_pokemon(
        label_prefix + i.to_string(),
        "ノーマル",
        "",
        100,
        100,
        80,
        80,
        80,
        speeds[i],
      ),
      [mv],
    )
  }
  team
}

///|
test "end_to_end_select_with_switching_game_model_returns_valid_distribution" {
  let team = build_6_team("T", [100, 95, 105, 90, 110, 85])
  let opp = build_6_team("O", [100, 100, 100, 100, 100, 100])
  let team_m = team_payoff_matrix_with_team_model(
    team, opp, Single, SwitchingGame(1),
  )
  assert_true(team_m.rows() == 20 && team_m.cols() == 20)
  let lp = @nash.solve_zero_sum(team_m)
  match lp {
    Optimal(row_strategy~, value~, ..) => {
      assert_true(value.is_nan() == false)
      let arr = row_strategy.to_array()
      assert_true(arr.length() == 20)
      let mut total = 0.0
      for x in arr {
        total += x
      }
      assert_true((total - 1.0).abs() < 1.0e-6)
    }
    _ => assert_true(false)
  }
}

///|
test "end_to_end_switching_game_reproducibility_same_inputs" {
  let team = build_6_team("T", [100, 95, 105, 90, 110, 85])
  let opp = build_6_team("O", [102, 101, 100, 99, 98, 97])
  let m1 = team_payoff_matrix_with_team_model(
    team, opp, Single, SwitchingGame(1),
  )
  let m2 = team_payoff_matrix_with_team_model(
    team, opp, Single, SwitchingGame(1),
  )
  for i in 0..<20 {
    for j in 0..<20 {
      assert_eq(m1.at(i, j), m2.at(i, j))
    }
  }
  let r1 = @nash.solve_zero_sum(m1)
  let r2 = @nash.solve_zero_sum(m2)
  match (r1, r2) {
    (
      Optimal(value=v1, row_strategy=p1, col_strategy=q1),
      Optimal(value=v2, row_strategy=p2, col_strategy=q2),
    ) => {
      assert_true(v1 == v2)
      for i in 0..<20 {
        assert_true(p1.at(i) == p2.at(i))
        assert_true(q1.at(i) == q2.at(i))
      }
    }
    _ => assert_true(false)
  }
}
