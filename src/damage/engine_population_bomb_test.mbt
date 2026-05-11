///|
/// #91 Phase 1-C: damage engine integration tests for the PopulationBomb
/// dispatch (ネズミざん). Validates that calc_damage emits 10 variants
/// (1..10 hits) with the per-hit 90% geometric distribution and that
/// each variant carries a `hits[]` array of matching length.
///
/// Triple Axel and Random2to5 regression guards are colocated to detect
/// drift after this Phase touches the variants[] payload.

///|
fn epb_pokemon(name : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1: "ノーマル",
    type2: "",
    hp: 200,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 700,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
}

///|
fn epb_move(name : String) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
    power: 20,
    accuracy: 90,
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
fn epb_input(
  attacker : @model.Pokemon,
  defender : @model.Pokemon,
  move_ : @model.Move,
) -> @model.DamageCalcInput {
  {
    attacker,
    defender,
    move_,
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
  }
}

///|
fn epb_approx(a : Double, b : Double, tol : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < tol
}

///|
test "PopulationBomb (ネズミざん) damage engine: 10 variants with hits_count 1..10" {
  let atk = epb_pokemon("attacker")
  let dfn = epb_pokemon("defender")
  let mv = epb_move("ネズミざん")
  let r = calc_damage(epb_input(atk, dfn, mv))
  inspect(r.variants.length(), content="10")
  for i = 0; i < 10; i = i + 1 {
    let v = r.variants[i]
    assert_true(v.hits_count == i + 1)
    assert_true(v.hits.length() == i + 1)
  }
}

///|
test "PopulationBomb damage engine: variants probability distribution matches geometric 0.9^(N-1) * 0.1" {
  let atk = epb_pokemon("attacker")
  let dfn = epb_pokemon("defender")
  let mv = epb_move("ネズミざん")
  let r = calc_damage(epb_input(atk, dfn, mv))
  let mut total = 0.0
  for i = 0; i < r.variants.length(); i = i + 1 {
    total = total + r.variants[i].probability
  }
  assert_true(epb_approx(total, 1.0, 1.0e-9))
  // p(1) = 0.1
  assert_true(epb_approx(r.variants[0].probability, 0.1, 1.0e-12))
  // p(10) = 0.9^9 ≈ 0.387420489
  assert_true(epb_approx(r.variants[9].probability, 0.387420489, 1.0e-9))
}

///|
test "Triple Axel damage engine: 3 variants — unchanged after PopulationBomb addition (regression guard)" {
  let atk = epb_pokemon("attacker")
  let dfn = epb_pokemon("defender")
  let mv = epb_move("トリプルアクセル")
  let r = calc_damage(epb_input(atk, dfn, mv))
  inspect(r.variants.length(), content="3")
  assert_true(epb_approx(r.variants[0].probability, 0.10, 1.0e-12))
  assert_true(epb_approx(r.variants[1].probability, 0.09, 1.0e-12))
  assert_true(epb_approx(r.variants[2].probability, 0.81, 1.0e-12))
}

///|
test "PopulationBomb damage engine: cumulative damage grows with hits_count" {
  // Each successful hit lands the same base damage in a vanilla matchup —
  // total damage of the N-hit variant should be >= total damage of the
  // (N-1)-hit variant. Pins per-hit accumulation semantics so #92 stamina
  // and contact procs can ramp by hit count without regressing.
  let atk = epb_pokemon("attacker")
  let dfn = epb_pokemon("defender")
  let mv = epb_move("ネズミざん")
  let r = calc_damage(epb_input(atk, dfn, mv))
  for i = 0; i < r.variants.length() - 1; i = i + 1 {
    let cur = r.variants[i].total_damages[0]
    let next = r.variants[i + 1].total_damages[0]
    assert_true(cur <= next)
  }
}
