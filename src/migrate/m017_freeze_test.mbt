///|
/// m017_move_meta_freeze の単体テスト。
///
/// 検証する不変量:
/// 1. data.json の 5 技 (れいとうビーム / ふぶき / れいとうパンチ / こおりのキバ / フリーズドライ)
///    が ailment_ja = こおり, ailment_chance = 10 の行になる (行が無い技は INSERT)。
/// 2. トライアタック (3 種の状態異常の 1/3 ずつ) は行を作らない。
/// 3. 既存行は ailment 列だけを data.json の値で上書きする (他の列は触らない)。
/// 4. 2 回目の実行で値も行数も変わらない (冪等)。

///|
fn setup_m017_temp_db(suffix : String) -> Result[@db.Db, String] {
  let path = "_build/test_m017_freeze_" + suffix + ".db"
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
/// move_meta の (ailment_ja, ailment_chance)。行が無ければ None。
fn m017_ailment_of(db : @db.Db, name : String) -> (String, String)? {
  let rows = match
    @db.query_binds(
      db,
      "SELECT ailment_ja, ailment_chance FROM move_meta WHERE name_ja = ?",
      [@db.BindText(name)],
    ) {
    Ok(r) => r
    Err(_) => return None
  }
  if rows.length() == 0 {
    return None
  }
  match (rows[0].get(0), rows[0].get(1)) {
    (Some(Some(a)), Some(Some(c))) => Some((a, c))
    _ => None
  }
}

///|
fn m017_row_count(db : @db.Db) -> Int {
  let rows = match @db.query_binds(db, "SELECT COUNT(*) FROM move_meta", []) {
    Ok(r) => r
    Err(_) => return -1
  }
  match rows[0].get(0) {
    Some(Some(s)) => @string.parse_int(s) catch { _ => -1 }
    _ => -1
  }
}

///|
/// 1: 5 技が こおり / 10 の行になり、トライアタックには行が無い。
test "m017 freeze: five freeze moves are inserted with こおり 10, Tri Attack has no row" {
  let db = match setup_m017_temp_db("insert") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match @migrate.run_017(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_017 should succeed")
      return
    }
  }
  for name in [
    "れいとうビーム", "ふぶき", "れいとうパンチ", "こおりのキバ", "フリーズドライ",
  ] {
    @debug.assert_eq(m017_ailment_of(db, name), Some(("こおり", "10")))
  }
  @debug.assert_eq(m017_ailment_of(db, "トライアタック"), None)
  @db.close(db)
}

///|
/// 2: 既存行 (ailment 空) は ailment 列だけが上書きされ、他の列 (priority) は残る。
test "m017 freeze: existing row gets ailment columns only" {
  let db = match setup_m017_temp_db("update") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match
    @db.exec_binds(
      db,
      "INSERT INTO move_meta (name_ja, priority, stat_effects_json) VALUES (?, 2, '[]')",
      [@db.BindText("ふぶき")],
    ) {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "seed should succeed")
      return
    }
  }
  match @migrate.run_017(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_017 should succeed")
      return
    }
  }
  @debug.assert_eq(m017_ailment_of(db, "ふぶき"), Some(("こおり", "10")))
  let rows = match
    @db.query_binds(db, "SELECT priority FROM move_meta WHERE name_ja = ?", [
      @db.BindText("ふぶき"),
    ]) {
    Ok(r) => r
    Err(_) => []
  }
  @debug.assert_eq(rows[0].get(0), Some(Some("2")))
  @db.close(db)
}

///|
/// 3: 2 回目の実行で行数も値も変わらない。
test "m017 freeze: second run is a no-op" {
  let db = match setup_m017_temp_db("second") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match @migrate.run_017(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "first run should succeed")
      return
    }
  }
  let count_after_first = m017_row_count(db)
  match @migrate.run_017(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "second run should succeed")
      return
    }
  }
  @debug.assert_eq(m017_row_count(db), count_after_first)
  @debug.assert_eq(m017_ailment_of(db, "こおりのキバ"), Some(("こおり", "10")))
  @db.close(db)
}
