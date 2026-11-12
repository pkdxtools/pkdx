///|
/// m020_move_meta_fake_out の単体テスト。
///
/// 1. 既存の priority 3 行は flinch_chance だけ 100 になり、priority は残る。
/// 2. はやてがえし は行を作らない。
/// 3. 2 回目の実行で値も行数も変わらない (冪等)。

///|
fn m020_setup_temp_db(suffix : String) -> Result[@db.Db, String] {
  let path = "_build/test_m020_fake_out_" + suffix + ".db"
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
fn m020_flinch_of(db : @db.Db, name : String) -> Int? {
  let rows = match
    @db.query_binds(
      db,
      "SELECT flinch_chance FROM move_meta WHERE name_ja = ?",
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
fn m020_priority_of(db : @db.Db, name : String) -> Int? {
  let rows = match
    @db.query_binds(
      db,
      "SELECT priority FROM move_meta WHERE name_ja = ?",
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
fn m020_count(db : @db.Db) -> Int {
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
test "m020 fake out: existing priority-3 row gets flinch 100 and keeps priority" {
  let db = match m020_setup_temp_db("seed") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match
    @db.exec_binds(
      db,
      "INSERT INTO move_meta (name_ja, priority, stat_effects_json) VALUES (?, 3, '[]')",
      [@db.BindText("ねこだまし")],
    ) {
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "seed insert should succeed")
      return
    }
    Ok(_) => ()
  }
  match @migrate.run_020(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_020 should succeed")
      return
    }
  }
  assert_true(m020_flinch_of(db, "ねこだまし") == Some(100))
  assert_true(m020_priority_of(db, "ねこだまし") == Some(3))
  assert_true(m020_flinch_of(db, "はやてがえし") == None)
  assert_true(m020_flinch_of(db, "であいがしら") == None)
  let n = m020_count(db)
  match @migrate.run_020(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "second run_020 should succeed")
      return
    }
  }
  assert_true(m020_flinch_of(db, "ねこだまし") == Some(100))
  assert_true(m020_priority_of(db, "ねこだまし") == Some(3))
  assert_true(m020_count(db) == n)
  @db.close(db)
}
