///|
/// move_meta に状態異常サポート列 (ailment_ja, ailment_chance) を
/// 追加し、data.json のエントリで埋める。
/// 冪等性: 既存カラムは PRAGMA table_info で検出してスキップ。
pub fn run_008(db : @db.Db, repo_root : String) -> Result[String, String] {
  match ensure_column(db, "move_meta", "ailment_ja",
      "ALTER TABLE move_meta ADD COLUMN ailment_ja TEXT NOT NULL DEFAULT ''") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match ensure_column(db, "move_meta", "ailment_chance",
      "ALTER TABLE move_meta ADD COLUMN ailment_chance INTEGER NOT NULL DEFAULT 100") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let path = repo_root + "/pkdx_patch/008_move_meta_ailment/data.json"
  let raw = match @db.read_file(path) {
    Some(s) => s
    None => return Err(path + " not found.")
  }
  let json = try @json.parse(raw) catch {
    e => return Err("JSON parse: " + e.to_string())
  }
  let entries = match expect_array(json) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let mut updated = 0
  let mut inserted = 0
  for entry_json in entries {
    let entry = match entry_json {
      Object(o) => o
      _ => return Err("ailment entry is not an object")
    }
    let name = str_field(entry, "name")
    let ailment_ja = str_field(entry, "ailment_ja")
    let ailment_chance = int_field(entry, "ailment_chance", 100)
    let rows = match @db.query_binds(
        db,
        "SELECT 1 FROM move_meta WHERE name_ja = ? LIMIT 1",
        [@db.BindText(name)],
      ) {
      Err(e) => return Err(e)
      Ok(r) => r
    }
    if rows.length() > 0 {
      match @db.exec_binds(
          db,
          "UPDATE move_meta SET ailment_ja = ?, ailment_chance = ? WHERE name_ja = ?",
          [
            @db.BindText(ailment_ja),
            @db.BindInt(ailment_chance),
            @db.BindText(name),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      updated = updated + 1
    } else {
      match @db.exec_binds(
          db,
          "INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance) VALUES (?, 0, '[]', ?, ?)",
          [
            @db.BindText(name),
            @db.BindText(ailment_ja),
            @db.BindInt(ailment_chance),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "ailment columns added; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}

///|
/// ALTER TABLE を冪等に適用するヘルパー。PRAGMA table_info で既存列を
/// 検出し、まだ存在しなければ alter_sql を実行する。008/010 で同じ
/// パターンを使うため runner_util 相当としてここに置く。
pub fn ensure_column(
  db : @db.Db,
  table : String,
  column : String,
  alter_sql : String,
) -> Result[Unit, String] {
  let rows = match @db.query_binds(
      db,
      "PRAGMA table_info(" + table + ")",
      [],
    ) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  for row in rows {
    match row.get(1) {
      Some(Some(name)) =>
        if name == column {
          return Ok(())
        }
      _ => ()
    }
  }
  @db.exec(db, alter_sql)
}
