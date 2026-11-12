///|
/// ひるみ (flinch_chance, m019) の DB 側ヘルパーの whitebox テスト。
/// - `flinch_chance_map`: flinch_chance > 0 の行だけを表にする。列が無い DB では空。
/// - `apply_flinch_chance`: 表に無い技は触らず、表にある技は名前一致で載せる。
/// - `flinch_chance_of`: 表に無い技は 0。

///|
fn flinch_wb_move(name : String, flinch_chance : Int) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
    power: 60,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
    flinch_chance,
  }
}

///|
fn flinch_wb_db(path : String, with_column : Bool) -> Result[Db, String] {
  let _ = unlink_file(path)
  let db = match open_rwc(path) {
    Ok(d) => d
    Err(e) => return Err("open_rwc: " + e)
  }
  let base = "CREATE TABLE move_meta (name_ja TEXT PRIMARY KEY, priority INTEGER NOT NULL DEFAULT 0, stat_effects_json TEXT NOT NULL DEFAULT '[]', ailment_ja TEXT NOT NULL DEFAULT '', ailment_chance INTEGER NOT NULL DEFAULT 100)"
  let create = if with_column {
    "CREATE TABLE move_meta (name_ja TEXT PRIMARY KEY, priority INTEGER NOT NULL DEFAULT 0, stat_effects_json TEXT NOT NULL DEFAULT '[]', ailment_ja TEXT NOT NULL DEFAULT '', ailment_chance INTEGER NOT NULL DEFAULT 100, flinch_chance INTEGER NOT NULL DEFAULT 0)"
  } else {
    base
  }
  match exec(db, create) {
    Err(e) => {
      close(db)
      return Err("CREATE TABLE: " + e)
    }
    Ok(_) => ()
  }
  if with_column {
    match
      exec(
        db,
        "INSERT INTO move_meta (name_ja, flinch_chance) VALUES ('かみつく', 30), ('たいあたり', 0), ('ゴッドバード', 30)",
      ) {
      Err(e) => {
        close(db)
        return Err("INSERT: " + e)
      }
      Ok(_) => ()
    }
  }
  Ok(db)
}

///|
test "flinch_chance_map: only flinch > 0 rows; the table is empty without the column" {
  let path = "_build/test_flinch_wb_with.db"
  let db = match flinch_wb_db(path, true) {
    Ok(d) => d
    Err(e) => fail(e)
  }
  let map = flinch_chance_map(db, "")
  assert_true(map.get("かみつく") == Some(30))
  assert_true(map.get("ゴッドバード") == Some(30))
  assert_true(map.get("たいあたり") == None)
  assert_true(map.length() == 2)
  close(db)
  let path2 = "_build/test_flinch_wb_without.db"
  let db2 = match flinch_wb_db(path2, false) {
    Ok(d) => d
    Err(e) => fail(e)
  }
  assert_true(flinch_chance_map(db2, "").length() == 0)
  close(db2)
}

///|
test "apply_flinch_chance: attaches by name; unknown names keep their value" {
  let map : Map[String, Int] = Map([])
  map["かみつく"] = 30
  let moves = [flinch_wb_move("かみつく", 0), flinch_wb_move("たいあたり", 0)]
  let applied = apply_flinch_chance(moves, map)
  assert_true(applied[0].flinch_chance == 30)
  assert_true(applied[1].flinch_chance == 0)
  assert_true(flinch_chance_of(map, "かみつく") == 30)
  assert_true(flinch_chance_of(map, "ねこだまし") == 0)
}
