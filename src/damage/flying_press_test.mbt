///|
/// フライングプレスの複合相性。
/// 期待値は Showdown `onEffectiveness` (技タイプの typeMod + ひこう) と
/// Bulbapedia の単タイプ表に合わせ、ダメージは「同じ x4 スロットになる
/// 通常技」との equality-by-construction でピンする。
/// STAB・半減実のタイプ一致・タイプ強化道具は技タイプ (かくとう) のみ。
/// 抜群ゲート (たつじんのおび / フィルター / プリズムアーマー / いろめがね /
/// ヨプのみ) は複合後の倍率。

///|
fn fp_mon(type1 : String, type2 : String) -> @model.Pokemon {
  mk_pokemon_typed(
    "フライングプレス試験", type1, type2, 160, 90, 110, 80, 100, 70,
  )
}

///|
fn fp_move() -> @model.Move {
  mk_move("フライングプレス", "かくとう", @model.Physical, 100)
}

///|
fn fp_typed(name : String, type_ : String) -> @model.Move {
  mk_move(name, type_, @model.Physical, 100)
}

///|
fn assert_same_rolls(
  actual : @model.DamageCalcResult,
  expected : @model.DamageCalcResult,
) -> Unit raise {
  assert_eq(actual.is_immune, expected.is_immune)
  for i = 0; i < 16; i = i + 1 {
    assert_true(actual.damages[i] == expected.damages[i])
  }
}

///|
test "flying press: extra effectiveness type is Flying" {
  match @damage.extra_effectiveness_type("フライングプレス") {
    Some(t) => assert_true(t == @types.Flying)
    None => assert_true(false)
  }
  match @damage.extra_effectiveness_type("フリーズドライ") {
    None => ()
    Some(_) => assert_true(false)
  }
  match @damage.extra_effectiveness_type("インファイト") {
    None => ()
    Some(_) => assert_true(false)
  }
}

///|
test "flying press: per-defender-type x4 is Fighting times Flying" {
  let fight = @types.Fighting
  let fly = @types.Flying
  let types = @types.all_types
  for i = 0; i < types.length(); i = i + 1 {
    let def = types[i]
    let expected = @types.get_effectiveness_x4(fight, def) *
      @types.get_effectiveness_x4(fly, def) /
      4
    assert_eq(
      @damage.move_effectiveness_x4("フライングプレス", fight, def),
      expected,
    )
  }
  // フリーズドライの上書きは追加タイプを持たないので従来どおり。
  assert_eq(
    @damage.move_effectiveness_x4(
      "フリーズドライ",
      @types.Ice,
      @types.Water,
    ),
    8,
  )
}

///|
test "flying press: changed move type still multiplies Flying" {
  // ノーマライズ相当: ノーマル × ひこう。ゴーストはノーマル無効のまま 0。
  // いわは 0.5 × 0.5 = 0.25 (x4 = 1)。くさは 1 × 2 = 2。
  assert_eq(
    @damage.move_effectiveness_x4(
      "フライングプレス",
      @types.Normal,
      @types.Ghost,
    ),
    0,
  )
  assert_eq(
    @damage.move_effectiveness_x4(
      "フライングプレス",
      @types.Normal,
      @types.Rock,
    ),
    1,
  )
  assert_eq(
    @damage.move_effectiveness_x4(
      "フライングプレス",
      @types.Normal,
      @types.Grass,
    ),
    8,
  )
  // そうでん相当: でんき × ひこう。
  // じめん無効は残る。みずは 2 × 1 = 2。くさは 0.5 × 2 = 1。
  assert_eq(
    @damage.move_effectiveness_x4(
      "フライングプレス",
      @types.Electric,
      @types.Ground,
    ),
    0,
  )
  assert_eq(
    @damage.move_effectiveness_x4(
      "フライングプレス",
      @types.Electric,
      @types.Water,
    ),
    8,
  )
  assert_eq(
    @damage.move_effectiveness_x4(
      "フライングプレス",
      @types.Electric,
      @types.Grass,
    ),
    4,
  )
  // フェアリースキン相当の 1 タイプ 4 倍: フェアリー 2 × ひこう 2。
  assert_eq(
    @damage.move_effectiveness_x4(
      "フライングプレス",
      @types.Fairy,
      @types.Fighting,
    ),
    16,
  )
}

///|
test "flying press: slots vs Steel/Rock are neutral, Ghost is immune" {
  let (steel, rock) = @damage.effectiveness_slots_x4(
    "フライングプレス",
    @types.Fighting,
    @types.Steel,
    Some(@types.Rock),
  )
  assert_eq(steel, 4)
  assert_eq(rock, 4)
  let (ghost, dark) = @damage.effectiveness_slots_x4(
    "フライングプレス",
    @types.Fighting,
    @types.Ghost,
    Some(@types.Dark),
  )
  assert_eq(ghost, 0)
  // あく単体なら 2 倍だが、ゴースト側が 0 なのでエンジンは無効。
  assert_eq(dark, 8)
}

///|
test "is_super_effective: flying press uses the product" {
  // くさ: かくとう等倍 × ひこう 2 倍 = 抜群。通常かくとうは抜群ではない。
  assert_eq(
    @damage.is_super_effective(
      "かくとう",
      "くさ",
      "",
      move_name="フライングプレス",
    ),
    true,
  )
  assert_eq(@damage.is_super_effective("かくとう", "くさ", ""), false)
  // はがね/いわ: 素のかくとうは 4 倍、フライングプレスは等倍。
  assert_eq(
    @damage.is_super_effective(
      "かくとう",
      "はがね",
      "いわ",
      move_name="フライングプレス",
    ),
    false,
  )
  assert_eq(
    @damage.is_super_effective("かくとう", "はがね", "いわ"),
    true,
  )
  // むし: 0.5 × 2 = 等倍。抜群でも半減でもない。
  assert_eq(
    @damage.is_super_effective(
      "かくとう",
      "むし",
      "",
      move_name="フライングプレス",
    ),
    false,
  )
  // でんき: 1 × 0.5 = 半減。
  assert_eq(
    @damage.is_super_effective(
      "かくとう",
      "でんき",
      "",
      move_name="フライングプレス",
    ),
    false,
  )
  // ゴーストは無効。
  assert_eq(
    @damage.is_super_effective(
      "かくとう",
      "ゴースト",
      "",
      move_name="フライングプレス",
    ),
    false,
  )
  // かくとう/ひこう: 2 × 0.5 = 等倍。
  assert_eq(
    @damage.is_super_effective(
      "かくとう",
      "かくとう",
      "ひこう",
      move_name="フライングプレス",
    ),
    false,
  )
}

///|
test "flying press: 2x vs Grass matches chart 2x reference" {
  // ノーマル使い (STAB なし)。くさへの複合 2 倍 = かくとう技のノーマル単 2 倍。
  let atk = fp_mon("ノーマル", "")
  let fp = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("くさ", ""), fp_move()),
  )
  let expected = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("ノーマル", ""),
      fp_typed("かくとうテスト技", "かくとう"),
    ),
  )
  assert_same_rolls(fp, expected)
  let naive = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("くさ", ""),
      fp_typed("かくとうテスト技", "かくとう"),
    ),
  )
  assert_true(fp.max_damage > naive.max_damage)
}

///|
test "flying press: 1x vs Steel/Rock, not the naive Fighting 4x" {
  let atk = fp_mon("ノーマル", "")
  let fp = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("はがね", "いわ"), fp_move()),
  )
  // かくとう vs みず/くさ は両スロット等倍。はがね/いわへの複合も両スロット等倍。
  let neutral = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("みず", "くさ"),
      fp_typed("かくとうテスト技", "かくとう"),
    ),
  )
  assert_same_rolls(fp, neutral)
  let naive = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("はがね", "いわ"),
      fp_typed("かくとうテスト技", "かくとう"),
    ),
  )
  assert_true(naive.max_damage > fp.max_damage)
}

///|
test "flying press: 1x vs Fighting/Flying matches mixed 2x then 0.5x" {
  // type1 かくとう = 2 倍、type2 ひこう = 0.5 倍。
  // ひこう技 vs かくとう/いわ が同じスロット順になる。
  let atk = fp_mon("ノーマル", "")
  let fp = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("かくとう", "ひこう"), fp_move()),
  )
  let expected = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("かくとう", "いわ"),
      fp_typed("ひこうテスト技", "ひこう"),
    ),
  )
  assert_same_rolls(fp, expected)
}

///|
test "flying press: Ghost is immune, a Flying move is not" {
  let atk = fp_mon("ノーマル", "")
  let fp = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("ゴースト", ""), fp_move()),
  )
  assert_true(fp.is_immune)
  assert_eq(fp.max_damage, 0)
  let ghost_dark = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("ゴースト", "あく"), fp_move()),
  )
  assert_true(ghost_dark.is_immune)
  let flying = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("ゴースト", ""),
      fp_typed("ひこうテスト技", "ひこう"),
    ),
  )
  assert_true(!flying.is_immune)
  assert_true(flying.max_damage > 0)
}

///|
test "flying press: STAB is Fighting only" {
  let grass = fp_mon("くさ", "")
  let fighting = @damage.calc_damage(
    mk_damage_input(fp_mon("かくとう", ""), grass, fp_move()),
  )
  let flying = @damage.calc_damage(
    mk_damage_input(fp_mon("ひこう", ""), grass, fp_move()),
  )
  let both = @damage.calc_damage(
    mk_damage_input(fp_mon("かくとう", "ひこう"), grass, fp_move()),
  )
  let normal = @damage.calc_damage(
    mk_damage_input(fp_mon("ノーマル", ""), grass, fp_move()),
  )
  assert_true(fighting.max_damage > flying.max_damage)
  assert_same_rolls(fighting, both)
  assert_same_rolls(flying, normal)
}

///|
test "flying press: Tera does not rewrite the move type" {
  let grass = fp_mon("くさ", "")
  let atk = fp_mon("かくとう", "")
  let base = @damage.calc_damage(mk_damage_input(atk, grass, fp_move()))
  let tera_fight = @damage.calc_damage(
    mk_damage_input(atk, grass, fp_move(), tera_type="かくとう"),
  )
  let tera_fly = @damage.calc_damage(
    mk_damage_input(atk, grass, fp_move(), tera_type="ひこう"),
  )
  // 元タイプとテラスタイプがかくとうで技タイプも一致 → STAB 2 倍。
  assert_true(tera_fight.max_damage > base.max_damage)
  // ひこうテラスタルは技タイプを変えない。元タイプのかくとう STAB 1.5 のまま。
  assert_same_rolls(tera_fly, base)
  let ghost = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("ゴースト", ""),
      fp_move(),
      tera_type="ひこう",
    ),
  )
  assert_true(ghost.is_immune)
}

///|
test "flying press: type-boost items follow the Fighting move type" {
  let atk = fp_mon("ノーマル", "")
  let def = fp_mon("くさ", "")
  let plain = @damage.calc_damage(mk_damage_input(atk, def, fp_move()))
  let belt = @damage.calc_damage(
    mk_damage_input(atk, def, fp_move(), atk_item="くろおび"),
  )
  let beak = @damage.calc_damage(
    mk_damage_input(atk, def, fp_move(), atk_item="するどいくちばし"),
  )
  assert_true(belt.max_damage > plain.max_damage)
  assert_same_rolls(beak, plain)
}

///|
test "flying press: Expert Belt and Filter key on overall effectiveness" {
  let atk = fp_mon("ノーマル", "")
  let grass = fp_mon("くさ", "")
  let steel_rock = fp_mon("はがね", "いわ")
  let grass_plain = @damage.calc_damage(mk_damage_input(atk, grass, fp_move()))
  let grass_belt = @damage.calc_damage(
    mk_damage_input(atk, grass, fp_move(), atk_item="たつじんのおび"),
  )
  let neutral_plain = @damage.calc_damage(
    mk_damage_input(atk, steel_rock, fp_move()),
  )
  let neutral_belt = @damage.calc_damage(
    mk_damage_input(
      atk,
      steel_rock,
      fp_move(),
      atk_item="たつじんのおび",
    ),
  )
  assert_true(grass_belt.max_damage > grass_plain.max_damage)
  assert_same_rolls(neutral_belt, neutral_plain)
  let grass_filter = @damage.calc_damage(
    mk_damage_input(atk, grass, fp_move(), def_ability="フィルター"),
  )
  let grass_prism = @damage.calc_damage(
    mk_damage_input(
      atk,
      grass,
      fp_move(),
      def_ability="プリズムアーマー",
    ),
  )
  let neutral_filter = @damage.calc_damage(
    mk_damage_input(atk, steel_rock, fp_move(), def_ability="フィルター"),
  )
  assert_true(grass_filter.max_damage < grass_plain.max_damage)
  assert_same_rolls(grass_filter, grass_prism)
  assert_same_rolls(neutral_filter, neutral_plain)
}

///|
test "flying press: Tinted Lens keys on overall not-very-effective" {
  let atk = fp_mon("ノーマル", "")
  // むしは 0.5 × 2 = 等倍。いろめがねは乗らない。
  let bug = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("むし", ""), fp_move()),
  )
  let bug_lens = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("むし", ""),
      fp_move(),
      atk_ability="いろめがね",
    ),
  )
  assert_same_rolls(bug, bug_lens)
  // でんきは 1 × 0.5 = 半減。いろめがねが 2 倍する。
  let electric = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("でんき", ""), fp_move()),
  )
  let electric_lens = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("でんき", ""),
      fp_move(),
      atk_ability="いろめがね",
    ),
  )
  assert_true(electric_lens.max_damage > electric.max_damage)
}

///|
test "flying press: Chople Berry triggers on overall SE, Coba does not" {
  // くさは通常かくとう等倍なのでヨプのみは不発。複合後は抜群なので発動する。
  // バコウのみはひこう実だが技タイプはかくとうのままなので不発。
  let atk = fp_mon("ノーマル", "")
  let grass = fp_mon("くさ", "")
  let plain = @damage.calc_damage(mk_damage_input(atk, grass, fp_move()))
  let chople = @damage.calc_damage(
    mk_damage_input(atk, grass, fp_move(), def_item="ヨプのみ"),
  )
  let coba = @damage.calc_damage(
    mk_damage_input(atk, grass, fp_move(), def_item="バコウのみ"),
  )
  let fighting_chople = @damage.calc_damage(
    mk_damage_input(
      atk,
      grass,
      fp_typed("かくとうテスト技", "かくとう"),
      def_item="ヨプのみ",
    ),
  )
  let fighting_plain = @damage.calc_damage(
    mk_damage_input(
      atk,
      grass,
      fp_typed("かくとうテスト技", "かくとう"),
    ),
  )
  assert_true(chople.max_damage < plain.max_damage)
  assert_same_rolls(coba, plain)
  assert_same_rolls(fighting_chople, fighting_plain)
  // 等倍の はがね/いわ と むし ではヨプのみは不発。
  let steel = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("はがね", "いわ"), fp_move()),
  )
  let steel_chople = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("はがね", "いわ"),
      fp_move(),
      def_item="ヨプのみ",
    ),
  )
  let bug = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("むし", ""), fp_move()),
  )
  let bug_chople = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("むし", ""),
      fp_move(),
      def_item="ヨプのみ",
    ),
  )
  assert_same_rolls(steel, steel_chople)
  assert_same_rolls(bug, bug_chople)
}

///|
test "flying press: Pixilate on a Normal-typed press uses Fairy times Flying" {
  // 実装済みのタイプ変化はスキン (ノーマル技のみ)。フライングプレスの
  // type をノーマルにしたとき、フェアリースキン後の相性はフェアリー×ひこう。
  // かくとう単への 4 倍は、フェアリー技の かくとう/ドラゴン (2×2) と一致する。
  let atk = fp_mon("ノーマル", "")
  let press = { ..fp_move(), type_: "ノーマル", }
  let pix = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("かくとう", ""),
      press,
      atk_ability="フェアリースキン",
    ),
  )
  let reference = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("かくとう", "ドラゴン"),
      fp_typed("たいあたり", "ノーマル"),
      atk_ability="フェアリースキン",
    ),
  )
  assert_same_rolls(pix, reference)
  // 技タイプがフェアリーになるとゴースト無効ではなくなる。
  let ghost = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("ゴースト", ""),
      press,
      atk_ability="フェアリースキン",
    ),
  )
  assert_true(!ghost.is_immune)
  assert_true(ghost.max_damage > 0)
}

///|
test "flying press: Electric-typed press keeps Ground immunity" {
  // そうでん相当で技タイプがでんきになっても、
  // じめん無効はひこう相性では解除されない。みずは 2 倍のまま。
  let atk = fp_mon("ノーマル", "")
  let press = { ..fp_move(), type_: "でんき", }
  let ground = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("じめん", ""), press),
  )
  assert_true(ground.is_immune)
  let water = @damage.calc_damage(
    mk_damage_input(atk, fp_mon("みず", ""), press),
  )
  let electric_water = @damage.calc_damage(
    mk_damage_input(
      atk,
      fp_mon("みず", ""),
      fp_typed("でんきテスト技", "でんき"),
    ),
  )
  assert_same_rolls(water, electric_water)
}
