///|
/// Modifiers for the **incoming** side of a reflect move (Counter / Mirror
/// Coat / Metal Burst / Comeuppance). Mirrors the attacker-side subset of
/// `DamageCalcInput` because reflect's Step 1 runs a normal damage
/// calculation in the direction `incoming_attacker → reflect_user`, and we
/// must apply Choice Band / Life Orb / Adamant nature / Tera / crit / burn
/// / +ranks just like a regular hit. Without these, the Step 1 number can
/// be off by 50% and the reflected damage is useless for real battle plans.
///
/// All fields are defaultable: an empty/zero value means "no modifier", so
/// CLI flags can be optional. `attacker` and `move_` are required.
pub(all) struct IncomingOpts {
  attacker : Pokemon
  move_ : Move
  atk_ability : String
  atk_item : String
  // None = +10% offensive-nature default (matches DamageCalcInput.atk_nature
  // semantics). Some(n) = explicit nature multiplier.
  atk_nature : Nature?
  atk_rank : Int
  // 0 = engine derives stat from species + nature + IV; non-zero overrides
  // the pre-rank offensive stat.
  atk_stat_override : Int
  atk_status_condition : StatusCondition
  // つけあがる / アシストパワー: total positive rank stages on the incoming
  // attacker. Defaults to 0.
  atk_rank_up_count : Int
  // やけっぱち: incoming attacker's HP ratio at use time. Default 2/2 (full).
  atk_hp_num : Int
  atk_hp_den : Int
  // Empty string = no Tera. Otherwise the Tera type (ja) of the incoming
  // attacker — Tera STAB / type rewrite applies normally to Step 1.
  tera_type : String
  // Was Step 1 a critical? Reflect itself ignores crit, but the incoming
  // attack can still crit and that scales the reflected damage.
  critical : Bool
} derive(Debug)
