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
