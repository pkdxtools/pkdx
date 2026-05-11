///|
/// Orthogonal resolution of the attacker and defender stat kinds, the
/// effective physicality of the attack, and per-side rank masks.
///
/// Ground rules:
/// - Move category (Physical / Special) picks the default stat kinds.
/// - `is_body_press` moves override `atk_stat_kind` to Def (attacker value
///   comes from own Defense) while keeping the attack physical.
/// - Psyshock-family moves (サイコショック / サイコブレイク / しんぴのつるぎ)
///   keep the category special but look up the defender's Def, not SpD.
/// - せいなるつるぎ stays physical but sets `def_rank_positive_mask`.
///   Negative defender stages still apply.
/// - シェルアームズ picks physical iff `atk_atk * def_spd > atk_spa * def_def`
///   (strict `>`; a tie falls to special, matching Showdown).
///   WONDER_ROOM_NOT_SUPPORTED: Wonder Room swaps Def <-> SpD mid-turn, which
///   would flip the Shell Side Arm ratio and the Psyshock-family defender
///   lookup. pkdx assumes single battles and does not model it. If a future
///   PR adds doubles / field hazards, re-examine this branch.
/// - てんねん: if the defender has it, attacker's stages are fully masked
///   (`atk_rank_mask`). If the attacker has it, defender's stages are fully
///   masked. Both sides can hold it independently.
/// - Critical hit composes on top of whatever else is set:
///   `atk_rank_negative_mask` and `def_rank_positive_mask` go true.
/// - Multiple conditions OR together (e.g. Unaware × critical both set def_
///   rank_positive_mask) — that matches the real rule that any one trigger is
///   enough to ignore that stage direction.

///|
/// Attacker / defender stat kind plus per-side stage masks. The engine reads
/// the six `*_mask` booleans to zero out the right sides of the rank ladder
/// before feeding `apply_rank`.
pub(all) struct StatResolution {
  atk_stat_kind : @model.StatIndex
  def_stat_kind : @model.StatIndex
  effective_physical : Bool
  // Full-rank ignores (Unaware).
  atk_rank_mask : Bool
  def_rank_mask : Bool
  // Directional masks (critical hit / Secret Sword).
  atk_rank_positive_mask : Bool
  atk_rank_negative_mask : Bool
  def_rank_positive_mask : Bool
  def_rank_negative_mask : Bool
  // Optional contact-flag override: some moves (notably Shell Side Arm in
  // physical mode) need contact recomputed from the chosen category rather
  // than the static table.
  force_contact : Bool?
} derive(Show, Eq)

///|
/// Drive the decision table documented at the top of this file.
///
/// The four raw stats (`atk_atk`, `atk_spa`, `def_def`, `def_spd`) are passed
/// as pre-nature-and-item-adjusted integers because Shell Side Arm's choice
/// must look at the same numbers the engine will use downstream.
pub fn resolve_stat_resolution(
  mv : @model.Move,
  atk_atk~ : Int,
  atk_spa~ : Int,
  def_def~ : Int,
  def_spd~ : Int,
  atk_ability~ : String,
  def_ability~ : String,
  critical~ : Bool,
) -> StatResolution {
  let name = mv.name
  let is_physical = mv.category == @model.Physical

  // Base category-driven selection.
  let mut atk_stat_kind : @model.StatIndex = if is_physical {
    @model.StatIndex::Atk
  } else {
    @model.StatIndex::SpA
  }
  let mut def_stat_kind : @model.StatIndex = if is_physical {
    @model.StatIndex::Def
  } else {
    @model.StatIndex::SpD
  }
  let mut effective_physical = is_physical
  let mut force_contact : Bool? = None

  // Body Press: physical move; use own Defense as attack stat.
  if name == "ボディプレス" {
    atk_stat_kind = @model.StatIndex::Def
    // effective_physical stays true (inherited from is_physical).
  }

  // Psyshock family: special category but target defender's Def.
  // WONDER_ROOM_NOT_SUPPORTED: under Wonder Room the defender's Def/SpD roles
  // would be swapped, so this override would need to flip to SpD. pkdx's
  // single-battle scope treats the raw stat kind as the source of truth.
  if name == "サイコショック" ||
     name == "サイコブレイク" ||
     name == "しんぴのつるぎ" {
    def_stat_kind = @model.StatIndex::Def
  }

  // Shell Side Arm dynamic choice. Use strict > so ties fall to special.
  // WONDER_ROOM_NOT_SUPPORTED: the comparison reads raw Def/SpD which would
  // be swapped under Wonder Room. Not handled today.
  if name == "シェルアームズ" {
    let phys_score = atk_atk * def_spd
    let spec_score = atk_spa * def_def
    if phys_score > spec_score {
      atk_stat_kind = @model.StatIndex::Atk
      def_stat_kind = @model.StatIndex::Def
      effective_physical = true
      force_contact = Some(true)
    } else {
      atk_stat_kind = @model.StatIndex::SpA
      def_stat_kind = @model.StatIndex::SpD
      effective_physical = false
      force_contact = Some(false)
    }
  }

  // Rank masks: start cleared, then OR on each contributing rule. Only the
  // mask booleans that some rule actually flips are `mut`; the others stay
  // `let` because no current rule touches them (attacker's +rank, defender's
  // -rank). If future mechanics need them, convert the binding to `mut`.
  let mut atk_rank_mask = false
  let mut def_rank_mask = false
  let atk_rank_positive_mask = false
  let mut atk_rank_negative_mask = false
  let mut def_rank_positive_mask = false
  let def_rank_negative_mask = false

  // せいなるつるぎ: ignore defender's + ranks only.
  if name == "せいなるつるぎ" {
    def_rank_positive_mask = true
  }

  // Unaware (bidirectional, independent on each side).
  if def_ability == "てんねん" {
    atk_rank_mask = true
  }
  if atk_ability == "てんねん" {
    def_rank_mask = true
  }

  // Critical hit masks.
  if critical {
    atk_rank_negative_mask = true
    def_rank_positive_mask = true
  }

  {
    atk_stat_kind,
    def_stat_kind,
    effective_physical,
    atk_rank_mask,
    def_rank_mask,
    atk_rank_positive_mask,
    atk_rank_negative_mask,
    def_rank_positive_mask,
    def_rank_negative_mask,
    force_contact,
  }
}

///|
/// Fold the mask flags against the raw stage to get the effective stage the
/// engine should pass to `apply_rank`. Shared helper so the attacker and
/// defender paths in `engine.mbt` look symmetric.
///
/// Rule: if `full_mask` is on, return 0. Else, if the stage is positive and
/// `positive_mask` is on, or the stage is negative and `negative_mask` is on,
/// zero it. Otherwise pass through.
pub fn apply_rank_masks(
  stage : Int,
  full_mask : Bool,
  positive_mask : Bool,
  negative_mask : Bool,
) -> Int {
  if full_mask {
    0
  } else if stage > 0 && positive_mask {
    0
  } else if stage < 0 && negative_mask {
    0
  } else {
    stage
  }
}
