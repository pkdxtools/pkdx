///|
/// Champions learnset を正規化し、yakkun 由来の没収技を
/// state='inactive' でマークする。
///
/// アルゴリズム: 各 (globalNo, form, region, mega_evolution, gigantamax)
/// グループ内で技を rowid 順に辿り、タイプ遷移を監視する。タイプが
/// 一度閉じた(=別タイプへ遷移した)状態で再出現したら、その位置から
/// 没収技として inactive にする。
pub fn run_005(db : @db.Db, _repo_root : String) -> Result[String, String] {
  match @db.exec(
      db,
      "CREATE TABLE IF NOT EXISTS champions_learnset (id TEXT, globalNo TEXT, form TEXT, region TEXT, mega_evolution TEXT, gigantamax TEXT, pokedex TEXT, conditions TEXT, waza TEXT, state TEXT NOT NULL DEFAULT 'active' CHECK (state IN ('active', 'inactive')))",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // `champions_learnset` は 005 が所有するテーブル。--resync で 004 が
  // local_pokedex_waza を再投入した後、再び此処に INSERT する際に重複
  // しないよう、実行のたびに全行を捨てて正規化結果で上書きする。
  match @db.exec(db, "DELETE FROM champions_learnset") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let type_rows = match @db.query_binds(
      db,
      "SELECT waza, type FROM local_waza WHERE version = 'Champions'",
      [],
    ) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  let type_map : Map[String, String] = Map::new()
  for row in type_rows {
    let waza = match row.get(0) {
      Some(Some(s)) => s
      _ => continue
    }
    let ty = match row.get(1) {
      Some(Some(s)) => s
      _ => continue
    }
    type_map[waza] = ty
  }
  let rows = match @db.query_binds(
      db,
      "SELECT id, globalNo, form, region, mega_evolution, gigantamax, pokedex, conditions, waza FROM local_pokedex_waza WHERE version = 'Champions' ORDER BY rowid",
      [],
    ) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  if rows.is_empty() {
    return Ok(
      "No Champions rows in local_pokedex_waza — assuming already normalized.",
    )
  }

  // 挿入順を保った LinkedHashMap 相当が欲しいので、Map + 順序配列で代用する。
  let group_index : Map[String, Int] = Map::new()
  let group_keys : Array[String] = []
  let groups : Array[Array[Array[String?]]] = []
  for row in rows {
    let key = group_key(row)
    match group_index.get(key) {
      Some(i) => groups[i].push(row)
      None => {
        group_index[key] = groups.length()
        group_keys.push(key)
        groups.push([row])
      }
    }
  }

  let mut active = 0
  let mut inactive = 0
  let mut unknown_type = 0
  for gi = 0; gi < groups.length(); gi = gi + 1 {
    let items = groups[gi]
    let seen_closed : Map[String, Bool] = Map::new()
    let mut current_type : String? = None
    let mut cutoff : Int? = None
    for idx = 0; idx < items.length(); idx = idx + 1 {
      let waza = match items[idx].get(8) {
        Some(Some(s)) => s
        _ => continue
      }
      let ty = match type_map.get(waza) {
        Some(t) => t
        None => {
          unknown_type = unknown_type + 1
          continue
        }
      }
      match current_type {
        None => current_type = Some(ty)
        Some(c) =>
          if ty != c {
            seen_closed[c] = true
            current_type = Some(ty)
            match seen_closed.get(ty) {
              Some(true) => {
                cutoff = Some(idx)
                break
              }
              _ => ()
            }
          }
      }
    }
    for idx = 0; idx < items.length(); idx = idx + 1 {
      let is_inactive = match cutoff {
        Some(c) => idx >= c
        None => false
      }
      let state = if is_inactive { "inactive" } else { "active" }
      if is_inactive {
        inactive = inactive + 1
      } else {
        active = active + 1
      }
      let r = items[idx]
      match @db.exec_binds(
          db,
          "INSERT INTO champions_learnset (id, globalNo, form, region, mega_evolution, gigantamax, pokedex, conditions, waza, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [
            cell_bind(r, 0),
            cell_bind(r, 1),
            cell_bind(r, 2),
            cell_bind(r, 3),
            cell_bind(r, 4),
            cell_bind(r, 5),
            cell_bind(r, 6),
            cell_bind(r, 7),
            cell_bind(r, 8),
            @db.BindText(state),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    }
  }
  match @db.exec(db, "DELETE FROM local_pokedex_waza WHERE version = 'Champions'") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // group_keys intentionally unused; kept to make the LinkedHashMap-like
  // intent visible to readers even if iteration order is derived from the
  // `groups` array itself.
  let _ = group_keys
  Ok(
    "Migrated " +
    (active + inactive).to_string() +
    " rows (active=" +
    active.to_string() +
    ", inactive=" +
    inactive.to_string() +
    ", unknown_type=" +
    unknown_type.to_string() +
    ")",
  )
}

///|
/// グループ化キー: (globalNo, form, region, mega_evolution, gigantamax)
/// を U+001F (unit separator) 区切りで join。NULL 列は空文字扱いで
/// 衝突しない。
fn group_key(row : Array[String?]) -> String {
  let sep = "\u{001F}"
  cell_str(row, 1) +
  sep +
  cell_str(row, 2) +
  sep +
  cell_str(row, 3) +
  sep +
  cell_str(row, 4) +
  sep +
  cell_str(row, 5)
}

///|
fn cell_str(row : Array[String?], idx : Int) -> String {
  match row.get(idx) {
    Some(Some(s)) => s
    _ => ""
  }
}

///|
fn cell_bind(row : Array[String?], idx : Int) -> @db.BindValue {
  match row.get(idx) {
    Some(Some(s)) => @db.BindText(s)
    _ => @db.BindNull
  }
}
