///|
/// champions.db.pokemon_name に対し、フォーム別 / 性別別の合成 alias を
/// 投入する。pokedex.db 側の m006_form_name_aliases / m007_gender_symbol_aliases
/// と同じ役割で、原種引きから 2 手目で `{species}（{form}）` 表記の
/// クエリを成立させるためのもの。Champions のマスターデータは champout
/// 由来で「{X}のすがた」「メスのすがた」など form 名が globalNo を跨いで
/// 重複するため、合成 alias がないと別 globalNo の同名 form が誤ヒットする。
///
/// 投入ルール:
///   1. 同 globalNo に "メスのすがた" form がある場合、base 行 (M) と
///      F 行に gender alias を入れる:
///        - base id: `{species}（オス）`
///        - F id   : `{species}（メス）`
///   2. form 名が "{X}のすがた" で終わる (gender 以外) 場合、
///      その id に `{species}（{X}）` alias を入れる
///        - 例: "アローラのすがた" → "ライチュウ（アローラ）"
///        - 例: "パルデアのすがた・コンバットしゅ" → suffix 剥ぎ後
///              "パルデア・コンバットしゅ" → "ケンタロス（パルデア・コンバットしゅ）"
///
/// pokemon_name の PK は `(id, language, name)` なので 1 つの id に複数の
/// alias 行を持てる。`INSERT OR IGNORE` で再適用時の重複を防止する。
pub fn run_013(db : @db.Db, _repo_root : String) -> Result[String, String] {
  // species map: global_no → base 行の name
  let species_map : Map[String, String] = Map::new()
  let species_rows = match
    @db.query(
      db,
      "SELECT p.global_no, pn.name FROM pokemon p JOIN pokemon_name pn ON p.id = pn.id AND pn.language = 'jpn' WHERE p.form = ''",
      [],
    ) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  for i = 0; i < species_rows.length(); i = i + 1 {
    let row = species_rows[i]
    species_map[row[0]] = row[1]
  }
  let mut inserted = 0
  // Step 1: gender aliases (M base / F differentiated)
  let f_rows = match
    @db.query(
      db,
      "SELECT p.id, p.global_no FROM pokemon p WHERE p.form = 'メスのすがた' ORDER BY p.global_no",
      [],
    ) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  for i = 0; i < f_rows.length(); i = i + 1 {
    let f_id = f_rows[i][0]
    let gn = f_rows[i][1]
    let species = match species_map.get(gn) {
      Some(s) => s
      None => continue
    }
    let base_rows = match
      @db.query_binds(
        db,
        "SELECT id FROM pokemon WHERE global_no = ? AND form = '' LIMIT 1",
        [@db.BindText(gn)],
      ) {
      Err(e) => return Err(e)
      Ok(r) => r
    }
    if base_rows.length() == 0 {
      continue
    }
    let base_id = match base_rows[0][0] {
      Some(s) => s
      None => continue
    }
    let male_alias = species + "（オス）"
    let female_alias = species + "（メス）"
    match
      @db.exec_binds(
        db,
        "INSERT OR IGNORE INTO pokemon_name (id, language, name) VALUES (?, 'jpn', ?)",
        [@db.BindText(base_id), @db.BindText(male_alias)],
      ) {
      Err(e) => return Err(e)
      Ok(_) => inserted = inserted + 1
    }
    match
      @db.exec_binds(
        db,
        "INSERT OR IGNORE INTO pokemon_name (id, language, name) VALUES (?, 'jpn', ?)",
        [@db.BindText(f_id), @db.BindText(female_alias)],
      ) {
      Err(e) => return Err(e)
      Ok(_) => inserted = inserted + 1
    }
  }
  // Step 2: "{X}のすがた" suffix → species（X）合成 alias
  let suffix = "のすがた"
  let r_rows = match
    @db.query(
      db,
      "SELECT p.id, p.global_no, p.form FROM pokemon p WHERE p.form LIKE '%のすがた%' AND p.form != 'メスのすがた' ORDER BY p.id",
      [],
    ) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  for i = 0; i < r_rows.length(); i = i + 1 {
    let id = r_rows[i][0]
    let gn = r_rows[i][1]
    let form = r_rows[i][2]
    let species = match species_map.get(gn) {
      Some(s) => s
      None => continue
    }
    let stripped = strip_first_occurrence(form, suffix)
    if stripped.length() == 0 {
      continue
    }
    let alias = species + "（" + stripped + "）"
    match
      @db.exec_binds(
        db,
        "INSERT OR IGNORE INTO pokemon_name (id, language, name) VALUES (?, 'jpn', ?)",
        [@db.BindText(id), @db.BindText(alias)],
      ) {
      Err(e) => return Err(e)
      Ok(_) => inserted = inserted + 1
    }
  }
  Ok("Inserted " + inserted.to_string() + " form aliases")
}

///|
/// `s` から `needle` の最初の出現を取り除く。`needle` が見つからなければ
/// 空文字を返す (caller は length() で判定して skip する)。
/// 例: strip_first_occurrence("パルデアのすがた・コンバットしゅ", "のすがた")
///     → "パルデア・コンバットしゅ"
fn strip_first_occurrence(s : String, needle : String) -> String {
  let n = s.length()
  let m = needle.length()
  if m == 0 || n < m {
    return ""
  }
  let mut idx = -1
  for i = 0; i + m <= n; i = i + 1 {
    let mut match_ = true
    for j = 0; j < m; j = j + 1 {
      if s.unsafe_get(i + j) != needle.unsafe_get(j) {
        match_ = false
        break
      }
    }
    if match_ {
      idx = i
      break
    }
  }
  if idx < 0 {
    return ""
  }
  let head = s.substring(start=0, end=idx)
  let tail = s.substring(start=idx + m, end=n)
  head + tail
}
