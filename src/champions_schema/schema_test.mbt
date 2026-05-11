///|
/// `champions_schema` のラウンドトリップ + DDL 適用テスト。アダプター層
/// (Phase 2 以降) と migration 層 (Phase 5 以降) が依存する不変条件をここで
/// 担保する。

///|
test "champions_ddl returns the expected number of statements" {
  let stmts = champions_ddl()
  // 7 tables + 3 indexes = 10 statements
  inspect(stmts.length(), content="10")
}

///|
test "apply_ddl is idempotent on in-memory DB" {
  let db = match @db.open_rwc(":memory:") {
    Err(e) => {
      inspect(e, content="open succeeds")
      return
    }
    Ok(d) => d
  }
  match apply_ddl(db) {
    Err(e) => {
      inspect(e, content="first apply_ddl Ok")
      return
    }
    Ok(_) => ()
  }
  match apply_ddl(db) {
    Err(e) => {
      inspect(e, content="second apply_ddl Ok")
      return
    }
    Ok(_) => ()
  }
  @db.close(db)
}

///|
test "parse_pokemon_entries accepts a minimal valid record" {
  let raw =
    #|[
    #|  {
    #|    "id": "0959000",
    #|    "no": "0959",
    #|    "globalNo": "0959",
    #|    "form": "",
    #|    "name_jpn": "チオンジェン",
    #|    "pokedex": "Champions",
    #|    "type1": "フェアリー",
    #|    "type2": "はがね",
    #|    "hp": 85,
    #|    "attack": 75,
    #|    "defense": 77,
    #|    "special_attack": 70,
    #|    "special_defense": 105,
    #|    "speed": 94,
    #|    "ability1": "かたやぶり",
    #|    "ability2": "マイペース",
    #|    "dream_ability": "わるいてぐせ"
    #|  }
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  match parse_pokemon_entries(json) {
    Err(e) => inspect(e, content="parse ok")
    Ok(entries) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].id, content="0959000")
      inspect(entries[0].hp, content="85")
      inspect(entries[0].type1, content="フェアリー")
      inspect(entries[0].form, content="")
    }
  }
}

///|
test "parse_pokemon_entries rejects missing required string field" {
  let raw =
    #|[
    #|  {
    #|    "id": "x",
    #|    "no": "1",
    #|    "globalNo": "1",
    #|    "name_jpn": "Foo",
    #|    "pokedex": "Champions",
    #|    "hp": 1, "attack": 1, "defense": 1,
    #|    "special_attack": 1, "special_defense": 1, "speed": 1
    #|  }
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  match parse_pokemon_entries(json) {
    Ok(_) => inspect("expected err", content="missing type1 should fail")
    Err(e) => inspect(e.contains("type1"), content="true")
  }
}

///|
test "parse_move_entries accepts power as a non-numeric token" {
  let raw =
    #|[
    #|  {"waza": "がむしゃら", "type": "ノーマル", "category": "物理",
    #|   "pp": "8", "power": "-", "accuracy": "100"}
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  match parse_move_entries(json) {
    Err(e) => inspect(e, content="parse ok")
    Ok(entries) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].power, content="-")
    }
  }
}

///|
test "parse_learnset_entries minimal record" {
  let raw =
    #|[
    #|  {"id": "0959000", "conditions": "基本", "waza": "ねこだまし"}
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  match parse_learnset_entries(json) {
    Err(e) => inspect(e, content="parse ok")
    Ok(entries) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].waza, content="ねこだまし")
    }
  }
}

///|
test "parse_item_entries minimal record" {
  let raw =
    #|[
    #|  {"name_ja": "こだわりハチマキ", "name_en": "Choice Band",
    #|   "category": "choice", "flavor": ""}
    #|]
  let json = try @json.parse(raw) catch {
    e => {
      inspect("json parse failed: " + e.to_string(), content="parse ok")
      return
    }
  }
  match parse_item_entries(json) {
    Err(e) => inspect(e, content="parse ok")
    Ok(entries) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].name_ja, content="こだわりハチマキ")
    }
  }
}
