///|
/// すてみ (Reckless) の威力補正。Showdown `data/abilities.ts` reckless:
/// `if (move.recoil || move.hasCrashDamage)` → `chainModify([4915, 4096])` (≒ 1.2x)。
/// 対象 = 通常の反動技 + 崩れ技 (とびひざげり / かかとおとし / サンダーダイブ)。
/// てっていこうせん は Showdown では `mindBlownRecoil` のみ (recoil / hasCrashDamage なし)
/// のため対象外。
test "reckless: crash moves (とびひざげり / かかとおとし / サンダーダイブ) get 1.2x" {
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "すてみ",
      "サンダーダイブ",
      "でんき",
      100,
      @model.Weather::None,
    ),
    120,
  )
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "すてみ",
      "とびひざげり",
      "かくとう",
      130,
      @model.Weather::None,
    ),
    156,
  )
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "すてみ",
      "かかとおとし",
      "かくとう",
      120,
      @model.Weather::None,
    ),
    144,
  )
}

///|
test "reckless: Steel Beam is not boosted (mindBlownRecoil only, per Showdown)" {
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "すてみ",
      "てっていこうせん",
      "はがね",
      140,
      @model.Weather::None,
    ),
    140,
  )
}

///|
test "reckless: normal recoil moves keep the boost" {
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "すてみ",
      "ブレイブバード",
      "ひこう",
      120,
      @model.Weather::None,
    ),
    144,
  )
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "すてみ",
      "すてみタックル",
      "ノーマル",
      120,
      @model.Weather::None,
    ),
    144,
  )
}

///|
test "reckless: moves that are neither recoil nor crash are not boosted" {
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "すてみ",
      "インファイト",
      "かくとう",
      120,
      @model.Weather::None,
    ),
    120,
  )
}

///|
test "reckless: other attacker abilities do not boost crash moves" {
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "もうか",
      "とびひざげり",
      "かくとう",
      130,
      @model.Weather::None,
    ),
    130,
  )
}

///|
/// Exact Lv50 damage through `calc_damage`. Attacker ゴースト (no STAB for any move
/// used here). Defender type is a parameter so that the effectiveness stays 1x:
/// ノーマル for でんき / ひこう / はがね moves, ほのお for かくとう moves (かくとう is 2x vs ノーマル).
/// No item / weather / crit. Stat overrides A = 200, D = 100.
/// base = floor(floor(22 * P * 200 / 100) / 50) + 2, roll = floor(base * r / 100), r = 85..100:
///   P=100 -> base 90 (76~90), P=120 -> 107 (90~107), P=130 -> 116 (98~116),
///   P=140 -> 125 (106~125), P=144 (120 boosted) -> 128 (108~128),
///   P=156 (130 boosted) -> 139 (118~139).
fn reckless_calc(
  mv : @model.Move,
  atk_ability : String,
  dfn_type : String,
) -> @model.DamageCalcResult {
  let atk = e2e_pokemon("reckless-atk", "ゴースト", 100, 80, 80, 80, 80, 80)
  let dfn = e2e_pokemon("reckless-dfn", dfn_type, 100, 80, 80, 80, 80, 80)
  @damage.calc_damage(
    mk_damage_input(
      atk,
      dfn,
      mv,
      atk_ability=atk_ability,
      atk_stat_override=200,
      def_stat_override=100,
    ),
  )
}

///|
test "reckless: exact damage, サンダーダイブ (crash) is boosted by すてみ" {
  let mv = mk_move("サンダーダイブ", "でんき", @model.Physical, 100)
  let off = reckless_calc(mv, "", "ノーマル")
  @debug.assert_eq(off.min_damage, 76)
  @debug.assert_eq(off.max_damage, 90)
  let on = reckless_calc(mv, "すてみ", "ノーマル")
  @debug.assert_eq(on.min_damage, 90)
  @debug.assert_eq(on.max_damage, 107)
}

///|
test "reckless: exact damage, とびひざげり (crash) is boosted by すてみ" {
  let mv = mk_move("とびひざげり", "かくとう", @model.Physical, 130)
  let off = reckless_calc(mv, "", "ほのお")
  @debug.assert_eq(off.min_damage, 98)
  @debug.assert_eq(off.max_damage, 116)
  let on = reckless_calc(mv, "すてみ", "ほのお")
  @debug.assert_eq(on.min_damage, 118)
  @debug.assert_eq(on.max_damage, 139)
}

///|
test "reckless: exact damage, かかとおとし (crash) is boosted by すてみ" {
  let mv = mk_move("かかとおとし", "かくとう", @model.Physical, 120)
  let off = reckless_calc(mv, "", "ほのお")
  @debug.assert_eq(off.min_damage, 90)
  @debug.assert_eq(off.max_damage, 107)
  let on = reckless_calc(mv, "すてみ", "ほのお")
  @debug.assert_eq(on.min_damage, 108)
  @debug.assert_eq(on.max_damage, 128)
}

///|
test "reckless: exact damage, ブレイブバード (recoil) keeps the すてみ boost" {
  let mv = mk_move("ブレイブバード", "ひこう", @model.Physical, 120)
  let off = reckless_calc(mv, "", "ノーマル")
  @debug.assert_eq(off.min_damage, 90)
  @debug.assert_eq(off.max_damage, 107)
  let on = reckless_calc(mv, "すてみ", "ノーマル")
  @debug.assert_eq(on.min_damage, 108)
  @debug.assert_eq(on.max_damage, 128)
}

///|
test "reckless: exact damage, てっていこうせん is not boosted by すてみ" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let off = reckless_calc(mv, "", "ノーマル")
  @debug.assert_eq(off.min_damage, 106)
  @debug.assert_eq(off.max_damage, 125)
  let on = reckless_calc(mv, "すてみ", "ノーマル")
  @debug.assert_eq(on.min_damage, 106)
  @debug.assert_eq(on.max_damage, 125)
}
