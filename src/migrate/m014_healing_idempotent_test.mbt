///|
/// Stage 14 — m014_move_meta_healing 冪等性 (run-level) テスト。
///
/// `run_014` を一時 sqlite db に対して 2 回連続実行し、戻り値の "X updated,
/// Y inserted" 数値と move_meta の総行数が想定通りに収束することを assert
/// する。具体的に観測する不変量:
///
/// 1. **1 回目の実行**: 既存行 0 件 → 21 件すべて INSERT
///    ("0 updated, 21 inserted")
/// 2. **2 回目の実行**: 21 件が UPDATE (内容は同じだが reset + upsert で
///    UPDATE 経路を通る) → 0 件 INSERT ("21 updated, 0 inserted")
/// 3. `move_meta` 行数は 2 回目以降 21 のまま不変
/// 4. `heal_kind != ''` または `weather_set != ''` の行数が 21 のまま不変
///    (= 全 healing/weather 行が正しく投入されており、reset で消失していない)
/// 5. PRAGMA table_info で m014 が追加した 9 列が **2 回 ALTER せずに**
///    1 セットだけ存在する (ensure_column の冪等性)
///
/// 一時 db のセットアップは m002/m004/m005 の **schema 等価** な move_meta
/// テーブルを直接 CREATE TABLE することで、上流 migration への依存を避ける
/// (それらの data.json 読み込みを並走させない)。これは「m014 単体の
/// 冪等性」を pin する unit-level 検証であり、`migrations_pokedex()` 経由
/// の e2e 順次適用は別途 setup.sh / `bin/pkdx migrate --repo-root .` 経由
/// で検証する (Plan 段階 14.E)。

///|
/// 一時 db を `_build/test_m014_idempotent_<n>.db` に作成し、`move_meta`
/// テーブルを m002/m004/m005 等価のスキーマで初期化する。
fn setup_temp_db(suffix : String) -> Result[@db.Db, String] {
  let path = "_build/test_m014_idempotent_" + suffix + ".db"
  // 既存ファイルがあれば削除 (前回 test の残骸を無視)
  let _ = @db.unlink_file(path)
  let db = match @db.open_rwc(path) {
    Ok(d) => d
    Err(e) => return Err("open_rwc: " + e)
  }
  // m002 + m004 + m005 等価の move_meta スキーマ。m014 が ADD COLUMN する
  // 9 列はここでは作らない (run_014 の ensure_column が走ることを観測したい)。
  let create_sqls = [
    "CREATE TABLE IF NOT EXISTS move_meta (name_ja TEXT PRIMARY KEY, priority INTEGER NOT NULL DEFAULT 0, stat_effects_json TEXT NOT NULL DEFAULT '[]', ailment_ja TEXT NOT NULL DEFAULT '', ailment_chance INTEGER NOT NULL DEFAULT 100, recoil_num INTEGER NOT NULL DEFAULT 0, recoil_den INTEGER NOT NULL DEFAULT 1, self_ko INTEGER NOT NULL DEFAULT 0, recharge INTEGER NOT NULL DEFAULT 0)",
  ]
  for sql in create_sqls {
    match @db.exec(db, sql) {
      Err(e) => return Err("CREATE TABLE: " + e)
      Ok(_) => ()
    }
  }
  Ok(db)
}

///|
/// move_meta の行数を取得。
fn count_rows(db : @db.Db) -> Int {
  let rows = match @db.query_binds(db, "SELECT COUNT(*) FROM move_meta", []) {
    Ok(r) => r
    Err(_) => return -1
  }
  if rows.length() == 0 {
    return -1
  }
  match rows[0].get(0) {
    Some(Some(s)) => @string.parse_int(s) catch { _ => -1 }
    _ => -1
  }
}

///|
/// heal_kind != '' OR weather_set != '' の行数を取得 (= 投入された healing/
/// weather 行の総数)。
fn count_healing_rows(db : @db.Db) -> Int {
  let rows = match @db.query_binds(
      db,
      "SELECT COUNT(*) FROM move_meta WHERE heal_kind != '' OR weather_set != ''",
      [],
    ) {
    Ok(r) => r
    Err(_) => return -1
  }
  if rows.length() == 0 {
    return -1
  }
  match rows[0].get(0) {
    Some(Some(s)) => @string.parse_int(s) catch { _ => -1 }
    _ => -1
  }
}

///|
/// m014 が追加すべき 9 列 (heal_kind 〜 weather_turns) のうち、PRAGMA で
/// 実際に存在する列数を返す。
fn count_m014_columns(db : @db.Db) -> Int {
  let expected = [
    "heal_kind", "heal_num", "heal_den", "heal_sunny_num", "heal_sunny_den",
    "heal_harsh_num", "heal_harsh_den", "weather_set", "weather_turns",
  ]
  let rows = match @db.query_binds(db, "PRAGMA table_info(move_meta)", []) {
    Ok(r) => r
    Err(_) => return -1
  }
  let mut found = 0
  for col_name in expected {
    let mut hit = false
    for row in rows {
      match row.get(1) {
        Some(Some(name)) => if name == col_name { hit = true }
        _ => ()
      }
    }
    if hit { found = found + 1 }
  }
  found
}

///|
/// 1 回目の run_014: 既存 0 件 → 21 件すべて INSERT。
/// (data.json は 21 件)
test "m014 idempotent: first run inserts all 21 entries" {
  let db = match setup_temp_db("first") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  let msg = match run_014(db, ".") {
    Ok(s) => s
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_014 should succeed on a fresh schema")
      return
    }
  }
  // フォーマット: "healing/weather columns added; <updated> updated, <inserted> inserted"
  @debug.debug_inspect(
    msg, content="\"healing/weather columns added; 0 updated, 21 inserted\"",
  )
  @debug.assert_eq(count_rows(db), 21)
  @debug.assert_eq(count_healing_rows(db), 21)
  @debug.assert_eq(count_m014_columns(db), 9)
  @db.close(db)
}

///|
/// 2 回目の run_014 (同じ db): 21 件 UPDATE、0 INSERT、行数 / 列数不変。
test "m014 idempotent: second run re-applies as UPDATE, row count stable" {
  let db = match setup_temp_db("second") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  // 1 回目
  match run_014(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "first run should succeed")
      return
    }
  }
  let rows_after_first = count_rows(db)
  let healing_after_first = count_healing_rows(db)
  let cols_after_first = count_m014_columns(db)
  // 2 回目: authoritative reset → 21 件 UPDATE で同じ状態へ収束。
  let msg2 = match run_014(db, ".") {
    Ok(s) => s
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "second run should succeed")
      return
    }
  }
  @debug.debug_inspect(
    msg2, content="\"healing/weather columns added; 21 updated, 0 inserted\"",
  )
  @debug.assert_eq(count_rows(db), rows_after_first)
  @debug.assert_eq(count_healing_rows(db), healing_after_first)
  @debug.assert_eq(count_m014_columns(db), cols_after_first)
  @debug.assert_eq(count_m014_columns(db), 9)
  @db.close(db)
}

///|
/// 3 回目 (連続適用): 2 回目以降は永続的に "21 updated, 0 inserted" のまま、
/// 行数 / 列数 / healing 行数すべて不変。data.json 状態への収束保証。
test "m014 idempotent: third run is identical to second (steady state)" {
  let db = match setup_temp_db("third") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match run_014(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "first run should succeed")
      return
    }
  }
  match run_014(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "second run should succeed")
      return
    }
  }
  let msg3 = match run_014(db, ".") {
    Ok(s) => s
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "third run should succeed")
      return
    }
  }
  @debug.debug_inspect(
    msg3, content="\"healing/weather columns added; 21 updated, 0 inserted\"",
  )
  @debug.assert_eq(count_rows(db), 21)
  @debug.assert_eq(count_healing_rows(db), 21)
  @debug.assert_eq(count_m014_columns(db), 9)
  @db.close(db)
}
