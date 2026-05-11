///|
/// One landed hit inside a `DamageVariant`. Used by issue #92 (Stamina
/// per-hit defense ramp), #93 (per-hit contact proc), and #97 (per-hit
/// resist berry consumption) to mutate state at hit granularity instead
/// of collapsing the move into a single number.
///
/// `damage_per_roll` holds this hit's standalone 16-roll damage; the
/// variant's `total_damages` is the cumulative sum across `hits[0..i]`.
/// `def_stage_after` is the defender's def stage *after* this hit lands
/// (entry value for now — #92 fills the ramp). `contact` mirrors
/// `is_contact_move(name)` so #93 can fan out chance nodes without
/// re-querying move flags. `event` is reserved for future per-hit status
/// payloads (#93/#97 expansion).
pub(all) struct HitStep {
  damage_per_roll : FixedArray[Int]
  def_stage_after : Int
  contact : Bool
  event : StatusKind?
} derive(Show, Eq)

///|
/// A probabilistic outcome of a multi-hit move. `probability` is the chance
/// this variant materialises (Σ over a result's variants is 1.0 ± 1e-9).
/// `hits.length() == hits_count` is the number of hits that connected in
/// this variant — Triple-axel emits variants with hits_count ∈ {1,2,3}
/// and probabilities {0.10, 0.09, 0.81} (per-hit 90% accuracy conditioned
/// on hit 1 connecting); Random2to5 emits {2,3,4,5} with
/// {0.375, 0.375, 0.125, 0.125}; deterministic moves emit one variant
/// with probability 1.0.
///
/// `total_damages` and `min`/`max`/`ko_text` are derived caches kept
/// alongside `hits` so consumers (CLI output, payoff fanout) can read
/// the cumulative result without recomputing.
pub(all) struct DamageVariant {
  probability : Double
  hits : Array[HitStep]
  hits_count : Int
  total_damages : FixedArray[Int]
  min : Int
  max : Int
  ko_text : String
} derive(Show, Eq)

///|
pub(all) struct DamageCalcResult {
  damages : FixedArray[Int]
  percents : FixedArray[Double]
  min_damage : Int
  max_damage : Int
  min_percent : Double
  max_percent : Double
  ko_text : String
  defender_hp : Int
  is_immune : Bool
  // rev2: ばけのかわ初撃ブロック時に true。damages は全 0、呼び出し側で HP 1/8
  // の状態遷移を扱う。
  disguise_blocked : Bool
  // rev2: 連続技・おやこあいの実ヒット数。Single=1, Fixed(n)=n, ParentalBond=2。
  hits_dealt : Int
  // P1-A (issue #90): hit-by-hit chance-node representation. Always non-empty
  // (immune/disguise produce a 1-element variants with probability 1.0).
  // The legacy fields (damages, hits_dealt, min_damage, max_damage, ko_text)
  // are derived from the most-likely variant for backward compatibility.
  variants : Array[DamageVariant]
} derive(Show)
