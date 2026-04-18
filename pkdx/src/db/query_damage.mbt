///|
/// Look up a move by name (Japanese).
pub fn query_move(
  db : Db,
  move_name : String,
  version : String,
) -> Result[@model.Move, String] {
  let waza_ver = to_waza_version(version)
  let sql =
    #|SELECT wl.name, w.type, w.category, w.power, w.accuracy, w.pp,
    #|       COALESCE(mm.priority, 0) AS priority,
    #|       COALESCE(mm.stat_effects_json, '[]') AS stat_effects_json,
    #|       COALESCE(mm.ailment_ja, '') AS ailment_ja,
    #|       COALESCE(mm.ailment_chance, 100) AS ailment_chance
    #|FROM local_waza_language wl
    #|JOIN local_waza w ON wl.waza = w.waza AND w.version = ?
    #|LEFT JOIN move_meta mm ON mm.name_ja = wl.name
    #|WHERE wl.version = ? AND wl.language = 'jpn' AND wl.name = ?
    #|LIMIT 1
  let rows = match query(db, sql, [waza_ver, waza_ver, move_name]) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if rows.length() == 0 {
    return Err("Move not found: " + move_name)
  }
  let r = rows[0]
  let priority = if r.length() > 6 { parse_int(r[6]) } else { 0 }
  let stat_effects = if r.length() > 7 {
    parse_stat_effects_json(r[7])
  } else {
    []
  }
  let status_effect = if r.length() > 9 {
    parse_status_effect(r[8], r[9])
  } else {
    None
  }
  Ok(@model.Move::{
    name: r[0],
    type_: r[1],
    category: @model.category_from_jp(r[2]),
    power: parse_int(r[3]),
    accuracy: parse_int(r[4]),
    pp: parse_int(r[5]),
    learn_method: "",
    priority,
    stat_effects,
    status_effect,
  })
}
