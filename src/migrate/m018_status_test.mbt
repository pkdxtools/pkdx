///|
/// m018_move_meta_status の単体テスト。
///
/// 検証する不変量:
/// 1. data.json の 33 技が本文どおりの (ailment_ja, ailment_chance) の行になる (無い行は INSERT)。
/// 2. 含めない技 (トライアタック / フェイタルクロー / しっとのほのお) は行を作らない。
/// 3. 既存行は ailment 列だけを data.json の値で上書きする (recoil / priority は残る)。
/// 4. data.json に無い行 (freeze の こおり 行、pure status の おにび) は触らない。
/// 5. 2 回目の実行で値も行数も変わらない (冪等)。

///|
fn setup_m018_temp_db(suffix : String) -> Result[@db.Db, String] {
  let path = "_build/test_m018_status_" + suffix + ".db"
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
fn m018_ailment_of(db : @db.Db, name : String) -> (String, String)? {
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
fn m018_row_count(db : @db.Db) -> Int {
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
/// 1: 代表の技が本文どおりの行になり、含めない 3 技には行が無い。
test "m018 status: representative moves get the Champions text chance; excluded moves have no row" {
  let db = match setup_m018_temp_db("insert") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match @migrate.run_018(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_018 should succeed")
      return
    }
  }
  @debug.assert_eq(m018_row_count(db), 33)
  @debug.assert_eq(m018_ailment_of(db, "ほのおのパンチ"), Some(("やけど", "10")))
  @debug.assert_eq(m018_ailment_of(db, "れんごく"), Some(("やけど", "100")))
  @debug.assert_eq(m018_ailment_of(db, "ねっとう"), Some(("やけど", "30")))
  @debug.assert_eq(m018_ailment_of(db, "かみなりパンチ"), Some(("まひ", "10")))
  @debug.assert_eq(m018_ailment_of(db, "でんじほう"), Some(("まひ", "100")))
  @debug.assert_eq(m018_ailment_of(db, "ヘドロばくだん"), Some(("どく", "30")))
  @debug.assert_eq(m018_ailment_of(db, "キラースピン"), Some(("どく", "100")))
  @debug.assert_eq(m018_ailment_of(db, "どくどくのキバ"), Some(("もうどく", "50")))
  @debug.assert_eq(m018_ailment_of(db, "トライアタック"), None)
  @debug.assert_eq(m018_ailment_of(db, "フェイタルクロー"), None)
  @debug.assert_eq(m018_ailment_of(db, "しっとのほのお"), None)
  @db.close(db)
}

///|
/// 2: 既存行 (フレアドライブ: recoil 1/3) は ailment 列だけが上書きされ、他の列は残る。
test "m018 status: existing row gets ailment columns only (recoil and priority kept)" {
  let db = match setup_m018_temp_db("update") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match
    @db.exec_binds(
      db,
      "INSERT INTO move_meta (name_ja, priority, stat_effects_json, recoil_num, recoil_den) VALUES (?, 2, '[]', 1, 3)",
      [@db.BindText("フレアドライブ")],
    ) {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "seed should succeed")
      return
    }
  }
  match @migrate.run_018(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_018 should succeed")
      return
    }
  }
  @debug.assert_eq(m018_ailment_of(db, "フレアドライブ"), Some(("やけど", "10")))
  let rows = match
    @db.query_binds(
      db,
      "SELECT priority, recoil_num, recoil_den FROM move_meta WHERE name_ja = ?",
      [@db.BindText("フレアドライブ")],
    ) {
    Ok(r) => r
    Err(_) => []
  }
  @debug.assert_eq(rows[0].get(0), Some(Some("2")))
  @debug.assert_eq(rows[0].get(1), Some(Some("1")))
  @debug.assert_eq(rows[0].get(2), Some(Some("3")))
  @db.close(db)
}

///|
/// 3: data.json に無い行 (freeze の こおり 行、pure status の おにび 85) は触らない。
test "m018 status: rows outside data.json are untouched" {
  let db = match setup_m018_temp_db("untouched") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match
    @db.exec(
      db,
      "INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance) VALUES ('れいとうビーム', 0, '[]', 'こおり', 10), ('おにび', 0, '[]', 'やけど', 85)",
    ) {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "seed should succeed")
      return
    }
  }
  match @migrate.run_018(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_018 should succeed")
      return
    }
  }
  @debug.assert_eq(m018_ailment_of(db, "れいとうビーム"), Some(("こおり", "10")))
  @debug.assert_eq(m018_ailment_of(db, "おにび"), Some(("やけど", "85")))
  @db.close(db)
}

///|
/// 4: 2 回目の実行で行数も値も変わらない。
test "m018 status: second run is a no-op" {
  let db = match setup_m018_temp_db("second") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match @migrate.run_018(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "first run should succeed")
      return
    }
  }
  let count_after_first = m018_row_count(db)
  match @migrate.run_018(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "second run should succeed")
      return
    }
  }
  @debug.assert_eq(m018_row_count(db), count_after_first)
  @debug.assert_eq(m018_ailment_of(db, "どくどくのキバ"), Some(("もうどく", "50")))
  @db.close(db)
}
