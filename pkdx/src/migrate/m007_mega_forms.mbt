///|
/// メガ進化データの整合性検証のみ。データは書き換えない。
/// 001/002 が投入した status/type/ability のメガ行が期待件数を満たし、
/// かつ相互参照 (LEFT JOIN) に欠落がないことを確かめる。
pub fn run_007(db : @db.Db, _repo_root : String) -> Result[String, String] {
  let expected = [("legendsza", 60), ("champions", 55)]
  let report_parts : Array[String] = []
  let missing : Array[String] = []
  for exp in expected {
    let (version, min_count) = exp
    let rs = match get_count_triple(db, version) {
      Err(e) => return Err(e)
      Ok(triple) => triple
    }
    let (status, ty, ability) = rs
    report_parts.push(
      version +
      ": " +
      status.to_string() +
      " status / " +
      ty.to_string() +
      " type / " +
      ability.to_string() +
      " ability mega rows",
    )
    let min = if status < ty { if status < ability { status } else { ability } } else if ty <
      ability {
      ty
    } else {
      ability
    }
    if min < min_count {
      missing.push(
        version +
        ": status=" +
        status.to_string() +
        ", type=" +
        ty.to_string() +
        ", ability=" +
        ability.to_string() +
        " (expected >= " +
        min_count.to_string() +
        ")",
      )
    }
  }
  let mismatches : Array[String] = []
  for exp in expected {
    let (version, _) = exp
    let orphans = match find_orphans(db, version) {
      Err(e) => return Err(e)
      Ok(o) => o
    }
    if not(orphans.is_empty()) {
      mismatches.push(version + ": " + orphans.join(", "))
    }
  }
  if not(missing.is_empty()) || not(mismatches.is_empty()) {
    let mut msg = "Mega-form data integrity check FAILED."
    if not(missing.is_empty()) {
      msg = msg + "\n    Below minimum count:"
      for m in missing {
        msg = msg + "\n      " + m
      }
    }
    if not(mismatches.is_empty()) {
      msg = msg + "\n    Orphan mega rows (missing status/type/ability pair):"
      for m in mismatches {
        msg = msg + "\n      " + m
      }
    }
    msg = msg + "\n    Run 001_mega_legendsza and/or 002_champions_pokemon before 007."
    return Err(msg)
  }
  // まとめて 1 行で出してもよいが、Ruby 版は 1 バージョン 1 行で出して
  // いたので同形式を維持する。runner は複数行 summary をそのまま表示する。
  Ok(report_parts.join("\n    ") + "\n    Mega-form integrity: OK")
}

///|
fn get_count_triple(
  db : @db.Db,
  version : String,
) -> Result[(Int, Int, Int), String] {
  let status = match count_mega(db, "local_pokedex_status", version) {
    Err(e) => return Err(e)
    Ok(n) => n
  }
  let ty = match count_mega(db, "local_pokedex_type", version) {
    Err(e) => return Err(e)
    Ok(n) => n
  }
  let ability = match count_mega(db, "local_pokedex_ability", version) {
    Err(e) => return Err(e)
    Ok(n) => n
  }
  Ok((status, ty, ability))
}

///|
fn count_mega(db : @db.Db, table : String, version : String) -> Result[Int, String] {
  let sql = "SELECT COUNT(*) FROM " +
    table +
    " WHERE version = ? AND mega_evolution IS NOT NULL AND mega_evolution != ''"
  let rows = match @db.query_binds(db, sql, [@db.BindText(version)]) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  match rows.get(0).bind(fn(row) { row.get(0) }) {
    Some(Some(s)) => {
      let n = try @strconv.parse_int(s) catch {
        _ => return Ok(0)
      }
      Ok(n)
    }
    _ => Ok(0)
  }
}

///|
fn find_orphans(db : @db.Db, version : String) -> Result[Array[String], String] {
  let sql = "SELECT DISTINCT s.mega_evolution FROM local_pokedex_status s LEFT JOIN local_pokedex_type t ON s.id = t.id AND s.version = t.version AND COALESCE(s.mega_evolution, '') = COALESCE(t.mega_evolution, '') LEFT JOIN local_pokedex_ability a ON s.id = a.id AND s.version = a.version AND COALESCE(s.mega_evolution, '') = COALESCE(a.mega_evolution, '') WHERE s.version = ? AND s.mega_evolution IS NOT NULL AND s.mega_evolution != '' AND (t.id IS NULL OR a.id IS NULL)"
  let rows = match @db.query_binds(db, sql, [@db.BindText(version)]) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  let out : Array[String] = []
  for row in rows {
    match row.get(0) {
      Some(Some(s)) => out.push(s)
      _ => ()
    }
  }
  Ok(out)
}
