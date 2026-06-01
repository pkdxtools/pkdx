///|
/// Tests for へんげんじざい (Protean) / リベロ (Libero):
/// on the FIRST move after switch-in the user changes into the move's type
/// as it attacks, so that move gains STAB (1.5x). In Gen 9 this activates
/// only ONCE per switch-in: a `protean_consumed=true` input models a later
/// move where the ability has already fired, so no extra STAB is granted.
/// While Terastallized the type is locked and the ability does not activate.
///
/// These pin behavior by *ratio* and *equality* rather than hand-computed
/// Showdown rolls: the only effect is appending move_type to the STAB set,
/// which is fully characterized by (a) ~1.5x vs no ability on a non-matching
/// move, (b) suppression under Tera, (c) Protean == Libero, (d) no
/// double-count when the move already matches the user's type, (e) no STAB
/// once already consumed this switch-in.

///|
/// みず attacker firing a でんき move (non-matching, でんき→ノーマル = 1x).
/// リベロ should add STAB ~1.5x over the no-ability baseline.
test "libero: grants ~1.5x STAB on a non-matching move type" {
  let atk = mk_pokemon_typed("atk", "みず", "", 100, 100, 100, 120, 100, 100)
  let dfn = mk_pokemon_typed("dfn", "ノーマル", "", 100, 80, 80, 80, 80, 80)
  let mv = mk_move("でんき技", "でんき", @model.Special, 90)
  let inp_no = mk_damage_input(
    atk,
    dfn,
    mv,
    atk_nature=Some(neutral_nature()),
    def_nature=Some(neutral_nature()),
  )
  let inp_libero = mk_damage_input(
    atk,
    dfn,
    mv,
    atk_ability="リベロ",
    atk_nature=Some(neutral_nature()),
    def_nature=Some(neutral_nature()),
  )
  let r_no = calc_damage(inp_no)
  let r_libero = calc_damage(inp_libero)
  assert_true(r_libero.max_damage > r_no.max_damage)
  // 1.5x with 4096 rounding → bound to [1.4, 1.6] to absorb mid-pipeline rounding.
  assert_true(r_libero.max_damage * 10 >= r_no.max_damage * 14)
  assert_true(r_libero.max_damage * 10 <= r_no.max_damage * 16)
}

///|
/// へんげんじざい and リベロ are mechanically identical for damage.
test "protean == libero (identical damage)" {
  let atk = mk_pokemon_typed("atk", "みず", "", 100, 100, 100, 120, 100, 100)
  let dfn = mk_pokemon_typed("dfn", "ノーマル", "", 100, 80, 80, 80, 80, 80)
  let mv = mk_move("でんき技", "でんき", @model.Special, 90)
  let r_protean = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="へんげんじざい",
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  let r_libero = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="リベロ",
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  assert_eq(r_protean.min_damage, r_libero.min_damage)
  assert_eq(r_protean.max_damage, r_libero.max_damage)
}

///|
/// While Terastallized to a type that matches neither the move nor an original
/// type, Protean/Libero must NOT activate: the libero+tera result equals the
/// no-ability+tera baseline, and is strictly below the un-Tera libero (which
/// does get STAB).
test "libero: suppressed under Terastallization (no extra STAB)" {
  let atk = mk_pokemon_typed("atk", "みず", "", 100, 100, 100, 120, 100, 100)
  let dfn = mk_pokemon_typed("dfn", "ノーマル", "", 100, 80, 80, 80, 80, 80)
  let mv = mk_move("でんき技", "でんき", @model.Special, 90)
  let r_libero_tera = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="リベロ",
      tera_type="ほのお",
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  let r_noability_tera = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      tera_type="ほのお",
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  let r_libero_notera = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="リベロ",
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  // Tera gate: ability does nothing → equals plain tera baseline.
  assert_eq(r_libero_tera.min_damage, r_noability_tera.min_damage)
  assert_eq(r_libero_tera.max_damage, r_noability_tera.max_damage)
  // And strictly weaker than un-Tera libero (which DOES get STAB).
  assert_true(r_libero_tera.max_damage < r_libero_notera.max_damage)
}

///|
/// When the move already matches one of the user's types, リベロ grants no
/// extra multiplier (STAB is already present) — must equal the no-ability
/// natural-STAB result, not stack.
test "libero: no double-count when move already matches user type" {
  let atk = mk_pokemon_typed("atk", "みず", "", 100, 100, 100, 120, 100, 100)
  let dfn = mk_pokemon_typed("dfn", "ノーマル", "", 100, 80, 80, 80, 80, 80)
  let mv = mk_move("みず技", "みず", @model.Special, 90)
  let r_no = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  let r_libero = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="リベロ",
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  assert_eq(r_libero.max_damage, r_no.max_damage)
  assert_eq(r_libero.min_damage, r_no.min_damage)
}

///|
/// Gen 9 once-per-switch-in: when リベロ has already activated this switch-in
/// (`protean_consumed=true`), a later move of a non-matching type gets NO
/// auto-STAB. The consumed result must equal the no-ability baseline, and be
/// strictly below the un-consumed (first-use) libero which DOES get STAB.
/// This is the regression guard against modeling Protean/Libero as always-on.
test "libero: no STAB once already activated this switch-in (consumed)" {
  let atk = mk_pokemon_typed("atk", "みず", "", 100, 100, 100, 120, 100, 100)
  let dfn = mk_pokemon_typed("dfn", "ノーマル", "", 100, 80, 80, 80, 80, 80)
  let mv = mk_move("でんき技", "でんき", @model.Special, 90)
  let r_no = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  let r_libero_first = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="リベロ",
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  let r_libero_consumed = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="リベロ",
      protean_consumed=true,
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  // Consumed = no auto-STAB → identical to the no-ability baseline.
  assert_eq(r_libero_consumed.max_damage, r_no.max_damage)
  assert_eq(r_libero_consumed.min_damage, r_no.min_damage)
  // And strictly weaker than the first-use libero (which DOES get STAB).
  assert_true(r_libero_consumed.max_damage < r_libero_first.max_damage)
}

///|
/// Gen 9 regression: a Protean/Libero user firing a STATUS move must NOT
/// trigger the type-change/STAB path. 変化技はダメージを生まない攻撃でないため
/// STAB の概念がなく、ここで has_stab が立つと可変威力・status-like 経路へ波及
/// しうる (レビュー指摘)。みず使用者が非一致 (でんき) の変化技 (power 0) を撃っ
/// ても、リベロ / へんげんじざい の結果は無特性ベースラインと完全一致しなければ
/// ならない。ゲートが外れると STAB ×1.5 でダメージが増えて不一致になる。
test "protean/libero: does NOT activate on a status move (no auto-STAB leak)" {
  let atk = mk_pokemon_typed("atk", "みず", "", 100, 100, 100, 120, 100, 100)
  let dfn = mk_pokemon_typed("dfn", "ノーマル", "", 100, 80, 80, 80, 80, 80)
  // でんき変化技: 使用者タイプ みず とも防御 ノーマル とも非一致。
  let mv = mk_move("でんき変化技", "でんき", @model.Status, 0)
  let r_no = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  let r_libero = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="リベロ",
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  let r_protean = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="へんげんじざい",
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  // 変化技では auto-STAB が乗らない → 無特性と完全一致 (両特性とも)。
  assert_eq(r_libero.max_damage, r_no.max_damage)
  assert_eq(r_libero.min_damage, r_no.min_damage)
  assert_eq(r_protean.max_damage, r_no.max_damage)
  assert_eq(r_protean.min_damage, r_no.min_damage)
}

///|
/// へんげんじざい mirrors リベロ in the consumed case too: activating it
/// once-per-switch-in then using a non-matching move grants no STAB.
test "protean: consumed state matches libero consumed state" {
  let atk = mk_pokemon_typed("atk", "みず", "", 100, 100, 100, 120, 100, 100)
  let dfn = mk_pokemon_typed("dfn", "ノーマル", "", 100, 80, 80, 80, 80, 80)
  let mv = mk_move("でんき技", "でんき", @model.Special, 90)
  let r_protean_consumed = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="へんげんじざい",
      protean_consumed=true,
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  let r_libero_consumed = calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability="リベロ",
      protean_consumed=true,
      atk_nature=Some(neutral_nature()),
      def_nature=Some(neutral_nature()),
    ),
  )
  assert_eq(r_protean_consumed.max_damage, r_libero_consumed.max_damage)
  assert_eq(r_protean_consumed.min_damage, r_libero_consumed.min_damage)
}
