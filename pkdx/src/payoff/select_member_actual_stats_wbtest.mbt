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

///|
/// 不正な `nature` 文字列は `None` に丸めずエラーにする。
/// `None` は damage engine の "攻撃側 +10% 補正" 既定へフォールバックするため、
/// 典型的な typo (末尾空白 / 全角・半角ズレ) を黙って受け入れると攻撃が
/// 盛られた payoff が返ってしまう。
test "parse_combatant_json: malformed nature raises InvalidJson" {
  let src =
    #|{
    #|  "name": "マンムー",
    #|  "types": ["こおり","じめん"],
    #|  "base_stats": {"h":110,"a":130,"b":80,"c":70,"d":60,"s":80},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "ようき ",
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let err = try? parse_single_combatant(src)
  assert_true(err is Err(InvalidJson(_)))
}

///|
/// 型違いの `nature` (数値など) もエラーにする。
test "parse_combatant_json: non-string nature raises InvalidJson" {
  let src =
    #|{
    #|  "name": "マンムー",
    #|  "types": ["こおり","じめん"],
    #|  "base_stats": {"h":110,"a":130,"b":80,"c":70,"d":60,"s":80},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": 42,
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let err = try? parse_single_combatant(src)
  assert_true(err is Err(InvalidJson(_)))
}

///|
/// 明示的な `nature: null` / 空文字 / キー欠損は従来どおり `None` として
/// 許容する (engine のフォールバックに委ねる)。
test "parse_combatant_json: null/empty nature is accepted as None" {
  let with_null =
    #|{
    #|  "name": "マンムー",
    #|  "types": ["こおり","じめん"],
    #|  "base_stats": {"h":110,"a":130,"b":80,"c":70,"d":60,"s":80},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": null,
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let with_empty =
    #|{
    #|  "name": "マンムー",
    #|  "types": ["こおり","じめん"],
    #|  "base_stats": {"h":110,"a":130,"b":80,"c":70,"d":60,"s":80},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "",
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|  ]
    #|}
  let c1 = parse_single_combatant(with_null)
  let c2 = parse_single_combatant(with_empty)
  match c1.nature {
    None => ()
    Some(_) => fail("null nature must be None")
  }
  match c2.nature {
    None => ()
    Some(_) => fail("empty nature must be None")
  }
}

///|
/// `stat_points` が `{h,a,b,c,d,s}` 形式で読まれて Combatant に載ることを確認する。
test "parse_combatant_json: stat_points is lifted into Combatant" {
  let src =
    #|{
    #|  "name": "リザードン",
    #|  "types": ["ほのお","ひこう"],
    #|  "base_stats": {"h":78,"a":84,"b":78,"c":109,"d":85,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "おくびょう",
    #|  "stat_points": {"h":0,"a":0,"b":0,"c":32,"d":2,"s":32},
    #|  "actual_stats": {"h":153,"a":95,"b":98,"c":182,"d":107,"s":167},
    #|  "moves": [
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|  ]
    #|}
  let c = parse_single_combatant(src)
  match c.stat_points {
    Some(sp) => {
      assert_eq(sp.length(), 6)
      assert_eq(sp[0], 0)
      assert_eq(sp[3], 32) // C
      assert_eq(sp[5], 32) // S
    }
    None => fail("stat_points must be parsed")
  }
}

///|
/// メガ進化後の実数値は pre-mega `actual_stats` をそのまま使えないため、
/// `stat_points` + `nature` + post-mega base から再計算されることを確認する。
///
/// 入力: リザードン (base SpA 109 / Spe 100) + ようき / C=32 S=32。
///   pre-mega actual は C=179, S=167 相当。
/// メガ進化で SpA 159 / Spe 100 に上がる (メガリザY 相当)。
/// 正しい実装なら post-mega actual C は 159 ベースで再計算される。
/// ようき性格は C 下降なので `(159 + 32 + 20) * 9/10 = 189`。
/// 以前の (actual_stats を落とす) 実装では engine 既定 (SP 32 + ひかえめ相当)
/// へフォールバックしてしまい、この差を埋められない。
test "effective_combatant: mega recomputes actual_stats from stat_points/nature" {
  let src =
    #|{
    #|  "name": "リザードン",
    #|  "types": ["ほのお","ひこう"],
    #|  "base_stats": {"h":78,"a":84,"b":78,"c":109,"d":85,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "ようき",
    #|  "stat_points": {"h":0,"a":0,"b":0,"c":32,"d":2,"s":32},
    #|  "actual_stats": {"h":153,"a":95,"b":98,"c":179,"d":107,"s":167},
    #|  "mega_form": {
    #|    "atk":104, "def":78, "spa":159, "spd":115, "spe":100,
    #|    "type1":"ほのお", "type2":"ドラゴン", "ability":"ひでり",
    #|    "name_ja":"メガリザードンY"
    #|  },
    #|  "moves": [
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|  ]
    #|}
  let pre = parse_single_combatant(src)
  let post = effective_combatant(pre, true)
  // mega_form / nature / stat_points はすべて伝搬する。
  match post.nature {
    Some(n) => assert_eq(n.name_ja, "ようき")
    None => fail("post-mega nature must be preserved")
  }
  match post.stat_points {
    Some(sp) => assert_eq(sp[3], 32)
    None => fail("post-mega stat_points must be preserved")
  }
  match post.actual_stats {
    Some(arr) => {
      assert_eq(arr.length(), 6)
      // HP は mega で不変。pre-mega actual_stats[0] (= 153) を引き継ぐ。
      assert_eq(arr[0], 153)
      // SpA: post-mega base 159 + SP 32 + Champions オフセット 20 に
      // ようき (SpA 下降 9/10) を掛けて 189。
      assert_eq(arr[3], 189)
      // Spe: post-mega base 100 + SP 32 + 20 にようき (Spe 上昇 11/10) = 167。
      assert_eq(arr[5], 167)
    }
    None =>
      fail(
        "post-mega actual_stats must be recomputed when stat_points and nature are available",
      )
  }
}

///|
/// `stat_points` / `nature` が片方でも欠けているときは post-mega 実数値を
/// 再計算できないので `None` にフォールバックする (= engine 既定投資へ)。
/// 再計算パスが silent に誤った値を返すより、engine 既定に戻すほうが
/// 「データが欠けている」ことが payoff 上で分かりやすい。
test "effective_combatant: mega without stat_points drops actual_stats" {
  let src =
    #|{
    #|  "name": "リザードン",
    #|  "types": ["ほのお","ひこう"],
    #|  "base_stats": {"h":78,"a":84,"b":78,"c":109,"d":85,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "ひかえめ",
    #|  "actual_stats": {"h":153,"a":72,"b":98,"c":205,"d":107,"s":149},
    #|  "mega_form": {
    #|    "atk":104, "def":78, "spa":159, "spd":115, "spe":100,
    #|    "type1":"ほのお", "type2":"ドラゴン", "ability":"ひでり",
    #|    "name_ja":"メガリザードンY"
    #|  },
    #|  "moves": [
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|  ]
    #|}
  let pre = parse_single_combatant(src)
  let post = effective_combatant(pre, true)
  match post.actual_stats {
    None => ()
    Some(_) =>
      fail("actual_stats must be dropped when stat_points are not available")
  }
  // nature は引き続き伝搬 (engine は nature + 既定投資で再計算できる)。
  match post.nature {
    Some(n) => assert_eq(n.name_ja, "ひかえめ")
    None => fail("post-mega nature must still be preserved")
  }
}

///|
/// メガ進化経由でも pre-mega の `stat_points` 由来 SpA が damage に効くことを
/// end-to-end で確認する: `compute_mean_damage` を post-mega Combatant に対して
/// 直接呼び、SP 32 投資 vs SP 0 投資で damage が増えることを見る。
/// これが壊れていると、select で mega 進化を含むセルだけ engine 既定投資に
/// 戻ってしまうため、実構築と乖離した評価になる。
test "compute_mean_damage via effective_combatant: mega uses stat_points-derived SpA" {
  let invested_src =
    #|{
    #|  "name": "リザードン",
    #|  "types": ["ほのお","ひこう"],
    #|  "base_stats": {"h":78,"a":84,"b":78,"c":109,"d":85,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "ひかえめ",
    #|  "stat_points": {"h":0,"a":0,"b":0,"c":32,"d":2,"s":32},
    #|  "actual_stats": {"h":153,"a":72,"b":98,"c":205,"d":107,"s":149},
    #|  "mega_form": {
    #|    "atk":104, "def":78, "spa":159, "spd":115, "spe":100,
    #|    "type1":"ほのお", "type2":"ドラゴン", "ability":"",
    #|    "name_ja":"メガリザードンY"
    #|  },
    #|  "moves": [
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|  ]
    #|}
  let uninvested_src =
    #|{
    #|  "name": "リザードン",
    #|  "types": ["ほのお","ひこう"],
    #|  "base_stats": {"h":78,"a":84,"b":78,"c":109,"d":85,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "ひかえめ",
    #|  "stat_points": {"h":0,"a":0,"b":0,"c":0,"d":0,"s":0},
    #|  "actual_stats": {"h":153,"a":72,"b":98,"c":173,"d":93,"s":117},
    #|  "mega_form": {
    #|    "atk":104, "def":78, "spa":159, "spd":115, "spe":100,
    #|    "type1":"ほのお", "type2":"ドラゴン", "ability":"",
    #|    "name_ja":"メガリザードンY"
    #|  },
    #|  "moves": [
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
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
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|  ]
    #|}
  let invested = effective_combatant(parse_single_combatant(invested_src), true)
  let uninvested = effective_combatant(
    parse_single_combatant(uninvested_src), true,
  )
  let dfn = parse_single_combatant(dfn_src)
  let mv : @model.Move = {
    name: "かえんほうしゃ",
    type_: "ほのお",
    category: @model.Special,
    power: 90,
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
  let d_invested = compute_mean_damage(invested, dfn, mv, 0, 0)
  let d_uninvested = compute_mean_damage(uninvested, dfn, mv, 0, 0)
  assert_true(d_invested > 0)
  assert_true(d_uninvested > 0)
  assert_true(d_invested > d_uninvested)
}

///|
/// Standard (EV/IV) format で Combatant の `ivs` フィールドが
/// `parse_combatant_json` → Combatant に流れ込むことを確認する。
test "parse_combatant_json: ivs field is lifted into Combatant" {
  let src =
    #|{
    #|  "name": "リザードン",
    #|  "types": ["ほのお","ひこう"],
    #|  "base_stats": {"h":78,"a":84,"b":78,"c":109,"d":85,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "おくびょう",
    #|  "stat_points": {"h":0,"a":0,"b":0,"c":252,"d":4,"s":252},
    #|  "actual_stats": {"h":153,"a":80,"b":98,"c":161,"d":106,"s":167},
    #|  "ivs": {"h":31,"a":0,"b":31,"c":31,"d":31,"s":31},
    #|  "moves": [
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|  ]
    #|}
  let j = @json.parse(src)
  let c = parse_combatant_json(j, "test", stat_system=@model.Standard)
  match c.ivs {
    Some(arr) => {
      assert_eq(arr.length(), 6)
      assert_eq(arr[0], 31)
      assert_eq(arr[1], 0) // 0 Atk IV (混乱自傷ケア想定)
      assert_eq(arr[5], 31)
    }
    None => fail("ivs must be parsed")
  }
}

///|
/// `ivs` キー欠損は `None` にフォールバックする (= 再計算時 31 揃いを仮定)。
test "parse_combatant_json: missing ivs keeps Combatant None" {
  let src =
    #|{
    #|  "name": "リザードン",
    #|  "types": ["ほのお","ひこう"],
    #|  "base_stats": {"h":78,"a":84,"b":78,"c":109,"d":85,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "おくびょう",
    #|  "stat_points": {"h":0,"a":0,"b":0,"c":252,"d":4,"s":252},
    #|  "actual_stats": {"h":153,"a":80,"b":98,"c":161,"d":106,"s":167},
    #|  "moves": [
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|  ]
    #|}
  let j = @json.parse(src)
  let c = parse_combatant_json(j, "test", stat_system=@model.Standard)
  match c.ivs {
    None => ()
    Some(_) => fail("missing ivs should be None")
  }
}

///|
/// Standard フォーマットでメガ進化後の実数値を再計算するとき、
/// `Combatant.ivs` がユーザ指定の IV を尊重することを確認する。
/// これが 31 ハードコードに戻ると、0 Atk (混乱自傷ケアの特殊アタッカー) や
/// 0 Spe (トリル下行動) の意図的な非 31 IV 構築が post-mega で壊れる。
///
/// 入力: リザードン (pre-mega base Atk 84 / SpA 109) + おくびょう
///        (SpA ±0, Atk 0.9, Spe 1.1) + EV {H:0,A:0,B:0,C:252,D:4,S:252}
///        + IVs {H:31,A:0,B:31,C:31,D:31,S:31}
/// メガ Y: base Atk 104, Def 78, SpA 159, SpD 115, Spe 100。
///
/// IV 0 の Atk で再計算されれば post-mega Atk =
///   floor((104*2 + 0 + 0)*50/100 + 5) = 109, ×9/10 = 98。
/// IV 31 をハードコードしていれば 124 → ×9/10 = 111 になる。
/// → `arr[1] == 98` を assert することで回帰を検出する。
test "effective_combatant: mega honors non-31 Standard IVs in post-mega recompute" {
  let src =
    #|{
    #|  "name": "リザードン",
    #|  "types": ["ほのお","ひこう"],
    #|  "base_stats": {"h":78,"a":84,"b":78,"c":109,"d":85,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "おくびょう",
    #|  "stat_points": {"h":0,"a":0,"b":0,"c":252,"d":4,"s":252},
    #|  "actual_stats": {"h":153,"a":80,"b":98,"c":161,"d":106,"s":167},
    #|  "ivs": {"h":31,"a":0,"b":31,"c":31,"d":31,"s":31},
    #|  "mega_form": {
    #|    "atk":104, "def":78, "spa":159, "spd":115, "spe":100,
    #|    "type1":"ほのお", "type2":"ドラゴン", "ability":"ひでり",
    #|    "name_ja":"メガリザードンY"
    #|  },
    #|  "moves": [
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|  ]
    #|}
  let j = @json.parse(src)
  let pre = parse_combatant_json(j, "test", stat_system=@model.Standard)
  let post = effective_combatant(pre, true)
  match post.actual_stats {
    Some(arr) => {
      assert_eq(arr.length(), 6)
      // HP は mega で不変。pre-mega actual_stats[0] (=153) を引き継ぐ。
      assert_eq(arr[0], 153)
      // Atk: IV 0 が尊重されれば 98。IV 31 ハードコードだと 111 になる (= 回帰)。
      assert_eq(arr[1], 98)
      // SpA: IV 31 / EV 252 / neutral nature / post-mega base 159
      // = floor((159*2+31+63)*50/100+5) = 211。
      assert_eq(arr[3], 211)
      // Spe: IV 31 / EV 252 / +10% / post-mega base 100 変化なしなので 167。
      assert_eq(arr[5], 167)
    }
    None => fail("post-mega actual_stats must be recomputed")
  }
  match post.ivs {
    Some(arr) => {
      assert_eq(arr[1], 0)
    }
    None => fail("ivs must be preserved through effective_combatant")
  }
}

///|
/// IV を明示していないときは 31 揃いを仮定する既存挙動を確認する。
/// (後方互換: cache に `ivs` を書いていない古い構築でも動く)
test "effective_combatant: mega defaults IVs to 31 when ivs is missing (Standard)" {
  let src =
    #|{
    #|  "name": "リザードン",
    #|  "types": ["ほのお","ひこう"],
    #|  "base_stats": {"h":78,"a":84,"b":78,"c":109,"d":85,"s":100},
    #|  "ability": "","item": "","tera": "",
    #|  "nature": "おくびょう",
    #|  "stat_points": {"h":0,"a":0,"b":0,"c":252,"d":4,"s":252},
    #|  "actual_stats": {"h":153,"a":111,"b":98,"c":161,"d":106,"s":167},
    #|  "mega_form": {
    #|    "atk":104, "def":78, "spa":159, "spd":115, "spe":100,
    #|    "type1":"ほのお", "type2":"ドラゴン", "ability":"ひでり",
    #|    "name_ja":"メガリザードンY"
    #|  },
    #|  "moves": [
    #|    {"name":"かえんほうしゃ","type":"ほのお","category":"特殊","power":90}
    #|  ]
    #|}
  let j = @json.parse(src)
  let pre = parse_combatant_json(j, "test", stat_system=@model.Standard)
  let post = effective_combatant(pre, true)
  match post.actual_stats {
    Some(arr) => {
      // IV 31 デフォルト + 0.9 nature の post-mega Atk = 111。
      assert_eq(arr[1], 111)
    }
    None => fail("post-mega actual_stats must be recomputed")
  }
}
