///|
/// こおり (Freeze) の二次効果を持つダメージ技を move_meta に投入する。
///
/// 出典 (Champions 本文を優先):
/// - れいとうビーム 10% (`champout/rom-txt/usa/wazainfo_syn.json:636`
///   "Has a 10% chance of freezing the target.")
/// - ふぶき 10% (:658 "Has a 10% chance of freezing targets. ...")
/// - れいとうパンチ 10% (:38)
/// - こおりのキバ 10% (:8136 "... 10% chance of freezing the target and a 10% chance
///   of making the target flinch."。ひるみ 10% は未モデル)
/// - フリーズドライ 10% (:11178 の本文は「みずタイプに抜群」のみで凍結に触れない。
///   Showdown `data/moves.ts` の `secondary.chance: 10` / `status: frz` で補う = 判断事項)
///
/// 意図的に含めないもの:
/// - トライアタック (:2208 "20% chance of leaving the target burned, frozen, or paralyzed"):
///   3 種の状態異常を 1/3 ずつ振るため、単一の `ailment_ja` / 整数 `ailment_chance` で表せない。
/// - こなゆき / いてつくしせん / ポーラーフレア: Champions の技プールに無い。
///
/// move_meta には従来ダメージ技の行が無いので、無い行は INSERT する (m004 と同じ列構成。
/// 他の列は DDL の既定値)。既存の行は ailment 列だけを data.json の値に上書きする。
/// 何度流しても data.json の状態へ収束する (冪等)。
pub fn run_017(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/017_move_meta_freeze/data.json"
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
      _ => return Err("freeze entry is not an object")
    }
    let name = str_field(entry, "name")
    let ailment_ja = str_field(entry, "ailment_ja")
    let ailment_chance = int_field(entry, "ailment_chance", 100)
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
      match
        @db.exec_binds(
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
    "freeze ailment rows; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}
