///|
/// move_meta にフィールド設定技 (エレキフィールド / グラスフィールド /
/// ミストフィールド / サイコフィールド) のメタデータを投入する。Weather と
/// 完全対称な構造で、`weather_set` / `weather_turns` の隣に `field_set` /
/// `field_turns` 列を追加し、4 件の data.json を流す。Gen9 base 5T (Terrain
/// Extender 延長は本 PR 未対応)。
///
/// 列構成:
/// - `field_set`   : '' (なし) / 'electric' / 'grassy' / 'misty' / 'psychic'
/// - `field_turns` : フィールド持続ターン数 (Gen9 base 5)
///
/// 冪等性戦略 (authoritative overlay) — m014 と完全に同じ pattern:
/// 1. ensure_column で 2 列追加 (DEFAULT neutral)
/// 2. **全 move_meta 行を field 列について neutral に reset** —
///    過去 data.json から技を消した場合に「以前は electric だった行」が
///    DB に残り続けるのを防ぐ
/// 3. data.json から upsert (UPDATE 優先、無ければ INSERT)
///
/// この戦略により m015 は何度流しても data.json の現在状態へ収束する。
/// m014 の heal_* 列とは独立に走るため、m014 行 (=2014 で追加された 21 件)
/// と m015 行 (=2015 で追加される 4 件) は重ならない (heal_kind と field_set
/// は別カラムで別概念)。
pub fn run_015(db : @db.Db, repo_root : String) -> Result[String, String] {
  let alters = [
    (
      "field_set", "ALTER TABLE move_meta ADD COLUMN field_set TEXT NOT NULL DEFAULT ''",
    ),
    (
      "field_turns", "ALTER TABLE move_meta ADD COLUMN field_turns INTEGER NOT NULL DEFAULT 0",
    ),
  ]
  for col in alters {
    let (name, sql) = col
    match ensure_column(db, "move_meta", name, sql) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  // Authoritative reset: 過去の m015 run で投入された行を data.json から
  // 削除した場合にも DB を収束させるため、全行を neutral に戻してから
  // upsert する。
  match @db.exec(db, "UPDATE move_meta SET field_set='', field_turns=0") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let path = repo_root + "/pkdx_patch/015_move_meta_field/data.json"
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
      _ => return Err("field entry is not an object")
    }
    let name = str_field(entry, "name")
    let field_set = str_field(entry, "field_set")
    let field_turns = int_field(entry, "field_turns", 0)
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
          "UPDATE move_meta SET field_set = ?, field_turns = ? WHERE name_ja = ?",
          [
            @db.BindText(field_set),
            @db.BindInt(field_turns),
            @db.BindText(name),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      updated = updated + 1
    } else {
      // m014 が同じ name の行を作っていないフィールド技は INSERT が必要。
      // 既存 m002/m004/m005 のデフォルト値も埋めて other columns を neutral
      // 状態にする (m014 と同じ pattern)。
      match
        @db.exec_binds(
          db,
          "INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance, recoil_num, recoil_den, self_ko, recharge, field_set, field_turns) VALUES (?, 0, '[]', '', 100, 0, 1, 0, 0, ?, ?)",
          [
            @db.BindText(name),
            @db.BindText(field_set),
            @db.BindInt(field_turns),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "field columns added; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}
