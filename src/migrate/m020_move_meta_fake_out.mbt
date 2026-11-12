///|
/// ねこだまし のひるみ 100% を move_meta に投入する。
///
/// 失敗ゲート (`my_fresh` / `opp_fresh`、`fake_out.mbt`) とセットで入れる。ゲートの無い
/// 100% 行は 2 手目以降もひるませるので、m019 では見送っていた。
///
/// 本文: `champout/rom-txt/usa/wazainfo_syn.json` の `WAZAINFO_SYN_252`
/// "Makes the target flinch. This move fails unless it is the first move used
/// by the user after it enters a battle."
///
/// 既存行 (m002 の priority 3) は `flinch_chance` だけを上書きする。行が無ければ
/// priority 0 で INSERT する (本番 DB では m002 が先に行を作る)。
/// はやてがえし と であいがしら は入れない。はやてがえし の行は m021。
///
/// 何度流しても data.json の状態へ収束する (冪等)。
pub fn run_020(db : @db.Db, repo_root : String) -> Result[String, String] {
  match
    ensure_column(
      db,
      "move_meta",
      "flinch_chance",
      "ALTER TABLE move_meta ADD COLUMN flinch_chance INTEGER NOT NULL DEFAULT 0",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let path = repo_root + "/pkdx_patch/020_move_meta_fake_out/data.json"
  let raw = match @db.read_file(path) {
    Some(s) => s
    None => return Err(path + " not found.")
  }
  let json = @json.parse(raw) catch {
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
      _ => return Err("fake out entry is not an object")
    }
    let name = str_field(entry, "name")
    let flinch_chance = int_field(entry, "flinch_chance", 0)
    let rows = match
      @db.query_binds(db, "SELECT 1 FROM move_meta WHERE name_ja = ? LIMIT 1", [
        @db.BindText(name),
      ]) {
      Err(e) => return Err(e)
      Ok(r) => r
    }
    if rows.length() > 0 {
      match
        @db.exec_binds(
          db,
          "UPDATE move_meta SET flinch_chance = ? WHERE name_ja = ?",
          [@db.BindInt(flinch_chance), @db.BindText(name)],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      updated = updated + 1
    } else {
      match
        @db.exec_binds(
          db,
          "INSERT INTO move_meta (name_ja, priority, stat_effects_json, flinch_chance) VALUES (?, 0, '[]', ?)",
          [@db.BindText(name), @db.BindInt(flinch_chance)],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "fake out flinch; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}
