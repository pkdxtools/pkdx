///|
/// `pkdx_patch/013_items/data.json` を champions.db.items に投入し、
/// damage 計算で参照する `item_effect` 行を seed する。アイテムマスター自体は
/// champout 由来 (約 100 件 + 木の実) で広範に登録するが、`item_effect` は
/// pkdx の damage ロジック側で挙動定義済みのアイテムだけを seed する。
///
/// Champions マスターに存在する seed 対象アイテム (Phase 4 の検証で確認):
///   - オッカのみ (resist_berry: ほのお × 2048/4096 super_effective_only)
///   - きあいのタスキ (consume_on_hit: post-damage HP=1 を 1 度だけ保証)
///
/// 旧 m013 が seed していた こだわりハチマキ / いのちのたま / フィラのみ は
/// Champions マスターに存在しないため除外。将来 Champions ゲームが SV 互換
/// アイテムを追加した時点で本 migration に追記して seed を増やす。
pub fn run_012(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/012_items/data.json"
  let raw = match @db.read_file(path) {
    None => return Err(path + " not found.")
    Some(s) => s
  }
  let json = try @json.parse(raw) catch {
    e => return Err("JSON parse: " + e.to_string())
  }
  let entries = match @champions_schema.parse_item_entries(json) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match @db.exec(db, "DELETE FROM items") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match @db.exec(db, "DELETE FROM item_effect") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  for i = 0; i < entries.length(); i = i + 1 {
    let e = entries[i]
    match @db.exec_binds(
        db,
        "INSERT OR IGNORE INTO items (name_ja, name_en, category, flavor) VALUES (?, ?, ?, ?)",
        [
          @db.BindText(e.name_ja),
          @db.BindText(e.name_en),
          @db.BindText(e.category),
          @db.BindText(e.flavor),
        ],
      ) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  // item_effect seed (Champions 在庫と整合する 2 件のみ)
  match @db.exec_binds(
      db,
      "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES (?, 'resist_berry', 0, 2048, 4096, ?, NULL, NULL, 1)",
      [@db.BindText("オッカのみ"), @db.BindText("ほのお")],
    ) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match @db.exec_binds(
      db,
      "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES (?, 'consume_on_hit', 4, 0, 0, NULL, NULL, NULL, 0)",
      [@db.BindText("きあいのタスキ")],
    ) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  Ok(
    "Inserted " +
    entries.length().to_string() +
    " items + 2 item_effect rows",
  )
}
