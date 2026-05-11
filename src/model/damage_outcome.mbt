///|
/// #91: Per-variant payoff-layer outcome derived from a `DamageVariant`.
///
/// payoff/switching_game.mbt's `damage_variants_cached` returns
/// `Array[DamageOutcome]` so that `apply_damage_variants_fanout` can
/// fan attack-resolution into hit-count-specific leaves without leaking
/// the engine's `DamageCalcResult` shape into the payoff layer.
///
/// `mean_damage` is the 16-roll mean of the variant's `total_damages`,
/// matching the existing `compute_mean_damage` semantics — payoff still
/// consumes a single Int per hit-count branch. `hits_count` and
/// `hit_steps` are forwarded so downstream fanouts (status / contact
/// proc) can fire per-hit (e.g. でんじは secondary fires `hits_count`
/// independent rolls).
///
/// L2 disk cache fallback note: when restoring from a pre-v3 cache the
/// `hit_steps` array may be empty even though `hits_count > 0`. Callers
/// that need per-hit metadata must guard for `hit_steps.is_empty()`
/// and recompute via `damage_variants_cached` (or accept the cached
/// `mean_damage` + `hits_count` summary).
pub(all) struct DamageOutcome {
  probability : Double
  mean_damage : Int
  hits_count : Int
  hit_steps : Array[HitStep]
} derive(Show, Eq)
