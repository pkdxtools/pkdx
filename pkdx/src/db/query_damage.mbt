/// Look up a move by name (Japanese).
pub fn query_move(
  db : Db,
  move_name : String,
  version : String
) -> Result[@model.Move, String] {
  let waza_ver = to_waza_version(version)
  let sql =
    #|SELECT wl.name, w.type, w.category, w.power, w.accuracy, w.pp
    #|FROM local_waza_language wl
    #|JOIN local_waza w ON wl.waza = w.waza AND w.version = ?
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
  Ok(@model.Move::{
    name: r[0],
    type_: r[1],
    category: r[2],
    power: parse_int(r[3]),
    accuracy: parse_int(r[4]),
    pp: parse_int(r[5]),
    learn_method: "",
  })
}
