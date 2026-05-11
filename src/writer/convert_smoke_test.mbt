///|
/// Integration smoke: 旧 schema fixture → migrate_pokemon_meta_v011
/// → validate_pokemon_json → build_pokemon_document → markdown.serialize
/// のフルパスが decomposition なく通ることを担保。
test "convert_smoke: legacy pokemon fixture migrates then renders md" {
  let legacy_src =
    #|{
    #|  "version": "champions",
    #|  "regulation": "M-A",
    #|  "pokemon": {
    #|    "name": "マンムー",
    #|    "type1": "こおり",
    #|    "type2": "じめん",
    #|    "base_stats": {"hp":110,"atk":130,"def":80,"spa":70,"spd":60,"spe":80},
    #|    "abilities": {
    #|      "ability1": "あついしぼう",
    #|      "ability2": "どんかん",
    #|      "dream_ability": "ゆきがくれ"
    #|    }
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "nature_up": "すばやさ",
    #|    "nature_down": "とくこう",
    #|    "ability": "あついしぼう",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100},
    #|      {"name":"つららおとし","type":"こおり","category":"物理","power":85,"accuracy":90},
    #|      {"name":"つららばり","type":"こおり","category":"物理","power":25,"accuracy":100},
    #|      {"name":"ばかぢから","type":"かくとう","category":"物理","power":120,"accuracy":100}
    #|    ],
    #|    "evs": {"hp":20,"atk":32,"def":0,"spa":0,"spd":0,"spe":14},
    #|    "actual_stats": {"hp":205,"atk":182,"def":100,"spa":81,"spd":80,"spe":145}
    #|  },
    #|  "damage_calcs": []
    #|}
  let legacy = @json.parse(legacy_src)

  // 旧 schema を直接 validate すると legacy 誘導エラー。
  let legacy_validation = validate_pokemon_json(legacy)
  guard legacy_validation is Err(errs) else {
    fail("legacy schema must not pass validation")
  }
  assert_true(errs.iter().any(fn(e) { e.contains("pkdx convert meta") }))

  // migrate で新 schema に変換すれば通る。
  let migrated = match migrate_pokemon_meta_v011(legacy) {
    Ok(j) => j
    Err(e) => {
      fail("migrate failed: \{e}")
    }
  }
  inspect(validate_pokemon_json(migrated), content="Ok(())")

  // md 出力が期待される内容を含む。
  let doc = build_pokemon_document(migrated, "マンムー")
  let md = @markdown.serialize(doc)
  assert_true(md.contains("# マンムー 育成データ"))
  assert_true(md.contains("| タイプ | こおり/じめん |"))
  assert_true(md.contains("ようき (すばやさ↑ とくこう↓)"))
  assert_true(md.contains("あついしぼう"))
  assert_true(md.contains("こだわりスカーフ"))
}

///|
/// migrate は冪等。2 回適用しても差分なし。
test "convert_smoke: migration is idempotent" {
  let legacy_src =
    #|{
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "type1": "ドラゴン",
    #|    "type2": "じめん",
    #|    "base_stats": {"hp":108,"atk":130,"def":95,"spa":80,"spd":85,"spe":102},
    #|    "abilities": {"ability1":"さめはだ"}
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "nature_up": "すばやさ",
    #|    "nature_down": "とくこう",
    #|    "ability": "さめはだ",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [],
    #|    "evs": {"hp":0,"atk":252,"def":0,"spa":0,"spd":4,"spe":252},
    #|    "actual_stats": {"hp":183,"atk":182,"def":115,"spa":90,"spd":106,"spe":169}
    #|  }
    #|}
  let legacy = @json.parse(legacy_src)
  let once = match migrate_pokemon_meta_v011(legacy) {
    Ok(j) => j
    Err(e) => {
      fail("migrate failed: \{e}")
    }
  }
  let twice = match migrate_pokemon_meta_v011(once) {
    Ok(j) => j
    Err(e) => {
      fail("migrate failed on new-format input: \{e}")
    }
  }
  assert_eq(once, twice)
}
