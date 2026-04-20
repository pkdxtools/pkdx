///|
fn format_errors(
  errors : Array[@jsonschema.ValidationError],
) -> Array[String] {
  let result : Array[String] = []
  for e in errors {
    result.push("\{e.json_path}: \{e.message}")
  }
  result
}

///|
fn extract_version(json : Json) -> String {
  match json {
    Object(m) =>
      match m.get("version") {
        Some(String(v)) => v
        _ => ""
      }
    _ => ""
  }
}

///|
/// Champions SP ルール: 合計 ≤ 66, 各ステ ≤ 32, 非負
fn validate_champions_sp(sp_obj : Map[String, Json]) -> Array[String] {
  let result : Array[String] = []
  let mut total = 0
  for k, v in sp_obj {
    match v {
      Number(n, ..) => {
        let iv = n.to_int()
        total = total + iv
        if iv < 0 {
          result.push(
            "#/build/stat_points/\{k}: Champions SP for \{k} is negative (\{iv})",
          )
        }
        if iv > 32 {
          result.push(
            "#/build/stat_points/\{k}: Champions SP for \{k} is \{iv}, must be <= 32",
          )
        }
      }
      _ => ()
    }
  }
  if total > 66 {
    result.push(
      "#/build/stat_points: Champions SP total is \{total}, must be <= 66",
    )
  }
  result
}

///|
/// stats 系フィールドが long-key 形式なら legacy エラーを `errs` に push。
/// 判定ロジックは `has_long_stat_key` (stat_keys.mbt) を共有する。
fn check_long_stats_field(
  errs : Array[String],
  obj : Map[String, Json],
  field : String,
  path_prefix : String,
  hint : String,
) -> Unit {
  match obj.get(field) {
    Some(Object(stats)) =>
      if has_long_stat_key(stats) {
        errs.push("\{path_prefix}/\{field}: \{hint}")
      }
    _ => ()
  }
}

///|
/// obj 内の `stats_field_names` (SSoT) 全フィールドを一括で検査する。
/// migrator (convert.mbt) と同じリストを走査するため、列を増減しても
/// detector 側を書き換える必要はない。
fn check_all_stats_fields(
  errs : Array[String],
  obj : Map[String, Json],
  path_prefix : String,
  hint : String,
) -> Unit {
  for field in stats_field_names {
    check_long_stats_field(errs, obj, field, path_prefix, hint)
  }
}

///|
let legacy_hint : String = "legacy schema detected — run: pkdx convert meta --in-place <path>"

///|
/// v011 より前のスキーマを検出。検出時は `pkdx convert meta --in-place` への
/// 誘導メッセージを返す（ユーザー体験: 手動でスキーマ差分を読まずに復旧可能）。
/// migrate_pokemon_meta_v011 が変換する全 shape を網羅する必要がある。
fn detect_legacy_pokemon(root : Map[String, Json]) -> Array[String] {
  let errs : Array[String] = []
  match root.get("pokemon") {
    Some(Object(p)) => {
      if p.get("type1") is Some(_) {
        errs.push("#/pokemon/type1: \{legacy_hint}")
      }
      match p.get("abilities") {
        Some(Object(_)) => errs.push("#/pokemon/abilities: \{legacy_hint}")
        _ => ()
      }
      check_all_stats_fields(errs, p, "#/pokemon", legacy_hint)
    }
    _ => ()
  }
  match root.get("build") {
    Some(Object(b)) => {
      if b.get("evs") is Some(_) {
        errs.push("#/build/evs: \{legacy_hint}")
      }
      if b.get("nature_up") is Some(_) {
        errs.push("#/build/nature_up: \{legacy_hint}")
      }
      if b.get("nature_down") is Some(_) {
        errs.push("#/build/nature_down: \{legacy_hint}")
      }
      check_all_stats_fields(errs, b, "#/build", legacy_hint)
    }
    _ => ()
  }
  errs
}

///|
/// migrate_team_meta_v011 が members[] の stats 系全フィールドを short-key へ
/// 揃えるため、検出器も同じ範囲 (`stats_field_names`) をカバーする。
fn detect_legacy_team(root : Map[String, Json]) -> Array[String] {
  let errs : Array[String] = []
  match root.get("members") {
    Some(Array(members)) =>
      for i, m in members {
        match m {
          Object(mo) =>
            check_all_stats_fields(errs, mo, "#/members/\{i}", legacy_hint)
          _ => ()
        }
      }
    _ => ()
  }
  errs
}

///|
pub fn validate_team_json(json : Json) -> Result[Unit, Array[String]] {
  // 旧スキーマ検出は jsonschema 検証より前に走らせ、早期に誘導する。
  match json {
    Object(root) => {
      let legacy = detect_legacy_team(root)
      if not(legacy.is_empty()) {
        return Err(legacy)
      }
    }
    _ => ()
  }
  let b = @jsonschema.Builder::new()
  let schema = team_schema(b, strict=true)
  let resolver = try @jsonschema.build_resolver(
      ({} : Map[String, Json]).to_json(),
    ) catch {
    _ => return Err(["internal: failed to build schema resolver"])
  }
  let errors = @jsonschema.Validatable::validate(
    schema,
    json,
    resolver~,
    json_path=@jsonschema.JsonPointer::Root,
    schema_path=@jsonschema.JsonPointer::Root,
  )
  if errors.is_empty() {
    Ok(())
  } else {
    Err(format_errors(errors))
  }
}

///|
pub fn validate_pokemon_json(json : Json) -> Result[Unit, Array[String]] {
  // 旧スキーマ検出は jsonschema 検証より前に走らせ、早期に誘導する。
  match json {
    Object(root) => {
      let legacy = detect_legacy_pokemon(root)
      if not(legacy.is_empty()) {
        return Err(legacy)
      }
    }
    _ => ()
  }
  let b = @jsonschema.Builder::new()
  let schema = pokemon_schema(b, strict=true)
  let resolver = try @jsonschema.build_resolver(
      ({} : Map[String, Json]).to_json(),
    ) catch {
    _ => return Err(["internal: failed to build schema resolver"])
  }
  let errors = @jsonschema.Validatable::validate(
    schema,
    json,
    resolver~,
    json_path=@jsonschema.JsonPointer::Root,
    schema_path=@jsonschema.JsonPointer::Root,
  )
  let result = format_errors(errors)
  // SP/EV 合計チェック（jsonschemaでは表現不可のビジネスルール）
  // version=champions → SP ルール (合計 ≤ 66, 各 ≤ 32, 非負)
  // else               → 旧作 EV ルール (合計 ≤ 510)
  let version = extract_version(json)
  match json {
    Object(m) =>
      match m.get("build") {
        Some(Object(build)) =>
          match build.get("stat_points") {
            Some(Object(sp_obj)) =>
              if version == "champions" {
                for err in validate_champions_sp(sp_obj) {
                  result.push(err)
                }
              } else {
                let mut total = 0
                for _k, v in sp_obj {
                  match v {
                    Number(n, ..) => total = total + n.to_int()
                    _ => ()
                  }
                }
                if total > 510 {
                  result.push(
                    "#/build/stat_points: total is \{total}, must be <= 510",
                  )
                }
              }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  // moves が全て null でないことを保証（キャッシュは段階的に埋まるため）
  match json {
    Object(m) =>
      match m.get("build") {
        Some(Object(build)) =>
          match build.get("moves") {
            Some(Array(moves)) =>
              for i, mv in moves {
                match mv {
                  Object(mv_obj) =>
                    match mv_obj.get("name") {
                      Some(String(n)) if n.length() == 0 =>
                        result.push(
                          "#/build/moves[\{i}]: move name must not be empty",
                        )
                      None =>
                        result.push(
                          "#/build/moves[\{i}]: move name must not be empty",
                        )
                      _ => ()
                    }
                  _ => ()
                }
              }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  if result.is_empty() {
    Ok(())
  } else {
    Err(result)
  }
}
