/// Query a Pokemon by name (Japanese or English).
pub fn query_pokemon(
  db : Db,
  name : String,
  version : String
) -> Result[@model.Pokemon, String] {
  let sql =
    #|SELECT
    #|  pn.globalNo,
    #|  pn.name AS name_ja,
    #|  pne.name AS name_en,
    #|  t.type1, t.type2,
    #|  s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed,
    #|  (s.hp + s.attack + s.defense + s.special_attack + s.special_defense + s.speed) AS bst,
    #|  a.ability1, a.ability2, a.dream_ability
    #|FROM pokedex_name pn
    #|JOIN pokedex_name pne ON pn.globalNo = pne.globalNo
    #|  AND pne.language = 'eng'
    #|  AND COALESCE(pne.form, '') = '' AND COALESCE(pne.region, '') = ''
    #|  AND COALESCE(pne.mega_evolution, '') = '' AND COALESCE(pne.gigantamax, '') = ''
    #|JOIN local_pokedex_type t ON pn.globalNo = t.globalNo
    #|  AND t.version = ?
    #|JOIN local_pokedex_status s ON pn.globalNo = s.globalNo
    #|  AND s.version = ?
    #|JOIN local_pokedex_ability a ON pn.globalNo = a.globalNo
    #|  AND a.version = ?
    #|WHERE COALESCE(pn.form, '') = ''
    #|  AND COALESCE(pn.region, '') = ''
    #|  AND COALESCE(pn.mega_evolution, '') = ''
    #|  AND COALESCE(pn.gigantamax, '') = ''
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
  })
}

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
  if negative { -result } else { result }
}
