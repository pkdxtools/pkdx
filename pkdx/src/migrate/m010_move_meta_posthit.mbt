///|
/// payoff 層の post-hit 副次効果に必要な列
/// (recoil_num, recoil_den, self_ko, recharge) を move_meta に追加し、
/// data.json のエントリを upsert する。stat_effects_json の構造
/// (2 要素 → 3 要素拡張) は JSON シリアライズがそのまま通る。
pub fn run_010(db : @db.Db, repo_root : String) -> Result[String, String] {
  let alters = [
    (
      "recoil_num",
      "ALTER TABLE move_meta ADD COLUMN recoil_num INTEGER NOT NULL DEFAULT 0",
    ),
    (
      "recoil_den",
      "ALTER TABLE move_meta ADD COLUMN recoil_den INTEGER NOT NULL DEFAULT 1",
    ),
    (
      "self_ko",
      "ALTER TABLE move_meta ADD COLUMN self_ko INTEGER NOT NULL DEFAULT 0",
    ),
    (
      "recharge",
      "ALTER TABLE move_meta ADD COLUMN recharge INTEGER NOT NULL DEFAULT 0",
    ),
  ]
  for col in alters {
    let (name, sql) = col
    match ensure_column(db, "move_meta", name, sql) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  let path = repo_root + "/pkdx_patch/010_move_meta_posthit/data.json"
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
      _ => return Err("posthit entry is not an object")
    }
    let name = str_field(entry, "name")
    let priority = int_field(entry, "priority", 0)
    let effects_json = match entry.get("stat_effects") {
      Some(j) => j.stringify()
      None => "[]"
    }
    let recoil_num = int_field(entry, "recoil_num", 0)
    let recoil_den = int_field(entry, "recoil_den", 1)
    let self_ko = if bool_field(entry, "self_ko") { 1 } else { 0 }
    let recharge = if bool_field(entry, "recharge") { 1 } else { 0 }
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
          "UPDATE move_meta SET priority = ?, stat_effects_json = ?, ailment_ja = ?, ailment_chance = ?, recoil_num = ?, recoil_den = ?, self_ko = ?, recharge = ? WHERE name_ja = ?",
          [
            @db.BindInt(priority),
            @db.BindText(effects_json),
            @db.BindText(ailment_ja),
            @db.BindInt(ailment_chance),
            @db.BindInt(recoil_num),
            @db.BindInt(recoil_den),
            @db.BindInt(self_ko),
            @db.BindInt(recharge),
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
          "INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance, recoil_num, recoil_den, self_ko, recharge) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [
            @db.BindText(name),
            @db.BindInt(priority),
            @db.BindText(effects_json),
            @db.BindText(ailment_ja),
            @db.BindInt(ailment_chance),
            @db.BindInt(recoil_num),
            @db.BindInt(recoil_den),
            @db.BindInt(self_ko),
            @db.BindInt(recharge),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "post-hit columns added; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}
