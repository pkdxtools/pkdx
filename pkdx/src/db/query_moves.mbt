///|
/// Query all moves a Pokemon can learn (level-up + TM).
/// For champions version, reads from champions_learnset; other versions
/// use local_pokedex_waza + local_pokedex_waza_machine.
pub fn query_moves(
  db : Db,
  global_no : String,
  version : String,
  include_inactive~ : Bool = false,
) -> Result[Array[@model.Move], String] {
  if version == "champions" {
    query_moves_champions(db, global_no, include_inactive)
  } else {
    query_moves_legacy(db, global_no, version)
  }
}

///|
fn query_moves_champions(
  db : Db,
  global_no : String,
  include_inactive : Bool,
) -> Result[Array[@model.Move], String] {
  let gno = normalize_global_no(global_no)
  let state_filter = if include_inactive {
    ""
  } else {
    " AND cl.state = 'active'"
  }
  // learn_method column returns 'active' or 'inactive' so callers/formatters
  // can distinguish confiscated moves. For legacy versions this stays as
  // 'basic' / 'TM' — a small but visible shift in semantics worth noting
  // if you touch the formatter.
  // LEFT JOIN move_meta (pkdx_patch/006_move_meta) so payoff metadata flows
  // inline on the returned `@model.Move`. Missing rows default to priority=0
  // and empty stat_effects via COALESCE.
  let sql_head =
    #|SELECT DISTINCT wl.name AS move_name, w.type, w.category,
    #|       w.power, w.accuracy, w.pp, cl.state AS learn_method,
    #|       COALESCE(mm.priority, 0) AS priority,
    #|       COALESCE(mm.stat_effects_json, '[]') AS stat_effects_json,
    #|       COALESCE(mm.ailment_ja, '') AS ailment_ja,
    #|       COALESCE(mm.ailment_chance, 100) AS ailment_chance,
    #|       COALESCE(mm.recoil_num, 0) AS recoil_num,
    #|       COALESCE(mm.recoil_den, 1) AS recoil_den,
    #|       COALESCE(mm.self_ko, 0) AS self_ko,
    #|       COALESCE(mm.recharge, 0) AS recharge
    #|FROM champions_learnset cl
    #|JOIN local_waza w ON cl.waza = w.waza AND w.version = 'Champions'
    #|JOIN local_waza_language wl ON cl.waza = wl.waza
    #|  AND wl.version = 'Champions' AND wl.language = 'jpn'
    #|LEFT JOIN move_meta mm ON mm.name_ja = wl.name
    #|WHERE cl.globalNo = ?
    #|  AND COALESCE(cl.form, '') = '' AND COALESCE(cl.region, '') = ''
    #|  AND COALESCE(cl.mega_evolution, '') = '' AND COALESCE(cl.gigantamax, '') = ''
  let sql_tail =
    #|ORDER BY power DESC
  let sql = sql_head + state_filter + "\n" + sql_tail
  collect_moves_rows(db, sql, [gno])
}

///|
fn query_moves_legacy(
  db : Db,
  global_no : String,
  version : String,
) -> Result[Array[@model.Move], String] {
  let waza_ver = to_waza_version(version)
  let gno = normalize_global_no(global_no)
  // LEFT JOIN move_meta per both UNION branches so priority / stat_effects
  // ride along on the returned Move. COALESCE defaults preserve the legacy
  // "no metadata" behaviour for moves not in the seed table.
  let sql =
    #|SELECT DISTINCT wl.name AS move_name, w.type, w.category,
    #|       w.power, w.accuracy, w.pp, pw.conditions AS learn_method,
    #|       COALESCE(mm.priority, 0) AS priority,
    #|       COALESCE(mm.stat_effects_json, '[]') AS stat_effects_json,
    #|       COALESCE(mm.ailment_ja, '') AS ailment_ja,
    #|       COALESCE(mm.ailment_chance, 100) AS ailment_chance,
    #|       COALESCE(mm.recoil_num, 0) AS recoil_num,
    #|       COALESCE(mm.recoil_den, 1) AS recoil_den,
    #|       COALESCE(mm.self_ko, 0) AS self_ko,
    #|       COALESCE(mm.recharge, 0) AS recharge
    #|FROM local_pokedex_waza pw
    #|JOIN local_waza w ON pw.waza = w.waza AND w.version = ?
    #|JOIN local_waza_language wl ON pw.waza = wl.waza
    #|  AND wl.version = ? AND wl.language = 'jpn'
    #|LEFT JOIN move_meta mm ON mm.name_ja = wl.name
    #|WHERE pw.globalNo = ? AND pw.version = ?
    #|UNION
    #|SELECT DISTINCT wl.name AS move_name, w.type, w.category,
    #|       w.power, w.accuracy, w.pp, 'TM' AS learn_method,
    #|       COALESCE(mm.priority, 0) AS priority,
    #|       COALESCE(mm.stat_effects_json, '[]') AS stat_effects_json,
    #|       COALESCE(mm.ailment_ja, '') AS ailment_ja,
    #|       COALESCE(mm.ailment_chance, 100) AS ailment_chance,
    #|       COALESCE(mm.recoil_num, 0) AS recoil_num,
    #|       COALESCE(mm.recoil_den, 1) AS recoil_den,
    #|       COALESCE(mm.self_ko, 0) AS self_ko,
    #|       COALESCE(mm.recharge, 0) AS recharge
    #|FROM local_pokedex_waza_machine pm
    #|JOIN local_waza_machine wm ON pm.machine_no = wm.waza AND wm.version = ?
    #|JOIN local_waza w ON wm.machine_no = w.waza AND w.version = ?
    #|JOIN local_waza_language wl ON w.waza = wl.waza
    #|  AND wl.version = ? AND wl.language = 'jpn'
    #|LEFT JOIN move_meta mm ON mm.name_ja = wl.name
    #|WHERE pm.globalNo = ? AND pm.version = ?
    #|  AND COALESCE(pm.form, '') = '' AND COALESCE(pm.region, '') = ''
    #|ORDER BY power DESC
  let binds = [
    waza_ver, waza_ver, gno, waza_ver, waza_ver, waza_ver, waza_ver, gno, waza_ver,
  ]
  collect_moves_rows(db, sql, binds)
}

///|
fn collect_moves_rows(
  db : Db,
  sql : String,
  binds : Array[String],
) -> Result[Array[@model.Move], String] {
  let rows = match query(db, sql, binds) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let moves : Array[@model.Move] = []
  for i = 0; i < rows.length(); i = i + 1 {
    let r = rows[i]
    let priority = if r.length() > 7 { parse_int(r[7]) } else { 0 }
    let stat_effects = if r.length() > 8 {
      parse_stat_effects_json(r[8])
    } else {
      []
    }
    let status_effect = if r.length() > 10 {
      parse_status_effect(r[9], r[10])
    } else {
      None
    }
    // Phase 4 columns: r[11]=recoil_num, r[12]=recoil_den, r[13]=self_ko,
    // r[14]=recharge. COALESCE defaults guarantee numeric/int values even on
    // rows lacking move_meta entries, so `parse_int` never sees NULL.
    let recoil_num = if r.length() > 11 { parse_int(r[11]) } else { 0 }
    let recoil_den_raw = if r.length() > 12 { parse_int(r[12]) } else { 1 }
    let recoil_den = if recoil_den_raw <= 0 { 1 } else { recoil_den_raw }
    let self_ko = if r.length() > 13 { parse_int(r[13]) != 0 } else { false }
    let recharge = if r.length() > 14 { parse_int(r[14]) != 0 } else { false }
    moves.push(@model.Move::{
      name: r[0],
      type_: r[1],
      category: @model.category_from_jp(r[2]),
      power: parse_int(r[3]),
      accuracy: parse_int(r[4]),
      pp: parse_int(r[5]),
      learn_method: r[6],
      priority,
      stat_effects,
      status_effect,
      recoil_num,
      recoil_den,
      self_ko,
      recharge,
    })
  }
  Ok(moves)
}

///|
/// Parse a JSON-encoded array of stat-effect entries into
/// `Array[StatEffect]`. Accepts two shapes to preserve backwards compat:
///
/// - Legacy 2-element: `[stat, delta]` — `target` defaults to `0` (self)
/// - New 3-element: `[stat, delta, target]` — `target` 0=self, 1=opp
///
/// Returns `[]` on any parse error or non-conforming shape so a single
/// malformed DB row cannot break a whole moveset query.
fn parse_stat_effects_json(raw : String) -> Array[@model.StatEffect] {
  let out : Array[@model.StatEffect] = []
  let json = try @json.parse(raw) catch {
    _ => return out
  }
  match json {
    Array(arr) =>
      for item in arr {
        match item {
          Array(triple) => {
            let len = triple.length()
            if len == 2 || len == 3 {
              let a = json_number_to_int(triple[0])
              let b = json_number_to_int(triple[1])
              let t = if len == 3 {
                match json_number_to_int(triple[2]) {
                  Some(x) => x
                  None => 0
                }
              } else {
                0
              }
              match (a, b) {
                (Some(ai), Some(bi)) =>
                  out.push(@model.StatEffect::{ stat: ai, delta: bi, target: t })
                _ => ()
              }
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
fn json_number_to_int(j : Json) -> Int? {
  match j {
    Number(n, ..) => Some(n.to_int())
    _ => None
  }
}

///|
/// Build a `status_effect` tuple from the `ailment_ja` / `ailment_chance`
/// columns of `move_meta`. Empty string or unrecognised Japanese ailment
/// names yield `None`; chances < 0 or > 100 are clamped to 100 (matches the
/// MVP scope where dedicated status moves have deterministic-looking chance
/// fields in the seed data, not secondary-effect percentages).
fn parse_status_effect(
  ailment_ja : String,
  chance_str : String,
) -> (@model.StatusKind, Int)? {
  if ailment_ja == "" {
    return None
  }
  match @model.status_kind_from_jp(ailment_ja) {
    None => None
    Some(kind) => {
      let raw = parse_int(chance_str)
      let chance = if raw <= 0 {
        100
      } else if raw > 100 {
        100
      } else {
        raw
      }
      Some((kind, chance))
    }
  }
}
