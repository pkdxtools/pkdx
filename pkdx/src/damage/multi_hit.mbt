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
    FixedHit(n) => FixedHits(n)
    Random2to5 => FixedHits(3)
  }
}
