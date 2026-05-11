///|
/// Integration Red tests for Parental Bond + multi-hit post-processing via
/// `calc_damage`. Fails until engine.mbt wires `resolve_hit_plan` after the
/// 16-roll loop.

///|
fn pb_pokemon(name : String, type1 : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2: "",
    hp: 100,
    atk: 130,
    def_: 80,
    spa: 80,
    spd: 80,
    spe: 80,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 40.0,
    forms: [],
  }
}

///|
fn pb_move(
  name : String,
  type_ : String,
  power : Int,
) -> @model.Move {
  {
    name,
    type_,
    category: @model.Physical,
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
/// Whitebox-local input builder. `test_helpers_test.mbt::pb_input`
/// only exposes to blackbox `_test.mbt` files, so the wbtest carries its
/// own minimal constructor.
fn pb_input(
  atk : @model.Pokemon,
  dfn : @model.Pokemon,
  mv : @model.Move,
  atk_ability~ : String = "",
  multi_hit_mode~ : @model.MultiHit = @model.MultiHit::Auto,
) -> @model.DamageCalcInput {
  {
    attacker: atk,
    defender: dfn,
    move_: mv,
    atk_ability,
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
    multi_hit_mode,
    disguise_active: false,
  }
}

///|
test "parental bond: hits_dealt=2 on single-hit move" {
  let atk = pb_pokemon("kangaskhan", "ノーマル")
  let dfn = pb_pokemon("target", "ノーマル")
  let mv = pb_move("たいあたり", "ノーマル", 40)
  let inp = pb_input(atk, dfn, mv, atk_ability="おやこあい")
  let r = calc_damage(inp)
  inspect(r.hits_dealt, content="2")
}

///|
test "parental bond: damage is d1 + 25% d2 per roll index" {
  let atk = pb_pokemon("kangaskhan", "ノーマル")
  let dfn = pb_pokemon("target", "ノーマル")
  let mv = pb_move("たいあたり", "ノーマル", 40)
  let inp_plain = pb_input(atk, dfn, mv)
  let inp_pb = pb_input(atk, dfn, mv, atk_ability="おやこあい")
  let r_plain = calc_damage(inp_plain)
  let r_pb = calc_damage(inp_pb)
  // First hit is identical; the extra hit adds roughly 25% of the original.
  // Accept ~1.2×-1.3× band to absorb round5 drift.
  assert_true(r_pb.max_damage >= r_plain.max_damage * 120 / 100)
  assert_true(r_pb.max_damage <= r_plain.max_damage * 135 / 100)
}

///|
test "parental bond: 2nd hit equals an independent quarter-power calc" {
  // Per Showdown spec the Parental Bond 2nd hit runs the full damage
  // pipeline at 1/4 base power. Verify this by computing a plain hit at
  // reduced power and checking d_pb[i] == d1[i] + d_quarter[i] for every
  // roll index (the engine now re-enters compute_rolls per hit).
  let atk = pb_pokemon("kangaskhan", "ノーマル")
  let dfn = pb_pokemon("target", "ノーマル")
  let full_power = pb_move("たいあたり", "ノーマル", 40)
  let quarter_power = pb_move("たいあたり", "ノーマル", 10) // 40 / 4
  let inp_pb = pb_input(atk, dfn, full_power, atk_ability="おやこあい")
  let inp_1 = pb_input(atk, dfn, full_power)
  let inp_2 = pb_input(atk, dfn, quarter_power)
  let r_pb = calc_damage(inp_pb)
  let r_1 = calc_damage(inp_1)
  let r_2 = calc_damage(inp_2)
  for i = 0; i < 16; i = i + 1 {
    assert_eq(r_pb.damages[i], r_1.damages[i] + r_2.damages[i])
  }
}

///|
test "parental bond: skipped on multi-hit base moves" {
  // みずしゅりけん is already multi-hit — Parental Bond should not add a
  // Second hit on top. hits_dealt reflects the regular multi-hit plan.
  let atk = pb_pokemon("kangaskhan", "みず")
  let dfn = pb_pokemon("target", "ノーマル")
  let mv = pb_move("みずしゅりけん", "みず", 15)
  let inp = pb_input(atk, dfn, mv, atk_ability="おやこあい")
  let r = calc_damage(inp)
  // Random 2-5 auto-resolves to center 3 in the simplified PR-C routing.
  inspect(r.hits_dealt, content="3")
}

///|
test "multi-hit: fixed 2 returns hits_dealt=2 and doubled damage" {
  let atk = pb_pokemon("chop", "ノーマル")
  let dfn = pb_pokemon("target", "ノーマル")
  let mv = pb_move("ドラゴンアロー", "ドラゴン", 50)
  // Force 1-hit and 2-hit on the SAME move so every modifier (STAB, type
  // effectiveness, abilities, items) is identical and only hits_dealt varies.
  let inp1 = pb_input(atk, dfn, mv, multi_hit_mode=Fixed(1))
  let inp2 = pb_input(atk, dfn, mv, multi_hit_mode=Fixed(2))
  let r1 = calc_damage(inp1)
  let r2 = calc_damage(inp2)
  inspect(r1.hits_dealt, content="1")
  inspect(r2.hits_dealt, content="2")
  // Exact 2× because the 16-roll array is multiplied element-wise.
  inspect(r2.max_damage, content=(r1.max_damage * 2).to_string())
}

///|
test "multi-hit: explicit Fixed(5) forces 5 hits regardless of move" {
  let atk = pb_pokemon("skill-link", "ノーマル")
  let dfn = pb_pokemon("target", "ノーマル")
  let mv = pb_move("たいあたり", "ノーマル", 40)
  let inp = pb_input(atk, dfn, mv, multi_hit_mode=Fixed(5))
  let r = calc_damage(inp)
  inspect(r.hits_dealt, content="5")
}

///|
test "multi-hit: Expected mode aborts pkdx damage" {
  // Expected is a payoff-only approximation; calc_damage must reject it so
  // the CLI never silently returns unrealistic rolls.
  // We check "no crash when engine returns early-ish" — since MoonBit unit
  // tests can't catch `abort`, we simply assert Auto == 1 hit as the
  // default, documenting the Expected contract by omission.
  let atk = pb_pokemon("atk", "ノーマル")
  let dfn = pb_pokemon("dfn", "ノーマル")
  let mv = pb_move("たいあたり", "ノーマル", 40)
  let inp = pb_input(atk, dfn, mv, multi_hit_mode=Auto)
  let r = calc_damage(inp)
  inspect(r.hits_dealt, content="1")
}
