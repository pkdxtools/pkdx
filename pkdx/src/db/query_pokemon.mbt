///|
/// Query a Pokemon by name (Japanese or English).
pub fn query_pokemon(
  db : Db,
  name : String,
  version : String,
) -> Result[@model.Pokemon, String] {
  let sql =
    #|SELECT
    #|  pn.globalNo,
    #|  pn.name AS name_ja,
    #|  pne.name AS name_en,
    #|  t.type1, t.type2,
    #|  s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed,
    #|  (s.hp + s.attack + s.defense + s.special_attack + s.special_defense + s.speed) AS bst,
    #|  a.ability1, a.ability2, a.dream_ability,
    #|  p.weight
    #|FROM pokedex_name pn
    #|JOIN pokedex_name pne ON pn.id = pne.id
    #|  AND pne.language = 'eng'
    #|JOIN local_pokedex_type t ON pn.id = t.id
    #|  AND t.version = ?
    #|JOIN local_pokedex_status s ON pn.id = s.id
    #|  AND s.version = ?
    #|JOIN local_pokedex_ability a ON pn.id = a.id
    #|  AND a.version = ?
    #|JOIN pokedex p ON pn.id = p.id
    #|WHERE COALESCE(pn.form, '') = ''
    #|  AND COALESCE(pn.region, '') = ''
    #|  AND (
    #|    (pn.language = 'jpn' AND pn.name = ?)
    #|    OR (pn.language = 'eng' AND LOWER(pn.name) = LOWER(?))
    #|  )
    #|LIMIT 1
  let rows = match query(db, sql, [version, version, version, name, name]) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if rows.length() == 0 {
    return Err("Pokemon not found: " + name)
  }
  let r = rows[0]
  Ok(@model.Pokemon::{
    global_no: r[0],
    name_ja: r[1],
    name_en: r[2],
    type1: r[3],
    type2: r[4],
    hp: parse_int(r[5]),
    atk: parse_int(r[6]),
    def_: parse_int(r[7]),
    spa: parse_int(r[8]),
    spd: parse_int(r[9]),
    spe: parse_int(r[10]),
    bst: parse_int(r[11]),
    ability1: r[12],
    ability2: r[13],
    dream_ability: r[14],
    weight: parse_double(r[15]),
  })
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
