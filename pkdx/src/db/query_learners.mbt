///|
/// Query Pokemon that can learn a given move (level-up + TM).
/// For champions version, reads from champions_learnset; other versions
/// use local_pokedex_waza + local_pokedex_waza_machine.
/// include_inactive: when true and version=champions, also includes
/// moves marked state='inactive' (revoked in Champions).
pub fn query_learners(
  db : Db,
  move_name : String,
  version : String,
  include_inactive~ : Bool = false,
) -> Result[Array[SearchResult], String] {
  if version == "champions" {
    query_learners_champions(db, move_name, include_inactive)
  } else {
    query_learners_legacy(db, move_name, version)
  }
}

///|
/// champions.db (新スキーマ: learnset + pokemon + pokemon_name) を直接読む。
/// `include_inactive` は champout 由来データに inactive 概念がないため
/// 無視する。base form (pokemon.form='') のみを返す現行挙動を維持。
fn query_learners_champions(
  db : Db,
  move_name : String,
  _include_inactive : Bool,
) -> Result[Array[SearchResult], String] {
  let sql =
    #|SELECT p.global_no, MAX(pn.name) AS name_ja,
    #|       p.type1, p.type2,
    #|       p.hp, p.attack, p.defense, p.special_attack, p.special_defense, p.speed,
    #|       (p.hp + p.attack + p.defense + p.special_attack + p.special_defense + p.speed) AS bst
    #|FROM learnset l
    #|JOIN pokemon p ON l.id = p.id
    #|JOIN pokemon_name pn ON p.id = pn.id AND pn.language = 'jpn'
    #|WHERE l.waza = ? AND p.form = ''
    #|GROUP BY p.global_no
    #|ORDER BY bst DESC
  collect_learners_rows(db, sql, [move_name])
}

///|
fn query_learners_legacy(
  db : Db,
  move_name : String,
  version : String,
) -> Result[Array[SearchResult], String] {
  let waza_ver = to_waza_version(version)
  let sql =
    #|WITH learners AS (
    #|  SELECT pw.globalNo
    #|  FROM local_waza_language wl
    #|  JOIN local_pokedex_waza pw ON wl.waza = pw.waza AND pw.version = ?
    #|  WHERE wl.language = 'jpn' AND wl.name = ? AND wl.version = ?
    #|    AND COALESCE(pw.form, '') = '' AND COALESCE(pw.region, '') = ''
    #|  UNION ALL
    #|  SELECT pm.globalNo
    #|  FROM local_waza_language wl
    #|  JOIN local_waza_machine wm ON wl.waza = wm.machine_no AND wm.version = ?
    #|  JOIN local_pokedex_waza_machine pm ON wm.waza = pm.machine_no AND pm.version = ?
    #|  WHERE wl.language = 'jpn' AND wl.name = ? AND wl.version = ?
    #|    AND COALESCE(pm.form, '') = '' AND COALESCE(pm.region, '') = ''
    #|    AND COALESCE(pm.mega_evolution, '') = '' AND COALESCE(pm.gigantamax, '') = ''
    #|)
    #|SELECT l.globalNo, MIN(pn.name) AS name_ja,
    #|       t.type1, t.type2,
    #|       s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed,
    #|       (s.hp + s.attack + s.defense + s.special_attack + s.special_defense + s.speed) AS bst
    #|FROM learners l
    #|JOIN pokedex p ON l.globalNo = p.globalNo
    #|JOIN local_pokedex_type t ON p.globalNo = t.globalNo AND t.version = ?
    #|JOIN local_pokedex_status s ON p.globalNo = s.globalNo AND s.version = ?
    #|JOIN pokedex_name pn ON p.globalNo = pn.globalNo AND pn.language = 'jpn'
    #|  AND COALESCE(pn.form, '') = '' AND COALESCE(pn.region, '') = ''
    #|  AND COALESCE(pn.mega_evolution, '') = '' AND COALESCE(pn.gigantamax, '') = ''
    #|WHERE COALESCE(p.form, '') = '' AND COALESCE(p.region, '') = ''
    #|  AND COALESCE(p.mega_evolution, '') = '' AND COALESCE(p.gigantamax, '') = ''
    #|GROUP BY l.globalNo
    #|ORDER BY bst DESC
  let binds = [
    waza_ver, move_name, waza_ver, waza_ver, waza_ver, move_name, waza_ver,
    version, version,
  ]
  collect_learners_rows(db, sql, binds)
}

///|
fn collect_learners_rows(
  db : Db,
  sql : String,
  binds : Array[String],
) -> Result[Array[SearchResult], String] {
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
