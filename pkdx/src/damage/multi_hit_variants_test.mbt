///|
/// Variant-count and probability tests for hit-by-hit damage variants.
/// Pinned values (0.2/0.2/0.6 for triple-axel, 0.375/0.375/0.125/0.125 for
/// 2-5 hit) are the contract that #91 fanout layer depends on.

///|
fn mhv_pokemon(name : String) -> @model.Pokemon {
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
fn mhv_move(name : String) -> @model.Move {
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
fn mhv_input(
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
fn approx_eq(a : Double, b : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < 1.0e-9
}

///|
test "triple-axel: 3 variants with probabilities 0.2 / 0.2 / 0.6" {
  let atk = mhv_pokemon("attacker")
  let dfn = mhv_pokemon("defender")
  let mv = mhv_move("トリプルアクセル")
  let r = calc_damage(mhv_input(atk, dfn, mv))
  inspect(r.variants.length(), content="3")
  // 1 hit, 2 hit, 3 hit (in order) — 途中外れ仕様
  assert_true(approx_eq(r.variants[0].probability, 0.2))
  assert_true(approx_eq(r.variants[1].probability, 0.2))
  assert_true(approx_eq(r.variants[2].probability, 0.6))
  inspect(r.variants[0].hits.length(), content="1")
  inspect(r.variants[1].hits.length(), content="2")
  inspect(r.variants[2].hits.length(), content="3")
}

///|
test "fury attack (みだれづき): 4 variants with probabilities 0.375/0.375/0.125/0.125" {
  let atk = mhv_pokemon("attacker")
  let dfn = mhv_pokemon("defender")
  let mv = mhv_move("みだれづき")
  let r = calc_damage(mhv_input(atk, dfn, mv))
  inspect(r.variants.length(), content="4")
  assert_true(approx_eq(r.variants[0].probability, 0.375))
  assert_true(approx_eq(r.variants[1].probability, 0.375))
  assert_true(approx_eq(r.variants[2].probability, 0.125))
  assert_true(approx_eq(r.variants[3].probability, 0.125))
  inspect(r.variants[0].hits.length(), content="2")
  inspect(r.variants[1].hits.length(), content="3")
  inspect(r.variants[2].hits.length(), content="4")
  inspect(r.variants[3].hits.length(), content="5")
}

///|
test "Skill Link + fury attack: variants=1, hits=5" {
  let atk = mhv_pokemon("attacker")
  let dfn = mhv_pokemon("defender")
  let mv = mhv_move("みだれづき")
  let r = calc_damage(mhv_input(atk, dfn, mv, atk_ability="スキルリンク"))
  inspect(r.variants.length(), content="1")
  assert_true(approx_eq(r.variants[0].probability, 1.0))
  inspect(r.variants[0].hits.length(), content="5")
}

///|
test "fixed-3 non-variant move (すいりゅうれんだ): variants=1, hits=3" {
  // すいりゅうれんだ / トリプルダイブ are FixedHit(3), NOT TripleVariant —
  // they always land 3 hits, no probabilistic miss.
  let atk = mhv_pokemon("attacker")
  let dfn = mhv_pokemon("defender")
  let mv = mhv_move("すいりゅうれんだ")
  let r = calc_damage(mhv_input(atk, dfn, mv))
  inspect(r.variants.length(), content="1")
  inspect(r.variants[0].hits.length(), content="3")
}

///|
test "fixed-2 move (にどげり): variants=1, hits=2" {
  let atk = mhv_pokemon("attacker")
  let dfn = mhv_pokemon("defender")
  let mv = mhv_move("にどげり")
  let r = calc_damage(mhv_input(atk, dfn, mv))
  inspect(r.variants.length(), content="1")
  inspect(r.variants[0].hits.length(), content="2")
}

///|
test "single hit (たいあたり): variants=1, hits=1" {
  let atk = mhv_pokemon("attacker")
  let dfn = mhv_pokemon("defender")
  let mv = mhv_move("たいあたり")
  let r = calc_damage(mhv_input(atk, dfn, mv))
  inspect(r.variants.length(), content="1")
  inspect(r.variants[0].hits.length(), content="1")
}

///|
test "ParentalBond on single-hit base: variants=1, hits=2" {
  let atk = mhv_pokemon("attacker")
  let dfn = mhv_pokemon("defender")
  let mv = mhv_move("たいあたり")
  let r = calc_damage(mhv_input(atk, dfn, mv, atk_ability="おやこあい"))
  inspect(r.variants.length(), content="1")
  inspect(r.variants[0].hits.length(), content="2")
}

///|
test "triple-axel hits[i] damage_per_roll is monotonic in damage" {
  // Each hit lands the same base damage in a vanilla matchup — the cumulative
  // total_damages grows with hit count. This pins the per-hit semantics so
  // #92 (Stamina hit-loop) can introduce monotonic def stage growth.
  let atk = mhv_pokemon("attacker")
  let dfn = mhv_pokemon("defender")
  let mv = mhv_move("トリプルアクセル")
  let r = calc_damage(mhv_input(atk, dfn, mv))
  // 1-hit variant ≤ 2-hit variant ≤ 3-hit variant in total damage
  let t1 = r.variants[0].total_damages[0]
  let t2 = r.variants[1].total_damages[0]
  let t3 = r.variants[2].total_damages[0]
  assert_true(t1 <= t2)
  assert_true(t2 <= t3)
}
