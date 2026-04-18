///|
/// Whitebox tests for the `team_payoff_model` CLI string parser.

///|
test "parse_team_payoff_model_recognizes_switching_game_string" {
  match parse_team_payoff_model("switching_game") {
    SwitchingGame(n) => assert_eq(n, DP_TURN_LIMIT)
    _ => assert_true(false)
  }
}

///|
test "parse_team_payoff_model_rejects_unknown_prefix" {
  let errored = try {
    let _ = parse_team_payoff_model("unknown:3")
    false
  } catch {
    _ => true
  }
  assert_true(errored)
}

///|
test "parse_team_payoff_model_accepts_switching_game_with_turn_limit" {
  match parse_team_payoff_model("switching_game:3") {
    SwitchingGame(3) => ()
    _ => assert_true(false)
  }
}

///|
test "parse_team_payoff_model_recognizes_screened_switching_game_string" {
  match parse_team_payoff_model("screened_switching_game:1000:42:0.3") {
    ScreenedSwitchingGame(trials, seed, keep_top, refine_tl) => {
      assert_eq(trials, 1000)
      assert_eq(seed, 42UL)
      assert_true((keep_top - 0.3).abs() < 1.0e-9)
      assert_eq(refine_tl, DP_TURN_LIMIT)
    }
    _ => assert_true(false)
  }
}

///|
test "parse_team_payoff_model_rejects_screened_switching_game_with_keep_top_zero" {
  let errored = try {
    let _ = parse_team_payoff_model("screened_switching_game:1000:42:0.0")
    false
  } catch {
    _ => true
  }
  assert_true(errored)
}

///|
test "parse_team_payoff_model_rejects_screened_switching_game_with_trials_zero" {
  let errored = try {
    let _ = parse_team_payoff_model("screened_switching_game:0:42:0.3")
    false
  } catch {
    _ => true
  }
  assert_true(errored)
}

///|
test "parse_team_payoff_model_rejects_screened_switching_game_with_keep_top_above_one" {
  let errored = try {
    let _ = parse_team_payoff_model("screened_switching_game:1000:42:1.5")
    false
  } catch {
    _ => true
  }
  assert_true(errored)
}

///|
test "auto_upgrade_keeps_switching_game_below_threshold" {
  match auto_upgrade_team_model(SwitchingGame(3)) {
    SwitchingGame(3) => ()
    _ => assert_true(false)
  }
  match auto_upgrade_team_model(SwitchingGame(4)) {
    SwitchingGame(4) => ()
    _ => assert_true(false)
  }
}

///|
test "auto_upgrade_promotes_switching_game_at_or_above_threshold" {
  match auto_upgrade_team_model(SwitchingGame(AUTO_SCREEN_TURN_LIMIT)) {
    ScreenedSwitchingGame(trials, seed, keep_top, refine_tl) => {
      assert_eq(trials, AUTO_SCREEN_TRIALS)
      assert_eq(seed, AUTO_SCREEN_SEED)
      assert_true((keep_top - AUTO_SCREEN_KEEP_TOP).abs() < 1.0e-9)
      assert_eq(refine_tl, AUTO_SCREEN_TURN_LIMIT)
    }
    _ => assert_true(false)
  }
  match auto_upgrade_team_model(SwitchingGame(10)) {
    ScreenedSwitchingGame(_, _, _, refine_tl) => assert_eq(refine_tl, 10)
    _ => assert_true(false)
  }
}

///|
test "auto_upgrade_preserves_explicit_screened_switching_game" {
  let explicit = ScreenedSwitchingGame(500, 7UL, 0.5, 8)
  match auto_upgrade_team_model(explicit) {
    ScreenedSwitchingGame(trials, seed, keep_top, refine_tl) => {
      assert_eq(trials, 500)
      assert_eq(seed, 7UL)
      assert_true((keep_top - 0.5).abs() < 1.0e-9)
      assert_eq(refine_tl, 8)
    }
    _ => assert_true(false)
  }
}
