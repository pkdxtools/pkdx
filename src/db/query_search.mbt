///|
/// Search result item.
pub(all) struct SearchResult {
  global_no : String
  name_ja : String
  type1 : String
  type2 : String
  hp : Int
  atk : Int
  def_ : Int
  spa : Int
  spd : Int
  spe : Int
  bst : Int
} derive(Show)

///|
/// Search Pokemon by type with optional speed minimum.
///
/// version="champions" は champions.db (新スキーマ) ルートに delegate する。
pub fn search_by_type(
  db : Db,
  type1 : String,
  type2 : String,
  min_speed : Int,
  version : String,
) -> Result[Array[SearchResult], String] {
  if version == "champions" {
    return search_by_type_champions(db, type1, type2, min_speed)
  }
  let type_cond = if type2.length() > 0 {
    "AND ((t.type1 = ? AND t.type2 = ?) OR (t.type1 = ? AND t.type2 = ?))"
  } else {
    "AND (t.type1 = ? OR t.type2 = ?)"
  }
  let sql = "SELECT p.globalNo, MIN(pn.name) AS name_ja, t.type1, t.type2, s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed, (s.hp + s.attack + s.defense + s.special_attack + s.special_defense + s.speed) AS bst FROM pokedex p JOIN local_pokedex_type t ON p.globalNo = t.globalNo AND t.version = ? JOIN local_pokedex_status s ON p.globalNo = s.globalNo AND s.version = ? JOIN pokedex_name pn ON p.globalNo = pn.globalNo AND pn.language = 'jpn' AND COALESCE(pn.form, '') = '' AND COALESCE(pn.region, '') = '' AND COALESCE(pn.mega_evolution, '') = '' AND COALESCE(pn.gigantamax, '') = '' WHERE COALESCE(p.form, '') = '' AND COALESCE(p.region, '') = '' AND COALESCE(p.mega_evolution, '') = '' AND COALESCE(p.gigantamax, '') = '' " +
    type_cond +
    " AND s.speed >= ? GROUP BY p.globalNo ORDER BY bst DESC LIMIT 20"
  let binds : Array[String] = if type2.length() > 0 {
    [version, version, type1, type2, type2, type1, min_speed.to_string()]
  } else {
    [version, version, type1, type1, min_speed.to_string()]
  }
  let rows = match query(db, sql, binds) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let results : Array[SearchResult] = []
  for i = 0; i < rows.length(); i = i + 1 {
    let r = rows[i]
    results.push({
      global_no: r[0],
      name_ja: r[1],
      type1: r[2],
      type2: r[3],
      hp: parse_int(r[4]),
      atk: parse_int(r[5]),
      def_: parse_int(r[6]),
      spa: parse_int(r[7]),
      spd: parse_int(r[8]),
      spe: parse_int(r[9]),
      bst: parse_int(r[10]),
    })
  }
  Ok(results)
}

///|
/// champions.db.pokemon に対する type 検索。base form (form='') のみ。
fn search_by_type_champions(
  db : Db,
  type1 : String,
  type2 : String,
  min_speed : Int,
) -> Result[Array[SearchResult], String] {
  let type_cond = if type2.length() > 0 {
    "AND ((p.type1 = ? AND p.type2 = ?) OR (p.type1 = ? AND p.type2 = ?))"
  } else {
    "AND (p.type1 = ? OR p.type2 = ?)"
  }
  let sql_head =
    #|SELECT p.global_no, MAX(pn.name) AS name_ja, p.type1, p.type2,
    #|       p.hp, p.attack, p.defense, p.special_attack, p.special_defense, p.speed,
    #|       (p.hp + p.attack + p.defense + p.special_attack + p.special_defense + p.speed) AS bst
    #|FROM pokemon p
    #|JOIN pokemon_name pn ON p.id = pn.id AND pn.language = 'jpn'
    #|WHERE p.form = ''
  let sql_tail =
    #|AND p.speed >= ?
    #|GROUP BY p.global_no
    #|ORDER BY bst DESC
    #|LIMIT 20
  let sql = sql_head + " " + type_cond + " " + sql_tail
  let binds : Array[String] = if type2.length() > 0 {
    [type1, type2, type2, type1, min_speed.to_string()]
  } else {
    [type1, type1, min_speed.to_string()]
  }
  let rows = match query(db, sql, binds) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let results : Array[SearchResult] = []
  for i = 0; i < rows.length(); i = i + 1 {
    let r = rows[i]
    results.push({
      global_no: r[0],
      name_ja: r[1],
      type1: r[2],
      type2: r[3],
      hp: parse_int(r[4]),
      atk: parse_int(r[5]),
      def_: parse_int(r[6]),
      spa: parse_int(r[7]),
      spd: parse_int(r[8]),
      spe: parse_int(r[9]),
      bst: parse_int(r[10]),
    })
  }
  Ok(results)
}
