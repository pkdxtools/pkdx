/// Search result item.
pub struct SearchResult {
  pub global_no : String
  pub name_ja : String
  pub type1 : String
  pub type2 : String
  pub hp : Int
  pub atk : Int
  pub def_ : Int
  pub spa : Int
  pub spd : Int
  pub spe : Int
  pub bst : Int
} derive(Show)

/// Search Pokemon by type with optional speed minimum.
pub fn search_by_type(
  db : Db,
  type1 : String,
  type2 : String,
  min_speed : Int,
  version : String
) -> Result[Array[SearchResult], String] {
  let type_cond = if type2.length() > 0 {
    "AND ((t.type1 = ? AND t.type2 = ?) OR (t.type1 = ? AND t.type2 = ?))"
  } else {
    "AND (t.type1 = ? OR t.type2 = ?)"
  }
  let sql =
    "SELECT p.globalNo, MIN(pn.name) AS name_ja, t.type1, t.type2, s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed, (s.hp + s.attack + s.defense + s.special_attack + s.special_defense + s.speed) AS bst FROM pokedex p JOIN local_pokedex_type t ON p.globalNo = t.globalNo AND t.version = ? JOIN local_pokedex_status s ON p.globalNo = s.globalNo AND s.version = ? JOIN pokedex_name pn ON p.globalNo = pn.globalNo AND pn.language = 'jpn' AND COALESCE(pn.form, '') = '' AND COALESCE(pn.region, '') = '' AND COALESCE(pn.mega_evolution, '') = '' AND COALESCE(pn.gigantamax, '') = '' WHERE COALESCE(p.form, '') = '' AND COALESCE(p.region, '') = '' AND COALESCE(p.mega_evolution, '') = '' AND COALESCE(p.gigantamax, '') = '' " +
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
