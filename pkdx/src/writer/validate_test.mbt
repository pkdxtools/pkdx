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
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100},
    #|      {"name":"げきりん","type":"ドラゴン","category":"物理","power":120,"accuracy":100},
    #|      {"name":"つるぎのまい","type":"ノーマル","category":"変化","power":0,"accuracy":0},
    #|      {"name":"ステルスロック","type":"いわ","category":"変化","power":0,"accuracy":0}
    #|    ],
    #|    "stat_points": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
    #|  },
    #|  "damage_calcs": [],
    #|  "updated_at": "2026-04-06T00:00:00Z"
    #|}
  let json = @json.parse(src)
  inspect(validate_pokemon_json(json), content="Ok(())")
}

///|
test "validate_pokemon_json: stat_points over 510 rejected on sv" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":252,"a":252,"b":0,"c":0,"d":252,"s":0},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) { e.contains("must be <= 510") }),
    content="true",
  )
}

///|
test "validate_pokemon_json: missing build" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
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
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
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

///|
test "validate_pokemon_json: empty string nature rejected by strict schema" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
    #|  },
    #|  "damage_calcs": []
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

///|
test "validate_team_json: with regulation field" {
  let src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル,メガシンカ",
    #|  "version": "champions",
    #|  "regulation": "M-A",
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
test "validate_team_json: regulation null is valid (backward compat)" {
  let src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "regulation": null,
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
test "validate_pokemon_json: champions sp total 66 boundary passes" {
  let src =
    #|{
    #|  "version": "champions",
    #|  "regulation": "M-A",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":32,"a":32,"b":2,"c":0,"d":0,"s":0},
    #|    "actual_stats": {"h":215,"a":182,"b":117,"c":90,"d":105,"s":169}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  inspect(validate_pokemon_json(json), content="Ok(())")
}

///|
test "validate_pokemon_json: champions sp total 67 boundary fails" {
  let src =
    #|{
    #|  "version": "champions",
    #|  "regulation": "M-A",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":32,"a":32,"b":3,"c":0,"d":0,"s":0},
    #|    "actual_stats": {"h":215,"a":182,"b":118,"c":90,"d":105,"s":169}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) { e.contains("Champions SP total") }),
    content="true",
  )
}

///|
test "validate_pokemon_json: champions sp each stat 32 boundary passes" {
  let src =
    #|{
    #|  "version": "champions",
    #|  "regulation": "M-A",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":32,"a":0,"b":0,"c":0,"d":0,"s":0},
    #|    "actual_stats": {"h":215,"a":150,"b":115,"c":90,"d":105,"s":135}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  inspect(validate_pokemon_json(json), content="Ok(())")
}

///|
test "validate_pokemon_json: champions sp each stat 33 boundary fails" {
  let src =
    #|{
    #|  "version": "champions",
    #|  "regulation": "M-A",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":33,"a":0,"b":0,"c":0,"d":0,"s":0},
    #|    "actual_stats": {"h":216,"a":150,"b":115,"c":90,"d":105,"s":135}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) { e.contains("Champions SP") && e.contains("/h") }),
    content="true",
  )
}

///|
test "validate_pokemon_json: champions sp negative value fails" {
  let src =
    #|{
    #|  "version": "champions",
    #|  "regulation": "M-A",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":-1,"a":0,"b":0,"c":0,"d":0,"s":0},
    #|    "actual_stats": {"h":182,"a":150,"b":115,"c":90,"d":105,"s":135}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) { e.contains("Champions SP") && e.contains("negative") }),
    content="true",
  )
}

///|
test "validate_pokemon_json: sp rule not applied when version is sv" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":33,"a":0,"b":0,"c":0,"d":0,"s":0},
    #|    "actual_stats": {"h":160,"a":150,"b":115,"c":90,"d":105,"s":135}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  inspect(validate_pokemon_json(json), content="Ok(())")
}

///|
test "validate_pokemon_json: 510 rule not applied when version is champions" {
  let src =
    #|{
    #|  "version": "champions",
    #|  "regulation": "M-A",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":60,"a":60,"b":60,"c":60,"d":60,"s":60},
    #|    "actual_stats": {"h":243,"a":210,"b":175,"c":150,"d":165,"s":195}
    #|  },
    #|  "damage_calcs": []
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  // Champions では「合計 > 66」エラーのみ発生し、「合計 > 510」エラーは起きない。
  inspect(
    errors.iter().any(fn(e) { e.contains("Champions SP total") }),
    content="true",
  )
  inspect(
    errors.iter().any(fn(e) { e.contains("must be <= 510") }),
    content="false",
  )
}

///|
/// 旧 schema (build.evs / nature_up/down / pokemon.type1) は "legacy" エラーで
/// pkdx convert meta --in-place に誘導する。
test "validate_pokemon_json: legacy schema detection for build.evs" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [],
    #|    "evs": {"hp":0,"atk":252,"def":0,"spa":0,"spd":4,"spe":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
    #|  }
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) {
      e.contains("legacy schema detected") && e.contains("pkdx convert meta")
    }),
    content="true",
  )
}

///|
/// long-key base_stats のみで他は新形式の pokemon meta も legacy として誘導される。
/// migrate_pokemon_meta_v011 が変換する shape は全て検出器でカバーする必要がある。
test "validate_pokemon_json: legacy detection for long-key base_stats" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"hp":108,"atk":130,"def":95,"spa":80,"spd":85,"spe":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
    #|  }
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) {
      e.contains("#/pokemon/base_stats") &&
      e.contains("legacy schema detected") &&
      e.contains("pkdx convert meta")
    }),
    content="true",
  )
}

///|
/// long-key stat_points のみで他は新形式の pokemon meta も legacy として誘導される。
test "validate_pokemon_json: legacy detection for long-key stat_points" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"hp":0,"atk":252,"def":0,"spa":0,"spd":4,"spe":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
    #|  }
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) {
      e.contains("#/build/stat_points") &&
      e.contains("legacy schema detected")
    }),
    content="true",
  )
}

///|
/// long-key actual_stats のみで他は新形式の pokemon meta も legacy として誘導される。
test "validate_pokemon_json: legacy detection for long-key actual_stats" {
  let src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "きあいのタスキ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|    "actual_stats": {"hp":183,"atk":182,"def":115,"spa":90,"spd":106,"spe":169}
    #|  }
    #|}
  let json = @json.parse(src)
  let result = validate_pokemon_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) {
      e.contains("#/build/actual_stats") &&
      e.contains("legacy schema detected")
    }),
    content="true",
  )
}

///|
/// team member の long-key stat_points/actual_stats も legacy として検出する。
test "validate_team_json: legacy detection for long-key stat_points on member" {
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
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100},
    #|      {"name":"げきりん","type":"ドラゴン","category":"物理","power":120},
    #|      {"name":"アイアンヘッド","type":"はがね","category":"物理","power":80},
    #|      {"name":"ストーンエッジ","type":"いわ","category":"物理","power":100}
    #|    ],
    #|    "stat_points": {"hp":0,"atk":252,"def":0,"spa":0,"spd":4,"spe":252}
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
    errors.iter().any(fn(e) {
      e.contains("#/members/0/stat_points") &&
      e.contains("legacy schema detected")
    }),
    content="true",
  )
}

///|
test "validate_team_json: legacy schema detection for long stat keys" {
  let src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "members": [{
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン"],
    #|    "base_stats": {"hp":108,"atk":130,"def":95,"spa":80,"spd":85,"spe":102},
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
    #|  "strengths": [],
    #|  "weaknesses": []
    #|}
  let json = @json.parse(src)
  let result = validate_team_json(json)
  guard result is Err(errors) else {
    fail("Expected Err but got Ok")
  }
  inspect(
    errors.iter().any(fn(e) {
      e.contains("legacy schema detected") && e.contains("pkdx convert meta")
    }),
    content="true",
  )
}
