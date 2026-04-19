///|
/// Champions 技習得データを pokedex.db に INSERT OR IGNORE で載せる。
/// yakkun 由来の没収技混入は 005 が別テーブルへ整理するので、ここでは
/// 生データをそのまま流し込むだけでよい。
pub fn run_004(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/004_champions_learnset/data.json"
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
  // local_pokedex_waza にも UNIQUE 制約が無いので、--resync 時に重複が
  // 発生しないよう Champions 行を先にクリアする。通常フローでは 005 が
  // 最後に同条件で削除するため不要だが、005 失敗後の resync でも安全に
  // 再走するようここで防御する。
  match @db.exec_binds(
      db,
      "DELETE FROM local_pokedex_waza WHERE version = ?",
      [@db.BindText(waza_version)],
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  for entry_json in entries {
    let entry = match entry_json {
      Object(o) => o
      _ => return Err("learnset entry is not an object")
    }
    let form = bind_text_opt(str_opt(entry, "form"))
    let region = bind_text_opt(str_opt(entry, "region"))
    let mega_evo = bind_text_opt(str_opt(entry, "mega_evolution"))
    let gigantamax = bind_text_opt(str_opt(entry, "gigantamax"))
    match @db.exec_binds(
        db,
        "INSERT OR IGNORE INTO local_pokedex_waza (id, globalNo, form, region, mega_evolution, gigantamax, version, pokedex, conditions, waza) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(str_field(entry, "id")),
          @db.BindText(str_field(entry, "globalNo")),
          form,
          region,
          mega_evo,
          gigantamax,
          @db.BindText(waza_version),
          @db.BindText(str_field(entry, "pokedex")),
          @db.BindText(str_field(entry, "conditions")),
          @db.BindText(str_field(entry, "waza")),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  Ok("Inserted " + entries.length().to_string() + " Champions learnset entries")
}
