///|
/// フリーズドライの特殊相性 (みずタイプに 2 倍) のテスト。
/// 期待値は「同ステータスで通常チャートが同じ倍率になる疑似防御タイプ」に
/// 同威力のこおり技を撃った結果と突き合わせる equality-by-construction 方式。
/// (こおり→ひこう = 2 倍がチャート由来の 2 倍のリファレンスになる)

///|
/// グレイシア (65/60/110/130/95/65) こおり単
fn fixture_glaceon() -> @model.Pokemon {
  mk_pokemon_typed("グレイシア", "こおり", "", 65, 60, 110, 130, 95, 65)
}

///|
/// シャワーズ (130/65/60/110/95/65) みず単
fn fixture_vaporeon() -> @model.Pokemon {
  mk_pokemon_typed("シャワーズ", "みず", "", 130, 65, 60, 110, 95, 65)
}

///|
/// シャワーズと同ステータスの疑似防御。type は呼び出し側で指定し、
/// 通常チャートで目標倍率を再現するために使う。
fn fixture_vaporeon_stats_as(
  type1 : String,
  type2 : String,
) -> @model.Pokemon {
  mk_pokemon_typed("疑似シャワーズ", type1, type2, 130, 65, 60, 110, 95, 65)
}

///|
/// ギャラドス (95/125/79/60/100/81) みず/ひこう
fn fixture_gyarados() -> @model.Pokemon {
  mk_pokemon_typed("ギャラドス", "みず", "ひこう", 95, 125, 79, 60, 100, 81)
}

///|
/// ギャラドスと同ステータスの疑似防御
fn fixture_gyarados_stats_as(
  type1 : String,
  type2 : String,
) -> @model.Pokemon {
  mk_pokemon_typed("疑似ギャラドス", type1, type2, 95, 125, 79, 60, 100, 81)
}

///|
/// ラプラス (130/85/80/85/95/60) みず/こおり
fn fixture_lapras() -> @model.Pokemon {
  mk_pokemon_typed("ラプラス", "みず", "こおり", 130, 85, 80, 85, 95, 60)
}

///|
/// ラプラスと同ステータスの疑似防御
fn fixture_lapras_stats_as(type1 : String, type2 : String) -> @model.Pokemon {
  mk_pokemon_typed("疑似ラプラス", type1, type2, 130, 85, 80, 85, 95, 60)
}

///|
/// ナットレイ (74/94/131/54/116/20) くさ/はがね — みずを含まないコントロール
fn fixture_ferrothorn() -> @model.Pokemon {
  mk_pokemon_typed("ナットレイ", "くさ", "はがね", 74, 94, 131, 54, 116, 20)
}

///|
/// フリーズドライ (こおり, 特殊, 威力70)
fn fixture_freeze_dry() -> @model.Move {
  mk_move("フリーズドライ", "こおり", @model.Special, 70)
}

///|
/// 名前上書きなしの同威力こおり技 (リファレンス用)
fn fixture_plain_ice_move() -> @model.Move {
  mk_move("こおりテスト技", "こおり", @model.Special, 70)
}

///|
test "freeze-dry: 2x vs pure Water (matches chart 2x reference)" {
  // フリーズドライ vs みず単 == 同威力こおり技 vs ひこう単 (チャート2倍)
  let fd = calc_damage(
    mk_damage_input(fixture_glaceon(), fixture_vaporeon(), fixture_freeze_dry()),
  )
  let expected = calc_damage(
    mk_damage_input(
      fixture_glaceon(),
      fixture_vaporeon_stats_as("ひこう", ""),
      fixture_plain_ice_move(),
    ),
  )
  for i = 0; i < 16; i = i + 1 {
    assert_true(fd.damages[i] == expected.damages[i])
  }
  assert_eq(fd.max_damage, expected.max_damage)
}

///|
test "freeze-dry: pinned max damage vs Vaporeon" {
  // グレイシア C182(+10%)=200 / シャワーズ H205 D115 無振り想定 (engine デフォルト)。
  // 最大ロール: base 55 → STAB 82 (82.5 half-down) → 2 倍 = 164 (H205 の 80.0%)
  let fd = calc_damage(
    mk_damage_input(fixture_glaceon(), fixture_vaporeon(), fixture_freeze_dry()),
  )
  @debug.debug_inspect(
    fd.max_damage,
    content=(
      #|164
    ),
  )
}

///|
test "freeze-dry: 4x vs Water/Flying (Gyarados)" {
  // みず側 2 倍上書き × ひこう 2 倍 = 4 倍 == こおり技 vs ひこう/ドラゴン
  let fd = calc_damage(
    mk_damage_input(fixture_glaceon(), fixture_gyarados(), fixture_freeze_dry()),
  )
  let expected = calc_damage(
    mk_damage_input(
      fixture_glaceon(),
      fixture_gyarados_stats_as("ひこう", "ドラゴン"),
      fixture_plain_ice_move(),
    ),
  )
  for i = 0; i < 16; i = i + 1 {
    assert_true(fd.damages[i] == expected.damages[i])
  }
}

///|
test "freeze-dry: 1x vs Water/Ice (Lapras)" {
  // みず側 2 倍上書き × こおり 0.5 倍 = 等倍 == こおり技 vs ひこう/こおり
  let fd = calc_damage(
    mk_damage_input(fixture_glaceon(), fixture_lapras(), fixture_freeze_dry()),
  )
  let expected = calc_damage(
    mk_damage_input(
      fixture_glaceon(),
      fixture_lapras_stats_as("ひこう", "こおり"),
      fixture_plain_ice_move(),
    ),
  )
  for i = 0; i < 16; i = i + 1 {
    assert_true(fd.damages[i] == expected.damages[i])
  }
}

///|
test "freeze-dry: non-Water defender unchanged (Ferrothorn)" {
  // みずを含まない相手には通常チャート通り (くさ2倍 × はがね0.5倍 = 等倍)
  let fd = calc_damage(
    mk_damage_input(
      fixture_glaceon(),
      fixture_ferrothorn(),
      fixture_freeze_dry(),
    ),
  )
  let plain = calc_damage(
    mk_damage_input(
      fixture_glaceon(),
      fixture_ferrothorn(),
      fixture_plain_ice_move(),
    ),
  )
  for i = 0; i < 16; i = i + 1 {
    assert_true(fd.damages[i] == plain.damages[i])
  }
}

///|
test "freeze-dry: other Ice moves keep 0.5x vs Water" {
  // フリーズドライ以外のこおり技は従来通り == こおり技 vs こおり単 (0.5倍)
  let plain = calc_damage(
    mk_damage_input(
      fixture_glaceon(),
      fixture_vaporeon(),
      fixture_plain_ice_move(),
    ),
  )
  let expected = calc_damage(
    mk_damage_input(
      fixture_glaceon(),
      fixture_vaporeon_stats_as("こおり", ""),
      fixture_plain_ice_move(),
    ),
  )
  for i = 0; i < 16; i = i + 1 {
    assert_true(plain.damages[i] == expected.damages[i])
  }
}

///|
test "freeze-dry: Yache Berry triggers vs Water" {
  // 抜群扱いになるのでヤチェのみが発動し半減 == チャート2倍 (ひこう) + ヤチェ
  let fd = calc_damage(
    mk_damage_input(
      fixture_glaceon(),
      fixture_vaporeon(),
      fixture_freeze_dry(),
      def_item="ヤチェのみ",
    ),
  )
  let expected = calc_damage(
    mk_damage_input(
      fixture_glaceon(),
      fixture_vaporeon_stats_as("ひこう", ""),
      fixture_plain_ice_move(),
      def_item="ヤチェのみ",
    ),
  )
  for i = 0; i < 16; i = i + 1 {
    assert_true(fd.damages[i] == expected.damages[i])
  }
}

///|
test "is_super_effective: freeze-dry override via move_name" {
  // 技名なし = 従来チャート (こおり→みず 0.5倍)
  assert_eq(is_super_effective("こおり", "みず", ""), false)
  // フリーズドライ指定でみずに抜群
  assert_eq(
    is_super_effective("こおり", "みず", "", move_name="フリーズドライ"),
    true,
  )
  // みず/こおり は 2×0.5 = 等倍なので抜群ではない
  assert_eq(
    is_super_effective("こおり", "みず", "こおり", move_name="フリーズドライ"),
    false,
  )
  // みず/ひこう は 2×2 = 4倍
  assert_eq(
    is_super_effective("こおり", "みず", "ひこう", move_name="フリーズドライ"),
    true,
  )
  // みずを含まない相手は従来通り (くさ 2倍)
  assert_eq(
    is_super_effective("こおり", "くさ", "", move_name="フリーズドライ"),
    true,
  )
}
