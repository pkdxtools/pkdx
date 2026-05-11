///|
/// Whitebox tests pinning the Gen 7+ ate-ability semantics:
/// the type-changing skin (Pixilate / Aerilate / Refrigerate / Galvanize)
/// applies 1.2x to base power BEFORE damage calculation, not as a
/// post-STAB damage modifier. Reference values cross-checked against
/// Pokemon Showdown.

///|
test "ate skin: フェアリースキン on ハイパーボイス matches Showdown rolls" {
  // ニンフィア (C=158 pre-rank, no nature) → ガブリアス (HP=183, D=105).
  // ハイパーボイス double battle (spread 0.75x).
  // Showdown reference: 138-164, 確定2発.
  let atk = mk_pokemon_typed("ニンフィア", "フェアリー", "", 95, 65, 65, 110, 130, 60)
  let dfn = mk_pokemon_typed("ガブリアス", "ドラゴン", "じめん", 108, 130, 95, 80, 85, 102)
  let mv = mk_move("ハイパーボイス", "ノーマル", @model.Special, 90)
  let inp = mk_damage_input(
    atk, dfn, mv,
    atk_ability="フェアリースキン",
    atk_stat_override=158,
    def_stat_override=105,
    def_hp_override=183,
    atk_nature=Some(neutral_nature()),
    def_nature=Some(neutral_nature()),
    is_double=true,
  )
  let r = calc_damage(inp)
  inspect(r.is_immune, content="false")
  inspect(r.min_damage, content="138")
  inspect(r.max_damage, content="164")
  inspect(r.ko_text, content="確定2発")
}

///|
test "ate skin: フェアリースキン crit on ハイパーボイス matches Showdown rolls" {
  // Same matchup, critical hit. Showdown: 206-246, 確定1発.
  let atk = mk_pokemon_typed("ニンフィア", "フェアリー", "", 95, 65, 65, 110, 130, 60)
  let dfn = mk_pokemon_typed("ガブリアス", "ドラゴン", "じめん", 108, 130, 95, 80, 85, 102)
  let mv = mk_move("ハイパーボイス", "ノーマル", @model.Special, 90)
  let inp = mk_damage_input(
    atk, dfn, mv,
    atk_ability="フェアリースキン",
    atk_stat_override=158,
    def_stat_override=105,
    def_hp_override=183,
    atk_nature=Some(neutral_nature()),
    def_nature=Some(neutral_nature()),
    is_double=true,
    critical=true,
  )
  let r = calc_damage(inp)
  inspect(r.min_damage, content="206")
  inspect(r.max_damage, content="246")
  inspect(r.ko_text, content="確定1発")
}

///|
test "ate skin: type override drops Normal STAB but adds new-type STAB if matched" {
  // フェアリースキン on a Fairy attacker → STAB applies through the new type.
  // Without skin (= without ability), Normal STAB would NOT apply because
  // attacker is pure Fairy. Pinning the difference confirms type rewriting.
  let atk = mk_pokemon_typed("ニンフィア", "フェアリー", "", 95, 65, 65, 110, 130, 60)
  let dfn = mk_pokemon_typed("dummy", "ノーマル", "", 100, 80, 80, 80, 80, 80)
  let mv = mk_move("ハイパーボイス", "ノーマル", @model.Special, 90)
  let inp_skin = mk_damage_input(
    atk, dfn, mv,
    atk_ability="フェアリースキン",
    atk_nature=Some(neutral_nature()),
    def_nature=Some(neutral_nature()),
  )
  let inp_no_skin = mk_damage_input(
    atk, dfn, mv,
    atk_nature=Some(neutral_nature()),
    def_nature=Some(neutral_nature()),
  )
  let r_skin = calc_damage(inp_skin)
  let r_no = calc_damage(inp_no_skin)
  // skin: Fairy STAB 1.5x AND power 1.2x → both apply on top of no-skin Normal.
  // Mathematically the ratio is 1.5 * 1.2 = 1.8.
  assert_true(r_skin.max_damage * 10 >= r_no.max_damage * 17)
  assert_true(r_skin.max_damage * 10 <= r_no.max_damage * 19)
}
