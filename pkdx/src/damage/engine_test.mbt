///|
/// ガブリアス (108/130/95/80/85/102) ドラゴン/じめん
fn fixture_garchomp() -> @model.Pokemon {
  mk_pokemon_typed(
    "ガブリアス", "ドラゴン", "じめん", 108, 130, 95, 80, 85, 102,
  )
}

///|
/// じしん (じめん, 物理, 威力100) — STAB for ガブリアス
fn fixture_earthquake() -> @model.Move {
  mk_move("じしん", "じめん", @model.Physical, 100)
}

///|
test "calc_damage: baseline (no rank)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|117
  ))
}

///|
test "calc_damage: atk_rank +2 doubles damage" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=2,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|232
  ))
}

///|
test "calc_damage: def_rank +2 halves damage" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=2,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|60
  ))
}

///|
test "calc_damage: crit ignores atk negative rank" {
  let with_neg = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=-2,
    critical=true,
  )
  let without_neg = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_neg)
  let r2 = calc_damage(without_neg)
  inspect(r1.max_damage == r2.max_damage, content="true")
}

///|
test "calc_damage: crit ignores def positive rank" {
  let with_pos = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=2,
    critical=true,
  )
  let without_pos = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_pos)
  let r2 = calc_damage(without_pos)
  inspect(r1.max_damage == r2.max_damage, content="true")
}

///|
test "calc_damage: crit preserves atk positive rank" {
  let with_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=2,
    critical=true,
  )
  let without_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_rank)
  let r2 = calc_damage(without_rank)
  inspect(r1.max_damage != r2.max_damage, content="true")
}

///|
test "calc_damage: crit preserves def negative rank" {
  let with_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=-2,
    critical=true,
  )
  let without_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_rank)
  let r2 = calc_damage(without_rank)
  inspect(r1.max_damage != r2.max_damage, content="true")
}

///|
test "calc_damage: override ignores rank" {
  let with_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_stat_override=200,
    atk_rank=2,
  )
  let without_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_stat_override=200,
    atk_rank=0,
  )
  let r1 = calc_damage(with_rank)
  let r2 = calc_damage(without_rank)
  inspect(r1.max_damage == r2.max_damage, content="true")
}

///|
test "calc_damage: rank order matters with ability (ちからもち + rank +1)" {
  let atk = {
    ..fixture_garchomp(),
    ability1: "ちからもち",
  }
  let input = mk_damage_input(
    atk,
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=1,
    atk_ability="ちからもち",
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|346
  ))
}

// --- そうだいしょう ---

///|
test "calc_damage: そうだいしょう no boost (fainted_count=0)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=0,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|117
  ))
}

///|
test "calc_damage: そうだいしょう fainted_count=1 (x1.1)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=1,
  )
  let result = calc_damage(input)
  // round5(84, 4506) = (84*4506+2047)/4096 = 92
  inspect(result.max_damage, content=(
    #|129
  ))
}

///|
test "calc_damage: そうだいしょう fainted_count=2 (x1.2)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=2,
  )
  let result = calc_damage(input)
  // round5(84, 4915) = (84*4915+2047)/4096 = 101
  inspect(result.max_damage, content=(
    #|140
  ))
}

///|
test "calc_damage: そうだいしょう fainted_count=3 (x1.3)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=3,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|152
  ))
}

///|
test "calc_damage: そうだいしょう fainted_count=4 (x1.4)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=4,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|164
  ))
}

///|
test "calc_damage: そうだいしょう fainted_count=5 (x1.5)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=5,
  )
  let result = calc_damage(input)
  // round5(84, 6144) = (84*6144+2047)/4096 = 126
  inspect(result.max_damage, content=(
    #|175
  ))
}

///|
test "calc_damage: そうだいしょう clamps fainted_count > 5" {
  let input5 = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=5,
  )
  let input99 = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=99,
  )
  let r5 = calc_damage(input5)
  let r99 = calc_damage(input99)
  inspect(r5.max_damage == r99.max_damage, content="true")
}

///|
test "calc_damage: そうだいしょう clamps negative fainted_count" {
  let input_neg = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=-3,
  )
  let input0 = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_ability="そうだいしょう",
    fainted_count=0,
  )
  let r_neg = calc_damage(input_neg)
  let r0 = calc_damage(input0)
  inspect(r_neg.max_damage == r0.max_damage, content="true")
}

// --- おはかまいり ---

///|
fn fixture_last_respects() -> @model.Move {
  mk_move("おはかまいり", "ゴースト", @model.Physical, 50)
}

///|
test "calc_damage: おはかまいり base (fainted_count=0, power=50)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_last_respects(),
    fainted_count=0,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|40
  ))
}

///|
test "calc_damage: おはかまいり fainted_count=1 (power=100)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_last_respects(),
    fainted_count=1,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|78
  ))
}

///|
test "calc_damage: おはかまいり fainted_count=2 (power=150)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_last_respects(),
    fainted_count=2,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|116
  ))
}

///|
test "calc_damage: おはかまいり fainted_count=5 (power=300)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_last_respects(),
    fainted_count=5,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|231
  ))
}

///|
test "calc_damage: おはかまいり clamps fainted_count > 100" {
  let input100 = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_last_respects(),
    fainted_count=100,
  )
  let input999 = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_last_respects(),
    fainted_count=999,
  )
  let r100 = calc_damage(input100)
  let r999 = calc_damage(input999)
  // 両方 power=5050
  inspect(r100.max_damage == r999.max_damage, content="true")
}

// --- ダブルバトル全体技補正 ---

///|
test "calc_damage: spread move in double applies 0.75x" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    is_double=true,
  )
  let result = calc_damage(input)
  // baseline max_damage=84, round5(base, 3072) で 0.75倍
  inspect(result.max_damage, content=(
    #|87
  ))
}

///|
test "calc_damage: single-target move in double has no spread penalty" {
  let outrage = mk_move("げきりん", "ドラゴン", @model.Physical, 120)
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    outrage,
    is_double=true,
  )
  let baseline = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    outrage,
  )
  let r1 = calc_damage(input)
  let r2 = calc_damage(baseline)
  inspect(r1.max_damage == r2.max_damage, content="true")
}

///|
test "calc_damage: spread move in single has no penalty" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    is_double=false,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content=(
    #|117
  ))
}

///|
test "calc_damage: spread + sand weather in double" {
  // spread 補正は weather の前に適用される（丸め順序の回帰確認）
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    is_double=true,
    weather=@model.Weather::Sand,
  )
  let result = calc_damage(input)
  // base 56 → round5(56, 3072)=42 → weather(じめん+すなあらし=補正なし) → ...
  // シングルの sand 結果と比較して spread 分だけ小さいことを確認
  let single = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    weather=@model.Weather::Sand,
  )
  let r_single = calc_damage(single)
  inspect(result.max_damage < r_single.max_damage, content="true")
}

// --- そうだいしょう + おはかまいり 併用 ---

///|
test "calc_damage: そうだいしょう + おはかまいり (fainted_count=3)" {
  let input_combo = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_last_respects(),
    atk_ability="そうだいしょう",
    fainted_count=3,
  )
  let input_move_only = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_last_respects(),
    fainted_count=3,
  )
  let r_combo = calc_damage(input_combo)
  let r_move = calc_damage(input_move_only)
  // そうだいしょう x1.3 がさらに乗るので、技威力だけより大きい
  inspect(r_combo.max_damage > r_move.max_damage, content="true")
}

// ──────────────────────────────────────────────
// Champions mode integration tests
// ──────────────────────────────────────────────

///|
test "calc_damage: champions mode dispatches correctly" {
  // At max investment (SP=32 vs IV31/EV252), Champions and Standard formulas
  // are algebraically equivalent (base+52 for non-HP, base+107 for HP).
  // Verify Champions mode produces same baseline damage as Standard.
  let input_champ = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    stat_system=@model.Champions,
  )
  let input_standard = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
  )
  let r_champ = calc_damage(input_champ)
  let r_standard = calc_damage(input_standard)
  inspect(r_champ.max_damage, content=(
    #|117
  ))
  inspect(r_champ.max_damage == r_standard.max_damage, content="true")
}

///|
test "calc_damage: champions with rank modifier" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    stat_system=@model.Champions,
    atk_rank=2,
  )
  let no_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    stat_system=@model.Champions,
  )
  let r = calc_damage(input)
  let r_no = calc_damage(no_rank)
  inspect(r.max_damage > r_no.max_damage, content="true")
}

///|
/// 防御側デフォルトが「無投資・性格補正なし」であることを保証する回帰テスト。
/// メガギャラドス (155 Atk) +1 ランク → メガリザードンY (78 Def) たきのぼり / 晴れ。
/// PokeVision など主要ダメ計と同じ 156–186 (102–121.5%) を出すこと。
test "calc_damage: Champions defender defaults to 0 SP / neutral nature" {
  let mega_gyarados = mk_pokemon_typed(
    "メガギャラドス", "みず", "あく", 95, 155, 109, 70, 130, 81,
  )
  let mega_charizard_y = mk_pokemon_typed(
    "メガリザードンY", "ほのお", "ひこう", 78, 104, 78, 159, 115, 100,
  )
  let waterfall = mk_move("たきのぼり", "みず", @model.Physical, 80)
  let input = mk_damage_input(
    mega_gyarados,
    mega_charizard_y,
    waterfall,
    weather=@model.Weather::Sun,
    atk_rank=1,
    stat_system=@model.Champions,
  )
  let r = calc_damage(input)
  inspect(r.min_damage, content="156")
  inspect(r.max_damage, content="186")
  inspect(r.defender_hp, content="153")
}
