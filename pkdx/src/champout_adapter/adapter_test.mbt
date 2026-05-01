///|
/// アダプター層のユニットテスト。LabelBundle を最小構成で組み立てた上で
/// 各 mapper が期待通りに champout 数値 ID を表示名へ翻訳することを検証する。

///|
fn fake_bundle() -> LabelBundle {
  let type_name : Map[String, String] = Map::new()
  // typename.json は Index 9 が欠番なので、TYPENAME_011 = みず, _012 = くさ
  type_name["TYPENAME_000"] = "ノーマル"
  type_name["TYPENAME_003"] = "どく"
  type_name["TYPENAME_010"] = "ほのお"
  type_name["TYPENAME_011"] = "みず"
  type_name["TYPENAME_012"] = "くさ"
  type_name["TYPENAME_018"] = "フェアリー"
  let tokusei : Map[String, String] = Map::new()
  tokusei["TOKUSEI_065"] = "しんりょく"
  tokusei["TOKUSEI_034"] = "ようりょくそ"
  let monsname : Map[String, String] = Map::new()
  monsname["MONSNAME_003"] = "フシギバナ"
  let wazaname : Map[String, String] = Map::new()
  wazaname["WAZANAME_001"] = "はたく"
  wazaname["WAZANAME_014"] = "つるぎのまい"
  wazaname["WAZANAME_034"] = "のしかかり"
  let itemname : Map[String, String] = Map::new()
  itemname["ITEMNAME_149"] = "オボンのみ"
  let zkn_form : Map[String, String] = Map::new()
  zkn_form["ZKN_FORM_003_000"] = ""
  zkn_form["ZKN_FORM_003_001"] = "メガフシギバナ"
  { type_name, tokusei, monsname, wazaname, itemname, zkn_form }
}

///|
test "resolve_type skips Index 9 in typename.json" {
  let b = fake_bundle()
  // type 値 11 はくさ (連続インデックス: 9 を飛ばして TYPENAME_012)
  inspect(resolve_type(b, "11"), content="くさ")
  // type 値 3 はどく
  inspect(resolve_type(b, "3"), content="どく")
  // 範囲外は空文字
  inspect(resolve_type(b, "99"), content="")
  // 不正な数値文字列は 0 扱い → ノーマル
  inspect(resolve_type(b, ""), content="ノーマル")
}

///|
test "resolve_ability returns empty for id 0" {
  let b = fake_bundle()
  inspect(resolve_ability(b, "65"), content="しんりょく")
  inspect(resolve_ability(b, "0"), content="")
  inspect(resolve_ability(b, ""), content="")
}

///|
test "resolve_move_category maps 0/1/2 to physical/special/status" {
  inspect(resolve_move_category("0"), content="物理")
  inspect(resolve_move_category("1"), content="特殊")
  inspect(resolve_move_category("2"), content="変化")
  inspect(resolve_move_category("9"), content="")
}

///|
test "map_pokemon_entries maps Venusaur grass/poison correctly" {
  let raw =
    #|[
    #|  {
    #|    "id": "0003000", "no": "3", "fo": "0",
    #|    "ms_name": "monsname_syn", "ms_name_lbl": "MONSNAME_003",
    #|    "ms_form": "zkn_form_syn", "ms_form_lbl": "ZKN_FORM_003_000",
    #|    "is_valid": "1",
    #|    "type1": "11", "type2": "3",
    #|    "hp": "80", "atk": "82", "def": "83",
    #|    "spatk": "100", "spdef": "100", "agi": "80",
    #|    "toku0": "65", "toku1": "65", "toku2": "34"
    #|  }
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  match map_pokemon_entries(fake_bundle(), json) {
    Err(e) => inspect(e, content="map ok")
    Ok(entries) => {
      inspect(entries.length(), content="1")
      let e = entries[0]
      inspect(e.id, content="0003000")
      inspect(e.no, content="0003")
      inspect(e.globalNo, content="0003")
      inspect(e.type1, content="くさ")
      inspect(e.type2, content="どく")
      inspect(e.ability1, content="しんりょく")
      // ability2 は ability1 と同じ id なので空文字に正規化される
      inspect(e.ability2, content="")
      inspect(e.dream_ability, content="ようりょくそ")
      inspect(e.hp, content="80")
      inspect(e.attack, content="82")
      inspect(e.special_attack, content="100")
      inspect(e.speed, content="80")
      inspect(e.form, content="")
      inspect(e.name_jpn, content="フシギバナ")
    }
  }
}

///|
test "map_pokemon_entries skips is_valid != 1" {
  let raw =
    #|[
    #|  {
    #|    "id": "9999000", "no": "9999", "fo": "0",
    #|    "ms_form_lbl": "ZKN_FORM_003_000",
    #|    "is_valid": "0",
    #|    "type1": "0", "type2": "0",
    #|    "hp": "1", "atk": "1", "def": "1",
    #|    "spatk": "1", "spdef": "1", "agi": "1",
    #|    "toku0": "0", "toku1": "0", "toku2": "0"
    #|  }
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  match map_pokemon_entries(fake_bundle(), json) {
    Err(e) => inspect(e, content="map ok")
    Ok(entries) => inspect(entries.length(), content="0")
  }
}

///|
test "map_move_entries normalizes power/accuracy zero to dash and copies direct/target" {
  let raw =
    #|[
    #|  {"id": "1", "type": "0", "category": "0", "target": "0",
    #|   "power": "40", "accuracy": "100", "pp": "20", "direct": "1",
    #|   "available": "1", "ms_lbl": "WAZANAME_001"},
    #|  {"id": "14", "type": "0", "category": "2", "target": "7",
    #|   "power": "0", "accuracy": "0", "pp": "20", "direct": "0",
    #|   "available": "1", "ms_lbl": "WAZANAME_014"}
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  match map_move_entries(fake_bundle(), json) {
    Err(e) => inspect(e, content="map ok")
    Ok(entries) => {
      inspect(entries.length(), content="2")
      inspect(entries[0].waza, content="はたく")
      inspect(entries[0].power, content="40")
      inspect(entries[0].category, content="物理")
      inspect(entries[0].direct, content="1")
      inspect(entries[0].target, content="0")
      inspect(entries[1].waza, content="つるぎのまい")
      inspect(entries[1].power, content="-")
      inspect(entries[1].accuracy, content="-")
      inspect(entries[1].category, content="変化")
      inspect(entries[1].direct, content="0")
      inspect(entries[1].target, content="7")
    }
  }
}

///|
test "map_learnset_entries filters by valid_ids" {
  let raw =
    #|[
    #|  {"id": "0003000", "waza": "1,14"},
    #|  {"id": "9999000", "waza": "1,14"}
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  let valid : Map[String, Bool] = Map::new()
  valid["0003000"] = true
  match map_learnset_entries(fake_bundle(), json, valid) {
    Err(e) => inspect(e, content="map ok")
    Ok(entries) => {
      inspect(entries.length(), content="2")
      inspect(entries[0].id, content="0003000")
      inspect(entries[0].waza, content="はたく")
      inspect(entries[0].conditions, content="基本")
      inspect(entries[1].waza, content="つるぎのまい")
    }
  }
}

///|
test "map_item_entries resolves id to name_ja" {
  let raw =
    #|[
    #|  {"id": "149", "category_a": "6", "category_b": "4", "category_c": "0",
    #|   "limit": "0", "ms_lbl": "ITEMNAME_149", "unlock": "0"}
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  match map_item_entries(fake_bundle(), json) {
    Err(e) => inspect(e, content="map ok")
    Ok(entries) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].name_ja, content="オボンのみ")
      inspect(entries[0].category, content="6")
    }
  }
}
