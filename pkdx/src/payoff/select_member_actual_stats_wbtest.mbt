///|
/// Whitebox tests: team-builder member 形式 (types / base_stats + nature /
/// stat_points / actual_stats) が `pkdx select` の内部 damage kernel まで
/// きちんと流れていることを保証する。
///
/// 設計意図: schema.mbt に nature / stat_points / actual_stats を追加しても
/// `parse_combatant_json` で拾われていなかったり、`build_input_with_ranks` が
/// 落とされていたりすると「cache に書いても select が見ていない」という
/// 一気通貫パスの穴が発生する。ここではその 3 層の連結をテストする:
///
///   1. parse_combatant_json が nature / actual_stats を Combatant に載せる
///   2. build_input_with_ranks が攻撃/防御側の override に転記する
///   3. actual_stats 有無で damage が変化する (= override が実際に効いている)

///|
fn parse_single_combatant(src : String) -> Combatant raise {
  let j = @json.parse(src)
  parse_combatant_json(j, "test")
}

///|
test "parse_combatant_json: nature and actual_stats are lifted into Combatant" {
  let src =
    #|{
    #|  "name": "マンムー",
    #|  "types": ["こおり","じめん"],
    #|  "base_stats": {"h":110,"a":130,"b":80,"c":70,"d":60,"s":80},
    #|  "ability": "あついしぼう",
    #|  "item": "こだわりスカーフ",
    #|  "tera": "",
    #|  "nature": "ようき",
    #|  "stat_points": {"h":20,"a":32,"b":0,"c":0,"d":0,"s":14},
    #|  "actual_stats": {"h":205,"a":181,"b":100,"c":90,"d":80,"s":124},
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let c = parse_single_combatant(src)
  match c.nature {
    Some(n) => assert_eq(n.name_ja, "ようき")
    None => fail("nature must be parsed")
  }
  match c.actual_stats {
    Some(arr) => {
      assert_eq(arr.length(), 6)
      assert_eq(arr[0], 205) // HP
      assert_eq(arr[1], 181) // Atk
      assert_eq(arr[5], 124) // Spe
    }
    None => fail("actual_stats must be parsed")
  }
}

///|
test "parse_combatant_json: missing nature/actual_stats keeps Combatant None" {
  let src =
    #|{
    #|  "name": "マンムー",
    #|  "types": ["こおり","じめん"],
    #|  "base_stats": {"h":110,"a":130,"b":80,"c":70,"d":60,"s":80},
    #|  "ability": "あついしぼう",
    #|  "item": "こだわりスカーフ",
    #|  "tera": "",
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let c = parse_single_combatant(src)
  match c.nature {
    None => ()
    Some(_) => fail("nature should be None")
  }
  match c.actual_stats {
    None => ()
    Some(_) => fail("actual_stats should be None")
  }
}

///|
test "build_input_with_ranks: physical attacker routes actual_stats[1] to atk_stat_override" {
  let atk_src =
    #|{
    #|  "name": "マンムー",
    #|  "types": ["こおり","じめん"],
    #|  "base_stats": {"h":110,"a":130,"b":80,"c":70,"d":60,"s":80},
    #|  "ability": "",
    #|  "item": "",
    #|  "tera": "",
    #|  "nature": "ようき",
    #|  "actual_stats": {"h":205,"a":181,"b":100,"c":90,"d":80,"s":124},
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let dfn_src =
    #|{
    #|  "name": "ヌメルゴン",
    #|  "types": ["ドラゴン"],
    #|  "base_stats": {"h":90,"a":100,"b":70,"c":110,"d":150,"s":80},
    #|  "ability": "",
    #|  "item": "",
    #|  "tera": "",
    #|  "nature": "ずぶとい",
    #|  "actual_stats": {"h":180,"a":120,"b":160,"c":150,"d":170,"s":90},
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let atk = parse_single_combatant(atk_src)
  let dfn = parse_single_combatant(dfn_src)
  let mv : @model.Move = {
    name: "じしん",
    type_: "じめん",
    category: @model.Physical,
    power: 100,
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
  let input = build_input_with_ranks(atk, dfn, mv, 0, 0)
  // 物理技なので attacker Atk (index 1) / defender Def (index 2)
  assert_eq(input.atk_stat_override, 181)
  assert_eq(input.def_stat_override, 160)
  assert_eq(input.def_hp_override, 180)
  match input.atk_nature {
    Some(n) => assert_eq(n.name_ja, "ようき")
    None => fail("atk_nature must be propagated")
  }
  match input.def_nature {
    Some(n) => assert_eq(n.name_ja, "ずぶとい")
    None => fail("def_nature must be propagated")
  }
}

///|
test "build_input_with_ranks: special move routes to SpA (3) / SpD (4)" {
  let atk_src =
    #|{
    #|  "name": "サーナイト",
    #|  "types": ["エスパー","フェアリー"],
    #|  "base_stats": {"h":68,"a":65,"b":65,"c":125,"d":115,"s":80},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "ひかえめ",
    #|  "actual_stats": {"h":155,"a":80,"b":95,"c":205,"d":151,"s":110},
    #|  "moves": [
    #|    {"name":"ムーンフォース","type":"フェアリー","category":"特殊","power":95}
    #|  ]
    #|}
  let dfn_src =
    #|{
    #|  "name": "ヌメルゴン",
    #|  "types": ["ドラゴン"],
    #|  "base_stats": {"h":90,"a":100,"b":70,"c":110,"d":150,"s":80},
    #|  "ability": "","item": "","tera": "",
    #|  "actual_stats": {"h":180,"a":120,"b":100,"c":150,"d":177,"s":90},
    #|  "moves": [
    #|    {"name":"ムーンフォース","type":"フェアリー","category":"特殊","power":95}
    #|  ]
    #|}
  let atk = parse_single_combatant(atk_src)
  let dfn = parse_single_combatant(dfn_src)
  let mv : @model.Move = {
    name: "ムーンフォース",
    type_: "フェアリー",
    category: @model.Special,
    power: 95,
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
  let input = build_input_with_ranks(atk, dfn, mv, 0, 0)
  // 特殊技: attacker SpA (index 3) / defender SpD (index 4)
  assert_eq(input.atk_stat_override, 205)
  assert_eq(input.def_stat_override, 177)
  assert_eq(input.def_hp_override, 180)
}

///|
test "build_input_with_ranks: missing actual_stats falls back to zero override" {
  let atk_src =
    #|{
    #|  "name": "マンムー",
    #|  "types": ["こおり","じめん"],
    #|  "base_stats": {"h":110,"a":130,"b":80,"c":70,"d":60,"s":80},
    #|  "ability": "","item": "","tera": "",
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let atk = parse_single_combatant(atk_src)
  let dfn = parse_single_combatant(atk_src)
  let mv : @model.Move = {
    name: "じしん",
    type_: "じめん",
    category: @model.Physical,
    power: 100,
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
  let input = build_input_with_ranks(atk, dfn, mv, 0, 0)
  assert_eq(input.atk_stat_override, 0)
  assert_eq(input.def_stat_override, 0)
  assert_eq(input.def_hp_override, 0)
  match input.atk_nature {
    None => ()
    Some(_) => fail("atk_nature should fall back to None (engine default +10%)")
  }
  match input.def_nature {
    None => ()
    Some(_) => fail("def_nature should fall back to None (engine default)")
  }
}

///|
test "build_input_with_ranks: body press picks Def (index 2) as atk stat" {
  // ボディプレスは攻撃側 Def を atk_stat として使う物理技。
  // actual_stats[2] (= B = Def) が atk_stat_override に入ることを確認。
  let atk_src =
    #|{
    #|  "name": "テストガブ",
    #|  "types": ["ドラゴン"],
    #|  "base_stats": {"h":100,"a":100,"b":100,"c":100,"d":100,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "ずぶとい",
    #|  "actual_stats": {"h":200,"a":110,"b":222,"c":120,"d":130,"s":140},
    #|  "moves": [
    #|    {"name":"ボディプレス","type":"かくとう","category":"物理","power":80}
    #|  ]
    #|}
  let dfn_src =
    #|{
    #|  "name": "テスト受け",
    #|  "types": ["ノーマル"],
    #|  "base_stats": {"h":100,"a":100,"b":100,"c":100,"d":100,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "actual_stats": {"h":180,"a":100,"b":144,"c":100,"d":100,"s":100},
    #|  "moves": [
    #|    {"name":"ボディプレス","type":"かくとう","category":"物理","power":80}
    #|  ]
    #|}
  let atk = parse_single_combatant(atk_src)
  let dfn = parse_single_combatant(dfn_src)
  let mv : @model.Move = {
    name: "ボディプレス",
    type_: "かくとう",
    category: @model.Physical,
    power: 80,
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
  let input = build_input_with_ranks(atk, dfn, mv, 0, 0)
  // ボディプレス: 攻撃側 Def = 222, 防御側 Def = 144
  assert_eq(input.atk_stat_override, 222)
  assert_eq(input.def_stat_override, 144)
  assert_eq(input.def_hp_override, 180)
}

///|
/// 一気通貫の end-to-end 検証: damage kernel レベルで override の effect を
/// 直接観測する。Nash value は payoff を正規化するスケール不変で差が埋もれる
/// ことがあるため、`compute_mean_damage` を直接呼んで
/// 「actual_stats / nature を付けると damage が動く」ことを確認する。
test "compute_mean_damage: actual_stats override changes damage output" {
  let base_atk_src =
    #|{
    #|  "name": "A",
    #|  "types": ["ノーマル"],
    #|  "base_stats": {"h":100,"a":100,"b":100,"c":100,"d":100,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let boosted_atk_src =
    #|{
    #|  "name": "A",
    #|  "types": ["ノーマル"],
    #|  "base_stats": {"h":100,"a":100,"b":100,"c":100,"d":100,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "いじっぱり",
    #|  "actual_stats": {"h":175,"a":222,"b":120,"c":90,"d":120,"s":110},
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let dfn_src =
    #|{
    #|  "name": "D",
    #|  "types": ["ほのお"],
    #|  "base_stats": {"h":100,"a":100,"b":100,"c":100,"d":100,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let base_atk = parse_single_combatant(base_atk_src)
  let boosted_atk = parse_single_combatant(boosted_atk_src)
  let dfn = parse_single_combatant(dfn_src)
  let mv : @model.Move = {
    name: "じしん",
    type_: "じめん",
    category: @model.Physical,
    power: 100,
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
  let d_default = compute_mean_damage(base_atk, dfn, mv, 0, 0)
  let d_boosted = compute_mean_damage(boosted_atk, dfn, mv, 0, 0)
  assert_true(d_default > 0)
  assert_true(d_boosted > 0)
  // Atk 222 は default (Atk 167 = (100+32+20)*11/10) より高いので damage も増える。
  assert_true(d_boosted > d_default)
}

///|
/// run_select が入力 JSON を正常に処理できることだけ確認する smoke test。
/// 値の差分検証は `compute_mean_damage` 側の直接テストに寄せた (Nash value は
/// スケール不変のため差分が 0 で埋もれうる)。
test "run_select: accepts team-builder member with actual_stats" {
  // 最小限の 3v3 select 用入力: 両チーム 3 体、物理/特殊/サポートを 1 本ずつ。
  // actual_stats を与えたときは攻撃側の実 A/C が base 相当より低く、
  // 期待値が base 投資 default と変わる。
  let with_stats =
    #|{
    #|  "format": "single",
    #|  "stat_system": "champions",
    #|  "team": [
    #|    {
    #|      "name": "A",
    #|      "types": ["ノーマル"],
    #|      "base_stats": {"h":100,"a":100,"b":100,"c":100,"d":100,"s":100},
    #|      "ability": "","item": "","tera": "",
    #|      "nature": "いじっぱり",
    #|      "actual_stats": {"h":175,"a":160,"b":120,"c":90,"d":120,"s":110},
    #|      "moves": [
    #|        {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|      ]
    #|    },
    #|    {
    #|      "name": "B",
    #|      "types": ["みず"],
    #|      "base_stats": {"h":100,"a":60,"b":100,"c":120,"d":100,"s":100},
    #|      "ability": "","item": "","tera": "",
    #|      "nature": "ひかえめ",
    #|      "actual_stats": {"h":175,"a":72,"b":120,"c":176,"d":120,"s":110},
    #|      "moves": [
    #|        {"name":"なみのり","type":"みず","category":"特殊","power":90}
    #|      ]
    #|    },
    #|    {
    #|      "name": "C",
    #|      "types": ["でんき"],
    #|      "base_stats": {"h":100,"a":80,"b":100,"c":110,"d":100,"s":120},
    #|      "ability": "","item": "","tera": "",
    #|      "nature": "おくびょう",
    #|      "actual_stats": {"h":175,"a":88,"b":120,"c":162,"d":120,"s":172},
    #|      "moves": [
    #|        {"name":"10まんボルト","type":"でんき","category":"特殊","power":90}
    #|      ]
    #|    }
    #|  ],
    #|  "opponent": [
    #|    {
    #|      "name": "X",
    #|      "types": ["ほのお"],
    #|      "base_stats": {"h":100,"a":110,"b":90,"c":90,"d":90,"s":100},
    #|      "ability": "","item": "","tera": "",
    #|      "moves": [
    #|        {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|      ]
    #|    },
    #|    {
    #|      "name": "Y",
    #|      "types": ["くさ"],
    #|      "base_stats": {"h":100,"a":90,"b":100,"c":110,"d":100,"s":80},
    #|      "ability": "","item": "","tera": "",
    #|      "moves": [
    #|        {"name":"エナジーボール","type":"くさ","category":"特殊","power":90}
    #|      ]
    #|    },
    #|    {
    #|      "name": "Z",
    #|      "types": ["いわ"],
    #|      "base_stats": {"h":100,"a":120,"b":130,"c":70,"d":90,"s":60},
    #|      "ability": "","item": "","tera": "",
    #|      "moves": [
    #|        {"name":"ストーンエッジ","type":"いわ","category":"物理","power":100}
    #|      ]
    #|    }
    #|  ]
    #|}
  let without_stats =
    #|{
    #|  "format": "single",
    #|  "stat_system": "champions",
    #|  "team": [
    #|    {
    #|      "name": "A",
    #|      "types": ["ノーマル"],
    #|      "base_stats": {"h":100,"a":100,"b":100,"c":100,"d":100,"s":100},
    #|      "ability": "","item": "","tera": "",
    #|      "moves": [
    #|        {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|      ]
    #|    },
    #|    {
    #|      "name": "B",
    #|      "types": ["みず"],
    #|      "base_stats": {"h":100,"a":60,"b":100,"c":120,"d":100,"s":100},
    #|      "ability": "","item": "","tera": "",
    #|      "moves": [
    #|        {"name":"なみのり","type":"みず","category":"特殊","power":90}
    #|      ]
    #|    },
    #|    {
    #|      "name": "C",
    #|      "types": ["でんき"],
    #|      "base_stats": {"h":100,"a":80,"b":100,"c":110,"d":100,"s":120},
    #|      "ability": "","item": "","tera": "",
    #|      "moves": [
    #|        {"name":"10まんボルト","type":"でんき","category":"特殊","power":90}
    #|      ]
    #|    }
    #|  ],
    #|  "opponent": [
    #|    {
    #|      "name": "X",
    #|      "types": ["ほのお"],
    #|      "base_stats": {"h":100,"a":110,"b":90,"c":90,"d":90,"s":100},
    #|      "ability": "","item": "","tera": "",
    #|      "moves": [
    #|        {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|      ]
    #|    },
    #|    {
    #|      "name": "Y",
    #|      "types": ["くさ"],
    #|      "base_stats": {"h":100,"a":90,"b":100,"c":110,"d":100,"s":80},
    #|      "ability": "","item": "","tera": "",
    #|      "moves": [
    #|        {"name":"エナジーボール","type":"くさ","category":"特殊","power":90}
    #|      ]
    #|    },
    #|    {
    #|      "name": "Z",
    #|      "types": ["いわ"],
    #|      "base_stats": {"h":100,"a":120,"b":130,"c":70,"d":90,"s":60},
    #|      "ability": "","item": "","tera": "",
    #|      "moves": [
    #|        {"name":"ストーンエッジ","type":"いわ","category":"物理","power":100}
    #|      ]
    #|    }
    #|  ]
    #|}
  let out_with = run_select(with_stats)
  let out_without = run_select(without_stats)
  // どちらも JSON としてはパース可能であり、既知のフィールドを含む。
  assert_true(out_with.length() > 0)
  assert_true(out_without.length() > 0)
  assert_true(out_with.contains("\"value\""))
  assert_true(out_with.contains("\"row_strategy\""))
  assert_true(out_without.contains("\"value\""))
  // Nash value は payoff のスケール不変で差が埋もれうるため、値の一致/不一致
  // には assert せず、parse が通ることだけを確認する smoke test。
  // damage 差分の検証は別 test (compute_mean_damage: ...) に寄せた。
}
