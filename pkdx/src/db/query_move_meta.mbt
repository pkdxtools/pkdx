///|
/// Query the `move_meta` table (installed by `pkdx_patch/006_move_meta`) for
/// a batch of move names. Returns a map of `name_ja → (priority, stat_effects_json)`.
///
/// `stat_effects_json` is the raw SQL-stored JSON string (e.g. `"[[0,2]]"`);
/// the payoff layer parses it at cache-load time because `@json` is not a
/// dependency of the db module.
///
/// Missing names are not returned; callers should fall back to their own
/// defaults (curated table, or `priority=0 / stat_effects=[]`). Unknown
/// table (missing migration) is returned as an `Err`.
pub fn query_move_meta(
  db : Db,
  names : Array[String],
) -> Result[Array[(String, Int, String)], String] {
  if names.length() == 0 {
    return Ok([])
  }
  if !table_exists(db, "move_meta") {
    return Err("move_meta table not found (run pkdx_patch)")
  }
  // Build a parameterised IN clause: `? , ? , ? ...`
  let mut placeholders = ""
  for i in 0..<names.length() {
    if i > 0 {
      placeholders = placeholders + ", "
    }
    placeholders = placeholders + "?"
  }
  let sql =
    "SELECT name_ja, priority, stat_effects_json FROM move_meta WHERE name_ja IN (" +
    placeholders +
    ")"
  let rows = match query(db, sql, names) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let out : Array[(String, Int, String)] = []
  for i in 0..<rows.length() {
    let r = rows[i]
    let priority = parse_int(r[1])
    out.push((r[0], priority, r[2]))
  }
  Ok(out)
}
