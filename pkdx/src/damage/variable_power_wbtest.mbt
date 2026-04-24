///|
/// Whitebox tests for `resolve_move_type_override` and `resolve_variable_power`.
/// Fail until `variable_power.mbt` is implemented.

///|
fn vp_move(
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
fn vp_pokemon(name : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1: "ノーマル",
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
    weight: 0.0,
  }
}

///|
/// Minimal `DamageCalcInput` builder tuned for `resolve_variable_power` unit
/// tests. Only the fields the function under test reads vary per test.
fn vp_input(
  mv : @model.Move,
  atk : @model.Pokemon,
  dfn : @model.Pokemon,
  weather~ : @model.Weather = @model.Weather::None,
  def_rank_up_count~ : Int = 0,
  atk_rank_up_count~ : Int = 0,
  atk_hp_num~ : Int = 2,
  atk_hp_den~ : Int = 2,
  def_item_removable~ : Bool = false,
  def_item~ : String = "",
  def_status_condition~ : @model.StatusCondition = @model.StatusCondition::None,
  atk_status_condition~ : @model.StatusCondition = @model.StatusCondition::None,
  fainted_count~ : Int = 0,
) -> @model.DamageCalcInput {
  {
    attacker: atk,
    defender: dfn,
    move_: mv,
    atk_ability: "",
    def_ability: "",
    atk_item: "",
    def_item,
    weather,
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
    fainted_count,
    is_double: false,
    stat_system: @model.Standard,
    wall: @model.Wall::NoWall,
    screen_pierce: false,
    atk_status_condition,
    def_status_condition,
    atk_rank_up_count,
    def_rank_up_count,
    atk_hp_num,
    atk_hp_den,
    def_item_removable,
    multi_hit_mode: @model.MultiHit::Auto,
    disguise_active: false,
  }
}

// ---- resolve_move_type_override ----

///|
test "weather ball: no weather keeps normal 50" {
  let mv = vp_move("ウェザーボール", "ノーマル", @model.Special, 50)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"))
  let (p, t) = resolve_move_type_override(mv, inp)
  inspect(p, content="50")
  inspect(t, content="ノーマル")
}

///|
test "weather ball: sun promotes to 100 fire" {
  let mv = vp_move("ウェザーボール", "ノーマル", @model.Special, 50)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"), weather=Sun)
  let (p, t) = resolve_move_type_override(mv, inp)
  inspect(p, content="100")
  inspect(t, content="ほのお")
}

///|
test "weather ball: rain promotes to 100 water" {
  let mv = vp_move("ウェザーボール", "ノーマル", @model.Special, 50)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"), weather=Rain)
  let (_, t) = resolve_move_type_override(mv, inp)
  inspect(t, content="みず")
}

///|
test "weather ball: sand promotes to 100 rock" {
  let mv = vp_move("ウェザーボール", "ノーマル", @model.Special, 50)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"), weather=Sand)
  let (_, t) = resolve_move_type_override(mv, inp)
  inspect(t, content="いわ")
}

///|
test "weather ball: snow promotes to 100 ice" {
  let mv = vp_move("ウェザーボール", "ノーマル", @model.Special, 50)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"), weather=Snow)
  let (_, t) = resolve_move_type_override(mv, inp)
  inspect(t, content="こおり")
}

///|
test "move type override: unrelated move passes through" {
  let mv = vp_move("たいあたり", "ノーマル", @model.Physical, 40)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"), weather=Sun)
  let (p, t) = resolve_move_type_override(mv, inp)
  inspect(p, content="40")
  inspect(t, content="ノーマル")
}

// ---- resolve_variable_power ----

///|
test "stored power: +3 opponent produces 80" {
  let mv = vp_move("つけあがる", "エスパー", @model.Special, 20)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), def_rank_up_count=3,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="80")
}

///|
test "stored power: zero boosts keeps base 20" {
  let mv = vp_move("つけあがる", "エスパー", @model.Special, 20)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"))
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="20")
}

///|
test "assist power: +6 self produces 140" {
  let mv = vp_move("アシストパワー", "エスパー", @model.Special, 20)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), atk_rank_up_count=6,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="140")
}

///|
test "assist power: clamps at 860 for absurd boost counts" {
  let mv = vp_move("アシストパワー", "エスパー", @model.Special, 20)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), atk_rank_up_count=100,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="860")
}

///|
test "lash out: HP at 50% exactly doubles power" {
  // やけっぱち: self HP <= max/2 → 2x power
  let mv = vp_move("やけっぱち", "あく", @model.Physical, 75)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), atk_hp_num=1, atk_hp_den=2,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="150")
}

///|
test "lash out: HP at 51% keeps base power" {
  let mv = vp_move("やけっぱち", "あく", @model.Physical, 75)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), atk_hp_num=51, atk_hp_den=100,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="75")
}

///|
test "knock off: removable item boosts to 97" {
  let mv = vp_move("はたきおとす", "あく", @model.Physical, 65)
  let inp = vp_input(
    mv,
    vp_pokemon("a"),
    vp_pokemon("b"),
    def_item="オボンのみ",
    def_item_removable=true,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="97")
}

///|
test "knock off: no item keeps base 65" {
  let mv = vp_move("はたきおとす", "あく", @model.Physical, 65)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), def_item_removable=false,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="65")
}

///|
test "hex: burn defender doubles to 130" {
  let mv = vp_move("たたりめ", "ゴースト", @model.Special, 65)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), def_status_condition=Burn,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="130")
}

///|
test "hex: healthy defender keeps base 65" {
  let mv = vp_move("たたりめ", "ゴースト", @model.Special, 65)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"))
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="65")
}

///|
test "facade: burn attacker doubles power to 140" {
  // からげんき: 攻撃側のまひ / やけど / どく / もうどく で 2x。
  let mv = vp_move("からげんき", "ノーマル", @model.Physical, 70)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), atk_status_condition=Burn,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="140")
}

///|
test "facade: poison attacker doubles power" {
  let mv = vp_move("からげんき", "ノーマル", @model.Physical, 70)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), atk_status_condition=Poison,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="140")
}

///|
test "facade: badly poisoned attacker doubles power" {
  let mv = vp_move("からげんき", "ノーマル", @model.Physical, 70)
  let inp = vp_input(
    mv,
    vp_pokemon("a"),
    vp_pokemon("b"),
    atk_status_condition=BadPoison(0),
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="140")
}

///|
test "facade: paralyzed attacker doubles power" {
  let mv = vp_move("からげんき", "ノーマル", @model.Physical, 70)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), atk_status_condition=Paralyze,
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="140")
}

///|
test "facade: sleep attacker keeps base power (can't act)" {
  // ねむり中は行動不能なので発動前提を満たさず base のまま。
  let mv = vp_move("からげんき", "ノーマル", @model.Physical, 70)
  let inp = vp_input(
    mv, vp_pokemon("a"), vp_pokemon("b"), atk_status_condition=Sleep(2),
  )
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="70")
}

///|
test "facade: healthy attacker keeps base power" {
  let mv = vp_move("からげんき", "ノーマル", @model.Physical, 70)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"))
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="70")
}

///|
test "existing weight move: body slam-like pass-through when not overridden" {
  // Non-variable move returns base power unchanged.
  let mv = vp_move("たいあたり", "ノーマル", @model.Physical, 40)
  let inp = vp_input(mv, vp_pokemon("a"), vp_pokemon("b"))
  let p = resolve_variable_power(
    mv.power, mv, inp, inp.defender, inp.attacker, "", "",
  )
  inspect(p, content="40")
}
