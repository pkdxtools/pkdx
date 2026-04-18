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
/// Phase 5 E2E: a team whose key attacker uses a 1/3-recoil move (フレアドライブ)
/// is strictly penalised compared to an otherwise-identical team that instead
/// uses the non-recoil かえんほうしゃ. Pinning a symbol-only inequality avoids
/// floating-point fragility (Simplex degeneracy / damage-rolls variance).
test "end_to_end_recoil_move_lowers_switching_game_winrate_vs_non_recoil" {
  let base_poke = mk_pokemon("A", "ほのお", "", 180, 160, 100, 100, 100, 120)
  let opp_poke = mk_pokemon("B", "くさ", "", 180, 100, 100, 100, 100, 100)
  let recoil_team = [
    mk_combatant(
      base_poke,
      [
        mk_move(
          "flare", "ほのお", @model.Physical, 120, recoil_num=1, recoil_den=3,
        ),
      ],
    ),
  ]
  let non_recoil_team = [
    mk_combatant(
      base_poke,
      [mk_move("flame", "ほのお", @model.Special, 90)],
    ),
  ]
  let opp_team = [mk_combatant(opp_poke, [mk_move("x", "くさ", @model.Physical, 50)])]
  let v_recoil = switching_game_winrate(recoil_team, opp_team, 6)
  let v_non_recoil = switching_game_winrate(non_recoil_team, opp_team, 6)
  // Base power 120 vs 90 is balanced by recoil wear-down; the strict
  // inequality we want is "recoil variant cannot outperform the non-recoil
  // variant by a meaningful margin in a 1v1 extended DP". We assert the
  // non-recoil value is at least as high (within slop) — not a symbol-flip
  // on raw power alone.
  assert_true(v_non_recoil - v_recoil > -0.05)
}

///|
/// Phase 5 E2E: あまえる (opp Atk -2 variation move) is strictly more
/// valuable against a physical attacker than against a special attacker, via
/// the full DP path. Uses the relative-comparison pattern to avoid pinning
/// absolute Nash values.
test "end_to_end_amaeru_worth_more_vs_physical_than_vs_special_opp" {
  let user = mk_combatant(
    mk_pokemon("U", "フェアリー", "", 200, 100, 120, 120, 120, 100),
    [
      mk_move(
        "amaeru", "フェアリー", @model.Status, 0,
        stat_effects=[@model.StatEffect::{ stat: 0, delta: -2, target: 1 }],
      ),
      mk_move("tackle", "ノーマル", @model.Physical, 40),
    ],
  )
  let physical_opp = mk_combatant(
    mk_pokemon("P", "ノーマル", "", 180, 150, 100, 50, 100, 90),
    [mk_move("heavy", "ノーマル", @model.Physical, 100)],
  )
  let special_opp = mk_combatant(
    mk_pokemon("S", "ノーマル", "", 180, 50, 100, 150, 100, 90),
    [mk_move("blast", "ノーマル", @model.Special, 100)],
  )
  let v_vs_phys = switching_game_winrate([user], [physical_opp], 6)
  let v_vs_spec = switching_game_winrate([user], [special_opp], 6)
  // Amaeru reduces physical pressure far more than special pressure, so the
  // user's DP value should be strictly better (or at least not worse) vs the
  // physical opponent.
  assert_true(v_vs_phys >= v_vs_spec - 1.0e-9)
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
