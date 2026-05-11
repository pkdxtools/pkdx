///|
/// 性別違いポケモン (M base / F differentiated) の M base 側に
/// `{base}（オス）` / `{base} (Male)` alias を pokedex_name へ投入する。
///
/// Problem: 011_form_name_aliases は base id (`_00000000_0_000_0`) を skip
/// するため、F form だけ `イダイトウ（メス）` / `Basculegion (Female)` の
/// 別名が生成され、M base 側は `イダイトウ` / `Basculegion` のままになる。
/// ステ/タイプ/特性が M/F で異なる種では F だけ「（メス）」付きで M は素の
/// 名前という非対称が発生し、`pkdx query "イダイトウ（オス）"` が
/// "Pokemon not found" になる。
///
/// 対象判定 (011 と同条件):
///   - 同 globalNo に jpn `pokedex_form.form='オスのすがた'` (M base) と
///     `'メスのすがた'` (F differentiated) の両方が存在
///   - status / type / ability の EXCEPT 比較で M id と F id に差がある
///     (= 011 が cosmetic と判定しなかった = F 側に既に「（メス）」alias
///      が入っている種)
///
/// 投入:
///   - M base id (`{gno}_00000000_0_000_0`) に jpn `{base}（オス）` と
///     eng `{base} (Male)` を新規 INSERT
///   - form / region は 011 と同様 local_pokedex_status の値
///     (SV/LegendsArceus 行: `オスのすがた` / `Male` 相当、Champions 行は空)
///   - pne 自己結合が成立するよう jpn / eng で同じ form / region を使う
///   - 011 が既に作った F 側 `{base}（メス）` 行はそのまま
///
/// 該当現状 (Gen9 時点): 0876 イエッサン / 0902 イダイトウ / 0916 パフュートン
/// (ステ差) と 0678 ニャオニクス (特性差) の 4 種、4 行 inserted (jpn+eng × 4)。
///
/// Resync 安全性: 先頭で `pokedex_name.name LIKE '%（オス）' OR LIKE '% (Male)'`
/// を一括 DELETE する。これらの suffix は本 migration 以外で使われない。
pub fn run_007(db : @db.Db, _repo_root : String) -> Result[String, String] {
  match @db.exec(
      db,
      "DELETE FROM pokedex_name WHERE name LIKE '%（オス）' OR name LIKE '% (Male)'",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let male_form_jpn = "オスのすがた"
  let female_form_jpn = "メスのすがた"
  let male_id_suffix = "_00000000_0_000_0"
  let female_id_suffix = "_00000001_0_000_0"
  let candidates_sql =
    #|SELECT DISTINCT pf.globalNo
    #|FROM pokedex_form pf
    #|WHERE pf.language = 'jpn' AND pf.form = ?
    #|  AND EXISTS (
    #|    SELECT 1 FROM pokedex_form pf2
    #|    WHERE pf2.language = 'jpn' AND pf2.form = ? AND pf2.globalNo = pf.globalNo
    #|  )
    #|ORDER BY pf.globalNo
  let rows = match @db.query_binds(
      db,
      candidates_sql,
      [@db.BindText(male_form_jpn), @db.BindText(female_form_jpn)],
    ) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  let mut inserted = 0
  let mut skipped_cosmetic = 0
  let mut skipped_no_base = 0
  let mut skipped_other = 0
  for row in rows {
    let gno = match row.get(0) {
      Some(Some(s)) => s
      _ => continue
    }
    let male_id = gno + male_id_suffix
    let female_id = gno + female_id_suffix
    let cosmetic = match compare_battle_data(db, male_id, female_id) {
      Err(e) => return Err(e)
      Ok(b) => b
    }
    if cosmetic {
      skipped_cosmetic = skipped_cosmetic + 1
      continue
    }
    let (lp_form, lp_region) = match fetch_form_region(db, male_id) {
      Err(e) => return Err(e)
      Ok(pair) => pair
    }
    // M alias を 1 種につき jpn / eng 両方投入
    for lang in ["jpn", "eng"] {
      let base_name = match fetch_base_name(db, gno, lang) {
        Err(e) => return Err(e)
        Ok(n) => n
      }
      if base_name.length() == 0 {
        skipped_no_base = skipped_no_base + 1
        continue
      }
      let form_label = match fetch_form_label(db, male_id, lang) {
        Err(e) => return Err(e)
        Ok(s) => s
      }
      if form_label.length() == 0 {
        skipped_no_base = skipped_no_base + 1
        continue
      }
      let display_alias = compose_alias(form_label, base_name, lang)
      if display_alias.length() == 0 || display_alias == base_name {
        skipped_other = skipped_other + 1
        continue
      }
      let (form_col, region_col) = if lp_region.length() == 0 {
        (@db.text_or_null(lp_form), @db.BindNull)
      } else {
        (@db.BindNull, @db.text_or_null(lp_region))
      }
      match @db.exec_binds(
          db,
          "INSERT INTO pokedex_name (id, globalNo, form, region, mega_evolution, gigantamax, language, name) VALUES (?, ?, ?, ?, NULL, NULL, ?, ?)",
          [
            @db.BindText(male_id),
            @db.BindText(gno),
            form_col,
            region_col,
            @db.BindText(lang),
            @db.BindText(display_alias),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "gender male-base aliases: " +
    inserted.to_string() +
    " inserted; skipped " +
    skipped_cosmetic.to_string() +
    " cosmetic, " +
    skipped_no_base.to_string() +
    " no-base, " +
    skipped_other.to_string() +
    " other",
  )
}

///|
/// 指定 id / language の `pokedex_form.form` を返す (jpn なら 'オスのすがた'、
/// eng なら 'Male' 等)。compose_alias へ渡す原料。
fn fetch_form_label(
  db : @db.Db,
  id : String,
  lang : String,
) -> Result[String, String] {
  let sql = "SELECT form FROM pokedex_form WHERE id = ? AND language = ? LIMIT 1"
  match @db.query_binds(
      db,
      sql,
      [@db.BindText(id), @db.BindText(lang)],
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
