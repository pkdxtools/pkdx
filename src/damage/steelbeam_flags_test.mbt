///|
/// てっていこうせん の move フラグ (Champions / Showdown 準拠):
/// - Mega Launcher (メガランチャー) の波動技ブースト対象ではない (Showdown
///   `flags` に `pulse` が無い。`data/moves.ts` steelbeam は `protect` / `mirror` のみ)。
/// - 使用者の最大 HP の 1/2 反動技 (`is_max_hp_recoil_move`)。
test "steel beam: Mega Launcher does not boost it (not a pulse move)" {
  @debug.assert_eq(@damage.is_pulse_move("てっていこうせん"), false)
  // 対照: 波動技 (はどうだん) は従来どおり 1.5 倍。
  @debug.assert_eq(@damage.is_pulse_move("はどうだん"), true)
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "メガランチャー",
      "てっていこうせん",
      "はがね",
      140,
      @model.Weather::None,
    ),
    140,
  )
  @debug.assert_eq(
    @damage.apply_atk_ability_power(
      "メガランチャー",
      "はどうだん",
      "かくとう",
      80,
      @model.Weather::None,
    ),
    120,
  )
}

///|
test "steel beam: self-damage flag is limited to てっていこうせん" {
  @debug.assert_eq(@damage.is_max_hp_recoil_move("てっていこうせん"), true)
  // Champions 非収録 (waza.json available=0) のマインドブロウは対象外。
  @debug.assert_eq(@damage.is_max_hp_recoil_move("マインドブロウ"), false)
  // 通常の反動技 (ブレイブバード) は既存の recoil_num 経路で扱い、本フラグは立たない。
  @debug.assert_eq(@damage.is_max_hp_recoil_move("ブレイブバード"), false)
  @debug.assert_eq(@damage.is_max_hp_recoil_move("インファイト"), false)
}
