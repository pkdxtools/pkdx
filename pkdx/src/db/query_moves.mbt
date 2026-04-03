/// Query all moves a Pokemon can learn (level-up + TM).
pub fn query_moves(
  db : Db,
  global_no : String,
  version : String
) -> Result[Array[@model.Move], String] {
  let waza_ver = to_waza_version(version)
  let gno = normalize_global_no(global_no)
  let sql =
    #|SELECT DISTINCT wl.name AS move_name, w.type, w.category,
    #|       w.power, w.accuracy, w.pp, pw.conditions AS learn_method
    #|FROM local_pokedex_waza pw
    #|JOIN local_waza w ON pw.waza = w.waza AND w.version = ?
    #|JOIN local_waza_language wl ON pw.waza = wl.waza
    #|  AND wl.version = ? AND wl.language = 'jpn'
    #|WHERE pw.globalNo = ? AND pw.version = ?
    #|UNION
    #|SELECT DISTINCT wl.name AS move_name, w.type, w.category,
    #|       w.power, w.accuracy, w.pp, 'TM' AS learn_method
    #|FROM local_pokedex_waza_machine pm
    #|JOIN local_waza_machine wm ON pm.machine_no = wm.waza AND wm.version = ?
    #|JOIN local_waza w ON wm.machine_no = w.waza AND w.version = ?
    #|JOIN local_waza_language wl ON w.waza = wl.waza
    #|  AND wl.version = ? AND wl.language = 'jpn'
    #|WHERE pm.globalNo = ? AND pm.version = ?
    #|  AND COALESCE(pm.form, '') = '' AND COALESCE(pm.region, '') = ''
    #|ORDER BY power DESC
  let binds = [
    waza_ver, waza_ver, gno, waza_ver, waza_ver, waza_ver, waza_ver, gno,
    waza_ver,
  ]
  let rows = match query(db, sql, binds) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let moves : Array[@model.Move] = []
  for i = 0; i < rows.length(); i = i + 1 {
    let r = rows[i]
    moves.push(@model.Move::{
      name: r[0],
      type_: r[1],
      category: r[2],
      power: parse_int(r[3]),
      accuracy: parse_int(r[4]),
      pp: parse_int(r[5]),
      learn_method: r[6],
    })
  }
  Ok(moves)
}
