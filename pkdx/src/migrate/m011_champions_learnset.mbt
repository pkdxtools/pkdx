///|
/// `pkdx_patch/004_champions_learnset/data.json` を champions.db.learnset
/// に投入する。`(id, waza)` の複合 PK で冪等。conditions は champout 由来
/// データ全行 "基本" として入る (champout は経路情報を持たないため)。
pub fn run_011(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/011_champions_learnset/data.json"
  let raw = match @db.read_file(path) {
    None => return Err(path + " not found.")
    Some(s) => s
  }
  let json = try @json.parse(raw) catch {
    e => return Err("JSON parse: " + e.to_string())
  }
  let entries = match @champions_schema.parse_learnset_entries(json) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match @db.exec(db, "DELETE FROM learnset") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  for i = 0; i < entries.length(); i = i + 1 {
    let e = entries[i]
    match @db.exec_binds(
        db,
        "INSERT OR IGNORE INTO learnset (id, waza, conditions) VALUES (?, ?, ?)",
        [
          @db.BindText(e.id),
          @db.BindText(e.waza),
          @db.BindText(e.conditions),
        ],
      ) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  Ok("Inserted " + entries.length().to_string() + " learnset rows")
}
