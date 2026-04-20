///|
/// long → short stat key mapping used across pokemon/build sections.
/// 旧 schema と新 schema の唯一の対応付け表。
let stat_key_long_short : Array[(String, String)] = [
  ("hp", "h"),
  ("atk", "a"),
  ("def", "b"),
  ("spa", "c"),
  ("spd", "d"),
  ("spe", "s"),
]

///|
/// 旧 long-key stats {hp,atk,...} / 新 short-key stats {h,a,...} のどちらが来ても
/// 常に short-key で返す。冪等。
fn normalize_stats_to_short(value : Json) -> Json {
  guard value is Object(obj) else { return value }
  let out : Map[String, Json] = {}
  for pair in stat_key_long_short {
    let (long_k, short_k) = pair
    match obj.get(short_k) {
      Some(v) => out[short_k] = v
      None =>
        match obj.get(long_k) {
          Some(v) => out[short_k] = v
          None => ()
        }
    }
  }
  out.to_json()
}

///|
/// 旧 type1+type2 から canonical order の types[] を構築。
/// null / 空 / 欠損は除外。既に types[] がある場合はそのまま返す。
fn normalize_types(pokemon : Map[String, Json]) -> Array[Json] {
  match pokemon.get("types") {
    Some(Array(arr)) => return arr
    _ => ()
  }
  let out : Array[Json] = []
  fn push_if_string(k : String) -> Unit {
    match pokemon.get(k) {
      Some(String(s)) => if s.length() > 0 { out.push(s.to_json()) }
      _ => ()
    }
  }

  push_if_string("type1")
  push_if_string("type2")
  out
}

///|
/// 旧 abilities{ability1,ability2,dream_ability} から canonical order の
/// abilities[] を構築。null / 空は除外。既に abilities[] がある場合はそのまま返す。
fn normalize_abilities(pokemon : Map[String, Json]) -> Array[Json] {
  match pokemon.get("abilities") {
    Some(Array(arr)) => return arr
    _ => ()
  }
  let out : Array[Json] = []
  fn push_from(k : String) -> Unit {
    match pokemon.get("abilities") {
      Some(Object(ab)) =>
        match ab.get(k) {
          Some(String(s)) => if s.length() > 0 { out.push(s.to_json()) }
          _ => ()
        }
      _ => ()
    }
  }

  push_from("ability1")
  push_from("ability2")
  push_from("dream_ability")
  out
}

///|
/// Convert a single pokemon/build meta.json between old schema (PR #65 以前)
/// and the new short-key / array-based schema introduced for issue #66.
/// Idempotent: already-migrated inputs return unchanged.
pub fn migrate_pokemon_meta_v011(input : Json) -> Result[Json, String] {
  guard input is Object(root) else {
    return Err("migrate_pokemon_meta_v011: expected object at top level")
  }
  let out : Map[String, Json] = {}
  // Preserve top-level non-touched fields (version, regulation, phase, damage_calcs, updated_at, etc.)
  for k, v in root {
    if k != "pokemon" && k != "build" {
      out[k] = v
    }
  }
  match root.get("pokemon") {
    Some(Object(pokemon)) => {
      let pokemon_out : Map[String, Json] = {}
      // 保持する識別子
      for k in ["name", "name_en", "globalNo"] {
        match pokemon.get(k) {
          Some(v) => pokemon_out[k] = v
          None => ()
        }
      }
      pokemon_out["types"] = normalize_types(pokemon).to_json()
      match pokemon.get("base_stats") {
        Some(v) => pokemon_out["base_stats"] = normalize_stats_to_short(v)
        None => ()
      }
      pokemon_out["abilities"] = normalize_abilities(pokemon).to_json()
      out["pokemon"] = pokemon_out.to_json()
    }
    _ => ()
  }
  match root.get("build") {
    Some(Object(build)) => {
      let build_out : Map[String, Json] = {}
      for k in ["nature", "ability", "item", "moves"] {
        match build.get(k) {
          Some(v) => build_out[k] = v
          None => ()
        }
      }
      // evs → stat_points (新 key 優先、なければ旧 evs を short key 化)
      match build.get("stat_points") {
        Some(v) => build_out["stat_points"] = normalize_stats_to_short(v)
        None =>
          match build.get("evs") {
            Some(v) => build_out["stat_points"] = normalize_stats_to_short(v)
            None => ()
          }
      }
      match build.get("actual_stats") {
        Some(v) => build_out["actual_stats"] = normalize_stats_to_short(v)
        None => ()
      }
      // role は optional として新形式のみに存在
      match build.get("role") {
        Some(v) => build_out["role"] = v
        None => ()
      }
      out["build"] = build_out.to_json()
    }
    _ => ()
  }
  Ok(out.to_json())
}

///|
/// Convert a team meta.json (`members[]` shape). 新 schema は旧 member 形式を
/// 受け入れられる (accuracy 許容のみ追加) ため、現状は identity に近い。
/// 将来的に member 側の互換レイヤーを足す場所として関数を保持する。
pub fn migrate_team_meta_v011(input : Json) -> Result[Json, String] {
  guard input is Object(_) else {
    return Err("migrate_team_meta_v011: expected object at top level")
  }
  Ok(input)
}

///|
/// 入力 JSON が pokemon/team どちらの meta であるかを構造で推定。
pub enum MetaKind {
  Pokemon
  Team
  Unknown
} derive(Show, Eq)

///|
pub fn detect_meta_kind(input : Json) -> MetaKind {
  guard input is Object(root) else { return Unknown }
  match (root.get("pokemon"), root.get("build"), root.get("members")) {
    (Some(_), Some(_), _) => Pokemon
    (_, _, Some(_)) => Team
    _ => Unknown
  }
}

///|
/// Migrate dispatcher used by the `pkdx convert meta` CLI.
pub fn migrate_meta_v011(input : Json) -> Result[Json, String] {
  match detect_meta_kind(input) {
    Pokemon => migrate_pokemon_meta_v011(input)
    Team => migrate_team_meta_v011(input)
    Unknown =>
      Err("migrate_meta_v011: unrecognized meta JSON (missing pokemon/build or members)")
  }
}
