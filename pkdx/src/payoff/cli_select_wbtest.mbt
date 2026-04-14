///|
/// Whitebox tests for `parse_model` — the MonteCarloSim string format is a
/// first-party CLI contract, so it is tested directly rather than through the
/// JSON round-trip.

///|
test "parse_model_recognizes_monte_carlo_string_with_trials_and_seed" {
  let m = parse_model("monte_carlo:1000:42")
  match m {
    MonteCarloSim(trials, seed) => {
      assert_eq(trials, 1000)
      assert_eq(seed, 42UL)
    }
    _ => assert_true(false)
  }
}

///|
test "parse_model_rejects_malformed_monte_carlo_strings" {
  let cases = [
    "monte_carlo",
    "monte_carlo:1000",
    "monte_carlo:abc:42",
    "monte_carlo:0:42",
  ]
  for s in cases {
    let errored = try {
      let _ = parse_model(s)
      false
    } catch {
      _ => true
    }
    assert_true(errored)
  }
}

///|
test "parse_team_payoff_model_recognizes_pairwise_and_switching_game_strings" {
  match parse_team_payoff_model("pairwise:best1v1") {
    Pairwise(Best1v1) => ()
    _ => assert_true(false)
  }
  match parse_team_payoff_model("pairwise:nash_responses") {
    Pairwise(NashResponses) => ()
    _ => assert_true(false)
  }
  match parse_team_payoff_model("pairwise:monte_carlo:100:42") {
    Pairwise(MonteCarloSim(100, 42UL)) => ()
    _ => assert_true(false)
  }
  match parse_team_payoff_model("switching_game:3") {
    SwitchingGame(3) => ()
    _ => assert_true(false)
  }
  // Malformed cases
  let errored = try {
    let _ = parse_team_payoff_model("switching_game:abc")
    false
  } catch {
    _ => true
  }
  assert_true(errored)
  let errored2 = try {
    let _ = parse_team_payoff_model("unknown:3")
    false
  } catch {
    _ => true
  }
  assert_true(errored2)
}
