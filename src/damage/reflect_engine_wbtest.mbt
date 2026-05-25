///|
/// Integration tests for the engine-level reflect path (calc_damage → reflect
/// dispatch → calc_reflect_damage → Step1 recursion). These exercise real
/// engine recursion, not mocks.

///|
fn rf_pokemon(
  name : String,
  type1 : String,
  type2 : String,
  hp : Int,
  atk : Int,
  def_ : Int,
  spa : Int,
  spd : Int,
  spe : Int,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2,
    hp,
    atk,
    def_,
    spa,
    spd,
    spe,
    bst: hp + atk + def_ + spa + spd + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 0.0,
    forms: [],
  }
}

///|
fn rf_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
  }
}

///|
fn rf_input(
  reflect_user : @model.Pokemon,
  reflect_move : @model.Move,
  incoming_attacker : @model.Pokemon,
  incoming_move : @model.Move,
) -> @model.DamageCalcInput {
  {
    attacker: reflect_user,
    // The reflected target is whoever receives the reflect damage. In normal
    // game mechanics this is the same Pokemon as the incoming attacker, so
    // the fixture uses `incoming_attacker` here. target_hp / percent / KO
    // context is computed from this Pokemon (post calc_def_stat).
    defender: incoming_attacker,
    move_: reflect_move,
    atk_ability: "",
    def_ability: "",
    atk_item: "",
    def_item: "",
    weather: @model.Weather::None,
    field: @model.Field::None,
    tera_type: "",
    critical: false,
    atk_nature: None,
    def_nature: None,
    atk_stat_override: 0,
    def_stat_override: 0,
    def_hp_override: 0,
    atk_rank: 0,
    def_rank: 0,
    fainted_count: 0,
    is_double: false,
    stat_system: @model.Standard,
    wall: @model.Wall::NoWall,
    screen_pierce: false,
    atk_status_condition: @model.StatusCondition::None,
    def_status_condition: @model.StatusCondition::None,
    atk_rank_up_count: 0,
    def_rank_up_count: 0,
    atk_hp_num: 2,
    atk_hp_den: 2,
    def_item_removable: false,
    multi_hit_mode: @model.MultiHit::Auto,
    disguise_active: false,
    incoming: Some(
      @model.IncomingOpts::{
        attacker: incoming_attacker,
        move_: incoming_move,
        atk_ability: "",
        atk_item: "",
        atk_nature: None,
        atk_rank: 0,
        atk_stat_override: 0,
        atk_status_condition: @model.StatusCondition::None,
        atk_rank_up_count: 0,
        atk_hp_num: 2,
        atk_hp_den: 2,
        tera_type: "",
        critical: false,
      },
    ),
  }
}

///|
test "reflect: Counter doubles Step1 damage at every roll" {
  // Asymmetric atk fixture: incoming side at atk=200, reflect user at atk=50
  // so we can observe that Step1 is driven by the INCOMING side, not own.
  let reflect_user = rf_pokemon(
    "user", "ノーマル", "", 200, 50, 100, 50, 100, 100,
  )
  let incoming = rf_pokemon(
    "incoming", "ノーマル", "", 200, 200, 100, 50, 100, 100,
  )
  let reflect_mv = rf_move("カウンター", "かくとう", @model.Physical, 1)
  let incoming_mv = rf_move("たいあたり", "ノーマル", @model.Physical, 40)
  let input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  let r = calc_damage(input)
  // Per-roll: reflect = 2 × step1 (integer division floors but ×2 has no
  // fractional remainder, so exact equality holds).
  let step1_input = {
    ..input,
    attacker: incoming,
    defender: reflect_user,
    move_: incoming_mv,
    incoming: None,
  }
  let step1 = calc_damage(step1_input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(
      r.damages[i] == step1.damages[i] * 2,
      content="true",
    )
  }
  // defender_hp is the reflected target's actual HP via calc_def_stat:
  //   (base*2 + IV31 + EV0) * 50 / 100 + 60 = (200*2+31)*50/100 + 60 = 275
  @debug.debug_inspect(r.defender_hp, content="275")
  @debug.debug_inspect(r.is_immune, content="false")
}

///|
test "reflect: MirrorCoat doubles special Step1 damage" {
  let reflect_user = rf_pokemon(
    "user", "エスパー", "", 200, 50, 100, 50, 100, 100,
  )
  let incoming = rf_pokemon(
    "incoming", "ノーマル", "", 200, 50, 100, 200, 100, 100,
  )
  let reflect_mv = rf_move("ミラーコート", "エスパー", @model.Special, 1)
  let incoming_mv = rf_move("ねっぷう", "ほのお", @model.Special, 95)
  let input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  let r = calc_damage(input)
  let step1_input = {
    ..input,
    attacker: incoming,
    defender: reflect_user,
    move_: incoming_mv,
    incoming: None,
  }
  let step1 = calc_damage(step1_input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(
      r.damages[i] == step1.damages[i] * 2,
      content="true",
    )
  }
}

///|
test "reflect: MetalBurst multiplies physical Step1 by 1.5 (floor)" {
  let reflect_user = rf_pokemon(
    "user", "はがね", "", 200, 50, 100, 50, 100, 100,
  )
  let incoming = rf_pokemon(
    "incoming", "ノーマル", "", 200, 200, 100, 50, 100, 100,
  )
  let reflect_mv = rf_move("メタルバースト", "はがね", @model.Physical, 1)
  let incoming_mv = rf_move("たいあたり", "ノーマル", @model.Physical, 40)
  let input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  let r = calc_damage(input)
  let step1_input = {
    ..input,
    attacker: incoming,
    defender: reflect_user,
    move_: incoming_mv,
    incoming: None,
  }
  let step1 = calc_damage(step1_input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(
      r.damages[i] == step1.damages[i] * 3 / 2,
      content="true",
    )
  }
}

///|
test "reflect: Revenge multiplies special Step1 by 1.5 (floor)" {
  let reflect_user = rf_pokemon("user", "あく", "", 200, 50, 100, 50, 100, 100)
  let incoming = rf_pokemon(
    "incoming", "ノーマル", "", 200, 50, 100, 200, 100, 100,
  )
  let reflect_mv = rf_move("ほうふく", "あく", @model.Physical, 1)
  let incoming_mv = rf_move("ねっぷう", "ほのお", @model.Special, 95)
  let input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  let r = calc_damage(input)
  let step1_input = {
    ..input,
    attacker: incoming,
    defender: reflect_user,
    move_: incoming_mv,
    incoming: None,
  }
  let step1 = calc_damage(step1_input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(
      r.damages[i] == step1.damages[i] * 3 / 2,
      content="true",
    )
  }
}

///|
test "reflect: Counter against Ghost-type incoming attacker → 0 (type immune)" {
  let reflect_user = rf_pokemon(
    "user", "ノーマル", "", 200, 50, 100, 50, 100, 100,
  )
  // Incoming attacker is Ghost-type → Counter (Fighting) has 0 effectiveness.
  let incoming = rf_pokemon(
    "incoming", "ゴースト", "", 200, 200, 100, 50, 100, 100,
  )
  let reflect_mv = rf_move("カウンター", "かくとう", @model.Physical, 1)
  // The incoming move itself must hit (Normal vs Normal works fine).
  let incoming_mv = rf_move("シャドーパンチ", "ゴースト", @model.Physical, 60)
  let input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  let r = calc_damage(input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(r.damages[i], content="0")
  }
  @debug.debug_inspect(r.ko_text, content="\"failed\"")
}

///|
test "reflect: MirrorCoat against Dark-type incoming attacker → 0 (type immune)" {
  let reflect_user = rf_pokemon(
    "user", "エスパー", "", 200, 50, 100, 50, 100, 100,
  )
  let incoming = rf_pokemon(
    "incoming", "あく", "", 200, 50, 100, 200, 100, 100,
  )
  let reflect_mv = rf_move("ミラーコート", "エスパー", @model.Special, 1)
  let incoming_mv = rf_move("あくのはどう", "あく", @model.Special, 80)
  let input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  let r = calc_damage(input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(r.damages[i], content="0")
  }
}

///|
test "reflect: category mismatch → 0 (Counter vs special incoming)" {
  let reflect_user = rf_pokemon(
    "user", "ノーマル", "", 200, 50, 100, 50, 100, 100,
  )
  let incoming = rf_pokemon(
    "incoming", "ノーマル", "", 200, 50, 100, 200, 100, 100,
  )
  let reflect_mv = rf_move("カウンター", "かくとう", @model.Physical, 1)
  // Special move → Counter rejects it.
  let incoming_mv = rf_move("ねっぷう", "ほのお", @model.Special, 95)
  let input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  let r = calc_damage(input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(r.damages[i], content="0")
  }
}

///|
test "reflect: category mismatch → 0 (MirrorCoat vs physical incoming)" {
  let reflect_user = rf_pokemon(
    "user", "エスパー", "", 200, 50, 100, 50, 100, 100,
  )
  let incoming = rf_pokemon(
    "incoming", "ノーマル", "", 200, 200, 100, 50, 100, 100,
  )
  let reflect_mv = rf_move("ミラーコート", "エスパー", @model.Special, 1)
  // Physical move → MirrorCoat rejects it.
  let incoming_mv = rf_move("たいあたり", "ノーマル", @model.Physical, 40)
  let input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  let r = calc_damage(input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(r.damages[i], content="0")
  }
}

///|
test "reflect: incoming unset → 0 (engine safe fallback)" {
  let reflect_user = rf_pokemon(
    "user", "ノーマル", "", 200, 50, 100, 50, 100, 100,
  )
  let any = rf_pokemon("any", "ノーマル", "", 200, 50, 100, 50, 100, 100)
  let reflect_mv = rf_move("カウンター", "かくとう", @model.Physical, 1)
  let any_mv = rf_move("たいあたり", "ノーマル", @model.Physical, 40)
  let mut input = rf_input(reflect_user, reflect_mv, any, any_mv)
  // Drop incoming_* to simulate the CLI-layer-bypassed misuse.
  input = { ..input, incoming: None }
  let r = calc_damage(input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(r.damages[i], content="0")
  }
}

///|
/// Regression: outer atk_ability is the reflect user's ability and must
/// drive Step1 defender-side immunity. Before the role-mapping fix, the
/// engine read reflect-user defensive modifiers from `input.def_*`, so
/// `--atk-ability ふゆう` (reflect user) was silently ignored against an
/// incoming じめん move. After the fix, Step1 returns is_immune=true and
/// reflect returns all-zero with ko_text="failed".
test "reflect: outer atk_ability ふゆう blocks じしん incoming" {
  // Reflect user (Normal type so it isn't immune by type; ability does it).
  let reflect_user = rf_pokemon(
    "user", "ノーマル", "", 200, 50, 100, 50, 100, 100,
  )
  let incoming = rf_pokemon(
    "incoming", "じめん", "", 200, 200, 100, 50, 100, 100,
  )
  let reflect_mv = rf_move("カウンター", "かくとう", @model.Physical, 1)
  let incoming_mv = rf_move("じしん", "じめん", @model.Physical, 100)
  let mut input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  input = { ..input, atk_ability: "ふゆう" }
  let r = calc_damage(input)
  for i = 0; i < 16; i = i + 1 {
    @debug.debug_inspect(r.damages[i], content="0")
  }
  @debug.debug_inspect(r.ko_text, content="\"failed\"")
}

///|
/// Regression: outer def_ability must NOT be applied to the reflect user.
/// `--def-ability ふゆう` is for the reflected target, not the reflect
/// user, so an incoming じしん still lands on the reflect user. The
/// converse of the previous test — defender ability does not grant Step1
/// immunity to the reflect user.
test "reflect: outer def_ability does not grant Step1 immunity to reflect user" {
  let reflect_user = rf_pokemon(
    "user", "ノーマル", "", 200, 50, 100, 50, 100, 100,
  )
  let incoming = rf_pokemon(
    "incoming", "じめん", "", 200, 200, 100, 50, 100, 100,
  )
  let reflect_mv = rf_move("カウンター", "かくとう", @model.Physical, 1)
  let incoming_mv = rf_move("じしん", "じめん", @model.Physical, 100)
  let mut input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  input = { ..input, def_ability: "ふゆう" }
  let r = calc_damage(input)
  // Damage is non-zero because the reflected target's ふゆう has no effect
  // on the reflect user's Step1 defensive context.
  @debug.debug_inspect(r.max_damage > 0, content="true")
}

///|
/// Regression: --def-hp affects percent / KO context for reflect results.
/// Before the fix, target_hp came from `incoming_attacker.hp` (raw base)
/// and ignored `def_hp_override` entirely. After the fix, target_hp is
/// computed from `input.defender` via calc_def_stat with the override
/// applied — identical semantics to non-reflect damage.
test "reflect: def_hp_override drives reflect-target percent denominator" {
  let reflect_user = rf_pokemon(
    "user", "ノーマル", "", 200, 50, 100, 50, 100, 100,
  )
  let incoming = rf_pokemon(
    "incoming", "ノーマル", "", 200, 200, 100, 50, 100, 100,
  )
  let reflect_mv = rf_move("カウンター", "かくとう", @model.Physical, 1)
  let incoming_mv = rf_move("たいあたり", "ノーマル", @model.Physical, 40)
  let mut input = rf_input(reflect_user, reflect_mv, incoming, incoming_mv)
  // Override the reflect target's HP to a fixed value.
  input = { ..input, def_hp_override: 100 }
  let r = calc_damage(input)
  @debug.debug_inspect(r.defender_hp, content="100")
  // Percent denominator follows defender_hp.
  let expected_pct = r.damages[0].to_double() / 100.0 * 100.0
  @debug.debug_inspect(r.percents[0] == expected_pct, content="true")
}
