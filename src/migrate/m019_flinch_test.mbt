///|
/// m019_move_meta_flinch の単体テスト。
///
/// 検証する不変量:
/// 1. data.json の技が本文の確率 (`flinch_chance`) の行になる (無い行は INSERT、ailment は既定値 = なし)。
/// 2. ねこだまし / はやてがえし は行を作らない (ねこだまし は m020、はやてがえし は m021)。
/// 3. 既存行は flinch 列だけを上書きし、priority / ailment 列は残る (m017 / m018 の牙の行を壊さない)。
/// 4. 表記違い (champions 全角 3 / pokedex ASCII 3) は両方の行を持つ。
/// 5. 2 回目の実行で値も行数も変わらない (冪等)。

///|
fn m019_setup_temp_db(suffix : String) -> Result[@db.Db, String] {
  let path = "_build/test_m019_flinch_" + suffix + ".db"
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
/// move_meta の flinch_chance。行が無ければ None。
fn m019_flinch_of(db : @db.Db, name : String) -> Int? {
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
/// move_meta の (priority, ailment_ja)。行が無ければ None。
fn m019_priority_ailment_of(db : @db.Db, name : String) -> (String, String, String)? {
  let rows = match
    @db.query_binds(
      db,
      "SELECT priority, ailment_ja, flinch_chance FROM move_meta WHERE name_ja = ?",
      [@db.BindText(name)],
    ) {
    Ok(r) => r
    Err(_) => return None
  }
  if rows.length() == 0 {
    return None
  }
  match (rows[0].get(0), rows[0].get(1), rows[0].get(2)) {
    (Some(Some(p)), Some(Some(a)), Some(Some(f))) => Some((p, a, f))
    _ => None
  }
}

///|
fn m019_row_count(db : @db.Db) -> Int {
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
/// 1: 本文の確率どおりに行が入る (牙 3 種を含む)。m019 は ねこだまし / はやてがえし を入れない。
test "m019 flinch: representative moves get the Champions text chance; conditional moves have no row" {
  let db = match m019_setup_temp_db("representative") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match @migrate.run_019(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_019 should succeed")
      return
    }
  }
  assert_true(m019_flinch_of(db, "かみつく") == Some(30))
  assert_true(m019_flinch_of(db, "たきのぼり") == Some(20))
  assert_true(m019_flinch_of(db, "ゴッドバード") == Some(30))
  assert_true(m019_flinch_of(db, "いびき") == Some(30))
  assert_true(m019_flinch_of(db, "ドラゴンダイブ") == Some(20))
  assert_true(m019_flinch_of(db, "じんつうりき") == Some(10))
  assert_true(m019_flinch_of(db, "かみなりのキバ") == Some(10))
  assert_true(m019_flinch_of(db, "こおりのキバ") == Some(10))
  assert_true(m019_flinch_of(db, "ほのおのキバ") == Some(10))
  assert_true(m019_flinch_of(db, "アイアンヘッド") == Some(20))
  assert_true(m019_flinch_of(db, "ひょうざんおろし") == Some(30))
  // m019 は ねこだまし を入れない (失敗ゲート付きの 100% は m020)。
  // はやてがえし も入れない (失敗ゲート付きの priority 3 / 100% は m021)。
  assert_true(m019_flinch_of(db, "ねこだまし") == None)
  assert_true(m019_flinch_of(db, "はやてがえし") == None)
  @db.close(db)
}

///|
/// 2: 既存行 (m017 / m018 が入れた牙の状態異常) は flinch 列だけ上書きし、priority / ailment は残る。
test "m019 flinch: existing row keeps its priority and ailment, only flinch_chance is set" {
  let db = match m019_setup_temp_db("existing") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match
    @db.exec_binds(
      db,
      "INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance) VALUES (?, 2, '[]', 'まひ', 10)",
      [@db.BindText("かみなりのキバ")],
    ) {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "seed should succeed")
      return
    }
  }
  match @migrate.run_019(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_019 should succeed")
      return
    }
  }
  assert_true(m019_priority_ailment_of(db, "かみなりのキバ") == Some(("2", "まひ", "10")))
  @db.close(db)
}

///|
/// 3: 表記違い (champions 全角 3 / pokedex ASCII 3) は両方とも 30% の行を持つ。
test "m019 flinch: Triple Arrows has both the full-width (champions) and ASCII (pokedex) rows" {
  let db = match m019_setup_temp_db("spelling") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match @migrate.run_019(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_019 should succeed")
      return
    }
  }
  assert_true(m019_flinch_of(db, "３ぼんのや") == Some(30))
  assert_true(m019_flinch_of(db, "3ぼんのや") == Some(30))
  @db.close(db)
}

///|
/// 4: 2 回目の実行は no-op (行数も値も変わらず、INSERT は 0 件)。
test "m019 flinch: second run is a no-op" {
  let db = match m019_setup_temp_db("idempotent") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  let first = match @migrate.run_019(db, ".") {
    Ok(s) => s
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "first run should succeed")
      return
    }
  }
  let count_after_first = m019_row_count(db)
  match @migrate.run_019(db, ".") {
    Ok(s) => {
      assert_true(first.contains("inserted"))
      assert_true(s.contains("0 inserted"))
    }
    Err(e) => @debug.assert_eq(e, "second run should succeed")
  }
  assert_true(m019_row_count(db) == count_after_first)
  assert_true(count_after_first == 19)
  assert_true(m019_flinch_of(db, "かみつく") == Some(30))
  @db.close(db)
}
