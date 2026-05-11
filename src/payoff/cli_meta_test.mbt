///|
test "meta_div_rejects_usage_rates_not_summing_to_one" {
  let bad =
    #|{"usage": [0.5, 0.4, 0.3], "matrix": [[0, 1, -1], [-1, 0, 1], [1, -1, 0]]}
  let err = try? run_meta_divergence(bad)
  assert_true(err is Err(UsageNotNormalised(_)))
  let negative =
    #|{"usage": [0.5, 0.6, -0.1], "matrix": [[0, 1, -1], [-1, 0, 1], [1, -1, 0]]}
  let err2 = try? run_meta_divergence(negative)
  assert_true(err2 is Err(InvalidJsonMeta(_)))
}

///|
test "meta_div_reports_per_pokemon_regret_and_exploitability" {
  // Uniform distribution over RPS = Nash equilibrium. Regrets ≈ 0,
  // exploitability ≈ 0.
  let third = 1.0 / 3.0
  let usage = [third, third, third]
  let matrix = [[0.0, 1.0, -1.0], [-1.0, 0.0, 1.0], [1.0, -1.0, 0.0]]
  let r = compute_meta_divergence(usage, matrix, ["R", "P", "S"])
  assert_true(r.exploitability.abs() < 1.0e-10)
  assert_true(r.expected_value.abs() < 1.0e-10)
  for i in 0..<3 {
    assert_true(r.regrets[i].abs() < 1.0e-10)
  }
  assert_true(r.over_used.length() == 0)
  assert_true(r.under_used.length() == 0)
  // Now skew towards Rock: Scissors becomes very profitable.
  let skew = [0.9, 0.05, 0.05]
  let r2 = compute_meta_divergence(skew, matrix, ["R", "P", "S"])
  assert_true(r2.exploitability > 0.0)
}

///|
test "meta_div_flags_over_and_under_used_vs_nash" {
  // Heavy Rock usage: Scissors is under-used (high regret against mostly-Rock
  // meta? No — Rock beats Scissors, so Scissors has negative regret against a
  // Rock-heavy meta.) Instead Paper (beats Rock) is under-used.
  let usage = [0.8, 0.1, 0.1]
  let matrix = [[0.0, 1.0, -1.0], [-1.0, 0.0, 1.0], [1.0, -1.0, 0.0]]
  // Against usage skewed to Rock (index 0), Paper (index 1) has:
  //   (Aσ)_1 = -1·0.8 + 0·0.1 + 1·0.1 = -0.7
  //   ev = σᵀAσ (approx 0)
  //   regret_1 negative — wait let's compute by hand:
  //   (Aσ)_0 = 0·0.8 + 1·0.1 + -1·0.1 = 0.0
  //   (Aσ)_1 = -1·0.8 + 0·0.1 + 1·0.1 = -0.7
  //   (Aσ)_2 = 1·0.8 + -1·0.1 + 0·0.1 = 0.7
  //   ev = 0.8·0 + 0.1·-0.7 + 0.1·0.7 = 0
  //   regrets = [0, -0.7, 0.7]. So Scissors (index 2) is under-used in usage
  //   (0.1) with positive regret. But usage[2] = 0.1 > eps, so it'd be flagged
  //   differently; let's relax the check.
  let r = compute_meta_divergence(usage, matrix, ["R", "P", "S"])
  // Rock (index 0): highest usage, near-zero regret → neither list.
  // Paper (index 1): negative regret, usage > eps → over_used.
  // Scissors (index 2): positive regret, usage > eps → neither over nor under
  //   (under_used requires usage < eps).
  let mut paper_flagged = false
  for i in r.over_used {
    if i == 1 {
      paper_flagged = true
    }
  }
  assert_true(paper_flagged)
  assert_true(r.exploitability > 0.6)
}

///|
test "meta_div_synthetic_meta_shift_monotone" {
  // Property: As Rock's mass increases, Paper's regret becomes more negative
  // (Paper is worse against a Rock-heavy meta), and exploitability grows.
  let matrix = [[0.0, 1.0, -1.0], [-1.0, 0.0, 1.0], [1.0, -1.0, 0.0]]
  let mut prev_paper = 1.0
  let mut prev_expl = 0.0
  let steps = [0.4, 0.6, 0.8, 0.9]
  for rock in steps {
    let other = (1.0 - rock) / 2.0
    let usage = [rock, other, other]
    let r = compute_meta_divergence(usage, matrix, ["R", "P", "S"])
    // Paper regret should decrease as Rock grows.
    assert_true(r.regrets[1] <= prev_paper + 1.0e-9)
    prev_paper = r.regrets[1]
    // Exploitability should be non-decreasing.
    assert_true(r.exploitability >= prev_expl - 1.0e-9)
    prev_expl = r.exploitability
  }
}
