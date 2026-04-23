///|
/// Multi-hit resolution strategy for `pkdx damage`.
///
/// - `Auto`: look up the move in the hardcoded multi-hit table. Fixed N-hit
///   moves use N; 2-5 random moves use the center value 3 (skill-link presence
///   is decided by attacker ability at call site).
/// - `Fixed(n)`: force exactly n hits (`--multi-hit 5` for worst-case analysis).
/// - `Expected`: payoff-layer approximation only. `pkdx damage` aborts on this
///   variant; the payoff module uses it internally to scale single-hit damage
///   by `19/6` when propagating through the switching game.
pub(all) enum MultiHit {
  Auto
  Fixed(Int)
  Expected
} derive(Show, Eq)
