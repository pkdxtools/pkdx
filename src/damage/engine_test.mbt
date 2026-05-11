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
/// Regression: --atk-stat override 指定時に atk_rank が silent に無視されていた
/// (engine.mbt の `if input.atk_stat_override <= 0` ガードが原因)。
/// 新仕様では override は「rank 前の実数値」として扱い、rank は常に適用される。
test "calc_damage: atk_stat_override + rank applies rank on top" {
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
  inspect(r1.max_damage > r2.max_damage, content="true")
}

///|
/// Regression: def_stat_override + def_rank も同様に rank が掛かる。
test "calc_damage: def_stat_override + rank applies rank on top" {
  let with_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_stat_override=150,
    def_rank=2,
  )
  let without_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_stat_override=150,
    def_rank=0,
  )
  let r1 = calc_damage(with_rank)
  let r2 = calc_damage(without_rank)
  // def_rank+2 は damage を約半分にする
  inspect(r1.max_damage < r2.max_damage, content="true")
}

///|
/// Regression: 実ケース再現 — メガギャラ (A=207 想定) + ドドゲザン + たきのぼり + rank+1。
/// 過去の挙動: rank が無視され max 81 程度。期待: rank 適用で max > 100。
test "calc_damage: mega-gyarados waterfall vs kingambit rank+1 regression" {
  let mega_gyarados = mk_pokemon_typed(
    "メガギャラドス", "みず", "あく", 95, 155, 109, 70, 130, 81,
  )
  let kingambit = mk_pokemon_typed(
    "ドドゲザン", "あく", "はがね", 100, 135, 120, 60, 85, 50,
  )
  let waterfall = mk_move("たきのぼり", "みず", @model.Physical, 80)
  let input = mk_damage_input(
    mega_gyarados,
    kingambit,
    waterfall,
    atk_stat_override=207,
    def_stat_override=140,
    def_hp_override=207,
    atk_rank=1,
  )
  let result = calc_damage(input)
  // rank+1 で atk 207->310、STAB 1.5x、等倍、rand 100/100 で max≈121
  inspect(result.max_damage > 100, content="true")
}

// --- Nature (--atk-nature / --def-nature) ---

///|
/// 物理技で Atk+ 性格 (いじっぱり) は Atk 中立 (まじめ) より damage が高い。
/// 旧挙動は nature 無視で両者が +10% default になり等しくなる。
test "calc_damage: atk_nature adamant > serious on physical" {
  match (
    @model.nature_from_ja("いじっぱり"),
    @model.nature_from_ja("まじめ"),
  ) {
    (Some(adamant), Some(serious)) => {
      let with_adamant = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        atk_nature=Some(adamant),
        stat_system=@model.Champions,
      )
      let with_serious = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        atk_nature=Some(serious),
        stat_system=@model.Champions,
      )
      let r1 = calc_damage(with_adamant)
      let r2 = calc_damage(with_serious)
      inspect(r1.max_damage > r2.max_damage, content="true")
    }
    _ => fail("nature not found")
  }
}

///|
/// 特殊技で SpA+ 性格 (ひかえめ) は中立より damage が高い。
test "calc_damage: atk_nature modest > serious on special" {
  let surf = mk_move("なみのり", "みず", @model.Special, 90)
  let vaporeon = mk_pokemon_typed(
    "シャワーズ", "みず", "", 130, 65, 60, 110, 95, 65,
  )
  match (
    @model.nature_from_ja("ひかえめ"),
    @model.nature_from_ja("まじめ"),
  ) {
    (Some(modest), Some(serious)) => {
      let with_modest = mk_damage_input(
        vaporeon,
        fixture_garchomp(),
        surf,
        atk_nature=Some(modest),
        stat_system=@model.Champions,
      )
      let with_serious = mk_damage_input(
        vaporeon,
        fixture_garchomp(),
        surf,
        atk_nature=Some(serious),
        stat_system=@model.Champions,
      )
      let r1 = calc_damage(with_modest)
      let r2 = calc_damage(with_serious)
      inspect(r1.max_damage > r2.max_damage, content="true")
    }
    _ => fail("nature not found")
  }
}

///|
/// ようき (Spe+/SpA-, Atk 中立) を物理技に適用しても Atk 無補正。
/// まじめ (全中立) と同等の damage になる。
test "calc_damage: atk_nature jolly equals serious on physical (both neutral for Atk)" {
  match (@model.nature_from_ja("ようき"), @model.nature_from_ja("まじめ")) {
    (Some(jolly), Some(serious)) => {
      let with_jolly = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        atk_nature=Some(jolly),
        stat_system=@model.Champions,
      )
      let with_serious = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        atk_nature=Some(serious),
        stat_system=@model.Champions,
      )
      let r1 = calc_damage(with_jolly)
      let r2 = calc_damage(with_serious)
      inspect(r1.max_damage == r2.max_damage, content="true")
    }
    _ => fail("nature not found")
  }
}

///|
/// ボディプレスは攻撃側の Def を攻撃値として使う物理技。
/// ずぶとい (Def+/Atk-) は body press の攻撃値を押し上げるので damage が上がる。
test "calc_damage: atk_nature bold boosts body press (Def+ applies)" {
  let body_press = mk_move("ボディプレス", "かくとう", @model.Physical, 80)
  // 防御型ポケモン (A低, B高) を用意して body press の効果を確認
  let skeledirge = mk_pokemon_typed(
    "ラウドボーン", "ほのお", "ゴースト", 104, 75, 100, 110, 75, 66,
  )
  match (
    @model.nature_from_ja("ずぶとい"),
    @model.nature_from_ja("まじめ"),
  ) {
    (Some(bold), Some(serious)) => {
      let with_bold = mk_damage_input(
        skeledirge,
        fixture_garchomp(),
        body_press,
        atk_nature=Some(bold),
        stat_system=@model.Champions,
      )
      let with_serious = mk_damage_input(
        skeledirge,
        fixture_garchomp(),
        body_press,
        atk_nature=Some(serious),
        stat_system=@model.Champions,
      )
      let r1 = calc_damage(with_bold)
      let r2 = calc_damage(with_serious)
      inspect(r1.max_damage > r2.max_damage, content="true")
    }
    _ => fail("nature not found")
  }
}

///|
/// def_nature で Def+ 性格 (ずぶとい) を物理技の防御側に当てると damage が減る。
test "calc_damage: def_nature bold reduces physical damage" {
  match (
    @model.nature_from_ja("ずぶとい"),
    @model.nature_from_ja("まじめ"),
  ) {
    (Some(bold), Some(serious)) => {
      let with_bold = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        def_nature=Some(bold),
        stat_system=@model.Champions,
      )
      let with_serious = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        def_nature=Some(serious),
        stat_system=@model.Champions,
      )
      let r1 = calc_damage(with_bold)
      let r2 = calc_damage(with_serious)
      inspect(r1.max_damage < r2.max_damage, content="true")
    }
    _ => fail("nature not found")
  }
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

///|
/// nature × rank × ability の 3変数が独立に適用される順序保護テスト。
/// まじめ (Atk 中立) にすると default (+10%) より低くなることで nature 分岐を検知。
/// rank+1 と ちからもち が両方掛かることで計算順序を保護。
/// golden value で snapshot し、どの変数がズレても検知できるようにする。
test "calc_damage: nature + rank + ability 3-way interaction (golden)" {
  let atk = {
    ..fixture_garchomp(),
    ability1: "ちからもち",
  }
  match @model.nature_from_ja("まじめ") {
    Some(serious) => {
      let input = mk_damage_input(
        atk,
        fixture_garchomp(),
        fixture_earthquake(),
        atk_nature=Some(serious),
        atk_rank=1,
        atk_ability="ちからもち",
        stat_system=@model.Champions,
      )
      let result = calc_damage(input)
      inspect(result.max_damage, content=(
        #|315
      ))
    }
    None => fail("nature not found")
  }
}

///|
/// Standard (scarlet_violet 等) モードでも nature が適用されることの確認。
/// Champions 系テストと同じ枠組みが Standard 分岐でも通る。
test "calc_damage: atk_nature applies in Standard mode" {
  match (
    @model.nature_from_ja("いじっぱり"),
    @model.nature_from_ja("まじめ"),
  ) {
    (Some(adamant), Some(serious)) => {
      let with_adamant = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        atk_nature=Some(adamant),
        stat_system=@model.Standard,
      )
      let with_serious = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        atk_nature=Some(serious),
        stat_system=@model.Standard,
      )
      let r1 = calc_damage(with_adamant)
      let r2 = calc_damage(with_serious)
      inspect(r1.max_damage > r2.max_damage, content="true")
    }
    _ => fail("nature not found")
  }
}

///|
/// Standard モードで def_nature も効くこと。
test "calc_damage: def_nature applies in Standard mode" {
  match (
    @model.nature_from_ja("ずぶとい"),
    @model.nature_from_ja("まじめ"),
  ) {
    (Some(bold), Some(serious)) => {
      let with_bold = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        def_nature=Some(bold),
        stat_system=@model.Standard,
      )
      let with_serious = mk_damage_input(
        fixture_garchomp(),
        fixture_garchomp(),
        fixture_earthquake(),
        def_nature=Some(serious),
        stat_system=@model.Standard,
      )
      let r1 = calc_damage(with_bold)
      let r2 = calc_damage(with_serious)
      inspect(r1.max_damage < r2.max_damage, content="true")
    }
    _ => fail("nature not found")
  }
}

///|
/// critical + atk_stat_override + 負ランクの組み合わせ。
/// 急所は攻撃側負ランクを無視する既存仕様。override 併用でもこの挙動を維持する。
test "calc_damage: atk_stat_override + critical ignores negative rank" {
  let with_neg = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_stat_override=200,
    atk_rank=-2,
    critical=true,
  )
  let without_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_stat_override=200,
    atk_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_neg)
  let r2 = calc_damage(without_rank)
  inspect(r1.max_damage == r2.max_damage, content="true")
}

///|
/// critical + atk_stat_override + 正ランクの組み合わせ。
/// 急所でも正ランクはそのまま乗る (既存仕様を override 経路でも保護)。
test "calc_damage: atk_stat_override + critical preserves positive rank" {
  let with_pos = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_stat_override=200,
    atk_rank=2,
    critical=true,
  )
  let without_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_stat_override=200,
    atk_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_pos)
  let r2 = calc_damage(without_rank)
  inspect(r1.max_damage > r2.max_damage, content="true")
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
