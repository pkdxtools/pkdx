///|
/// pokedex_name に対しフォーム別の一意な別名を投入する。
///
/// Problem: pokedex_name.name は種族共通の名前しか持たないため、
/// `pkdx query ウォッシュロトム` や `pkdx query 'キュウコン（アローラ）'`
/// が "Pokemon not found" になっていた。形態別名は pokedex_form.form に
/// あるが検索経路は参照していなかった。mega (001 / 002 / 007) と同じ
/// ように、pokedex_name に alias 行を書き込む。
///
/// 方針:
///   - pokedex_form.form が原種名を含む (例: `ウォッシュロトム` ⊃ `ロトム`)
///     ならそのまま別名として使う
///   - 含まない場合は `{species}（{form}）` に合成して一意化
///     (例: `アローラのすがた` → `キュウコン（アローラ）`)
///     `のすがた` / `フォルム` / ` Form(e)` は情報量ゼロなので接尾辞を剥ぐ
///   - 戦闘面で base と完全に同じフォーム (トリミアン毛型・ビビヨン模様・
///     フラベベ花色・Unown 文字・マホイップ flavor 等) は status/type/ability
///     の EXCEPT 比較で cosmetic 判定して除外
///   - mega / gigantamax は out of scope (mega は 001/002/007 済)
///   - base id (`_00000000_0_000_0`) は触らない
///   - pokedex_name.form / region には local_pokedex_status の値を書く
///     (language 非依存なので jpn/eng 両行で揃い、query_pokemon の pne 自己結合
///     が成立する。query_search / query_learners の `COALESCE(pn.form,'')=''`
///     フィルタが初めて機能するようになる)
pub fn run_006(db : @db.Db, _repo_root : String) -> Result[String, String] {
  let langs = ["jpn", "eng"]
  let mut inserted = 0
  let mut updated = 0
  let mut skipped_cosmetic = 0
  let mut skipped_no_stats = 0
  let mut skipped_same = 0
  let mut skipped_no_base = 0
  for lang in langs {
    let rows = match @db.query_binds(
        db,
        "SELECT pf.id, pf.globalNo, pf.form FROM pokedex_form pf WHERE pf.language = ? AND pf.form IS NOT NULL AND pf.form != ''",
        [@db.BindText(lang)],
      ) {
      Err(e) => return Err(e)
      Ok(r) => r
    }
    for row in rows {
      let id = match row.get(0) {
        Some(Some(s)) => s
        _ => continue
      }
      let gno = match row.get(1) {
        Some(Some(s)) => s
        _ => continue
      }
      let form = match row.get(2) {
        Some(Some(s)) => s
        _ => continue
      }
      if is_base_id(id) {
        continue
      }
      let cosmetic = match form_cosmetic(db, id, gno) {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      if cosmetic {
        skipped_cosmetic = skipped_cosmetic + 1
        continue
      }
      let (lp_form, lp_region) = match fetch_form_region(db, id) {
        Ok(pair) => pair
        Err(e) => return Err(e)
      }
      if lp_form.length() == 0 && lp_region.length() == 0 {
        skipped_no_stats = skipped_no_stats + 1
        continue
      }
      let base_name = match fetch_base_name(db, gno, lang) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      if base_name.length() == 0 {
        skipped_no_base = skipped_no_base + 1
        continue
      }
      let alias_name = compose_alias(form, base_name, lang)
      if alias_name.length() == 0 || alias_name == base_name {
        skipped_same = skipped_same + 1
        continue
      }
      let (form_col, region_col) = if lp_region.length() == 0 {
        (@db.text_or_null(lp_form), @db.BindNull)
      } else {
        (@db.BindNull, @db.text_or_null(lp_region))
      }
      let existed = match @db.query_binds(
          db,
          "SELECT 1 FROM pokedex_name WHERE id = ? AND language = ? LIMIT 1",
          [@db.BindText(id), @db.BindText(lang)],
        ) {
        Err(e) => return Err(e)
        Ok(r) => r.length() > 0
      }
      if existed {
        match @db.exec_binds(
            db,
            "UPDATE pokedex_name SET name = ?, form = ?, region = ? WHERE id = ? AND language = ?",
            [
              @db.BindText(alias_name),
              form_col,
              region_col,
              @db.BindText(id),
              @db.BindText(lang),
            ],
          ) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
        updated = updated + 1
      } else {
        match @db.exec_binds(
            db,
            "INSERT INTO pokedex_name (id, globalNo, form, region, mega_evolution, gigantamax, language, name) VALUES (?, ?, ?, ?, NULL, NULL, ?, ?)",
            [
              @db.BindText(id),
              @db.BindText(gno),
              form_col,
              region_col,
              @db.BindText(lang),
              @db.BindText(alias_name),
            ],
          ) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
        inserted = inserted + 1
      }
    }
  }
  Ok(
    "form-name aliases: " +
    inserted.to_string() +
    " inserted, " +
    updated.to_string() +
    " updated; skipped " +
    skipped_cosmetic.to_string() +
    " cosmetic, " +
    skipped_no_stats.to_string() +
    " no-stats, " +
    skipped_no_base.to_string() +
    " no-base, " +
    skipped_same.to_string() +
    " same-as-base",
  )
}

///|
/// base id (末尾 `_00000000_0_000_0`) 判定。
fn is_base_id(id : String) -> Bool {
  let suffix = "_00000000_0_000_0"
  if id.length() < suffix.length() {
    return false
  }
  let start = id.length() - suffix.length()
  for i = 0; i < suffix.length(); i = i + 1 {
    if id[start + i] != suffix[i] {
      return false
    }
  }
  true
}

///|
/// local_pokedex_status / _type / _ability の EXCEPT 比較で、指定 form id と
/// base id の戦闘データが完全一致するか判定する。全テーブルで差分ゼロなら
/// cosmetic (トリミアン毛型・ビビヨン模様 等) と判定して alias 投入から除外。
fn form_cosmetic(
  db : @db.Db,
  form_id : String,
  global_no : String,
) -> Result[Bool, String] {
  compare_battle_data(db, form_id, global_no + "_00000000_0_000_0")
}

///|
/// 任意の 2 つの id (`local_pokedex_*` の主キー) について status / type / ability
/// が全 version で一致するなら true。 form_cosmetic / m012.forms_identical の
/// 共通実装。
///
/// EXCEPT は非対称差なので、片側にしかない version 行があると「差あり」と判定
/// される。 version 揃いのデータに対してのみ「全 version で同一なら一致」が
/// 厳密に成り立つ。
fn compare_battle_data(
  db : @db.Db,
  id_a : String,
  id_b : String,
) -> Result[Bool, String] {
  let stat_sql =
    #|SELECT COUNT(*) FROM (
    #|  SELECT version, hp, attack, defense, special_attack, special_defense, speed
    #|    FROM local_pokedex_status WHERE id = ?
    #|  EXCEPT
    #|  SELECT version, hp, attack, defense, special_attack, special_defense, speed
    #|    FROM local_pokedex_status WHERE id = ?
    #|)
  let type_sql =
    #|SELECT COUNT(*) FROM (
    #|  SELECT version, type1, COALESCE(type2, '')
    #|    FROM local_pokedex_type WHERE id = ?
    #|  EXCEPT
    #|  SELECT version, type1, COALESCE(type2, '')
    #|    FROM local_pokedex_type WHERE id = ?
    #|)
  let ab_sql =
    #|SELECT COUNT(*) FROM (
    #|  SELECT version, COALESCE(ability1, ''), COALESCE(ability2, ''), COALESCE(dream_ability, '')
    #|    FROM local_pokedex_ability WHERE id = ?
    #|  EXCEPT
    #|  SELECT version, COALESCE(ability1, ''), COALESCE(ability2, ''), COALESCE(dream_ability, '')
    #|    FROM local_pokedex_ability WHERE id = ?
    #|)
  for sql in [stat_sql, type_sql, ab_sql] {
    match count_diff(db, sql, id_a, id_b) {
      Err(e) => return Err(e)
      Ok(n) => if n > 0 { return Ok(false) }
    }
  }
  Ok(true)
}

///|
fn count_diff(
  db : @db.Db,
  sql : String,
  a : String,
  b : String,
) -> Result[Int, String] {
  match @db.query_binds(db, sql, [@db.BindText(a), @db.BindText(b)]) {
    Err(e) => Err(e)
    Ok(rows) =>
      if rows.length() == 0 {
        Ok(0)
      } else {
        match rows[0].get(0) {
          Some(Some(s)) => {
            let n = try @strconv.parse_int(s) catch {
              _ => 0
            }
            Ok(n)
          }
          _ => Ok(0)
        }
      }
  }
}

///|
/// id に対応する form / region 列の値 (language 非依存) を
/// local_pokedex_status から取得。mega / gmax 行は除外、form か region の
/// どちらかに値が入っているバージョン行を優先的に返す (Champions では
/// form/region が空のダミー行になるケースがあるため)。
fn fetch_form_region(
  db : @db.Db,
  id : String,
) -> Result[(String, String), String] {
  let sql =
    #|SELECT form, region FROM local_pokedex_status
    #|WHERE id = ?
    #|  AND COALESCE(mega_evolution, '') = ''
    #|  AND COALESCE(gigantamax, '')     = ''
    #|  AND (COALESCE(form, '') != '' OR COALESCE(region, '') != '')
    #|LIMIT 1
  match @db.query_binds(db, sql, [@db.BindText(id)]) {
    Err(e) => Err(e)
    Ok(rows) =>
      if rows.length() == 0 {
        Ok(("", ""))
      } else {
        let row = rows[0]
        let f = match row.get(0) {
          Some(Some(s)) => s
          _ => ""
        }
        let r = match row.get(1) {
          Some(Some(s)) => s
          _ => ""
        }
        Ok((f, r))
      }
  }
}

///|
/// 原種 (base) 行の name を取得。form / region / mega / gmax が全て空な行が
/// 該当する。見つからなければ "" を返す。
fn fetch_base_name(
  db : @db.Db,
  global_no : String,
  lang : String,
) -> Result[String, String] {
  let sql =
    #|SELECT name FROM pokedex_name
    #|WHERE globalNo = ? AND language = ?
    #|  AND COALESCE(form, '')           = ''
    #|  AND COALESCE(region, '')         = ''
    #|  AND COALESCE(mega_evolution, '') = ''
    #|  AND COALESCE(gigantamax, '')     = ''
    #|LIMIT 1
  match @db.query_binds(
      db,
      sql,
      [@db.BindText(global_no), @db.BindText(lang)],
    ) {
    Err(e) => Err(e)
    Ok(rows) =>
      if rows.length() == 0 {
        Ok("")
      } else {
        match rows[0].get(0) {
          Some(Some(s)) => Ok(s)
          _ => Ok("")
        }
      }
  }
}

///|
/// 情報量ゼロの接尾辞 (`のすがた` / `フォルム` / ` Form(e)` トレーリング空白含む)
/// を剥ぐ。どちらも剥いだ結果が空ならそのまま元を返して呼び出し側で skip 判定。
fn strip_noise_suffix(form : String) -> String {
  let mut s = form
  let nosugata = "のすがた"
  let forumu = "フォルム"
  if ends_with(s, nosugata) {
    s = s.substring(start=0, end=s.length() - nosugata.length())
  } else if ends_with(s, forumu) {
    s = s.substring(start=0, end=s.length() - forumu.length())
  } else {
    // " Form" / " Forme" / "Form" / "Forme" (ケース非依存)
    s = strip_trailing_form(s)
  }
  // 末尾空白除去
  while s.length() > 0 && s[s.length() - 1] == ' ' {
    s = s.substring(start=0, end=s.length() - 1)
  }
  s
}

///|
fn ends_with(s : String, suffix : String) -> Bool {
  if s.length() < suffix.length() {
    return false
  }
  let start = s.length() - suffix.length()
  for i = 0; i < suffix.length(); i = i + 1 {
    if s[start + i] != suffix[i] {
      return false
    }
  }
  true
}

///|
/// 末尾 ` Form` / ` Forme` / `Form` / `Forme` をケース非依存で剥ぐ。
fn strip_trailing_form(s : String) -> String {
  let variants = ["Forme", "Form", " Forme", " Form"]
  for v in variants {
    if ends_with_ci(s, v) {
      return s.substring(start=0, end=s.length() - v.length())
    }
  }
  s
}

///|
fn ends_with_ci(s : String, suffix : String) -> Bool {
  if s.length() < suffix.length() {
    return false
  }
  let start = s.length() - suffix.length()
  for i = 0; i < suffix.length(); i = i + 1 {
    if ascii_lower_u16(s[start + i]) != ascii_lower_u16(suffix[i]) {
      return false
    }
  }
  true
}

///|
fn ascii_lower_u16(c : UInt16) -> UInt16 {
  // 'A'..'Z' なら +0x20 して小文字化、その他はそのまま。
  let a : UInt16 = 0x41
  let z : UInt16 = 0x5A
  let shift : UInt16 = 0x20
  if c >= a && c <= z {
    c + shift
  } else {
    c
  }
}

///|
/// 別名を生成。
/// - form が原種名を含むなら verbatim (ウォッシュロトム)
/// - 含まないなら情報量ゼロな接尾辞を剥いで "{species}（{form}）" (jpn) /
///   "{species} ({form})" (eng) に合成
/// 合成結果が空 / base_name と同じなら "" を返す
fn compose_alias(form : String, base_name : String, lang : String) -> String {
  if contains(form, base_name) {
    return form
  }
  let stripped = strip_noise_suffix(form)
  if stripped.length() == 0 {
    return ""
  }
  if lang == "jpn" {
    base_name + "（" + stripped + "）"
  } else {
    base_name + " (" + stripped + ")"
  }
}

///|
fn contains(s : String, needle : String) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if s.length() < needle.length() {
    return false
  }
  let limit = s.length() - needle.length() + 1
  for i = 0; i < limit; i = i + 1 {
    let mut ok = true
    for j = 0; j < needle.length() && ok; j = j + 1 {
      if s[i + j] != needle[j] {
        ok = false
      }
    }
    if ok {
      return true
    }
  }
  false
}
