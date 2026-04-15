///|
/// Integration smoke: vision 抽出後の固定 cache JSON が
/// validate → build_pokemon_document → markdown.serialize の決定論的パイプラインを
/// 通過し、必須情報 (名前 / 性格 / 特性 / 持ち物 / 技 / SP / 実数値) が md に全て含まれることを確認。
///
/// Claude vision 自体はテストしないが、「vision 後の JSON 契約」を満たす固定 fixture を
/// 流して後段のパイプラインが decomposition なく通ることを担保する境界設計。
test "champions_import_smoke: round_trip_vision_json_to_md" {
  let src =
    #|{
    #|  "version": "champions",
    #|  "regulation": "M-A",
    #|  "pokemon": {
    #|    "name": "マンムー",
    #|    "type1": "こおり",
    #|    "type2": "じめん",
    #|    "base_stats": {"hp":110,"atk":130,"def":80,"spa":70,"spd":60,"spe":80}
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
  let json = @json.parse(src)

  // Step 1: validate (Champions SP 合計 66, 各 ≤ 32 を通過)
  inspect(validate_pokemon_json(json), content="Ok(())")

  // Step 2: build_pokemon_document → markdown.serialize
  let doc = build_pokemon_document(json, "マンムー")
  let md = @markdown.serialize(doc)

  // Step 3: 決定論性 (同一入力 → 同一出力)
  let doc2 = build_pokemon_document(json, "マンムー")
  let md2 = @markdown.serialize(doc2)
  assert_eq(md, md2)

  // Step 4: 必須情報が md に含まれる
  assert_true(md.contains("マンムー"))
  assert_true(md.contains("ようき"))
  assert_true(md.contains("あついしぼう"))
  assert_true(md.contains("こだわりスカーフ"))
  assert_true(md.contains("じしん"))
  assert_true(md.contains("つららおとし"))
  assert_true(md.contains("つららばり"))
  assert_true(md.contains("ばかぢから"))
  // 実数値
  assert_true(md.contains("205"))
  assert_true(md.contains("182"))
  assert_true(md.contains("145"))
  // SP (Champions は evs フィールドを SP として出力)
  assert_true(md.contains("32"))
}
