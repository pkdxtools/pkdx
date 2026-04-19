///|
/// Champions 技データを pokedex.db に載せる。local_waza と
/// local_waza_language (日本語表示名のみ) の 2 テーブルを同時更新。
pub fn run_003(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/003_champions_moves/data.json"
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
  let waza_version = "Champions"
  for entry_json in entries {
    let m = match entry_json {
      Object(o) => o
      _ => return Err("move entry is not an object")
    }
    let waza = str_field(m, "waza")
    // pp / power / accuracy は JSON 上でも文字列 ("20", "-" 等) で
    // 保持されており、Ruby 版はそのまま TEXT で格納していた。SQLite 側
    // の既存レコードも TEXT 型運用なので、型を揃えるため BindText で通す。
    match @db.exec_binds(
        db,
        "INSERT OR REPLACE INTO local_waza (waza, version, type, category, pp, power, accuracy) VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(waza),
          @db.BindText(waza_version),
          @db.BindText(str_field(m, "type")),
          @db.BindText(str_field(m, "category")),
          @db.BindText(str_field(m, "pp")),
          @db.BindText(str_field(m, "power")),
          @db.BindText(str_field(m, "accuracy")),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match @db.exec_binds(
        db,
        "INSERT OR IGNORE INTO local_waza_language (waza, version, language, name, description) VALUES (?, ?, ?, ?, ?)",
        [
          @db.BindText(waza),
          @db.BindText(waza_version),
          @db.BindText("jpn"),
          @db.BindText(waza),
          @db.BindNull,
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  Ok(
    "Inserted/replaced " + entries.length().to_string() + " Champions move entries",
  )
}
