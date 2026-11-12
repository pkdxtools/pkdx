///|
/// m021_move_meta_upper_hand の単体テスト。
///
/// 1. 行が無ければ priority 3・flinch_chance 100 で INSERT する。
/// 2. 既存行は priority と flinch_chance だけを上書きし、ailment / stat_effects は残る。
/// 3. であいがしら は行を作らない。
/// 4. 2 回目の実行で値も行数も変わらない (冪等)。
/// m019 / m020 単体は今も はやてがえし を入れない (そちらのテストが押さえる)。

///|
fn m021_setup_temp_db(suffix : String) -> Result[@db.Db, String] {
  let path = "_build/test_m021_upper_hand_" + suffix + ".db"
  let _ = @db.unlink_file(path)
  let db = match @db.open_rwc(path) {
    Ok(d) => d
    Err(e) => return Err("open_rwc: " + e)
  }
  let create_sql = "CREATE TABLE IF NOT EXISTS move_meta (name_ja TEXT PRIMARY KEY, priority INTEGER NOT NULL DEFAULT 0, stat_effects_json TEXT NOT NULL DEFAULT '[]', ailment_ja TEXT NOT NULL DEFAULT '', ailment_chance INTEGER NOT NULL DEFAULT 100, recoil_num INTEGER NOT NULL DEFAULT 0, recoil_den INTEGER NOT NULL DEFAULT 1, self_ko INTEGER NOT NULL DEFAULT 0, recharge INTEGER NOT NULL DEFAULT 0)"
  match @db.exec(db, create_sql) {
    Err(e) => Err("CREATE TABLE: " + e)
    Ok(_) => Ok(db)
  }
}

///|
fn m021_cell(db : @db.Db, name : String, column : String) -> String? {
  let rows = match
    @db.query_binds(
      db,
      "SELECT " + column + " FROM move_meta WHERE name_ja = ?",
      [@db.BindText(name)],
    ) {
    Ok(r) => r
    Err(_) => return None
  }
  if rows.length() == 0 {
    return None
  }
  match rows[0].get(0) {
    Some(Some(s)) => Some(s)
    _ => None
  }
}

///|
fn m021_count(db : @db.Db) -> Int {
  let rows = match @db.query(db, "SELECT COUNT(*) FROM move_meta", []) {
    Ok(r) => r
    Err(_) => return -1
  }
  if rows.length() == 0 {
    return -1
  }
  @string.parse_int(rows[0][0]) catch { _ => -1 }
}

///|
test "m021 upper hand: missing row is inserted at priority 3 and flinch 100" {
  let db = match m021_setup_temp_db("insert") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  let first = match @migrate.run_021(db, ".") {
    Ok(s) => s
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_021 should succeed")
      return
    }
  }
  assert_true(first.contains("1 inserted"))
  assert_true(m021_cell(db, "はやてがえし", "priority") == Some("3"))
  assert_true(m021_cell(db, "はやてがえし", "flinch_chance") == Some("100"))
  assert_true(m021_cell(db, "であいがしら", "flinch_chance") == None)
  assert_true(m021_cell(db, "ねこだまし", "flinch_chance") == None)
  let n = m021_count(db)
  let second = match @migrate.run_021(db, ".") {
    Ok(s) => s
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "second run_021 should succeed")
      return
    }
  }
  assert_true(second.contains("0 inserted"))
  assert_true(m021_count(db) == n)
  assert_true(m021_cell(db, "はやてがえし", "priority") == Some("3"))
  assert_true(m021_cell(db, "はやてがえし", "flinch_chance") == Some("100"))
  @db.close(db)
}

///|
test "m021 upper hand: existing row keeps ailment and stat effects" {
  let db = match m021_setup_temp_db("existing") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match
    @db.exec(
      db,
      "INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance) VALUES ('はやてがえし', 1, '[{\"stat\":0}]', 'まひ', 10)",
    ) {
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "seed insert should succeed")
      return
    }
    Ok(_) => ()
  }
  match @migrate.run_021(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_021 should succeed")
      return
    }
  }
  assert_true(m021_cell(db, "はやてがえし", "priority") == Some("3"))
  assert_true(m021_cell(db, "はやてがえし", "flinch_chance") == Some("100"))
  assert_true(m021_cell(db, "はやてがえし", "ailment_ja") == Some("まひ"))
  assert_true(m021_cell(db, "はやてがえし", "ailment_chance") == Some("10"))
  assert_true(m021_cell(db, "はやてがえし", "stat_effects_json") == Some("[{\"stat\":0}]"))
  assert_true(m021_count(db) == 1)
  @db.close(db)
}
