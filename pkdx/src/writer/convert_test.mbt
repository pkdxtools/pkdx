///|
/// migrate_pokemon_meta_v011: 旧 breed JSON（long stat keys, type1/type2, abilities{},
/// nature_up/down, evs）→ 新 schema（short keys, types[], abilities[], stat_points）。
test "migrate_pokemon_meta_v011: full conversion" {
  let old_src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "name_en": "Garchomp",
    #|    "globalNo": "0445",
    #|    "type1": "ドラゴン",
    #|    "type2": "じめん",
    #|    "base_stats": {"hp":108,"atk":130,"def":95,"spa":80,"spd":85,"spe":102},
    #|    "abilities": {
    #|      "ability1": "さめはだ",
    #|      "ability2": null,
    #|      "dream_ability": "かちき"
    #|    }
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "nature_up": "すばやさ",
    #|    "nature_down": "とくこう",
    #|    "ability": "さめはだ",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "evs": {"hp":0,"atk":252,"def":0,"spa":0,"spd":4,"spe":252},
    #|    "actual_stats": {"hp":183,"atk":182,"def":115,"spa":90,"spd":106,"spe":169}
    #|  },
    #|  "damage_calcs": []
    #|}
  let expected_src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "name_en": "Garchomp",
    #|    "globalNo": "0445",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ", "かちき"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
    #|  },
    #|  "damage_calcs": []
    #|}
  let old = @json.parse(old_src)
  let expected = @json.parse(expected_src)
  let result = migrate_pokemon_meta_v011(old)
  guard result is Ok(converted) else { fail("Expected Ok") }
  assert_eq(converted, expected)
}

///|
/// 新形式入力では no-op（冪等）。
test "migrate_pokemon_meta_v011: idempotent on new-format input" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [{"name":"じしん","type":"じめん","category":"物理","power":100}],
    #|    "stat_points": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
    #|  }
    #|}
  let new_input = @json.parse(src)
  let result = migrate_pokemon_meta_v011(new_input)
  guard result is Ok(converted) else { fail("Expected Ok") }
  assert_eq(converted, new_input)
}

///|
/// type2 が欠損 (key なし) の場合、types[] は要素数 1。
test "migrate_pokemon_meta_v011: single-type pokemon without type2 key" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "name": "ピカチュウ",
    #|    "name_en": "Pikachu",
    #|    "globalNo": "0025",
    #|    "type1": "でんき",
    #|    "base_stats": {"hp":35,"atk":55,"def":40,"spa":50,"spd":50,"spe":90},
    #|    "abilities": {"ability1":"せいでんき"}
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "nature_up": "すばやさ",
    #|    "nature_down": "とくこう",
    #|    "ability": "せいでんき",
    #|    "item": "でんきだま",
    #|    "moves": [{"name":"10まんボルト","type":"でんき","category":"特殊","power":90,"accuracy":100}],
    #|    "evs": {"hp":0,"atk":0,"def":0,"spa":252,"spd":4,"spe":252},
    #|    "actual_stats": {"hp":110,"atk":75,"def":60,"spa":105,"spd":75,"spe":161}
    #|  }
    #|}
  let old = @json.parse(src)
  let result = migrate_pokemon_meta_v011(old)
  guard result is Ok(Object(root)) else { fail("Expected Ok(Object)") }
  guard root.get("pokemon") is Some(Object(pokemon)) else {
    fail("pokemon section missing")
  }
  guard pokemon.get("types") is Some(Array(types)) else {
    fail("types[] missing")
  }
  assert_eq(types.length(), 1)
  assert_eq(types[0], "でんき".to_json())
  assert_true(pokemon.get("type1") is None)
  assert_true(pokemon.get("type2") is None)
}

///|
/// type2 が null の場合、types[] は要素数 1。
test "migrate_pokemon_meta_v011: type2 is null" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "type1": "でんき",
    #|    "type2": null,
    #|    "base_stats": {"hp":35,"atk":55,"def":40,"spa":50,"spd":50,"spe":90},
    #|    "abilities": {"ability1":"せいでんき"}
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "nature_up": "すばやさ",
    #|    "nature_down": "とくこう",
    #|    "ability": "せいでんき",
    #|    "item": "でんきだま",
    #|    "moves": [],
    #|    "evs": {"hp":0,"atk":0,"def":0,"spa":0,"spd":0,"spe":0},
    #|    "actual_stats": {"hp":0,"atk":0,"def":0,"spa":0,"spd":0,"spe":0}
    #|  }
    #|}
  let old = @json.parse(src)
  let result = migrate_pokemon_meta_v011(old)
  guard result is Ok(Object(root)) else { fail("Expected Ok(Object)") }
  guard root.get("pokemon") is Some(Object(pokemon)) else {
    fail("pokemon section missing")
  }
  guard pokemon.get("types") is Some(Array(types)) else {
    fail("types[] missing")
  }
  assert_eq(types.length(), 1)
}

///|
/// abilities の null / 空は配列から除外される。順序は ability1 → ability2 → dream_ability。
test "migrate_pokemon_meta_v011: abilities canonical order with nulls filtered" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "type1": "みず",
    #|    "base_stats": {"hp":0,"atk":0,"def":0,"spa":0,"spd":0,"spe":0},
    #|    "abilities": {
    #|      "ability1": "あついしぼう",
    #|      "ability2": "ちからもち",
    #|      "dream_ability": null
    #|    }
    #|  },
    #|  "build": {
    #|    "nature": "いじっぱり",
    #|    "nature_up": "こうげき",
    #|    "nature_down": "とくこう",
    #|    "ability": "ちからもち",
    #|    "item": "いのちのたま",
    #|    "moves": [],
    #|    "evs": {"hp":0,"atk":0,"def":0,"spa":0,"spd":0,"spe":0},
    #|    "actual_stats": {"hp":0,"atk":0,"def":0,"spa":0,"spd":0,"spe":0}
    #|  }
    #|}
  let old = @json.parse(src)
  let result = migrate_pokemon_meta_v011(old)
  guard result is Ok(Object(root)) else { fail("Expected Ok(Object)") }
  guard root.get("pokemon") is Some(Object(pokemon)) else {
    fail("pokemon section missing")
  }
  guard pokemon.get("abilities") is Some(Array(abilities)) else {
    fail("abilities[] missing")
  }
  assert_eq(abilities.length(), 2)
  assert_eq(abilities[0], "あついしぼう".to_json())
  assert_eq(abilities[1], "ちからもち".to_json())
}

///|
/// build.role が旧形式に無い場合、出力にも role は無い。同時に nature_up/down/evs も消える。
test "migrate_pokemon_meta_v011: build.role absent + legacy keys dropped" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "type1": "ほのお",
    #|    "base_stats": {"hp":0,"atk":0,"def":0,"spa":0,"spd":0,"spe":0},
    #|    "abilities": {"ability1":"もうか"}
    #|  },
    #|  "build": {
    #|    "nature": "ひかえめ",
    #|    "nature_up": "とくこう",
    #|    "nature_down": "こうげき",
    #|    "ability": "もうか",
    #|    "item": "いのちのたま",
    #|    "moves": [],
    #|    "evs": {"hp":0,"atk":0,"def":0,"spa":0,"spd":0,"spe":0},
    #|    "actual_stats": {"hp":0,"atk":0,"def":0,"spa":0,"spd":0,"spe":0}
    #|  }
    #|}
  let old = @json.parse(src)
  let result = migrate_pokemon_meta_v011(old)
  guard result is Ok(Object(root)) else { fail("Expected Ok(Object)") }
  guard root.get("build") is Some(Object(build)) else {
    fail("build section missing")
  }
  assert_true(build.get("role") is None)
  assert_true(build.get("nature_up") is None)
  assert_true(build.get("nature_down") is None)
  assert_true(build.get("evs") is None)
}

///|
/// 新形式で role を含む入力は role を保持。
test "migrate_pokemon_meta_v011: preserves role on new-format input" {
  let src =
    #|{
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [],
    #|    "stat_points": {"h":0,"a":0,"b":0,"c":0,"d":0,"s":0},
    #|    "actual_stats": {"h":0,"a":0,"b":0,"c":0,"d":0,"s":0},
    #|    "role": "物理アタッカー"
    #|  }
    #|}
  let new_input = @json.parse(src)
  let result = migrate_pokemon_meta_v011(new_input)
  guard result is Ok(Object(root)) else { fail("Expected Ok(Object)") }
  guard root.get("build") is Some(Object(build)) else {
    fail("build section missing")
  }
  assert_eq(build.get("role"), Some("物理アタッカー".to_json()))
}

///|
/// 旧 team cache: members[].base_stats が long key。validate 段階で legacy 判定
/// されるため、migrate で short key へ正規化する必要がある。
test "migrate_team_meta_v011: members long-key stats are shortened" {
  let old_src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "members": [{
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"hp":108,"atk":130,"def":95,"spa":80,"spd":85,"spe":102},
    #|    "ability": "さめはだ",
    #|    "item": "こだわりハチマキ",
    #|    "role": "軸",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100},
    #|      {"name":"げきりん","type":"ドラゴン","category":"物理","power":120},
    #|      {"name":"アイアンヘッド","type":"はがね","category":"物理","power":80},
    #|      {"name":"ストーンエッジ","type":"いわ","category":"物理","power":100}
    #|    ],
    #|    "stat_points": {"hp":0,"atk":252,"def":0,"spa":0,"spd":4,"spe":252},
    #|    "actual_stats": {"hp":183,"atk":182,"def":115,"spa":90,"spd":106,"spe":169}
    #|  }],
    #|  "coverage": [],
    #|  "defense_matrix": [],
    #|  "matchup_plans": []
    #|}
  let old = @json.parse(old_src)
  let result = migrate_team_meta_v011(old)
  guard result is Ok(converted) else { fail("Expected Ok") }
  // 変換後は validate を通過する必要がある (legacy 誘導エラーが消えている)。
  inspect(validate_team_json(converted), content="Ok(())")
  // members[0].base_stats が short key になっている。
  guard converted is Object(root) else { fail("root not object") }
  guard root.get("members") is Some(Array(members)) else {
    fail("members not array")
  }
  guard members[0] is Object(m0) else { fail("member not object") }
  guard m0.get("base_stats") is Some(Object(bs)) else {
    fail("base_stats not object")
  }
  assert_eq(bs.get("h"), Some((108 : Int).to_json()))
  assert_eq(bs.get("s"), Some((102 : Int).to_json()))
  assert_true(bs.get("hp") is None)
  assert_true(bs.get("spe") is None)
  guard m0.get("stat_points") is Some(Object(sp)) else {
    fail("stat_points not object")
  }
  assert_eq(sp.get("s"), Some((252 : Int).to_json()))
  assert_true(sp.get("spe") is None)
}

///|
/// migrate_team_meta_v011 は冪等。新 schema 入力は no-op。
test "migrate_team_meta_v011: idempotent on new-format input" {
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
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ]
    #|  }],
    #|  "coverage": [],
    #|  "defense_matrix": [],
    #|  "matchup_plans": []
    #|}
  let input = @json.parse(src)
  let once = match migrate_team_meta_v011(input) {
    Ok(j) => j
    Err(e) => {
      fail("migrate failed: \{e}")
    }
  }
  let twice = match migrate_team_meta_v011(once) {
    Ok(j) => j
    Err(e) => {
      fail("migrate failed on new-format input: \{e}")
    }
  }
  assert_eq(once, twice)
}

///|
/// migrate_team_meta_v011: 既に short key の base_stats と long key の
/// actual_stats が混在していても、全員 short key に揃える (冪等)。
test "migrate_team_meta_v011: passthrough for new-format team cache" {
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
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ]
    #|  }],
    #|  "coverage": [],
    #|  "defense_matrix": [],
    #|  "matchup_plans": []
    #|}
  let input = @json.parse(src)
  let result = migrate_team_meta_v011(input)
  guard result is Ok(converted) else { fail("Expected Ok") }
  assert_eq(converted, input)
}

///|
/// 非オブジェクト入力は Err。
test "migrate_pokemon_meta_v011: error on non-object input" {
  let src =
    #|[]
  let bad = @json.parse(src)
  let result = migrate_pokemon_meta_v011(bad)
  assert_true(result is Err(_))
}
