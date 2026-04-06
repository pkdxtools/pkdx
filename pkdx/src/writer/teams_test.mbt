///|
test "build_team_document: deterministic markdown output" {
  let src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "members": [{
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "ability": "さめはだ",
    #|    "item": "こだわりハチマキ",
    #|    "role": "軸",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100},
    #|      {"name":"げきりん","type":"ドラゴン","category":"物理","power":120},
    #|      {"name":"アイアンヘッド","type":"はがね","category":"物理","power":80},
    #|      {"name":"ストーンエッジ","type":"いわ","category":"物理","power":100}
    #|    ]
    #|  }],
    #|  "coverage": [],
    #|  "defense_matrix": [],
    #|  "matchup_plans": [],
    #|  "strengths": ["広い攻撃範囲"],
    #|  "weaknesses": ["氷4倍弱点"]
    #|}
  let json = @json.parse(src)
  let doc = build_team_document(json, "ガブリアス", "2026-04-06")
  let md = @markdown.serialize(doc)
  let doc2 = build_team_document(json, "ガブリアス", "2026-04-06")
  let md2 = @markdown.serialize(doc2)
  assert_eq(md, md2)
  assert_true(md.contains("# ガブリアス軸構築 - 2026-04-06"))
  assert_true(md.contains("## チーム"))
  assert_true(md.contains("| 1 | ガブリアス |"))
  assert_true(md.contains("108/130/95/80/85/102"))
  assert_true(md.contains("## 推奨技構成"))
  assert_true(md.contains("### ガブリアス"))
  assert_true(md.contains("| じしん |"))
  assert_true(md.contains("## 構築の強み"))
  assert_true(md.contains("広い攻撃範囲"))
  assert_true(md.contains("## 構築の弱み・注意点"))
  assert_true(md.contains("氷4倍弱点"))
}

///|
test "build_team_document: doubles matchup plans" {
  let src =
    #|{
    #|  "battle_format": "doubles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "members": [{
    #|    "name": "テスト",
    #|    "types": ["ノーマル"],
    #|    "base_stats": {"h":100,"a":100,"b":100,"c":100,"d":100,"s":100},
    #|    "ability": "テスト",
    #|    "item": "テスト",
    #|    "role": "軸",
    #|    "moves": [
    #|      {"name":"a","type":"ノーマル","category":"物理","power":100},
    #|      {"name":"b","type":"ノーマル","category":"物理","power":100},
    #|      {"name":"c","type":"ノーマル","category":"物理","power":100},
    #|      {"name":"d","type":"ノーマル","category":"物理","power":100}
    #|    ]
    #|  }],
    #|  "coverage": [],
    #|  "defense_matrix": [],
    #|  "matchup_plans": [{
    #|    "opponent": "パオジアン",
    #|    "opponent_type": "あく/こおり",
    #|    "leads": ["テスト", "テスト2"],
    #|    "backs": ["テスト3"],
    #|    "reason": "先発で有利"
    #|  }],
    #|  "strengths": [],
    #|  "weaknesses": []
    #|}
  let json = @json.parse(src)
  let doc = build_team_document(json, "テスト", "2026-04-06")
  let md = @markdown.serialize(doc)
  assert_true(md.contains("## 選出パターン"))
  assert_true(md.contains("先発:"))
  assert_true(md.contains("後発:"))
}

///|
test "build_team_document: coverage and defense matrix" {
  let src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "バニラ",
    #|  "version": "scarlet_violet",
    #|  "members": [{
    #|    "name": "A",
    #|    "types": ["ほのお"],
    #|    "base_stats": {"h":100,"a":100,"b":100,"c":100,"d":100,"s":100},
    #|    "ability": "もらいび",
    #|    "item": "いのちのたま",
    #|    "role": "軸",
    #|    "moves": [
    #|      {"name":"a","type":"ほのお","category":"特殊","power":90},
    #|      {"name":"b","type":"くさ","category":"特殊","power":90},
    #|      {"name":"c","type":"こおり","category":"特殊","power":90},
    #|      {"name":"d","type":"でんき","category":"特殊","power":90}
    #|    ]
    #|  }],
    #|  "coverage": [
    #|    {"def_type":"くさ","best_move_type":"ほのお","user":"A","multiplier":"2.0"}
    #|  ],
    #|  "defense_matrix": [
    #|    {"atk_type":"みず","matchups":{"A":"2.0"},"best_switch":"A"}
    #|  ],
    #|  "matchup_plans": [],
    #|  "strengths": [],
    #|  "weaknesses": []
    #|}
  let json = @json.parse(src)
  let doc = build_team_document(json, "A", "2026-04-06")
  let md = @markdown.serialize(doc)
  assert_true(md.contains("## 攻撃カバー率"))
  assert_true(md.contains("| くさ | ほのお | A | 2.0 |"))
  assert_true(md.contains("## 防御相性マトリクス"))
  assert_true(md.contains("| みず |"))
}
