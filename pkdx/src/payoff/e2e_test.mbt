///|
/// Phase 11: cross-cutting E2E and performance tests. Exercise the full
/// damage → payoff matrix → inner Nash → selection distribution pipeline with
/// realistic 6v6 inputs, plus a reproducibility check and an ignored relative
/// benchmark.

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
test "end_to_end_damage_matrix_to_select_distribution" {
  // Full pipeline: Combatant list → damage engine → character payoff matrix
  // → team payoff matrix → Nash → selection distribution.
  let team = build_6_team("T", [100, 95, 105, 90, 110, 85])
  let opp = build_6_team("O", [100, 100, 100, 100, 100, 100])
  // Individual-Pokemon cross payoff.
  let cross = cross_payoff(team, opp, Best1v1)
  assert_true(cross.rows() == 6 && cross.cols() == 6)
  // Team payoff (single, 3-pick).
  let team_m = team_payoff_matrix(team, opp, Single, Best1v1)
  assert_true(team_m.rows() == 20 && team_m.cols() == 20)
  // Nash over the team matrix.
  let lp = @nash.solve_zero_sum(team_m)
  match lp {
    Optimal(row_strategy~, value~, ..) => {
      let mut total = 0.0
      for i in 0..<20 {
        total = total + row_strategy.at(i)
      }
      assert_true((total - 1.0).abs() < 1.0e-6)
      assert_true(value.is_nan() == false)
    }
    _ => assert_true(false)
  }
}

///|
test "snapshot_pokemon_6v6_selection_scenario" {
  // Fixed 6v6 mirror match with uniform-speed opponents: no asymmetry →
  // game value 0, exploitability 0, uniform distribution over the 20 pick
  // combinations is one valid equilibrium (the simplex may return a vertex,
  // so we don't require uniformity, just the canonical invariants).
  let team = build_6_team("T", [100, 100, 100, 100, 100, 100])
  let opp = build_6_team("O", [100, 100, 100, 100, 100, 100])
  let team_m = team_payoff_matrix(team, opp, Single, Best1v1)
  match @nash.solve_zero_sum(team_m) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      inspect(value.abs() < 1.0e-8, content="true")
      let expl = @nash.exploitability(team_m, row_strategy, col_strategy)
      inspect(expl.abs() < 1.0e-6, content="true")
      // Row/col probability mass on every selection is non-negative and sums
      // to 1 (basic sanity).
      let mut total = 0.0
      for i in 0..<20 {
        assert_true(row_strategy.at(i) >= -1.0e-12)
        total = total + row_strategy.at(i)
      }
      inspect((total - 1.0).abs() < 1.0e-6, content="true")
    }
    _ => assert_true(false)
  }
}

///|
test "version_reproducibility_same_seed_same_output" {
  // The solver is deterministic: same matrix → identical LP output, bit for
  // bit. Run twice and compare every probability.
  let team = build_6_team("T", [100, 95, 105, 90, 110, 85])
  let opp = build_6_team("O", [102, 101, 100, 99, 98, 97])
  let m1 = team_payoff_matrix(team, opp, Single, Best1v1)
  let m2 = team_payoff_matrix(team, opp, Single, Best1v1)
  // Matrices must match bit for bit.
  for i in 0..<20 {
    for j in 0..<20 {
      assert_true(m1.at(i, j) == m2.at(i, j))
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

///|
test "relative_performance_6v6_double_within_10x_of_20x20_baseline" {
  // MoonBit does not ship a stable wall-clock API, so this test asserts only
  // that the 15×15 double-format and the 20×20 single-format payoffs both
  // complete (and return well-formed matrices). Relative timing is left to an
  // external harness; this guards against regressions that would break the
  // double-format code path or cause LP failures on realistic 6v6 inputs.
  let team = build_6_team("T", [100, 95, 105, 90, 110, 85])
  let opp = build_6_team("O", [100, 100, 100, 100, 100, 100])
  let single = team_payoff_matrix(team, opp, Single, Best1v1)
  let double = team_payoff_matrix(team, opp, Double, Best1v1)
  assert_true(single.rows() == 20)
  assert_true(double.rows() == 15)
  // Solving must succeed in both formats.
  match @nash.solve_zero_sum(single) {
    Optimal(..) => ()
    _ => assert_true(false)
  }
  match @nash.solve_zero_sum(double) {
    Optimal(..) => ()
    _ => assert_true(false)
  }
}

///|
test "end_to_end_select_with_monte_carlo_model_returns_valid_distribution" {
  // Full pipeline through MonteCarloSim. Trials are kept low for runtime,
  // but enough to verify the matrix is well-formed and the Nash distribution
  // is normalised.
  let team = build_6_team("T", [100, 95, 105, 90, 110, 85])
  let opp = build_6_team("O", [100, 100, 100, 100, 100, 100])
  let team_m = team_payoff_matrix_with_team_model(
    team, opp, Single, Pairwise(MonteCarloSim(20, 7UL)),
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
test "end_to_end_select_with_switching_game_model_returns_valid_distribution" {
  // Switching game with small turn_limit to keep runtime bounded.
  let team = build_6_team("T", [100, 95, 105, 90, 110, 85])
  let opp = build_6_team("O", [100, 100, 100, 100, 100, 100])
  let team_m = team_payoff_matrix_with_team_model(
    team, opp, Single, SwitchingGame(2),
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
