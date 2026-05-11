///|
/// LegendsZA JSON からメガシンカデータを pokedex.db へパッチする。
/// JSON shape: pokedex.<region>.<no>.<form_id> = { id, mega_evolution, hp, attack, ... }
pub fn run_001(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pokedex/pokedex/LegendsZA/LegendsZA.json"
  let raw = match @db.read_file(path) {
    Some(s) => s
    None => return Err(path + " not found. Run 'git submodule update --init'.")
  }
  let json = try @json.parse(raw) catch {
    e => return Err("JSON parse: " + e.to_string())
  }
  let pokedex : Map[String, Json] = match json {
    Object(m) =>
      match m.get("pokedex") {
        Some(Object(p)) => p
        _ => return Err("missing 'pokedex' object in LegendsZA.json")
      }
    _ => return Err("LegendsZA.json is not an object")
  }
  let version = "legendsza"
  let megas = collect_megas(pokedex)
  if megas.is_empty() {
    return Ok("No mega evolution data found in JSON.")
  }
  let mut patched = 0
  for mega in megas {
    let id = str_field(mega, "id")
    let mega_name = str_field(mega, "mega_evolution")
    match @db.exec_binds(
        db,
        "UPDATE local_pokedex SET mega_evolution = ? WHERE id = ? AND version = ?",
        [@db.BindText(mega_name), @db.BindText(id), @db.BindText(version)],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match @db.exec_binds(
        db,
        "UPDATE local_pokedex_status SET mega_evolution = ?, hp = ?, attack = ?, defense = ?, special_attack = ?, special_defense = ?, speed = ? WHERE id = ? AND version = ?",
        [
          @db.BindText(mega_name),
          @db.BindInt(int_field(mega, "hp", 0)),
          @db.BindInt(int_field(mega, "attack", 0)),
          @db.BindInt(int_field(mega, "defense", 0)),
          @db.BindInt(int_field(mega, "special_attack", 0)),
          @db.BindInt(int_field(mega, "special_defense", 0)),
          @db.BindInt(int_field(mega, "speed", 0)),
          @db.BindText(id),
          @db.BindText(version),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let type2 = bind_text_opt(str_opt(mega, "type2"))
    match @db.exec_binds(
        db,
        "UPDATE local_pokedex_type SET mega_evolution = ?, type1 = ?, type2 = ? WHERE id = ? AND version = ?",
        [
          @db.BindText(mega_name),
          @db.BindText(str_field(mega, "type1")),
          type2,
          @db.BindText(id),
          @db.BindText(version),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let ability2 = bind_text_opt(str_opt(mega, "ability2"))
    let dream = bind_text_opt(str_opt(mega, "dream_ability"))
    match @db.exec_binds(
        db,
        "UPDATE local_pokedex_ability SET mega_evolution = ?, ability1 = ?, ability2 = ?, dream_ability = ? WHERE id = ? AND version = ?",
        [
          @db.BindText(mega_name),
          @db.BindText(str_field(mega, "ability1")),
          ability2,
          dream,
          @db.BindText(id),
          @db.BindText(version),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let names : Map[String, Json] = match mega.get("name") {
      Some(Object(m)) => m
      _ => Map::new()
    }
    match names.get("jpn") {
      Some(String(n)) =>
        match @db.exec_binds(
            db,
            "UPDATE pokedex_name SET mega_evolution = ?, name = ? WHERE id = ? AND language = ?",
            [
              @db.BindText(mega_name),
              @db.BindText(n),
              @db.BindText(id),
              @db.BindText("jpn"),
            ],
          ) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
      _ => ()
    }
    match names.get("eng") {
      Some(String(n)) =>
        match @db.exec_binds(
            db,
            "UPDATE pokedex_name SET mega_evolution = ?, name = ? WHERE id = ? AND language = ?",
            [
              @db.BindText(mega_name),
              @db.BindText(n),
              @db.BindText(id),
              @db.BindText("eng"),
            ],
          ) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
      _ => ()
    }
    patched = patched + 1
  }
  Ok("Patched " + patched.to_string() + " mega evolution entries")
}

///|
/// Walk pokedex.<region>.<no>.<form_id> three-level nesting and flatten to
/// a list of { id, mega_evolution, ... } entries that have a non-empty
/// mega_evolution field.
fn collect_megas(pokedex : Map[String, Json]) -> Array[Map[String, Json]] {
  let out : Array[Map[String, Json]] = []
  for _region, region_json in pokedex {
    let entries = match region_json {
      Object(m) => m
      _ => continue
    }
    for _no, no_json in entries {
      let forms = match no_json {
        Object(m) => m
        _ => continue
      }
      for _form_id, info_json in forms {
        let info = match info_json {
          Object(m) => m
          _ => continue
        }
        match info.get("mega_evolution") {
          Some(String(s)) => if s.length() > 0 { out.push(info) }
          _ => ()
        }
      }
    }
  }
  out
}

///|
/// Shared helper so every migration can turn an Option[String] into a
/// bind value without restating the match. Kept in this file so 001 has
/// a clear self-contained footprint; later migrations reference the
/// same helper via `bind_text_opt`.
pub fn bind_text_opt(opt : String?) -> @db.BindValue {
  match opt {
    Some(s) => @db.BindText(s)
    None => @db.BindNull
  }
}
