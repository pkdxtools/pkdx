///|
/// Import check: 冪等性判定
///
/// Claude vision で抽出した cache JSON が、既存の box/pokemons|teams/ 配下の
/// .meta.json 群と一致するか判定する。一致あれば Skip、部分差分あれば Diff、
/// 一致なしなら New を返す。
///
/// stdin 入力フォーマット:
/// ```json
/// {
///   "kind": "pokemon" | "team",
///   "cache": <新規 cache JSON>,
///   "existing": [
///     {"path": "box/pokemons/ガブリアス/スカーフ型.meta.json", "content": <既存 meta.json>}
///   ]
/// }
/// ```
///
/// 比較キー (pokemon): (species, nature, ability, item, evs vector, moves sorted by name)
/// 比較キー (team):    (battle_format, version, members sorted by species)

///|
pub(all) enum ImportCheckResult {
  Skip(String) // matched_file
  Diff(String, Array[String]) // matched_file, differing_fields
  New
} derive(Show, Eq)

///|
pub fn import_check_result_to_json(r : ImportCheckResult) -> Json {
  match r {
    Skip(path) => { "status": "skip", "matched_file": path.to_json() }
    Diff(path, fields) => {
      let fs : Array[Json] = []
      for f in fields {
        fs.push(f.to_json())
      }
      {
        "status": "diff",
        "matched_file": path.to_json(),
        "differing_fields": fs.to_json(),
      }
    }
    New => { "status": "new", "matched_file": Json::null() }
  }
}

///|
/// Pokemon cache JSON から比較用タプルを抽出
pub fn extract_pokemon_tuple(json : Json) -> PokemonTuple {
  let species = json_str_at(json, ["pokemon", "name"])
  let nature = json_str_at(json, ["build", "nature"])
  let ability = json_str_at(json, ["build", "ability"])
  let item = json_str_at(json, ["build", "item"])
  let evs = [
    json_int_at(json, ["build", "evs", "hp"]),
    json_int_at(json, ["build", "evs", "atk"]),
    json_int_at(json, ["build", "evs", "def"]),
    json_int_at(json, ["build", "evs", "spa"]),
    json_int_at(json, ["build", "evs", "spd"]),
    json_int_at(json, ["build", "evs", "spe"]),
  ]
  let moves = json_str_array_at(json, ["build", "moves"], "name")
  moves.sort()
  { species, nature, ability, item, evs, moves }
}

///|
pub(all) struct PokemonTuple {
  species : String
  nature : String
  ability : String
  item : String
  evs : Array[Int]
  moves : Array[String]
} derive(Show, Eq)

///|
/// Team cache JSON から比較用タプルを抽出
pub fn extract_team_tuple(json : Json) -> TeamTuple {
  let battle_format = json_str_at(json, ["battle_format"])
  let version = json_str_at(json, ["version"])
  let members : Array[TeamMemberTuple] = []
  match json {
    Object(m) =>
      match m.get("members") {
        Some(Array(arr)) =>
          for mb in arr {
            let name = json_str_at(mb, ["name"])
            let ability = json_str_at(mb, ["ability"])
            let item = json_str_at(mb, ["item"])
            let moves = json_str_array_at(mb, ["moves"], "name")
            moves.sort()
            members.push({ name, ability, item, moves })
          }
        _ => ()
      }
    _ => ()
  }
  members.sort_by(fn(a, b) { a.name.compare(b.name) })
  { battle_format, version, members }
}

///|
pub(all) struct TeamTuple {
  battle_format : String
  version : String
  members : Array[TeamMemberTuple]
} derive(Show, Eq)

///|
pub(all) struct TeamMemberTuple {
  name : String
  ability : String
  item : String
  moves : Array[String]
} derive(Show, Eq)

///|
/// Pokemon タプル差分を検出。一致なら空配列、差分あればフィールド名列挙
fn diff_pokemon_tuple(
  a : PokemonTuple,
  b : PokemonTuple,
) -> Array[String] {
  let d : Array[String] = []
  if a.species != b.species {
    d.push("species")
  }
  if a.nature != b.nature {
    d.push("nature")
  }
  if a.ability != b.ability {
    d.push("ability")
  }
  if a.item != b.item {
    d.push("item")
  }
  if a.evs != b.evs {
    d.push("evs")
  }
  if a.moves != b.moves {
    d.push("moves")
  }
  d
}

///|
fn diff_team_tuple(a : TeamTuple, b : TeamTuple) -> Array[String] {
  let d : Array[String] = []
  if a.battle_format != b.battle_format {
    d.push("battle_format")
  }
  if a.version != b.version {
    d.push("version")
  }
  if a.members.length() != b.members.length() {
    d.push("members")
    return d
  }
  for i in 0..<a.members.length() {
    if a.members[i] != b.members[i] {
      d.push("members[\{i}]")
    }
  }
  d
}

///|
/// Generic import check: exact match wins → best partial match → New.
/// `same_entity` gates whether a partial match is reported as a Diff
/// (pokemon requires species match; team has no such gate).
fn[T] check_import_generic(
  cache : Json,
  existing : Array[(String, Json)],
  extract : (Json) -> T,
  diff : (T, T) -> Array[String],
  same_entity : (T, T) -> Bool,
) -> ImportCheckResult {
  let target = extract(cache)
  let mut best_match : ImportCheckResult = New
  let mut best_diff_count = 9999
  for item in existing {
    let (path, content) = item
    let candidate = extract(content)
    let d = diff(target, candidate)
    if d.length() == 0 {
      return Skip(path)
    }
    if d.length() < best_diff_count && same_entity(target, candidate) {
      best_diff_count = d.length()
      best_match = Diff(path, d)
    }
  }
  best_match
}

///|
/// Pokemon cache を既存 meta.json 群と比較
pub fn check_pokemon_import(
  cache : Json,
  existing : Array[(String, Json)],
) -> ImportCheckResult {
  check_import_generic(
    cache,
    existing,
    extract_pokemon_tuple,
    diff_pokemon_tuple,
    fn(a, b) { a.species == b.species },
  )
}

///|
pub fn check_team_import(
  cache : Json,
  existing : Array[(String, Json)],
) -> ImportCheckResult {
  check_import_generic(
    cache,
    existing,
    extract_team_tuple,
    diff_team_tuple,
    fn(_, _) { true },
  )
}

///|
/// stdin JSON を ({kind, cache, existing}) に parse し、結果 JSON を返す
/// kind の不正、malformed JSON などは Err を返し、呼び出し側が exit_error する
pub fn run_import_check(input : Json) -> Result[Json, String] {
  let kind = json_str_at(input, ["kind"])
  let cache = json_at(input, ["cache"])
  match cache {
    Null => return Err("missing 'cache' field")
    _ => ()
  }
  let existing : Array[(String, Json)] = []
  match input {
    Object(m) =>
      match m.get("existing") {
        Some(Array(arr)) =>
          for entry in arr {
            let path = json_str_at(entry, ["path"])
            let content = json_at(entry, ["content"])
            existing.push((path, content))
          }
        _ => ()
      }
    _ => ()
  }
  let result = match kind {
    "pokemon" => check_pokemon_import(cache, existing)
    "team" => check_team_import(cache, existing)
    _ => return Err("invalid 'kind' (must be pokemon|team): \{kind}")
  }
  Ok(import_check_result_to_json(result))
}

// ---------- JSON path helpers ----------

///|
fn json_at(json : Json, path : Array[String]) -> Json {
  let mut cur = json
  for key in path {
    match cur {
      Object(m) =>
        match m.get(key) {
          Some(j) => cur = j
          None => return Json::null()
        }
      _ => return Json::null()
    }
  }
  cur
}

///|
fn json_str_at(json : Json, path : Array[String]) -> String {
  match json_at(json, path) {
    String(s) => s
    _ => ""
  }
}

///|
fn json_int_at(json : Json, path : Array[String]) -> Int {
  match json_at(json, path) {
    Number(n, ..) => n.to_int()
    _ => 0
  }
}

///|
/// array path に対して、各要素の key フィールドを文字列として集める
fn json_str_array_at(
  json : Json,
  path : Array[String],
  key : String,
) -> Array[String] {
  let result : Array[String] = []
  match json_at(json, path) {
    Array(arr) =>
      for item in arr {
        match item {
          Object(m) =>
            match m.get(key) {
              Some(String(s)) => result.push(s)
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  result
}
