///|
/// Generic chance-node combinator for the payoff layer.
///
/// `compose_fanouts(state, [step1, step2, ...])` threads a probabilistic
/// state evolution through a list of fanout steps. Each step is a pure
/// function `S -> Array[(Double, S)]` returning weighted alternative
/// outcomes; the result is the cartesian-product distribution over all
/// step combinations, with probabilities multiplied along each path.
///
/// Used by switching_game.mbt to compose chance-node layers cleanly:
/// - P2-A (#91): apply_damage_variants_fanout (hit-count branching)
/// - existing: maybe_apply_status_fanout (status effect proc)
/// - P4 (#93): apply_contact_proc_fanout (defender contact specialty)
/// - P5 (#97): apply_item_pre_damage_proc_fanout, item_post_damage_proc
///
/// Without this combinator, each new chance-node layer would need to
/// hand-roll its own flat_map nesting, duplicating probability mass
/// bookkeeping across `value()` recursion arms. compose_fanouts keeps
/// that bookkeeping in one place, including the `Σp ≈ 1.0` invariant
/// that downstream Nash solvers depend on.

///|
/// One layer of a chance-node fanout. Receives the current state and
/// returns a list of `(probability, next_state)` outcomes.
///
/// Implementations must guarantee that the returned probabilities sum
/// to 1.0 ± 1e-9 for the contract carried by `compose_fanouts` to hold
/// across multi-layer composition. Deterministic transitions return a
/// single-element array `[(1.0, new_state)]`.
pub type FanoutStep[S] = (S) -> Array[(Double, S)]

///|
/// Compose a list of fanout steps applied left-to-right. Probabilities
/// multiply along each path, leaves are flattened into a single
/// `Array[(Double, S)]`. The empty step list yields the identity:
/// `[(1.0, state)]`.
///
/// Complexity is O(∏ |step_i_outcomes|) in leaf count — a 4-step chain
/// with 4/3/2/2 outcomes at each layer expands to 48 leaves. The
/// switching_game memoize cache deduplicates equivalent states so the
/// game tree usually doesn't grow that fast in practice.
pub fn[S] compose_fanouts(
  state : S,
  steps : Array[FanoutStep[S]],
) -> Array[(Double, S)] {
  let mut current : Array[(Double, S)] = [(1.0, state)]
  for i = 0; i < steps.length(); i = i + 1 {
    let step = steps[i]
    let next : Array[(Double, S)] = []
    for j = 0; j < current.length(); j = j + 1 {
      let (p, s) = current[j]
      let outcomes = step(s)
      for k = 0; k < outcomes.length(); k = k + 1 {
        let (q, s2) = outcomes[k]
        next.push((p * q, s2))
      }
    }
    current = next
  }
  current
}

///|
/// Renormalise a probability-weighted state list so probabilities sum
/// to 1.0 exactly. Floating-point composition through `compose_fanouts`
/// can drift the total by a handful of ULPs across many layers; this
/// is a safety valve for callers that feed the result into
/// expectation-style computations sensitive to that drift.
///
/// Empty / zero-mass inputs are returned unchanged (they would yield
/// `0/0` under straight scaling). Already-normalised inputs (drift
/// `< 1e-9`) also return without rebuilding the array — the no-op fast
/// path keeps the L2 cache stable and avoids spurious allocation in
/// hot paths.
pub fn[S] normalize_probabilities(
  outcomes : Array[(Double, S)],
) -> Array[(Double, S)] {
  let mut sum = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    sum = sum + outcomes[i].0
  }
  if sum <= 0.0 {
    return outcomes
  }
  let drift = if sum > 1.0 { sum - 1.0 } else { 1.0 - sum }
  if drift < 1.0e-9 {
    return outcomes
  }
  let scale = 1.0 / sum
  let out : Array[(Double, S)] = []
  for i = 0; i < outcomes.length(); i = i + 1 {
    let (p, s) = outcomes[i]
    out.push((p * scale, s))
  }
  out
}
