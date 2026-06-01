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
/// with the incoming attacker as Step1.attacker and the reflect user
/// (= `input.attacker`) as Step1.defender, plus `incoming_*: None` to
/// prevent re-entry. Step 2 multiplies the resulting 16-roll table by the
/// reflect kind's integer fraction. Type immunity (Counter→Ghost,
/// MirrorCoat→Dark) is checked against the reflect move's own type vs the
/// incoming attacker's defensive type.
///
/// CLI / model role mapping inside the recursive Step1 call:
///   - The reflect user is the OUTER attacker (`input.attacker`), so all of
///     its defensive-side modifiers must be sourced from `input.atk_*`
///     fields (ability, item, nature, rank, status, rank-up count) and
///     written into Step1's `def_*` slots. Reading from `input.def_*` here
///     would silently apply the reflected target's modifiers to the reflect
///     user — wrong role.
///   - The incoming attacker has no dedicated CLI flags, so all Step1
///     attacker-side modifiers default to neutral. A future PR can add
///     explicit `--incoming-*` flags.
///   - `wall`, `screen_pierce`, `def_item_removable`, `disguise_active` in
///     the outer call apply to the reflected target / reflect-target
///     interaction, not to the reflect user as Step1 defender, so they are
///     intentionally NOT propagated. If reflect-user wall support is
///     needed, surface a separate CLI flag.
///
/// `defender_hp` / `target_hp` (the percent / KO denominator) is computed
/// from `input.defender` (the reflected target) with `def_hp_override`
/// applied, using the same `calc_def_stat[_champions]` path as the normal
/// engine — so `--def-hp` behaves identically to non-reflect damage.
pub fn calc_reflect_damage(
  kind : ReflectKind,
  input : @model.DamageCalcInput,
  opts : @model.IncomingOpts,
) -> @model.DamageCalcResult {
  // target_hp = reflected target's actual HP (post stat formula), with
  // --def-hp override honored. This matches normal damage calc semantics.
  let target_base_hp = if input.defender.hp > 0 { input.defender.hp } else { 1 }
  let target_hp = if input.stat_system == @model.Champions {
    calc_def_stat_champions(
      target_base_hp,
      is_hp=true,
      custom=input.def_hp_override,
    )
  } else {
    calc_def_stat(target_base_hp, is_hp=true, custom=input.def_hp_override)
  }

  // Step 0: category acceptance. Counter rejects special, MirrorCoat rejects
  // physical, MetalBurst/Revenge reject only status.
  if !reflect_accepts_category(kind, opts.move_.category) {
    return reflect_zero_result(target_hp)
  }

  // Step 1: compute the damage the reflect user would have taken from the
  // incoming attack. We reuse `calc_damage` with `incoming: None` so the
  // engine takes the normal power-based path and we cannot recurse.
  //
  // Field-routing rules:
  //   - opts.* = INCOMING attacker side modifiers (Step1.atk_*) — Choice
  //     items, Adamant/Modest nature, Tera, crit, burn, +ranks, etc. all
  //     scale the incoming damage and therefore the reflected number.
  //   - input.atk_* = REFLECT USER (outer attacker) modifiers, which in
  //     Step 1 sit on the defender side because the reflect user is the
  //     one absorbing the hit.
  //   - input.def_* / wall / screen_pierce / def_item_removable /
  //     disguise_active describe the reflected target, not the reflect user
  //     as Step 1 defender, so they are intentionally NOT propagated.
  let step1_input : @model.DamageCalcInput = {
    attacker: opts.attacker,
    defender: input.attacker,
    move_: opts.move_,
    atk_ability: opts.atk_ability,
    def_ability: input.atk_ability,
    atk_item: opts.atk_item,
    def_item: input.atk_item,
    weather: input.weather,
    field: input.field,
    tera_type: opts.tera_type,
    critical: opts.critical,
    atk_nature: opts.atk_nature,
    def_nature: input.atk_nature,
    atk_stat_override: opts.atk_stat_override,
    def_stat_override: 0,
    def_hp_override: 0,
    atk_rank: opts.atk_rank,
    def_rank: input.atk_rank,
    fainted_count: 0,
    is_double: input.is_double,
    stat_system: input.stat_system,
    wall: @model.Wall::NoWall,
    screen_pierce: false,
    atk_status_condition: opts.atk_status_condition,
    def_status_condition: input.atk_status_condition,
    atk_rank_up_count: opts.atk_rank_up_count,
    def_rank_up_count: input.atk_rank_up_count,
    atk_hp_num: opts.atk_hp_num,
    atk_hp_den: opts.atk_hp_den,
    def_item_removable: false,
    multi_hit_mode: @model.MultiHit::Auto,
    disguise_active: false,
    protean_consumed: false,
    incoming: None,
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
      match @types.type_from_jp(opts.attacker.type1) {
        Some(t1) => {
          let t2 = if opts.attacker.type2.length() > 0 {
            @types.type_from_jp(opts.attacker.type2)
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
    percents[i] = reflect_damages[i].to_double() / target_hp.to_double() * 100.0
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
