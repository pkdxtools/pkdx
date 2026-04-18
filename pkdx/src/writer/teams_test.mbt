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
test "build_team_document: members table uses メモ header" {
  let src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "members": [{
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "ability": "さめはだ",
    #|    "item": "こだわりハチマキ",
    #|    "role": "",
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
    #|  "strengths": [],
    #|  "weaknesses": []
    #|}
  let json = @json.parse(src)
  let doc = build_team_document(json, "ガブリアス", "2026-04-06")
  let md = @markdown.serialize(doc)
  assert_true(md.contains("| メモ |"))
  assert_false(md.contains("| 役割 |"))
}

///|
test "build_team_document: memo with pipe is escaped" {
  // 自由入力メモに `|` が含まれる場合でも、テーブル行が壊れてはならない。
  // markdown ライブラリが `|` → `\|` にエスケープするため、raw な `|` は混入しない想定。
  let src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "members": [{
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "ability": "さめはだ",
    #|    "item": "こだわりハチマキ",
    #|    "role": "HBD振り|物理受け|襷想定",
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
    #|  "strengths": [],
    #|  "weaknesses": []
    #|}
  let json = @json.parse(src)
  let doc = build_team_document(json, "ガブリアス", "2026-04-06")
  let md = @markdown.serialize(doc)
  // memo セル全体 (`| HBD振り\|物理受け\|襷想定 |`) が 1 行として残っていること。
  assert_true(md.contains("HBD振り\\|物理受け\\|襷想定"))
  // メンバー行が崩れて列数が増えていないこと。
  // `\|` (escaped) はセル区切りではないため除外し、生の `|` のみを数える
  // (ヘッダ 7 列に対応する生パイプは必ず 8 個)。
  let member_line_unescaped_pipes = {
    let lines = md.split("\n")
    let mut count = 0
    for line in lines {
      let line_str = line.to_string()
      if line_str.contains("ガブリアス") && line_str.contains("HBD振り") {
        let chars = line_str.to_array()
        for i, c in chars {
          if c == '|' && (i == 0 || chars[i - 1] != '\\') {
            count = count + 1
          }
        }
      }
    }
    count
  }
  inspect(member_line_unescaped_pipes, content="8")
}

///|
test "build_team_document: memo with newlines collapsed to single row" {
  // 改行を含むメモを渡しても、テーブル行は必ず 1 行で完結する必要がある
  // (cat -E 的に言えば row 内に改行が混ざると次行の区切りと衝突する)。
  let src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "members": [{
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "ability": "さめはだ",
    #|    "item": "こだわりハチマキ",
    #|    "role": "物理アタッカー\n襷ステロ型\tS最速",
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
    #|  "strengths": [],
    #|  "weaknesses": []
    #|}
  let json = @json.parse(src)
  let doc = build_team_document(json, "ガブリアス", "2026-04-06")
  let md = @markdown.serialize(doc)
  // 3 フィールドがすべてスペース区切りで同一行に存在すること
  assert_true(md.contains("物理アタッカー 襷ステロ型 S最速"))
  // ガブリアスを含むメンバー行は必ず 1 本だけ
  let member_row_count = {
    let lines = md.split("\n")
    let mut count = 0
    for line in lines {
      let line_str = line.to_string()
      if line_str.contains("| 1 | ガブリアス |") {
        count = count + 1
      }
    }
    count
  }
  inspect(member_row_count, content="1")
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
