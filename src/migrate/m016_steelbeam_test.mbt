///|
/// Stage 16 — m016_move_meta_steelbeam の単体テスト。
///
/// 検証する不変量:
/// 1. m005 が投入した古い値 (てっていこうせん の `[[1,-2,0],[3,-2,0]]`) が
///    run_016 で `[]` に戻る (= 使用者の自己能力低下が無くなる)。
/// 2. 2 回目以降の実行で値は変わらない (冪等)。
/// 3. move_meta に行が無い技へは INSERT しない (能力変化の無い技として扱う)。
/// 4. 他の技の行 (インファイト の自己 -1 / -1) には触れない。

///|
/// 一時 db を作成し、m005 と同じ stat_effects_json 列を持つ move_meta を用意する。
fn setup_m016_temp_db(suffix : String) -> Result[@db.Db, String] {
  let path = "_build/test_m016_steelbeam_" + suffix + ".db"
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
/// m005 相当の古い行 (てっていこうせん の自己 Def / SpD -2) を投入する。
fn seed_m016_bogus_steelbeam(db : @db.Db) -> Result[Unit, String] {
  @db.exec_binds(
    db,
    "INSERT INTO move_meta (name_ja, priority, stat_effects_json) VALUES (?, 0, ?)",
    [
      @db.BindText("てっていこうせん"),
      @db.BindText("[[1,-2,0],[3,-2,0]]"),
    ],
  )
}

///|
/// move_meta の指定技の stat_effects_json を返す。行が無ければ None。
fn m016_stat_effects_of(db : @db.Db, name : String) -> String? {
  let rows = match
    @db.query_binds(
      db,
      "SELECT stat_effects_json FROM move_meta WHERE name_ja = ?",
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
/// move_meta の総行数。
fn m016_row_count(db : @db.Db) -> Int {
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
/// 1: 古い自己能力低下 (m005 の値) が `[]` に戻る。
test "m016 steelbeam: stale self stat drop is removed" {
  let db = match setup_m016_temp_db("drop") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match seed_m016_bogus_steelbeam(db) {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "seed should succeed")
      return
    }
  }
  @debug.assert_eq(
    m016_stat_effects_of(db, "てっていこうせん"),
    Some("[[1,-2,0],[3,-2,0]]"),
  )
  match @migrate.run_016(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_016 should succeed")
      return
    }
  }
  @debug.assert_eq(m016_stat_effects_of(db, "てっていこうせん"), Some("[]"))
  @db.close(db)
}

///|
/// 2: 2 回目の実行でも `[]` のまま、行数も不変。
test "m016 steelbeam: second run is a no-op on the steady state" {
  let db = match setup_m016_temp_db("second") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match seed_m016_bogus_steelbeam(db) {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "seed should succeed")
      return
    }
  }
  match @migrate.run_016(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "first run should succeed")
      return
    }
  }
  let count_after_first = m016_row_count(db)
  match @migrate.run_016(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "second run should succeed")
      return
    }
  }
  @debug.assert_eq(m016_stat_effects_of(db, "てっていこうせん"), Some("[]"))
  @debug.assert_eq(m016_row_count(db), count_after_first)
  @db.close(db)
}

///|
/// 3: 行が無い場合は INSERT せず、エラーにもしない。
test "m016 steelbeam: missing row is not inserted" {
  let db = match setup_m016_temp_db("missing") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match @migrate.run_016(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_016 should succeed on an empty move_meta")
      return
    }
  }
  @debug.assert_eq(m016_row_count(db), 0)
  @debug.assert_eq(m016_stat_effects_of(db, "てっていこうせん"), None)
  @db.close(db)
}

///|
/// 4: 他の技の行 (インファイト の自己 -1 / -1) は変更しない。
test "m016 steelbeam: other moves keep their stat effects" {
  let db = match setup_m016_temp_db("others") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match
    @db.exec_binds(
      db,
      "INSERT INTO move_meta (name_ja, priority, stat_effects_json) VALUES (?, 0, ?)",
      [
        @db.BindText("インファイト"),
        @db.BindText("[[1,-1,0],[3,-1,0]]"),
      ],
    ) {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "seed should succeed")
      return
    }
  }
  match @migrate.run_016(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_016 should succeed")
      return
    }
  }
  @debug.assert_eq(
    m016_stat_effects_of(db, "インファイト"),
    Some("[[1,-1,0],[3,-1,0]]"),
  )
  @db.close(db)
}
