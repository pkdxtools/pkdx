///|
/// Tests for team-level Monte Carlo rollout used by the Screened pipeline.
/// Covers only team-specific behaviour (all-KO terminals, HP-ratio draw,
/// forced switch, determinism). Lower-level 1v1 MC semantics (ε-greedy
/// sampling, RNG determinism, turn order) live in `monte_carlo_test.mbt`.

///|
/// Dominant attacker: one-shots the 100-HP dummy with STAB 150 BP move.
fn build_dominant_team(label_prefix : String) -> Array[Combatant] {
  let mv = mk_move("はかいこうせん", "ノーマル", @model.Physical, 150)
  let team = Array::make(3, mk_combatant(
    mk_pokemon("dummy", "ノーマル", "", 100, 200, 100, 100, 100, 200),
    [mv],
  ))
  for i in 0..<3 {
    team[i] = mk_combatant(
      mk_pokemon(
        label_prefix + i.to_string(),
        "ノーマル",
        "",
        100,
        200,
        100,
        100,
        100,
        200,
      ),
      [mv],
    )
  }
  team
}

///|
/// Fragile target: 1 HP, 1 offence, slow — guaranteed to get OHKO'd.
fn build_fragile_team(label_prefix : String) -> Array[Combatant] {
  let mv = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let team = Array::make(3, mk_combatant(
    mk_pokemon("dummy", "ノーマル", "", 1, 1, 1, 1, 1, 1),
    [mv],
  ))
  for i in 0..<3 {
    team[i] = mk_combatant(
      mk_pokemon(
        label_prefix + i.to_string(),
        "ノーマル",
        "",
        1,
        1,
        1,
        1,
        1,
        1,
      ),
      [mv],
    )
  }
  team
}

///|
test "team_monte_carlo_value_returns_plus_one_when_own_dominates" {
  let own = build_dominant_team("D")
  let opp = build_fragile_team("F")
  let v = team_monte_carlo_value(own, opp, 1, 123UL)
  assert_eq(v, 1.0)
}

///|
test "team_monte_carlo_value_returns_minus_one_when_opponent_dominates" {
  let own = build_fragile_team("F")
  let opp = build_dominant_team("D")
  let v = team_monte_carlo_value(own, opp, 1, 123UL)
  assert_eq(v, -1.0)
}

///|
test "team_monte_carlo_value_stays_in_signed_unit_range" {
  let own = build_dominant_team("D")
  let opp = build_fragile_team("F")
  let v = team_monte_carlo_value(own, opp, 8, 42UL)
  assert_true(v >= -1.0 && v <= 1.0)
}

///|
test "team_monte_carlo_value_is_deterministic_for_same_seed" {
  let own = build_dominant_team("D")
  let opp = build_fragile_team("F")
  let v1 = team_monte_carlo_value(own, opp, 16, 7UL)
  let v2 = team_monte_carlo_value(own, opp, 16, 7UL)
  assert_eq(v1, v2)
}

///|
test "team_monte_carlo_value_zero_trials_returns_zero" {
  let own = build_dominant_team("D")
  let opp = build_fragile_team("F")
  let v = team_monte_carlo_value(own, opp, 0, 42UL)
  assert_eq(v, 0.0)
}

///|
test "team_rollout_single_trial_matches_monte_carlo_value_for_trivial_case" {
  // 1 trial の team_monte_carlo_value は team_rollout の結果と一致する。
  let own = build_dominant_team("D")
  let opp = build_fragile_team("F")
  let rng = seeded_rng(99UL)
  let v_rollout = team_rollout(own, opp, rng)
  let v_mc = team_monte_carlo_value(own, opp, 1, 99UL)
  assert_eq(v_rollout, v_mc)
}

///|
/// Regression: the MC rollout must honour same-turn sleep from a faster
/// status move. Previously `mc_try_apply_status` ran after the target's
/// attempt phase was already resolved, so the faster Spore user still took
/// a tackle on turn 1 before the sleep counter took effect. The fix
/// short-circuits the slower side's attack when its status changes mid-turn
/// from None to Sleep.
test "team_rollout: faster Spore prevents slower target from attacking on the turn it lands" {
  let own_p = mk_pokemon("sleeper", "ノーマル", "", 200, 100, 100, 100, 100, 120)
  let opp_p = mk_pokemon("hitter", "ノーマル", "", 200, 100, 100, 100, 100, 60)
  let spore = mk_move(
    "キノコのほうし", "くさ", @model.Status, 0,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  let own = [mk_combatant(own_p, [spore])]
  let opp = [mk_combatant(opp_p, [tackle])]
  let rng = seeded_rng(42UL)
  let v = team_rollout(own, opp, rng, turn_limit=3, epsilon=0.0)
  // With the fix, opp never gets to attack: turn 1 is blocked mid-turn by the
  // freshly-inflicted Sleep, and turns 2–3 are skipped by the pre-turn sleep
  // counter decrement. Both sides end at full HP, giving a clean 0.0 draw.
  // Without the fix, opp's turn-1 tackle resolves before the sleep fan-out
  // runs, so own takes damage and the rollout value is strictly negative.
  assert_eq(v, 0.0)
}

///|
test "team_rollout_handles_hp_ratio_draw_at_turn_limit_one" {
  // 両者ともに turn_limit=1 で KO しない構成。終了時は HP 比の差分で value を返す。
  let mv = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let own = Array::make(3, mk_combatant(
    mk_pokemon("O0", "ノーマル", "", 300, 100, 100, 100, 100, 100),
    [mv],
  ))
  let opp = Array::make(3, mk_combatant(
    mk_pokemon("P0", "ノーマル", "", 300, 100, 100, 100, 100, 100),
    [mv],
  ))
  let rng = seeded_rng(3UL)
  let v = team_rollout(own, opp, rng, turn_limit=1, epsilon=0.0)
  // 1 turn で双方生存 → HP 比 diff は [-1, +1] に収まる絶対値 ≤ 0.5 程度の小さな値
  assert_true(v >= -0.5 && v <= 0.5)
}
