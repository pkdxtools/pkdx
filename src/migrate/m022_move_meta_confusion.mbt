///|
/// こんらん確率 (`confusion_chance`) を move_meta に投入する。m019 と同じ冪等の
/// 書き方で、列は ensure_column、既存行は confusion 列だけ上書き、無い行は INSERT。
///
/// 出典は Champions 本文 `champout/rom-txt/jpn/wazainfo_syn.json`。
/// - 100%: あやしいひかり (WAZAINFO_SYN_109) / てんしのキッス (186) /
///   ばくれつパンチ (223)。本文は「相手をこんらん状態にする。」で百分率を書かない。
///   変化技の必中状態異常と同じく 100 とする。ばくれつパンチはダメージ技だが
///   同じく百分率が無く、追加効果の必中として 100。
/// - いばる (207) / おだてる (260): 能力上昇とこんらん。上昇は既存の stat_effects。
///   ここはこんらん 100 だけ足す。
/// - フラフラダンス (298): 「自分以外の場の全員」。シングルでは相手 1 体。100。
/// - みずのはどう (352) 20% / ぼうふう (542) 30% / かかとおとし (853) 30%。
///
/// 入れない:
/// - みわくのボイス (914): そのターンに能力が上がった相手だけ。追跡が無い。
/// - あばれる / げきりん / はなびらのまい: 本文はあばれ状態のあとこんらん。
///   あばれ自体が未モデル。
pub fn run_022(db : @db.Db, repo_root : String) -> Result[String, String] {
  match
    ensure_column(
      db,
      "move_meta",
      "confusion_chance",
      "ALTER TABLE move_meta ADD COLUMN confusion_chance INTEGER NOT NULL DEFAULT 0",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let path = repo_root + "/pkdx_patch/022_move_meta_confusion/data.json"
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
      _ => return Err("confusion entry is not an object")
    }
    let name = str_field(entry, "name")
    let confusion_chance = int_field(entry, "confusion_chance", 0)
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
          "UPDATE move_meta SET confusion_chance = ? WHERE name_ja = ?",
          [@db.BindInt(confusion_chance), @db.BindText(name)],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      updated = updated + 1
    } else {
      match
        @db.exec_binds(
          db,
          "INSERT INTO move_meta (name_ja, priority, stat_effects_json, confusion_chance) VALUES (?, 0, '[]', ?)",
          [@db.BindText(name), @db.BindInt(confusion_chance)],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "confusion rows; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}
