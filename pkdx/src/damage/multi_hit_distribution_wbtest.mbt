///|
/// #91 Phase 1-A: pure probability calculation unit tests for
/// `expand_variants` and `population_bomb_distribution`. These tests
/// stay independent of the damage engine — they exercise the chance-node
/// distribution layer in isolation so the math is pinned regardless of
/// engine refactors. They also serve as regression guards for Triple
/// Axel and Random2to5 distributions which the payoff layer (Phase 2)
/// relies on.

///|
fn approx(a : Double, b : Double, tol : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < tol
}

///|
fn sum_int_double_probs(arr : Array[(Int, Double)]) -> Double {
  // expand_variants は Array[(Int, Double)] = (hits_count, probability)。
  // 確率合計はタプル第二要素 (.1) を畳むこと。第一要素 (.0) は hits_count
  // なので合計しない。
  let mut s = 0.0
  for i = 0; i < arr.length(); i = i + 1 {
    let (_, p) = arr[i]
    s = s + p
  }
  s
}

///|
fn pow_double(base : Double, exp : Int) -> Double {
  let mut r = 1.0
  for i = 0; i < exp; i = i + 1 {
    r = r * base
  }
  r
}

///|
test "PopulationBomb cumulative probability is 1.0 within 1e-12" {
  let plan = HitPlan::PopulationBomb("ネズミざん")
  let probs = expand_variants(plan)
  let total = sum_int_double_probs(probs)
  assert_true(approx(total, 1.0, 1.0e-12))
}

///|
test "PopulationBomb returns 10 variants (1..10), no 0-hit" {
  // 0-hit (move miss) は per_side_attempt 側で処理されるので
  // expand_variants には現れないことを確定的に確認する。
  let plan = HitPlan::PopulationBomb("ネズミざん")
  let probs = expand_variants(plan)
  inspect(probs.length(), content="10")
  for i = 0; i < probs.length(); i = i + 1 {
    let (h, _) = probs[i]
    assert_true(h == i + 1)
  }
}

///|
test "PopulationBomb p(N) = 0.9^(N-1) * 0.1 for 1 <= N <= 9" {
  let plan = HitPlan::PopulationBomb("ネズミざん")
  let probs = expand_variants(plan)
  for n = 1; n <= 9; n = n + 1 {
    let (h, p) = probs[n - 1]
    assert_true(h == n)
    let expected = pow_double(0.9, n - 1) * 0.1
    assert_true(approx(p, expected, 1.0e-15))
  }
}

///|
test "PopulationBomb p(10) = 0.9^9 (the residual mass)" {
  let plan = HitPlan::PopulationBomb("ネズミざん")
  let probs = expand_variants(plan)
  let (h, p) = probs[9]
  assert_true(h == 10)
  let expected = pow_double(0.9, 9)
  assert_true(approx(p, expected, 1.0e-15))
}

///|
test "Triple Axel expand_variants unchanged: [(1,0.10),(2,0.09),(3,0.81)] (regression guard)" {
  // Phase 1 では Triple Axel に手を入れないことを安全網として明示する。
  // accuracy は per_side_attempt が move accuracy として処理するので、ここの
  // 分布は move connecting 後の per-hit 90% 継続を表す (Σ=1.0)。
  let plan = TripleVariant("トリプルアクセル")
  let probs = expand_variants(plan)
  inspect(probs.length(), content="3")
  let (h0, p0) = probs[0]
  let (h1, p1) = probs[1]
  let (h2, p2) = probs[2]
  assert_true(h0 == 1)
  assert_true(approx(p0, 0.10, 1.0e-12))
  assert_true(h1 == 2)
  assert_true(approx(p1, 0.09, 1.0e-12))
  assert_true(h2 == 3)
  assert_true(approx(p2, 0.81, 1.0e-12))
  let total = sum_int_double_probs(probs)
  assert_true(approx(total, 1.0, 1.0e-12))
}

///|
test "expand_random_2_5_variants returns 4 variants summing to 1.0" {
  let probs = expand_random_2_5_variants()
  inspect(probs.length(), content="4")
  let total = sum_int_double_probs(probs)
  assert_true(approx(total, 1.0, 1.0e-12))
  let (h0, p0) = probs[0]
  let (h1, p1) = probs[1]
  let (h2, p2) = probs[2]
  let (h3, p3) = probs[3]
  assert_true(h0 == 2 && approx(p0, 0.375, 1.0e-15))
  assert_true(h1 == 3 && approx(p1, 0.375, 1.0e-15))
  assert_true(h2 == 4 && approx(p2, 0.125, 1.0e-15))
  assert_true(h3 == 5 && approx(p3, 0.125, 1.0e-15))
}

///|
test "Single / FixedHits / ParentalBond return 1 variant with prob 1.0" {
  let cases : Array[(HitPlan, Int)] = [
    (Single, 1),
    (FixedHits(2), 2),
    (FixedHits(5), 5),
    (ParentalBond, 2),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (plan, expected_hits) = cases[i]
    let probs = expand_variants(plan)
    inspect(probs.length(), content="1")
    let (h, p) = probs[0]
    assert_true(h == expected_hits)
    assert_true(approx(p, 1.0, 1.0e-15))
  }
}
