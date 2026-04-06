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
  inspect(
    errors.iter().any(fn(e) { e.contains("moves") || e.contains("Items") }),
    content="true",
  )
}

///|
test "validate_pokemon_json: valid cache input" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "phase": 7,
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
    #|  "damage_calcs": [],
    #|  "updated_at": "2026-04-06T00:00:00Z"
    #|}
  let json = @json.parse(src)
  inspect(validate_pokemon_json(json), content="Ok(())")
}

///|
test "validate_pokemon_json: evs over 510" {
  let src =
    #|{
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
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "evs": {"hp":252,"atk":252,"def":0,"spa":0,"spd":252,"spe":0},
    #|    "actual_stats": {"hp":183,"atk":182,"def":115,"spa":90,"spd":106,"spe":169}
    #|  },
    #|  "damage_calcs": []
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
test "validate_pokemon_json: missing build" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "type1": "ドラゴン",
    #|    "base_stats": {"hp":108,"atk":130,"def":95,"spa":80,"spd":85,"spe":102}
    #|  }
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) { e.contains("build") }),
    content="true",
  )
}

///|
test "validate_pokemon_json: empty move name rejected" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "type1": "ドラゴン",
    #|    "base_stats": {"hp":108,"atk":130,"def":95,"spa":80,"spd":85,"spe":102}
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "nature_up": "すばやさ",
    #|    "nature_down": "とくこう",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "evs": {"hp":0,"atk":252,"def":0,"spa":0,"spd":4,"spe":252},
    #|    "actual_stats": {"hp":183,"atk":182,"def":115,"spa":90,"spd":106,"spe":169}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) { e.contains("move name must not be empty") }),
    content="true",
  )
}
