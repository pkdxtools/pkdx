///|
fn get_string(json : Json, key : String) -> String? {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
fn get_array(json : Json, key : String) -> Array[Json]? {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(Array(arr)) => Some(arr)
        _ => None
      }
    _ => None
  }
}

///|
fn get_object(json : Json, key : String) -> Map[String, Json]? {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(Object(obj)) => Some(obj)
        _ => None
      }
    _ => None
  }
}

///|
fn require_string(
  json : Json,
  key : String,
  errors : Array[String],
  path : String,
) -> String {
  match get_string(json, key) {
    Some(s) if s.length() > 0 => s
    _ => {
      errors.push("missing or empty required field \"\{path}.\{key}\"")
      ""
    }
  }
}

///|
fn require_array(
  json : Json,
  key : String,
  errors : Array[String],
  path : String,
) -> Array[Json] {
  match get_array(json, key) {
    Some(arr) => arr
    None => {
      errors.push("missing required array field \"\{path}.\{key}\"")
      []
    }
  }
}

///|
fn validate_stats(
  json : Json,
  key : String,
  errors : Array[String],
  path : String,
) -> Unit {
  match get_object(json, key) {
    Some(obj) => {
      let stat_keys = ["h", "a", "b", "c", "d", "s"]
      for k in stat_keys {
        match obj.get(k) {
          Some(Number(_)) => ()
          _ => errors.push("missing numeric field \"\{path}.\{key}.\{k}\"")
        }
      }
    }
    None => errors.push("missing required object field \"\{path}.\{key}\"")
  }
}

///|
fn validate_member(json : Json, errors : Array[String], path : String) -> Unit {
  require_string(json, "name", errors, path) |> ignore
  let types = require_array(json, "types", errors, path)
  if types.length() < 1 || types.length() > 2 {
    errors.push(
      "\{path}.types must have 1 or 2 elements, got \{types.length()}",
    )
  }
  validate_stats(json, "base_stats", errors, path)
  require_string(json, "ability", errors, path) |> ignore
  require_string(json, "item", errors, path) |> ignore
  require_string(json, "role", errors, path) |> ignore
  let moves = require_array(json, "moves", errors, path)
  if moves.length() != 4 {
    errors.push(
      "\{path}.moves must have exactly 4 elements, got \{moves.length()}",
    )
  }
  for i, mv in moves {
    let mv_path = "\{path}.moves[\{i}]"
    require_string(mv, "name", errors, mv_path) |> ignore
    require_string(mv, "type", errors, mv_path) |> ignore
    require_string(mv, "category", errors, mv_path) |> ignore
  }
}

///|
pub fn validate_team_json(json : Json) -> Result[Unit, Array[String]] {
  let errors : Array[String] = []
  let root = "$"
  let bf = require_string(json, "battle_format", errors, root)
  if bf.length() > 0 && bf != "singles" && bf != "doubles" {
    errors.push(
      "\{root}.battle_format must be \"singles\" or \"doubles\", got \"\{bf}\"",
    )
  }
  require_string(json, "mechanics", errors, root) |> ignore
  require_string(json, "version", errors, root) |> ignore
  let members = require_array(json, "members", errors, root)
  if members.length() < 1 || members.length() > 6 {
    errors.push(
      "\{root}.members must have 1-6 elements, got \{members.length()}",
    )
  }
  for i, m in members {
    validate_member(m, errors, "\{root}.members[\{i}]")
  }
  require_array(json, "coverage", errors, root) |> ignore
  require_array(json, "defense_matrix", errors, root) |> ignore
  require_array(json, "matchup_plans", errors, root) |> ignore
  require_array(json, "strengths", errors, root) |> ignore
  require_array(json, "weaknesses", errors, root) |> ignore
  if errors.is_empty() {
    Ok(())
  } else {
    Err(errors)
  }
}

///|
pub fn validate_pokemon_json(json : Json) -> Result[Unit, Array[String]] {
  let errors : Array[String] = []
  let root = "$"
  require_string(json, "name", errors, root) |> ignore
  let types = require_array(json, "types", errors, root)
  if types.length() < 1 || types.length() > 2 {
    errors.push(
      "\{root}.types must have 1 or 2 elements, got \{types.length()}",
    )
  }
  // nature
  match json {
    Object(m) =>
      match m.get("nature") {
        Some(Object(_) as nat_json) => {
          require_string(nat_json, "name", errors, "\{root}.nature") |> ignore
          require_string(nat_json, "plus", errors, "\{root}.nature") |> ignore
          require_string(nat_json, "minus", errors, "\{root}.nature") |> ignore
        }
        _ => errors.push("missing required object field \"\{root}.nature\"")
      }
    _ => errors.push("missing required object field \"\{root}.nature\"")
  }
  require_string(json, "ability", errors, root) |> ignore
  require_string(json, "item", errors, root) |> ignore
  validate_stats(json, "base_stats", errors, root)
  // evs validation
  validate_stats(json, "evs", errors, root)
  match get_object(json, "evs") {
    Some(ev_obj) => {
      let mut total = 0
      for _k, v in ev_obj {
        match v {
          Number(n, ..) => total = total + n.to_int()
          _ => ()
        }
      }
      if total > 510 {
        errors.push("evs total is \{total}, must be <= 510")
      }
    }
    None => ()
  }
  validate_stats(json, "actual_stats", errors, root)
  let moves = require_array(json, "moves", errors, root)
  if moves.length() < 1 || moves.length() > 4 {
    errors.push("\{root}.moves must have 1-4 elements, got \{moves.length()}")
  }
  for i, mv in moves {
    let mv_path = "\{root}.moves[\{i}]"
    require_string(mv, "name", errors, mv_path) |> ignore
    require_string(mv, "type", errors, mv_path) |> ignore
    require_string(mv, "category", errors, mv_path) |> ignore
  }
  require_string(json, "filename", errors, root) |> ignore
  if errors.is_empty() {
    Ok(())
  } else {
    Err(errors)
  }
}
