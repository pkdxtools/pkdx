///|
/// Reflect moves: Counter / Mirror Coat / Metal Burst / Comeuppance.
///
/// These four moves do not run the standard power-based damage formula —
/// instead they return `floor(incoming_damage × multiplier)` and only apply
/// type-immunity (Counter→Ghost, MirrorCoat→Dark) on top of the fixed
/// multiplier. See `.claude/skills/calc/references/special_cases.md` for the
/// full spec table.
///
/// This module hosts:
///   1. `ReflectKind` enum + identification helpers (`is_reflect_move`)
///   2. Multiplier / type / category-acceptance tables
///   3. `calc_reflect_damage` (added in a follow-up task) — the two-step
///      reflect damage routine that recurses into `calc_damage` for Step1.

///|
pub(all) enum ReflectKind {
  Counter
  MirrorCoat
  MetalBurst
  Revenge
} derive(Eq, Debug)

///|
/// Identify a reflect move by its Japanese name. Returns `None` for any
/// non-reflect move.
pub fn is_reflect_move(name : String) -> ReflectKind? {
  match name {
    "カウンター" => Some(Counter)
    "ミラーコート" => Some(MirrorCoat)
    "メタルバースト" => Some(MetalBurst)
    "ほうふく" => Some(Revenge)
    _ => None
  }
}

///|
/// Reflect damage multiplier as an integer fraction `(num, den)`. Counter
/// and MirrorCoat return (2, 1) (×2.0); MetalBurst and Revenge return
/// (3, 2) (×1.5). Integer division keeps the floor semantics required by
/// the in-game routine.
pub fn reflect_multiplier(kind : ReflectKind) -> (Int, Int) {
  match kind {
    Counter | MirrorCoat => (2, 1)
    MetalBurst | Revenge => (3, 2)
  }
}

///|
/// The Japanese type name of the reflect move itself. Used to drive the
/// type-immunity check against the original attacker (e.g. Counter vs
/// Ghost-type attacker → 0).
pub fn reflect_move_type(kind : ReflectKind) -> String {
  match kind {
    Counter => "かくとう"
    MirrorCoat => "エスパー"
    MetalBurst => "はがね"
    Revenge => "あく"
  }
}

///|
/// Which incoming damage categories each reflect move accepts. Counter is
/// physical-only, MirrorCoat is special-only, MetalBurst and Revenge accept
/// both physical and special. Status incoming never qualifies.
pub fn reflect_accepts_category(
  kind : ReflectKind,
  cat : @model.MoveCategory,
) -> Bool {
  match (kind, cat) {
    (Counter, @model.Physical) => true
    (MirrorCoat, @model.Special) => true
    (MetalBurst, @model.Physical) => true
    (MetalBurst, @model.Special) => true
    (Revenge, @model.Physical) => true
    (Revenge, @model.Special) => true
    _ => false
  }
}

///|
/// Two-step reflect damage calculation. Step 1 recurses into `calc_damage`
/// with `incoming_attacker → input.attacker` (the reflect user is the
/// defender) and `incoming_*: None` to prevent re-entry. Step 2 multiplies
/// the resulting 16-roll table by the reflect kind's integer fraction.
/// Type immunity (Counter→Ghost, MirrorCoat→Dark) is checked against the
/// reflect move's own type vs the incoming attacker's defensive type.
///
/// `defender_hp` in the returned result is `incoming_attacker.hp` — reflect
/// damage is dealt back to the attacker, so percent / KO context is theirs.
///
/// MVP simplifications (Step1 input construction):
///   - incoming side ability / item / nature / rank / status / tera / crit
///     all default to neutral. Future PR can surface them via dedicated
///     CLI flags.
///   - The reflect user's defensive stats (def_rank / def_ability / def_item
///     / def_status / wall) ARE propagated so e.g. マルチスケイル / オボン /
///     screen still affect the Step 1 damage.
pub fn calc_reflect_damage(
  kind : ReflectKind,
  input : @model.DamageCalcInput,
  incoming_attacker : @model.Pokemon,
  incoming_move : @model.Move,
) -> @model.DamageCalcResult {
  let target_hp = if incoming_attacker.hp > 0 { incoming_attacker.hp } else { 1 }

  // Step 0: category acceptance. Counter rejects special, MirrorCoat rejects
  // physical, MetalBurst/Revenge reject only status.
  if !reflect_accepts_category(kind, incoming_move.category) {
    return reflect_zero_result(target_hp)
  }

  // Step 1: compute the damage the reflect user would have taken from the
  // incoming attack. We reuse `calc_damage` with `incoming_*: None` so the
  // engine takes the normal power-based path and we cannot recurse.
  let step1_input : @model.DamageCalcInput = {
    attacker: incoming_attacker,
    defender: input.attacker,
    move_: incoming_move,
    atk_ability: "",
    def_ability: input.def_ability,
    atk_item: "",
    def_item: input.def_item,
    weather: input.weather,
    field: input.field,
    tera_type: "",
    critical: false,
    atk_nature: None,
    def_nature: None,
    atk_stat_override: 0,
    def_stat_override: 0,
    def_hp_override: 0,
    atk_rank: 0,
    def_rank: input.def_rank,
    fainted_count: 0,
    is_double: input.is_double,
    stat_system: input.stat_system,
    wall: input.wall,
    screen_pierce: false,
    atk_status_condition: @model.StatusCondition::None,
    def_status_condition: input.def_status_condition,
    atk_rank_up_count: 0,
    def_rank_up_count: 0,
    atk_hp_num: 2,
    atk_hp_den: 2,
    def_item_removable: false,
    multi_hit_mode: @model.MultiHit::Auto,
    disguise_active: false,
    incoming_attacker: None,
    incoming_move: None,
  }
  let step1 = calc_damage(step1_input)
  if step1.is_immune {
    return reflect_zero_result(target_hp)
  }

  // Step 2: type immunity of the reflect move itself. Counter (Fighting) is
  // blocked by Ghost; Mirror Coat (Psychic) by Dark; Metal Burst (Steel) and
  // Revenge (Dark) have no type immunity in Gen 9 but the same dual-type
  // calculation correctly returns 1.0 for them.
  let reflect_type = reflect_move_type(kind)
  let type_immune = match @types.type_from_jp(reflect_type) {
    Some(rt) =>
      match @types.type_from_jp(incoming_attacker.type1) {
        Some(t1) => {
          let t2 = if incoming_attacker.type2.length() > 0 {
            @types.type_from_jp(incoming_attacker.type2)
          } else {
            None
          }
          @types.get_dual_effectiveness(rt, t1, t2) == 0.0
        }
        None => false
      }
    None => false
  }
  if type_immune {
    return reflect_zero_result(target_hp)
  }

  // Step 3: multiply the 16-roll table by the reflect fraction. Integer
  // division gives the game-faithful floor for both ×2.0 and ×1.5.
  let (mult_num, mult_den) = reflect_multiplier(kind)
  let reflect_damages : FixedArray[Int] = FixedArray::make(16, 0)
  for i = 0; i < 16; i = i + 1 {
    reflect_damages[i] = step1.damages[i] * mult_num / mult_den
  }
  let percents : FixedArray[Double] = FixedArray::make(16, 0.0)
  for i = 0; i < 16; i = i + 1 {
    percents[i] = reflect_damages[i].to_double() / target_hp.to_double() *
      100.0
  }
  let min_dmg = reflect_damages[0]
  let max_dmg = reflect_damages[15]
  let ko_text = calc_ko_text(reflect_damages, target_hp)
  let reflect_step : @model.HitStep = {
    damage_per_roll: reflect_damages,
    def_stage_after: 0,
    contact: false,
    event: None,
  }
  @model.DamageCalcResult::{
    damages: reflect_damages,
    percents,
    min_damage: min_dmg,
    max_damage: max_dmg,
    min_percent: percents[0],
    max_percent: percents[15],
    ko_text,
    defender_hp: target_hp,
    is_immune: false,
    disguise_blocked: false,
    disguise_chip: 0,
    hits_dealt: 1,
    variants: [
      {
        probability: 1.0,
        hits: [reflect_step],
        hits_count: 1,
        total_damages: reflect_damages,
        min: min_dmg,
        max: max_dmg,
        ko_text,
      },
    ],
  }
}

///|
/// Reflect failure result — all-zero 16-roll table with `is_immune=false`.
/// We do not use the engine's `immune_result` because reflect failure is
/// semantically "miss" (`相手が反射対象を撃たなかった / タイプ無効 / 攻撃が0
/// だった`), not type immunity in the usual sense — UI consumers shouldn't
/// flash "効果がない" for a failed Counter, but the damage column being 0 is
/// still correct.
fn reflect_zero_result(target_hp : Int) -> @model.DamageCalcResult {
  let zero_damages : FixedArray[Int] = FixedArray::make(16, 0)
  let zero_step : @model.HitStep = {
    damage_per_roll: zero_damages,
    def_stage_after: 0,
    contact: false,
    event: None,
  }
  @model.DamageCalcResult::{
    damages: zero_damages,
    percents: FixedArray::make(16, 0.0),
    min_damage: 0,
    max_damage: 0,
    min_percent: 0.0,
    max_percent: 0.0,
    ko_text: "failed",
    defender_hp: target_hp,
    is_immune: false,
    disguise_blocked: false,
    disguise_chip: 0,
    hits_dealt: 1,
    variants: [
      {
        probability: 1.0,
        hits: [zero_step],
        hits_count: 1,
        total_damages: zero_damages,
        min: 0,
        max: 0,
        ko_text: "failed",
      },
    ],
  }
}
