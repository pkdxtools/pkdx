///|
/// `pkdx_patch/003_champions_moves/data.json` を champions.db.move と
/// champions.db.move_name に投入する。`waza` 列が PK なので INSERT OR
/// REPLACE で冪等。技名は jpn のみ最初から登録 (eng は将来追加)。
pub fn run_010(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/010_champions_moves/data.json"
  let raw = match @db.read_file(path) {
    None => return Err(path + " not found.")
    Some(s) => s
  }
  let json = try @json.parse(raw) catch {
    e => return Err("JSON parse: " + e.to_string())
  }
  let entries = match @champions_schema.parse_move_entries(json) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match @db.exec(db, "DELETE FROM move") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match @db.exec(db, "DELETE FROM move_name") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  for i = 0; i < entries.length(); i = i + 1 {
    let e = entries[i]
    match @db.exec_binds(
        db,
        "INSERT INTO move (waza, type, category, pp, power, accuracy, direct, target) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(e.waza),
          @db.BindText(e.type_),
          @db.BindText(e.category),
          @db.BindText(e.pp),
          @db.BindText(e.power),
          @db.BindText(e.accuracy),
          @db.BindText(e.direct),
          @db.BindText(e.target),
        ],
      ) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    match @db.exec_binds(
        db,
        "INSERT INTO move_name (waza, language, name, description) VALUES (?, ?, ?, NULL)",
        [@db.BindText(e.waza), @db.BindText("jpn"), @db.BindText(e.waza)],
      ) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  Ok("Inserted " + entries.length().to_string() + " move rows")
}
