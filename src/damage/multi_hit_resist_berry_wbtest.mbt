///|
/// Regression: resist berries must only halve the **first** qualifying hit
/// of a multi-hit move. Pre-fix the engine reused a single berry-halved
/// damage table for every hit, so a Skill-Link 5-hit attack into オッカのみ
/// got halved 5×. The fix splits the per-hit pipeline so the berry is
/// applied only on hit 0; later hits use a no-berry table.

///|
fn rb_pokemon(name : String, type1 : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
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
fn rb_move(name : String, type_ : String) -> @model.Move {
  {
    name,
    type_,
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
fn rb_input(
  attacker : @model.Pokemon,
  defender : @model.Pokemon,
  move_ : @model.Move,
  atk_ability~ : String = "",
  def_item~ : String = "",
) -> @model.DamageCalcInput {
  {
    attacker,
    defender,
    move_,
    atk_ability,
    def_ability: "",
    atk_item: "",
    def_item,
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
test "Skill Link みだれづき + オッカのみ: only hit 0 halved (5-hit ほのお SE)" {
  // くさ defender resists ほのお? No — くさ is 0.5x to ほのお (so ほのお
  // is super-effective on くさ). オッカのみ on くさ defender means each
  // ほのお hit is super-effective; pre-fix all 5 hits got halved.
  // Use みだれづき as the multi-hit + ほのお combo by overriding the move
  // type (engine doesn't enforce type ↔ move-name coupling).
  let atk = rb_pokemon("attacker", "ほのお")
  let dfn = rb_pokemon("defender", "くさ")
  let mv = rb_move("みだれづき", "ほのお")
  let with_berry = calc_damage(
    rb_input(atk, dfn, mv, atk_ability="スキルリンク", def_item="オッカのみ"),
  )
  let without_berry = calc_damage(
    rb_input(atk, dfn, mv, atk_ability="スキルリンク"),
  )
  // 5 hits guaranteed under Skill Link.
  inspect(with_berry.variants.length(), content="1")
  inspect(with_berry.variants[0].hits.length(), content="5")
  // First hit alone should be halved. Pre-fix: total ≈ no_berry / 2.
  // Post-fix: total ≈ no_berry - hit0_no_berry / 2 (i.e. 4 of 5 hits at full).
  // Lower-bound check: the new total must be strictly greater than
  // no_berry / 2 (the all-halved pathological case) and strictly less than
  // no_berry (since hit 0 still loses half).
  let with_total = with_berry.variants[0].total_damages[8]
  let without_total = without_berry.variants[0].total_damages[8]
  assert_true(with_total > without_total / 2)
  assert_true(with_total < without_total)
}

///|
test "fixed-3 すいりゅうれんだ + オッカのみ: hit 0 halved, hits 1-2 full" {
  let atk = rb_pokemon("attacker", "ほのお")
  let dfn = rb_pokemon("defender", "くさ")
  let mv = rb_move("すいりゅうれんだ", "ほのお")
  let r = calc_damage(rb_input(atk, dfn, mv, def_item="オッカのみ"))
  inspect(r.variants.length(), content="1")
  inspect(r.variants[0].hits.length(), content="3")
  let h0 = r.variants[0].hits[0].damage_per_roll[8]
  let h1 = r.variants[0].hits[1].damage_per_roll[8]
  let h2 = r.variants[0].hits[2].damage_per_roll[8]
  // Hit 0 must be ≈ half of hit 1 / hit 2 (within integer-rounding slack).
  // Hits 1 and 2 must be equal (no berry reduction either).
  inspect(h1 == h2, content="true")
  // Pre-fix h0 == h1 (all halved); post-fix h0 ≈ h1 / 2.
  assert_true(h0 < h1)
  assert_true(h0 * 2 >= h1 - 2 && h0 * 2 <= h1 + 2)
}

///|
test "single hit + オッカのみ unchanged: berry still halves the only hit" {
  // Sanity: the multi-hit fix must not regress single-hit berry behaviour.
  let atk = rb_pokemon("attacker", "ほのお")
  let dfn = rb_pokemon("defender", "くさ")
  let mv = rb_move("ひのこ", "ほのお")
  let with_berry = calc_damage(rb_input(atk, dfn, mv, def_item="オッカのみ"))
  let without_berry = calc_damage(rb_input(atk, dfn, mv))
  let w = with_berry.damages[8]
  let n = without_berry.damages[8]
  // Berry halves with 4096-base round5(2048), so w ≈ n / 2 within ±2.
  assert_true(w * 2 >= n - 2 && w * 2 <= n + 2)
}
