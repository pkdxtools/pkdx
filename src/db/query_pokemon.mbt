///|
/// Query a Pokemon by name (Japanese or English).
///
/// version="champions" のときは新スキーマ (champions.db.pokemon /
/// pokemon_name) ルートに delegate する。それ以外の version は従来の
/// pokedex.db ベースの JOIN を使う。
pub fn query_pokemon(
  db : Db,
  name : String,
  version : String,
) -> Result[@model.Pokemon, String] {
  if version == "champions" {
    return query_champions_pokemon(db, name)
  }
  // pokedex_name には base 行に加えて、011_form_name_aliases / 012_gender_symbol_aliases
  // で生成されたフォーム/性別別名 (ウォッシュロトム / キュウコン（アローラ） /
  // イダイトウ（オス） / Basculegion (Male) 等) が入っている。alias 行は
  // form / region が非空 (012 は M base id を共有するが form='オスのすがた' で
  // 区別される) なので、form / region による絞り込みは行わず WHERE で名前一致
  // させる。
  //
  // pn は jpn/eng どちらの行にもマッチしうるため、name_ja は必ず jpn 行から
  // 取れるよう pnj 自己結合を追加する。eng 引き (例: `Basculegion (Male)`) で
  // も name_ja が日本語名 (`イダイトウ（オス）`) になることを保証する。
  let sql =
    #|SELECT
    #|  pn.id,
    #|  pn.globalNo,
    #|  pnj.name AS name_ja,
    #|  pne.name AS name_en,
    #|  t.type1, t.type2,
    #|  s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed,
    #|  (s.hp + s.attack + s.defense + s.special_attack + s.special_defense + s.speed) AS bst,
    #|  a.ability1, a.ability2, a.dream_ability,
    #|  p.weight,
    #|  COALESCE(pn.form, ''), COALESCE(pn.region, ''),
    #|  COALESCE(pn.mega_evolution, ''), COALESCE(pn.gigantamax, '')
    #|FROM pokedex_name pn
    #|JOIN pokedex_name pnj ON pn.id = pnj.id
    #|  AND COALESCE(pnj.form, '')           = COALESCE(pn.form, '')
    #|  AND COALESCE(pnj.region, '')         = COALESCE(pn.region, '')
    #|  AND COALESCE(pnj.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND pnj.language = 'jpn'
    #|JOIN pokedex_name pne ON pn.id = pne.id
    #|  AND COALESCE(pne.form, '')           = COALESCE(pn.form, '')
    #|  AND COALESCE(pne.region, '')         = COALESCE(pn.region, '')
    #|  AND COALESCE(pne.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND pne.language = 'eng'
    #|JOIN local_pokedex_type t ON pn.id = t.id
    #|  AND COALESCE(t.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND t.version = ?
    #|JOIN local_pokedex_status s ON pn.id = s.id
    #|  AND COALESCE(s.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND s.version = ?
    #|JOIN local_pokedex_ability a ON pn.id = a.id
    #|  AND COALESCE(a.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND a.version = ?
    #|JOIN pokedex p ON pn.id = p.id
    #|WHERE (pn.language = 'jpn' AND pn.name = ?)
    #|   OR (pn.language = 'eng' AND LOWER(pn.name) = LOWER(?))
    #|LIMIT 1
  let rows = match query(db, sql, [version, version, version, name, name]) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if rows.length() == 0 {
    return Err("Pokemon not found: " + name)
  }
  let r = rows[0]
  let id = r[0]
  let global_no = r[1]
  // forms[] は「原種 (base) 行を直接引いた時」だけ埋める (discoverability)。
  // id 末尾だけで判定すると 012 の M 性別 alias (M base id を共有) も base 扱い
  // になってしまうため、マッチした pn 行の form/region/mega/gmax が全て空である
  // ことで base 行を判定する。
  let is_base_row = r[17].length() == 0 &&
    r[18].length() == 0 &&
    r[19].length() == 0 &&
    r[20].length() == 0
  let forms : Array[String] = if is_base_row {
    query_forms(db, global_no, id, version)
  } else {
    []
  }
  Ok(@model.Pokemon::{
    global_no,
    name_ja: r[2],
    name_en: r[3],
    type1: r[4],
    type2: r[5],
    hp: parse_int(r[6]),
    atk: parse_int(r[7]),
    def_: parse_int(r[8]),
    spa: parse_int(r[9]),
    spd: parse_int(r[10]),
    spe: parse_int(r[11]),
    bst: parse_int(r[12]),
    ability1: r[13],
    ability2: r[14],
    dream_ability: r[15],
    weight: parse_double(r[16]),
    forms,
  })
}

///|
/// 指定 globalNo の、引いた id 以外で該当 version に存在するフォーム alias を返す。
/// 011_form_name_aliases migration によって各 alias は語彙的に一意 (例:
/// "ウォッシュロトム", "キュウコン（アローラ）") なのでそのまま `pkdx query` の
/// 引数として使える。
fn query_forms(
  db : Db,
  global_no : String,
  self_id : String,
  version : String,
) -> Array[String] {
  let sql =
    #|SELECT DISTINCT pn.name
    #|FROM pokedex_name pn
    #|JOIN local_pokedex_status s ON pn.id = s.id
    #|  AND COALESCE(s.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND s.version = ?
    #|WHERE pn.globalNo = ?
    #|  AND pn.language = 'jpn'
    #|  AND pn.id != ?
    #|ORDER BY pn.id
  match query(db, sql, [version, global_no, self_id]) {
    Ok(rows) => {
      let out : Array[String] = []
      for i = 0; i < rows.length(); i = i + 1 {
        out.push(rows[i][0])
      }
      out
    }
    Err(_) => []
  }
}

///|
/// DBの weight カラムは "460.0" や "-" などの文字列。
/// "-" や解析不能値は 0.0 を返す。
fn parse_double(s : String) -> Double {
  if s.length() == 0 {
    return 0.0
  }
  let mut i = 0
  let mut negative = false
  if s[i] == '-' {
    // 単独の "-" はデータ欠損マーカー
    if s.length() == 1 {
      return 0.0
    }
    negative = true
    i = i + 1
  }
  let mut int_part = 0.0
  while i < s.length() && s[i] != '.' {
    let c = s[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      int_part = int_part * 10.0 + (c - 0x30).to_double()
    }
    i = i + 1
  }
  let mut frac = 0.0
  let mut div = 1.0
  if i < s.length() && s[i] == '.' {
    i = i + 1
    while i < s.length() {
      let c = s[i].to_int()
      if c >= 0x30 && c <= 0x39 {
        frac = frac * 10.0 + (c - 0x30).to_double()
        div = div * 10.0
      }
      i = i + 1
    }
  }
  let result = int_part + frac / div
  if negative {
    -result
  } else {
    result
  }
}

///|
fn parse_int(s : String) -> Int {
  let mut result = 0
  let mut i = 0
  let mut negative = false
  if i < s.length() && s[i] == '-' {
    negative = true
    i = i + 1
  }
  while i < s.length() {
    let c = s[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      result = result * 10 + (c - 0x30)
    }
    i = i + 1
  }
  if negative {
    -result
  } else {
    result
  }
}
