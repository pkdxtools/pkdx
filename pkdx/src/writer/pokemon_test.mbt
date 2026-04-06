///|
test "build_pokemon_document: deterministic output" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "type1": "ドラゴン",
    #|    "type2": "じめん",
    #|    "base_stats": {"hp":108,"atk":130,"def":95,"spa":80,"spd":85,"spe":102}
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "nature_up": "すばやさ",
    #|    "nature_down": "とくこう",
    #|    "ability": "さめはだ",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100},
    #|      {"name":"げきりん","type":"ドラゴン","category":"物理","power":120,"accuracy":100},
    #|      {"name":"アイアンヘッド","type":"はがね","category":"物理","power":80,"accuracy":100},
    #|      {"name":"ストーンエッジ","type":"いわ","category":"物理","power":100,"accuracy":80}
    #|    ],
    #|    "evs": {"hp":0,"atk":252,"def":0,"spa":0,"spd":4,"spe":252},
    #|    "actual_stats": {"hp":183,"atk":182,"def":115,"spa":90,"spd":106,"spe":169}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  let doc = build_pokemon_document(json, "ガブリアス")
  let md = @markdown.serialize(doc)
  let doc2 = build_pokemon_document(json, "ガブリアス")
  let md2 = @markdown.serialize(doc2)
  assert_eq(md, md2)
  assert_true(md.contains("# ガブリアス 育成データ"))
  assert_true(md.contains("## 基本情報"))
  assert_true(md.contains("| ポケモン | ガブリアス |"))
  assert_true(md.contains("| タイプ | ドラゴン/じめん |"))
  assert_true(md.contains("ようき (すばやさ↑ とくこう↓)"))
  assert_true(md.contains("## 実数値 (Lv50, 6V)"))
  assert_true(md.contains("| HP | 108 | 0 | 183 |"))
  assert_true(md.contains("| すばやさ | 102 | 252 | 169 |"))
  assert_true(md.contains("## 技構成"))
  assert_true(md.contains("| じしん | じめん | 物理 | 100 | 100 |"))
  assert_true(md.contains("## ダメージ計算用コマンド"))
  assert_true(md.contains("--atk-stat 182"))
  assert_true(md.contains("--def-hp 183"))
}

///|
test "build_pokemon_document: with damage calcs" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "type1": "ドラゴン",
    #|    "type2": "じめん",
    #|    "base_stats": {"hp":108,"atk":130,"def":95,"spa":80,"spd":85,"spe":102}
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "nature_up": "すばやさ",
    #|    "nature_down": "とくこう",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100},
    #|      {"name":"げきりん","type":"ドラゴン","category":"物理","power":120,"accuracy":100},
    #|      {"name":"つるぎのまい","type":"ノーマル","category":"変化","power":0,"accuracy":0},
    #|      {"name":"ステルスロック","type":"いわ","category":"変化","power":0,"accuracy":0}
    #|    ],
    #|    "evs": {"hp":0,"atk":252,"def":0,"spa":0,"spd":4,"spe":252},
    #|    "actual_stats": {"hp":183,"atk":182,"def":115,"spa":90,"spd":106,"spe":169}
    #|  },
    #|  "damage_calcs": [{
    #|    "direction": "attack",
    #|    "opponent": "サーフゴー",
    #|    "move": "じしん",
    #|    "damages": [150,152,154,156,158,160,162,164,166,168,170,172,174,176,178,180],
    #|    "percents": [0.920,0.932,0.944,0.957,0.969,0.981,0.993,1.006,1.018,1.030,1.042,1.055,1.067,1.079,1.092,1.104],
    #|    "defender_hp": 163,
    #|    "ko": "乱数1発 (50.0%)"
    #|  }]
    #|}
  let json = @json.parse(src)
  let doc = build_pokemon_document(json, "ガブリアス")
  let md = @markdown.serialize(doc)
  assert_true(md.contains("## ダメージ計算結果"))
  assert_true(md.contains("### 攻撃側 vs サーフゴー / じしん"))
  assert_true(md.contains("確定数: 乱数1発 (50.0%)"))
}

///|
test "build_pokemon_document: dual type pokemon" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "サーフゴー",
    #|    "type1": "はがね",
    #|    "type2": "ゴースト",
    #|    "base_stats": {"hp":87,"atk":60,"def":95,"spa":133,"spd":91,"spe":84}
    #|  },
    #|  "build": {
    #|    "nature": "ひかえめ",
    #|    "nature_up": "とくこう",
    #|    "nature_down": "こうげき",
    #|    "ability": "おうごんのからだ",
    #|    "item": "こだわりメガネ",
    #|    "moves": [
    #|      {"name":"ゴールドラッシュ","type":"はがね","category":"特殊","power":120,"accuracy":100},
    #|      {"name":"シャドーボール","type":"ゴースト","category":"特殊","power":80,"accuracy":100},
    #|      {"name":"きあいだま","type":"かくとう","category":"特殊","power":120,"accuracy":70},
    #|      {"name":"トリック","type":"エスパー","category":"変化","power":0,"accuracy":100}
    #|    ],
    #|    "evs": {"hp":0,"atk":0,"def":0,"spa":252,"spd":4,"spe":252},
    #|    "actual_stats": {"hp":162,"atk":72,"def":115,"spa":200,"spd":112,"spe":136}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  let doc = build_pokemon_document(json, "サーフゴー")
  let md = @markdown.serialize(doc)
  assert_true(md.contains("# サーフゴー 育成データ"))
  assert_true(md.contains("| タイプ | はがね/ゴースト |"))
  assert_true(md.contains("ひかえめ (とくこう↑ こうげき↓)"))
}
