///|
/// Integration tests for Disguise. Drives `calc_damage` end-to-end against a
/// ばけのかわ defender. When `disguise_active=true`, engine adds a 1/8 max-HP
/// chip on top of the move's normal damage and flags `disguise_blocked: true`
/// with `disguise_chip = def_hp / 8`.

///|
fn dg_pokemon(name : String, type1 : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2: "",
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 40.0,
    forms: [],
  }
}

///|
fn dg_move(
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
  }
}

///|
fn dg_input(
  atk : @model.Pokemon,
  dfn : @model.Pokemon,
  mv : @model.Move,
  def_ability~ : String = "",
  disguise_active~ : Bool = false,
) -> @model.DamageCalcInput {
  {
    attacker: atk,
    defender: dfn,
    move_: mv,
    atk_ability: "",
    def_ability,
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
    disguise_active,
    incoming: None,
  }
}

///|
test "disguise active + ばけのかわ → damages include 1/8 chip + base damage" {
  let atk = dg_pokemon("attacker", "ノーマル")
  // Normal type defender keeps the engine past the type-effectiveness check.
  // (Real Mimikyu is Ghost/Fairy, but that would short-circuit on Normal-vs-
  // Ghost immunity before the disguise check runs.)
  let dfn = dg_pokemon("mimikyu-normal", "ノーマル")
  let mv = dg_move("たいあたり", "ノーマル", @model.Physical, 40)
  let inp_active = dg_input(
    atk, dfn, mv, def_ability="ばけのかわ", disguise_active=true,
  )
  let r_active = calc_damage(inp_active)
  let inp_inactive = dg_input(
    atk, dfn, mv, def_ability="ばけのかわ", disguise_active=false,
  )
  let r_inactive = calc_damage(inp_inactive)
  let chip = r_inactive.defender_hp / 8
  assert_true(r_active.disguise_blocked)
  @debug.debug_inspect(r_active.disguise_chip, content=chip.to_string())
  // 各ロールに chip が加算されているはず。
  for i = 0; i < 16; i = i + 1 {
    assert_true(r_active.damages[i] == r_inactive.damages[i] + chip)
  }
  assert_true(r_active.min_damage == r_inactive.min_damage + chip)
  assert_true(r_active.max_damage == r_inactive.max_damage + chip)
  // is_immune stays false — disguise is a state transition, not type immunity.
  assert_true(!(r_active.is_immune))
}

///|
test "disguise inactive + ばけのかわ → damage as usual" {
  let atk = dg_pokemon("attacker", "ノーマル")
  // Mimikyu is Ghost/Fairy in-game, but we pick Normal to avoid Normal-vs-
  // Ghost immunity confusing the damage assertion.
  let dfn = dg_pokemon("mimikyu-normal", "ノーマル")
  let mv = dg_move("たいあたり", "ノーマル", @model.Physical, 40)
  let inp = dg_input(atk, dfn, mv, def_ability="ばけのかわ", disguise_active=false)
  let r = calc_damage(inp)
  assert_true(!(r.disguise_blocked))
  @debug.debug_inspect(r.disguise_chip, content="0")
  assert_true(r.max_damage > 0)
}

///|
test "disguise active + other ability → damage as usual (no spurious block)" {
  let atk = dg_pokemon("attacker", "ノーマル")
  let dfn = dg_pokemon("defender", "ノーマル")
  let mv = dg_move("たいあたり", "ノーマル", @model.Physical, 40)
  let inp = dg_input(atk, dfn, mv, def_ability="いかく", disguise_active=true)
  let r = calc_damage(inp)
  // disguise_active alone shouldn't trigger the block — only ばけのかわ does.
  assert_true(!(r.disguise_blocked))
  assert_true(r.max_damage > 0)
}
