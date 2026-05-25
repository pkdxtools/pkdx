///|
/// Stage 15 — m015_move_meta_field 冪等性 (run-level) テスト。
///
/// `run_015` を一時 sqlite db に対して 2 回連続実行し、戻り値の "X updated,
/// Y inserted" 数値と move_meta の総行数が想定通りに収束することを assert
/// する。m014 の冪等性テスト (`m014_healing_idempotent_test.mbt`) と完全に
/// 同じ pattern。具体的に観測する不変量:
///
/// 1. **1 回目の実行**: 既存行 0 件 → 4 件すべて INSERT
///    ("0 updated, 4 inserted")
/// 2. **2 回目の実行**: 4 件が UPDATE (内容は同じだが reset + upsert で
///    UPDATE 経路を通る) → 0 件 INSERT ("4 updated, 0 inserted")
/// 3. `move_meta` 行数は 2 回目以降 4 のまま不変
/// 4. `field_set != ''` の行数が 4 のまま不変 (= 全 field 行が正しく投入
///    されており、reset で消失していない)
/// 5. PRAGMA table_info で m015 が追加した 2 列が **2 回 ALTER せずに**
///    1 セットだけ存在する (ensure_column の冪等性)
///
/// 一時 db のセットアップは m002/m004/m005 の **schema 等価** な move_meta
/// テーブルを直接 CREATE TABLE することで、上流 migration への依存を避ける
/// (data.json 読み込みを並走させない)。これは「m015 単体の冪等性」を pin
/// する unit-level 検証であり、`migrations_pokedex()` 経由の e2e 順次適用
/// は別途 setup.sh / `bin/pkdx migrate --repo-root .` 経由で検証する。

///|
/// 一時 db を `_build/test_m015_idempotent_<n>.db` に作成し、`move_meta`
/// テーブルを m002/m004/m005 等価のスキーマで初期化する。m015 が ADD COLUMN
/// する 2 列はここでは作らない (run_015 の ensure_column が走ることを観測
/// したい)。
fn setup_m015_temp_db(suffix : String) -> Result[@db.Db, String] {
  let path = "_build/test_m015_idempotent_" + suffix + ".db"
  let _ = @db.unlink_file(path)
  let db = match @db.open_rwc(path) {
    Ok(d) => d
    Err(e) => return Err("open_rwc: " + e)
  }
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
fn count_m015_rows(db : @db.Db) -> Int {
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
/// field_set != '' の行数 (= 投入された field 行の総数)。
fn count_field_rows(db : @db.Db) -> Int {
  let rows = match @db.query_binds(
      db,
      "SELECT COUNT(*) FROM move_meta WHERE field_set != ''",
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
/// m015 が追加すべき 2 列 (field_set / field_turns) のうち、PRAGMA で実際に
/// 存在する列数を返す。
fn count_m015_columns(db : @db.Db) -> Int {
  let expected = ["field_set", "field_turns"]
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
    if hit {
      found = found + 1
    }
  }
  found
}

///|
/// 1 回目の run_015: 既存 0 件 → 4 件すべて INSERT (data.json は 4 件)
test "m015 idempotent: first run inserts all 4 entries" {
  let db = match setup_m015_temp_db("first") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  let msg = match run_015(db, ".") {
    Ok(s) => s
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_015 should succeed on a fresh schema")
      return
    }
  }
  @debug.debug_inspect(
    msg, content="\"field columns added; 0 updated, 4 inserted\"",
  )
  @debug.assert_eq(count_m015_rows(db), 4)
  @debug.assert_eq(count_field_rows(db), 4)
  @debug.assert_eq(count_m015_columns(db), 2)
  @db.close(db)
}

///|
/// 2 回目の run_015 (同じ db): 4 件 UPDATE、0 INSERT、行数 / 列数不変。
test "m015 idempotent: second run re-applies as UPDATE, row count stable" {
  let db = match setup_m015_temp_db("second") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match run_015(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "first run should succeed")
      return
    }
  }
  let rows_after_first = count_m015_rows(db)
  let field_after_first = count_field_rows(db)
  let cols_after_first = count_m015_columns(db)
  let msg2 = match run_015(db, ".") {
    Ok(s) => s
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "second run should succeed")
      return
    }
  }
  @debug.debug_inspect(
    msg2, content="\"field columns added; 4 updated, 0 inserted\"",
  )
  @debug.assert_eq(count_m015_rows(db), rows_after_first)
  @debug.assert_eq(count_field_rows(db), field_after_first)
  @debug.assert_eq(count_m015_columns(db), cols_after_first)
  @debug.assert_eq(count_m015_columns(db), 2)
  @db.close(db)
}

///|
/// 3 回目 (連続適用): 2 回目以降は永続的に "4 updated, 0 inserted" のまま、
/// 行数 / 列数 / field 行数すべて不変。data.json 状態への収束保証。
test "m015 idempotent: third run is identical to second (steady state)" {
  let db = match setup_m015_temp_db("third") {
    Ok(d) => d
    Err(e) => {
      @debug.assert_eq(e, "open or create_table should succeed")
      return
    }
  }
  match run_015(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "first run should succeed")
      return
    }
  }
  match run_015(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "second run should succeed")
      return
    }
  }
  let msg3 = match run_015(db, ".") {
    Ok(s) => s
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "third run should succeed")
      return
    }
  }
  @debug.debug_inspect(
    msg3, content="\"field columns added; 4 updated, 0 inserted\"",
  )
  @debug.assert_eq(count_m015_rows(db), 4)
  @debug.assert_eq(count_field_rows(db), 4)
  @debug.assert_eq(count_m015_columns(db), 2)
  @db.close(db)
}

///|
/// m014 + m015 を同じ DB に順次適用しても、両者の列が独立に共存することを
/// pin する。m014 の 9 列 (heal_* / weather_*) と m015 の 2 列
/// (field_set / field_turns) は別概念で同じ name_ja を共有しないため、
/// m014 行 21 件 + m015 行 4 件 = 合計 25 行が独立に立つ (重ならない)。
test "m014 + m015 co-existence: rows are independent across both migrations" {
  let db = match setup_m015_temp_db("coexist") {
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
      @debug.assert_eq(e, "run_014 should succeed")
      return
    }
  }
  match run_015(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_015 should succeed")
      return
    }
  }
  // 行総数: 21 (m014) + 4 (m015) = 25 (両 data.json で name_ja は重複しない)
  @debug.assert_eq(count_m015_rows(db), 25)
  // m015 の field 行は 4 件のまま (m014 が field_set を触らない)
  @debug.assert_eq(count_field_rows(db), 4)
  // m015 の列は 2 列 (m014 の列とは独立)
  @debug.assert_eq(count_m015_columns(db), 2)
  // m014 を再実行しても m015 行 / 列は影響しない (authoritative reset の境界)
  match run_014(db, ".") {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      @debug.assert_eq(e, "run_014 second pass should succeed")
      return
    }
  }
  @debug.assert_eq(count_m015_rows(db), 25)
  @debug.assert_eq(count_field_rows(db), 4)
  @db.close(db)
}
