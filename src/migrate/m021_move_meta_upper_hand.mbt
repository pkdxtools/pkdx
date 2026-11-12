///|
/// はやてがえし の priority 3 とひるみ 100% を move_meta に投入する。
///
/// 失敗ゲート (`upper_hand_fails`、`src/payoff/upper_hand.mbt`) とセットで入れる。
/// ゲートの無い 100% 行は、相手の通常技 (priority 0) でもひるませるので、
/// m019 と m020 では見送っていた。m019 / m020 は今もこの技の行を作らない。
///
/// 優先度の出典は `champout/masterdata/waza.json` id "918" の `"priority": "3"`。
/// ひるみ 100% の出典は `WAZAINFO_SYN_918` (Index 673):
/// "Makes the target flinch. This move fails if the target isn’t about to use a priority attack."
///
/// 既存行は `priority` と `flinch_chance` だけを上書きする (ailment や stat_effects は残す)。
/// 行が無ければ priority 3・flinch_chance 100 で INSERT する (m002 はこの技を入れない)。
/// であいがしら は入れない。
///
/// 何度流しても data.json の状態へ収束する (冪等)。
pub fn run_021(db : @db.Db, repo_root : String) -> Result[String, String] {
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
  let path = repo_root + "/pkdx_patch/021_move_meta_upper_hand/data.json"
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
      _ => return Err("upper hand entry is not an object")
    }
    let name = str_field(entry, "name")
    let priority = int_field(entry, "priority", 3)
    let flinch_chance = int_field(entry, "flinch_chance", 100)
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
          "UPDATE move_meta SET priority = ?, flinch_chance = ? WHERE name_ja = ?",
          [
            @db.BindInt(priority),
            @db.BindInt(flinch_chance),
            @db.BindText(name),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      updated = updated + 1
    } else {
      match
        @db.exec_binds(
          db,
          "INSERT INTO move_meta (name_ja, priority, stat_effects_json, flinch_chance) VALUES (?, ?, '[]', ?)",
          [
            @db.BindText(name),
            @db.BindInt(priority),
            @db.BindInt(flinch_chance),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "upper hand; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}
