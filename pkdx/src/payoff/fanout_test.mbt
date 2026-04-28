///|
/// Property tests for the compose_fanouts chance-node combinator.
/// Step 0 (Red Phase): fails until payoff/fanout.mbt is added with
/// FanoutStep, compose_fanouts, normalize_probabilities.

///|
/// Toy state used by the property tests below — Int counter so the
/// tests can verify state evolution without depending on
/// SwitchingGameState's larger surface.
fn const_step(value : Int) -> Array[(Double, Int)] {
  [(1.0, value)]
}

///|
fn split_step(s : Int) -> Array[(Double, Int)] {
  [(0.3, s + 1), (0.7, s + 2)]
}

///|
fn three_split_step(s : Int) -> Array[(Double, Int)] {
  [(0.2, s * 10), (0.2, s * 10 + 1), (0.6, s * 10 + 2)]
}

///|
fn sum_probs(outcomes : Array[(Double, Int)]) -> Double {
  let mut s = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    s = s + outcomes[i].0
  }
  s
}

///|
test "compose_fanouts: identity (empty steps array) returns [(1.0, state)]" {
  let result : Array[(Double, Int)] = compose_fanouts(42, [])
  inspect(result.length(), content="1")
  inspect(result[0].0, content="1")
  inspect(result[0].1, content="42")
}

///|
test "compose_fanouts: single step matches step's direct output" {
  let result = compose_fanouts(0, [split_step])
  inspect(result.length(), content="2")
  let s = sum_probs(result)
  let drift = if s > 1.0 { s - 1.0 } else { 1.0 - s }
  inspect(drift < 1.0e-9, content="true")
}

///|
test "compose_fanouts: two steps multiply probabilities and propagate state" {
  let result = compose_fanouts(0, [split_step, split_step])
  // 0 → {1@0.3, 2@0.7} → {(2,3)@0.09, (4,5)@0.21, (3,4)@0.21, (5,6)@0.49}
  // Above shorthand abuses notation; real layout is 4 outcomes total
  inspect(result.length(), content="4")
  let s = sum_probs(result)
  let drift = if s > 1.0 { s - 1.0 } else { 1.0 - s }
  inspect(drift < 1.0e-9, content="true")
}

///|
test "compose_fanouts: probability mass conserved across 3 steps" {
  let result = compose_fanouts(1, [three_split_step, split_step, split_step])
  // 1 step → 3 outcomes; each fans out by 2 then 2 → 12 leaves
  inspect(result.length(), content="12")
  let s = sum_probs(result)
  let drift = if s > 1.0 { s - 1.0 } else { 1.0 - s }
  inspect(drift < 1.0e-9, content="true")
}

///|
test "compose_fanouts: deterministic step (prob=1.0) preserves leaf count" {
  let det : (Int) -> Array[(Double, Int)] = const_step
  let result = compose_fanouts(7, [det, det, det])
  inspect(result.length(), content="1")
  inspect(result[0].0, content="1")
}

///|
test "normalize_probabilities: clamps drift back to 1.0" {
  // Hand-craft a slightly-drifted distribution (sum ≈ 1.000001).
  let drifted : Array[(Double, Int)] = [
    (0.500001, 0),
    (0.5, 1),
  ]
  let normalized = normalize_probabilities(drifted)
  let s = sum_probs(normalized)
  let drift = if s > 1.0 { s - 1.0 } else { 1.0 - s }
  inspect(drift < 1.0e-9, content="true")
}

///|
test "normalize_probabilities: passes through already-normalized array" {
  let exact : Array[(Double, Int)] = [(0.3, 0), (0.7, 1)]
  let normalized = normalize_probabilities(exact)
  inspect(normalized.length(), content="2")
  // Values should be unchanged (within float tolerance).
  let d0 = (normalized[0].0 - 0.3).abs()
  let d1 = (normalized[1].0 - 0.7).abs()
  inspect(d0 < 1.0e-9, content="true")
  inspect(d1 < 1.0e-9, content="true")
}
