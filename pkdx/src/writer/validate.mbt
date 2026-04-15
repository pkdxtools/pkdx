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
fn validate_champions_sp(ev_obj : Map[String, Json]) -> Array[String] {
  let result : Array[String] = []
  let mut total = 0
  for k, v in ev_obj {
    match v {
      Number(n, ..) => {
        let iv = n.to_int()
        total = total + iv
        if iv < 0 {
          result.push(
            "#/build/evs/\{k}: Champions SP for \{k} is negative (\{iv})",
          )
        }
        if iv > 32 {
          result.push(
            "#/build/evs/\{k}: Champions SP for \{k} is \{iv}, must be <= 32",
          )
        }
      }
      _ => ()
    }
  }
  if total > 66 {
    result.push("#/build/evs: Champions SP total is \{total}, must be <= 66")
  }
  result
}

///|
pub fn validate_team_json(json : Json) -> Result[Unit, Array[String]] {
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
  // EV/SP 合計チェック（jsonschemaでは表現不可のビジネスルール）
  // version=champions → SP ルール (合計 ≤ 66, 各 ≤ 32, 非負)
  // else               → SV 既存 EV ルール (合計 ≤ 510)
  let version = extract_version(json)
  match json {
    Object(m) =>
      match m.get("build") {
        Some(Object(build)) =>
          match build.get("evs") {
            Some(Object(ev_obj)) =>
              if version == "champions" {
                for err in validate_champions_sp(ev_obj) {
                  result.push(err)
                }
              } else {
                let mut total = 0
                for _k, v in ev_obj {
                  match v {
                    Number(n, ..) => total = total + n.to_int()
                    _ => ()
                  }
                }
                if total > 510 {
                  result.push(
                    "#/build/evs: evs total is \{total}, must be <= 510",
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
