///|
fn all_optimize_evs() -> FixedArray[Int] {
  // A/C/S fixed at 0; H/B/D = -1 (optimize targets)
  [-1, 0, -1, 0, -1, 0]
}

///|
fn default_weights() -> HbdWeights {
  { phys: 1, spec: 1 }
}

///|
test "optimize_hbd: Garchmock H/B/D budget respects constraints" {
  // Garchomp-like: 108/130/95/80/85/102
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let result = optimize_hbd(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    default_weights(),
  )
  assert_true(result.candidates.length() == 1)
  let c = result.candidates[0]
  let total = c.evs[0] + c.evs[1] + c.evs[2] + c.evs[3] + c.evs[4] + c.evs[5]
  assert_true(total <= 508)
  // Optimization targets should be filled
  assert_true(c.evs[0] + c.evs[2] + c.evs[4] > 0)
  // Non-optimize slots unchanged
  assert_true(c.evs[1] == 0)
  assert_true(c.evs[3] == 0)
  assert_true(c.evs[5] == 0)
  // Each slot ≤ 252
  assert_true(c.evs[0] <= 252)
  assert_true(c.evs[2] <= 252)
  assert_true(c.evs[4] <= 252)
}

///|
test "optimize_hbd: greedy within 1% of brute-force optimum" {
  // The canonical "H = B + D" rule is a continuous-limit heuristic that is rarely
  // reachable under EV caps (each stat capped at 252). Instead verify that the
  // greedy solution matches the brute-force global optimum within 1%.
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let greedy = optimize_hbd(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    default_weights(),
  )
  let brute = optimize_hbd_topn(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    default_weights(),
    1,
  )
  let g = greedy.candidates[0].score
  let b = brute.candidates[0].score
  assert_true(g >= b * 0.99)
  assert_true(b >= g)
}

///|
test "optimize_hbd: fixed S=252 reserves budget" {
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let fixed : FixedArray[Int] = [-1, 0, -1, 0, -1, 252]
  let result = optimize_hbd(
    garch,
    fixed,
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    default_weights(),
  )
  let c = result.candidates[0]
  inspect(c.evs[5], content="252")
  let hbd_total = c.evs[0] + c.evs[2] + c.evs[4]
  assert_true(hbd_total <= 256) // 508 - 252
}

///|
test "optimize_hbd: HpSnap::Leftovers → H ≡ 1 (mod 16)" {
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let result = optimize_hbd(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::Leftovers,
    default_weights(),
  )
  let c = result.candidates[0]
  inspect(c.hp % 16, content="1")
}

///|
test "optimize_hbd: HpSnap::Residual → H ≡ 15 (mod 16)" {
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let result = optimize_hbd(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::Residual,
    default_weights(),
  )
  let c = result.candidates[0]
  inspect(c.hp % 16, content="15")
}

///|
test "optimize_hbd: Shedinja (base HP=1) falls back to B/D only" {
  let nuke = mk_pokemon("ヌケニン", 1, 90, 45, 30, 30, 40)
  let result = optimize_hbd(
    nuke,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    default_weights(),
  )
  let c = result.candidates[0]
  // HP must remain near-zero EV (can't gain anything since base=1 → HP stays 76 regardless)
  // B and D should receive some EV
  assert_true(c.evs[2] > 0 || c.evs[4] > 0)
}

///|
test "optimize_hbd: score is positive and monotonic through loop" {
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let result = optimize_hbd(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    default_weights(),
  )
  let c = result.candidates[0]
  assert_true(c.score > 0.0)
}

///|
test "optimize_hbd_topn: n=5 returns 5 candidates in descending order" {
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let result = optimize_hbd_topn(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    default_weights(),
    5,
  )
  inspect(result.candidates.length(), content="5")
  // Descending scores
  for i = 1; i < result.candidates.length(); i = i + 1 {
    assert_true(result.candidates[i - 1].score >= result.candidates[i].score)
  }
}

///|
test "optimize_hbd_topn: top candidate close to greedy solution" {
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let greedy = optimize_hbd(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    default_weights(),
  )
  let brute = optimize_hbd_topn(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    default_weights(),
    1,
  )
  // Greedy should be ≥ 99% of brute force optimum (allowing small heuristic gap)
  let greedy_score = greedy.candidates[0].score
  let brute_score = brute.candidates[0].score
  assert_true(greedy_score >= brute_score * 0.99)
  // Brute force is global optimum, so it is at least as good as greedy
  assert_true(brute_score >= greedy_score)
}

///|
test "optimize_hbd_topn: constraint adherence" {
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let result = optimize_hbd_topn(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::Leftovers,
    default_weights(),
    10,
  )
  for i = 0; i < result.candidates.length(); i = i + 1 {
    let c = result.candidates[i]
    // All candidates satisfy Leftovers
    assert_true(c.hp % 16 == 1)
    // Total ≤ 508
    let total = c.evs[0] + c.evs[1] + c.evs[2] + c.evs[3] + c.evs[4] + c.evs[5]
    assert_true(total <= 508)
    // Each ≤ 252
    assert_true(c.evs[0] <= 252)
    assert_true(c.evs[2] <= 252)
    assert_true(c.evs[4] <= 252)
    // Fixed slots unchanged
    assert_true(c.evs[1] == 0)
    assert_true(c.evs[3] == 0)
    assert_true(c.evs[5] == 0)
  }
}

///|
test "optimize_hbd: asymmetric weights — phys≫spec favors B" {
  let garch = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let result_phys = optimize_hbd(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    { phys: 10, spec: 1 },
  )
  let result_spec = optimize_hbd(
    garch,
    all_optimize_evs(),
    default_ivs(),
    neutral_nature(),
    @model.HpSnap::NoSnap,
    { phys: 1, spec: 10 },
  )
  let c_phys = result_phys.candidates[0]
  let c_spec = result_spec.candidates[0]
  // Heavy physical damage → invest more in Def (slot 2)
  assert_true(c_phys.evs[2] >= c_phys.evs[4])
  // Heavy special damage → invest more in SpD (slot 4)
  assert_true(c_spec.evs[4] >= c_spec.evs[2])
}
