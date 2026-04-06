///|
test "validate_team_json: valid minimal input" {
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
    #|  "strengths": ["テスト"],
    #|  "weaknesses": ["テスト"]
    #|}
  let json = @json.parse(src)
  inspect(validate_team_json(json), content="Ok(())")
}

///|
test "validate_team_json: missing fields reports all errors" {
  let src =
    #|{"battle_format": "singles"}
  let json = @json.parse(src)
  let result = validate_team_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(errors.length() >= 8, content="true")
}

///|
test "validate_team_json: invalid battle_format" {
  let src =
    #|{
    #|  "battle_format": "triples",
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
    #|  "strengths": ["テスト"],
    #|  "weaknesses": ["テスト"]
    #|}
  let json = @json.parse(src)
  let result = validate_team_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) { e.contains("battle_format") }),
    content="true",
  )
}

///|
test "validate_team_json: wrong moves count" {
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
    #|    "role": "軸",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100}
    #|    ]
    #|  }],
    #|  "coverage": [],
    #|  "defense_matrix": [],
    #|  "matchup_plans": [],
    #|  "strengths": [],
    #|  "weaknesses": []
    #|}
  let json = @json.parse(src)
  let result = validate_team_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  // jsonschema reports minItems/maxItems violation
  inspect(
    errors.iter().any(fn(e) { e.contains("moves") || e.contains("Items") }),
    content="true",
  )
}

///|
test "validate_pokemon_json: valid input" {
  let src =
    #|{
    #|  "name": "ガブリアス",
    #|  "types": ["ドラゴン", "じめん"],
    #|  "nature": {"name": "ようき", "plus": "すばやさ", "minus": "とくこう"},
    #|  "ability": "さめはだ",
    #|  "item": "きあいのタスキ",
    #|  "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|  "evs": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|  "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169},
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100},
    #|    {"name":"げきりん","type":"ドラゴン","category":"物理","power":120,"accuracy":100},
    #|    {"name":"つるぎのまい","type":"ノーマル","category":"変化","power":0,"accuracy":0},
    #|    {"name":"ステルスロック","type":"いわ","category":"変化","power":0,"accuracy":0}
    #|  ],
    #|  "damage_calcs": [],
    #|  "filename": "スカーフ型"
    #|}
  let json = @json.parse(src)
  inspect(validate_pokemon_json(json), content="Ok(())")
}

///|
test "validate_pokemon_json: evs over 510" {
  let src =
    #|{
    #|  "name": "ガブリアス",
    #|  "types": ["ドラゴン", "じめん"],
    #|  "nature": {"name": "ようき", "plus": "すばやさ", "minus": "とくこう"},
    #|  "ability": "さめはだ",
    #|  "item": "きあいのタスキ",
    #|  "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|  "evs": {"h":252,"a":252,"b":0,"c":0,"d":252,"s":0},
    #|  "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169},
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100},
    #|    {"name":"げきりん","type":"ドラゴン","category":"物理","power":120,"accuracy":100},
    #|    {"name":"つるぎのまい","type":"ノーマル","category":"変化","power":0,"accuracy":0},
    #|    {"name":"ステルスロック","type":"いわ","category":"変化","power":0,"accuracy":0}
    #|  ],
    #|  "damage_calcs": [],
    #|  "filename": "スカーフ型"
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) { e.contains("evs total is") }),
    content="true",
  )
}

///|
test "validate_pokemon_json: missing nature" {
  let src =
    #|{
    #|  "name": "ガブリアス",
    #|  "types": ["ドラゴン"],
    #|  "ability": "さめはだ",
    #|  "item": "きあいのタスキ",
    #|  "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|  "evs": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|  "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169},
    #|  "moves": [
    #|    {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|  ],
    #|  "damage_calcs": [],
    #|  "filename": "テスト"
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) { e.contains("nature") }),
    content="true",
  )
}
