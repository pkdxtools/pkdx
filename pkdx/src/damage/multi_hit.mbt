///|
/// Multi-hit resolution for `pkdx damage`.
///
/// Two enums carry the decision flow:
/// - `HitSpec` reports what the move's own table says (data).
/// - `HitPlan` is the engine-facing decision, folding in ability overrides
///   (Parental Bond, Skill Link) and explicit `--multi-hit` flags.
///
/// Hardcoded move tables are the minimum viable source of truth for PR-C.
/// Moving this data into a patchable `pkdx_patch/NNN_waza_multihit/` entry
/// is future work once Champions-era new moves land; for now collection
/// gaps are caught by PR review (cross-check vs Showdown / PokeAPI).

///|
pub(all) enum HitSpec {
  SingleHit
  FixedHit(Int)
  Random2to5
} derive(Show, Eq)

///|
pub(all) enum HitPlan {
  Single
  FixedHits(Int)
  ParentalBond
  // P1-A (#90): probabilistic 1/2/3-hit moves with mid-flight miss
  // (トリプルアクセル / トリプルキック). Distinct from FixedHits(3) because
  // the latter never misses mid-attack (すいりゅうれんだ / トリプルダイブ).
  // The carried name is preserved so downstream engine code can branch on
  // move-specific power scaling once #90's variants[] is wired through.
  TripleVariant(String)
} derive(Show, Eq)

///|
/// Moves that always hit exactly twice.
let fixed_2_hit : Array[String] = [
  "にどげり",
  "ダブルアタック",
  "ダブルウイング",
  "ドラゴンアロー",
  "ツインビーム",
]

///|
/// Moves that always hit exactly three times.
let fixed_3_hit : Array[String] = [
  "トリプルキック",
  "トリプルアクセル",
  "トリプルダイブ",
  "すいりゅうれんだ",
]

///|
/// Subset of `fixed_3_hit` whose hits can miss mid-attack — Triple Kick and
/// Triple Axel ramp power per landed hit. 各 hit 命中率 90% を直に展開する
/// と、移動が成功した (= hit 1 が当たった) 条件下での landed-hit 分布は
/// p(1)=0.10, p(2)=0.09, p(3)=0.81 になる。すいりゅうれんだ /
/// トリプルダイブ are deterministic 3-hits and stay on FixedHits(3).
let triple_variant_hit : Array[String] = ["トリプルキック", "トリプルアクセル"]

///|
/// Moves that hit 2-5 times with the standard distribution
/// (P(2)=P(3)=3/8, P(4)=P(5)=1/8 → E[n] = 19/6). Under Skill Link they
/// upgrade to fixed 5; Auto collapses them to the center value 3.
let random_2_5_hit : Array[String] = [
  "みだれひっかき",
  "みだれづき",
  "ボーンラッシュ",
  "ロックブラスト",
  "タネマシンガン",
  "みずしゅりけん",
  "つららばり",
  "ミサイルばり",
  "つっぱり",
  "スケイルショット",
]

///|
fn in_set(s : String, set : Array[String]) -> Bool {
  for i = 0; i < set.length(); i = i + 1 {
    if set[i] == s {
      return true
    }
  }
  false
}

///|
/// Data lookup: what does this move's own table say?
pub fn resolve_auto_hits(name : String) -> HitSpec {
  if in_set(name, fixed_2_hit) {
    FixedHit(2)
  } else if in_set(name, fixed_3_hit) {
    FixedHit(3)
  } else if in_set(name, random_2_5_hit) {
    Random2to5
  } else {
    SingleHit
  }
}

///|
/// Engine-facing decision. Explicit Fixed(n) wins over everything;
/// Expected is rejected at the CLI boundary (payoff-only). Otherwise the
/// move table + attacker ability (Parental Bond, Skill Link) resolves the
/// plan.
pub fn resolve_hit_plan(
  mv : @model.Move,
  atk_ability : String,
  mode : @model.MultiHit,
) -> HitPlan {
  match mode {
    @model.MultiHit::Fixed(n) => {
      let c = if n < 1 {
        1
      } else {
        n
      }
      return FixedHits(c)
    }
    @model.MultiHit::Expected =>
      abort(
        "MultiHit::Expected is a payoff-only approximation; pkdx damage does not accept it",
      )
    @model.MultiHit::Auto => ()
  }
  let base = resolve_auto_hits(mv.name)
  // Parental Bond only applies to a move that would otherwise be single-hit.
  if atk_ability == "おやこあい" && base == HitSpec::SingleHit {
    return ParentalBond
  }
  // Skill Link upgrades Random2to5 → guaranteed 5.
  if base == HitSpec::Random2to5 && atk_ability == "スキルリンク" {
    return FixedHits(5)
  }
  match base {
    SingleHit => Single
    FixedHit(n) =>
      if n == 3 && in_set(mv.name, triple_variant_hit) {
        TripleVariant(mv.name)
      } else {
        FixedHits(n)
      }
    Random2to5 => FixedHits(3)
  }
}

///|
/// Probability distribution over hit counts for the variants[] payload.
/// Returns `[(hits_count, probability)]` whose probabilities sum to 1.0.
/// Used by `engine.mbt`'s multi-hit post-process to construct
/// `Array[DamageVariant]`.
///
/// - `Single` / `FixedHits(n)` / `ParentalBond` → 1 entry, probability 1.0
/// - `TripleVariant(_)` → [(1, 0.10), (2, 0.09), (3, 0.81)]
///   (per-hit 90% accuracy conditioned on the move connecting at all)
/// - Random2to5-resolved-to-Auto-FixedHits(3) carries the deterministic
///   fallback; the Random2to5 case is handled separately via
///   `expand_random_2_5_variants` because the HitPlan does not preserve
///   the original Random2to5 spec (Auto collapses it).
pub fn expand_variants(plan : HitPlan) -> Array[(Int, Double)] {
  match plan {
    Single => [(1, 1.0)]
    FixedHits(n) => [(n, 1.0)]
    ParentalBond => [(2, 1.0)]
    TripleVariant(_) => [(1, 0.10), (2, 0.09), (3, 0.81)]
  }
}

///|
/// Random2to5 hit-count distribution, used when the move resolves to
/// `Random2to5` from `resolve_auto_hits` (i.e. without Skill Link). Smogon
/// distribution: P(2)=P(3)=3/8, P(4)=P(5)=1/8.
///
/// Skill Link upgrades Random2to5 to `FixedHits(5)` *before* this is
/// consulted, so `expand_random_2_5_variants` is only called for the
/// non-Skill-Link path.
pub fn expand_random_2_5_variants() -> Array[(Int, Double)] {
  [(2, 0.375), (3, 0.375), (4, 0.125), (5, 0.125)]
}

///|
/// Full hit-count probability distribution for Auto-mode multi-hit
/// resolution. Folds `expand_variants` and `expand_random_2_5_variants`
/// behind a single entrypoint so callers (engine.mbt's variants loop and
/// payoff/switching_game's contact-proc fanout) share the source of
/// truth for "given this move + ability, how many landed hits should we
/// expect with what probabilities".
///
/// Random2to5 is the only branch that needs the auto_spec lookup —
/// HitPlan collapses it to `FixedHits(3)` when Auto fires, losing the
/// 4-way distribution otherwise.
pub fn resolve_hit_distribution(
  mv : @model.Move,
  atk_ability : String,
) -> Array[(Int, Double)] {
  let auto_spec = resolve_auto_hits(mv.name)
  let plan = resolve_hit_plan(mv, atk_ability, @model.MultiHit::Auto)
  match plan {
    Single => [(1, 1.0)]
    ParentalBond => [(2, 1.0)]
    TripleVariant(_) => [(1, 0.10), (2, 0.09), (3, 0.81)]
    FixedHits(n) =>
      match auto_spec {
        Random2to5 =>
          if atk_ability == "スキルリンク" {
            [(n, 1.0)]
          } else {
            expand_random_2_5_variants()
          }
        _ => [(n, 1.0)]
      }
  }
}
