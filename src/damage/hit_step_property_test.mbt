///|
/// Property tests for hit-by-hit variants[] schema (issue #90).
/// Step 0 (Red Phase): these tests fail until DamageCalcResult.variants is
/// populated by the engine. They encode the chance-node soundness contract
/// that downstream phases (#91 / #92 / #93 / #97) depend on.

///|
fn hsp_pokemon(name : String) -> @model.Pokemon {
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
fn hsp_move(name : String) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
    power: 25,
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
fn hsp_input(
  attacker : @model.Pokemon,
  defender : @model.Pokemon,
  move_ : @model.Move,
  atk_ability~ : String = "",
) -> @model.DamageCalcInput {
  {
    attacker,
    defender,
    move_,
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
    multi_hit_mode: @model.MultiHit::Auto,
    disguise_active: false,
  }
}

///|
fn sum_probabilities(variants : Array[@model.DamageVariant]) -> Double {
  let mut s = 0.0
  for i = 0; i < variants.length(); i = i + 1 {
    s = s + variants[i].probability
  }
  s
}

///|
test "variants: probability sum is 1.0 ± 1e-9 for single-hit move" {
  let atk = hsp_pokemon("attacker")
  let dfn = hsp_pokemon("defender")
  let mv = hsp_move("じしん")
  let r = calc_damage(hsp_input(atk, dfn, mv))
  let s = sum_probabilities(r.variants)
  let delta = if s > 1.0 { s - 1.0 } else { 1.0 - s }
  assert_true(delta < 1.0e-9)
}

///|
test "variants: probability sum is 1.0 ± 1e-9 for triple-axel" {
  let atk = hsp_pokemon("attacker")
  let dfn = hsp_pokemon("defender")
  let mv = hsp_move("トリプルアクセル")
  let r = calc_damage(hsp_input(atk, dfn, mv))
  let s = sum_probabilities(r.variants)
  let delta = if s > 1.0 { s - 1.0 } else { 1.0 - s }
  assert_true(delta < 1.0e-9)
}

///|
test "variants: probability sum is 1.0 ± 1e-9 for random 2-5 hit move" {
  let atk = hsp_pokemon("attacker")
  let dfn = hsp_pokemon("defender")
  let mv = hsp_move("みだれづき")
  let r = calc_damage(hsp_input(atk, dfn, mv))
  let s = sum_probabilities(r.variants)
  let delta = if s > 1.0 { s - 1.0 } else { 1.0 - s }
  assert_true(delta < 1.0e-9)
}

///|
test "variants: every result has at least one variant" {
  // immune / disguise / single / multi-hit — all paths produce variants.length >= 1
  let atk = hsp_pokemon("attacker")
  let dfn = hsp_pokemon("defender")
  let mv = hsp_move("じしん")
  let r = calc_damage(hsp_input(atk, dfn, mv))
  assert_true(r.variants.length() >= 1)
}

///|
test "Skill Link + Random2to5 degenerates to variants=1 hits=5" {
  let atk = hsp_pokemon("attacker")
  let dfn = hsp_pokemon("defender")
  let mv = hsp_move("みだれづき")
  let r = calc_damage(hsp_input(atk, dfn, mv, atk_ability="スキルリンク"))
  inspect(r.variants.length(), content="1")
  inspect(r.variants[0].hits.length(), content="5")
}

///|
test "Random2to5 and TripleVariant are mutually exclusive on resolve_auto_hits" {
  // Mutual exclusion property: no move resolves to both Random2to5 and
  // (FixedHit(3) routed through TripleVariant). #91 leaf-count estimates
  // depend on this.
  let triple_set = ["トリプルアクセル", "トリプルキック"]
  for i = 0; i < triple_set.length(); i = i + 1 {
    let spec = resolve_auto_hits(triple_set[i])
    inspect(spec, content="FixedHit(3)")
  }
  let random_2_5 = ["みだれづき", "ロックブラスト", "みずしゅりけん"]
  for i = 0; i < random_2_5.length(); i = i + 1 {
    let spec = resolve_auto_hits(random_2_5[i])
    inspect(spec, content="Random2to5")
  }
}

///|
test "single-hit move produces variants[0].hits.length == 1" {
  let atk = hsp_pokemon("attacker")
  let dfn = hsp_pokemon("defender")
  let mv = hsp_move("じしん")
  let r = calc_damage(hsp_input(atk, dfn, mv))
  inspect(r.variants.length(), content="1")
  inspect(r.variants[0].hits.length(), content="1")
}

///|
test "ParentalBond produces variants=1 hits=2" {
  let atk = hsp_pokemon("attacker")
  let dfn = hsp_pokemon("defender")
  let mv = hsp_move("じしん")
  let r = calc_damage(hsp_input(atk, dfn, mv, atk_ability="おやこあい"))
  inspect(r.variants.length(), content="1")
  inspect(r.variants[0].hits.length(), content="2")
}
