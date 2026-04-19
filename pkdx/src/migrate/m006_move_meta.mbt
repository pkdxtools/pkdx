///|
/// payoff 層が参照する技メタ (priority, stat_effects) を格納する
/// move_meta テーブルを初期化し、data.json からエントリを入れる。
/// stat_effects は配列配列の JSON としてそのまま格納する (後続パッチ
/// 010 が 2 要素→3 要素の拡張互換を維持する)。
pub fn run_006(db : @db.Db, repo_root : String) -> Result[String, String] {
  match @db.exec(
      db,
      "CREATE TABLE IF NOT EXISTS move_meta (name_ja TEXT PRIMARY KEY, priority INTEGER NOT NULL DEFAULT 0, stat_effects_json TEXT NOT NULL DEFAULT '[]')",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let path = repo_root + "/pkdx_patch/006_move_meta/data.json"
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
  for entry_json in entries {
    let entry = match entry_json {
      Object(o) => o
      _ => return Err("move_meta entry is not an object")
    }
    let name = str_field(entry, "name")
    let priority = int_field(entry, "priority", 0)
    let effects_json = match entry.get("stat_effects") {
      Some(j) => j.stringify()
      None => "[]"
    }
    match @db.exec_binds(
        db,
        "INSERT OR REPLACE INTO move_meta (name_ja, priority, stat_effects_json) VALUES (?, ?, ?)",
        [
          @db.BindText(name),
          @db.BindInt(priority),
          @db.BindText(effects_json),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  Ok(
    "Inserted/replaced " +
    entries.length().to_string() +
    " move_meta entries",
  )
}
