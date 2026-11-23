///|
/// m022 は本文の確率を confusion_chance に書き、2 回目も同じ行数に収束する。

///|
fn m022_setup(suffix : String) -> Result[@db.Db, String] {
  let path = "_build/test_m022_confusion_" + suffix + ".db"
  let _ = @db.unlink_file(path)
  let db = match @db.open_rwc(path) {
    Ok(d) => d
    Err(e) => return Err("open_rwc: " + e)
  }
  let create_sql = "CREATE TABLE IF NOT EXISTS move_meta (name_ja TEXT PRIMARY KEY, priority INTEGER NOT NULL DEFAULT 0, stat_effects_json TEXT NOT NULL DEFAULT '[]', ailment_ja TEXT NOT NULL DEFAULT '', ailment_chance INTEGER NOT NULL DEFAULT 100, flinch_chance INTEGER NOT NULL DEFAULT 0)"
  match @db.exec(db, create_sql) {
    Err(e) => Err("CREATE TABLE: " + e)
    Ok(_) => Ok(db)
  }
}

///|
fn m022_chance(db : @db.Db, name : String) -> Int? {
  let rows = match
    @db.query_binds(
      db,
      "SELECT confusion_chance FROM move_meta WHERE name_ja = ?",
      [@db.BindText(name)],
    ) {
    Ok(r) => r
    Err(_) => return None
  }
  if rows.length() == 0 {
    return None
  }
  match rows[0].get(0) {
    Some(Some(s)) => Some(@string.parse_int(s) catch { _ => -1 })
    _ => None
  }
}

///|
test "m022 confusion: Champions text chances, conditional moves stay absent" {
  let db = match m022_setup("representative") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match @migrate.run_022(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_022 should succeed")
      return
    }
  }
  assert_true(m022_chance(db, "あやしいひかり") == Some(100))
  assert_true(m022_chance(db, "てんしのキッス") == Some(100))
  assert_true(m022_chance(db, "いばる") == Some(100))
  assert_true(m022_chance(db, "ばくれつパンチ") == Some(100))
  assert_true(m022_chance(db, "おだてる") == Some(100))
  assert_true(m022_chance(db, "フラフラダンス") == Some(100))
  assert_true(m022_chance(db, "みずのはどう") == Some(20))
  assert_true(m022_chance(db, "ぼうふう") == Some(30))
  assert_true(m022_chance(db, "かかとおとし") == Some(30))
  assert_true(m022_chance(db, "みわくのボイス") == None)
  @db.close(db)
}

///|
test "m022 confusion: second run keeps the same chance" {
  let db = match m022_setup("idempotent") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  let _ = @migrate.run_022(db, ".")
  let _ = @migrate.run_022(db, ".")
  assert_true(m022_chance(db, "みずのはどう") == Some(20))
  assert_true(m022_chance(db, "あやしいひかり") == Some(100))
  @db.close(db)
}
