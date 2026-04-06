///|
fn stats_schema_short(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "h": b.number(),
      "a": b.number(),
      "b": b.number(),
      "c": b.number(),
      "d": b.number(),
      "s": b.number(),
    },
    required_all=true,
  )
}

///|
fn stats_schema_long(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "hp": b.number(),
      "atk": b.number(),
      "def": b.number(),
      "spa": b.number(),
      "spd": b.number(),
      "spe": b.number(),
    },
    required_all=true,
  )
}

///|
fn move_schema(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "name": b.string(),
      "type": b.string(),
      "category": b.string(),
      "power": b.number(),
    },
    required=["name", "type", "category"],
  )
}

///|
fn pokemon_move_schema(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "name": b.string(),
      "type": b.string(),
      "category": b.string(),
      "power": b.number(),
      "accuracy": b.number(),
    },
    required=["name", "type", "category"],
  )
}

///|
fn member_schema(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "name": b.string(),
      "types": b.array(items=b.string(), min_items=1, max_items=2),
      "base_stats": stats_schema_short(b),
      "ability": b.string(),
      "item": b.string(),
      "role": b.string(),
      "moves": b.array(items=move_schema(b), min_items=4, max_items=4),
    },
    required_all=true,
  )
}

///|
fn team_schema(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "battle_format": b.string(enum_=["singles", "doubles"]),
      "mechanics": b.string(),
      "version": b.string(),
      "members": b.array(items=member_schema(b), min_items=1, max_items=6),
      "coverage": b.array(items=b.any()),
      "defense_matrix": b.array(items=b.any()),
      "matchup_plans": b.array(items=b.any()),
      "strengths": b.array(items=b.string()),
      "weaknesses": b.array(items=b.string()),
    },
    required_all=true,
  )
}

///|
/// キャッシュ JSON 互換スキーマ
/// pokemon.build 以下のフィールドを検証する
fn pokemon_schema(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
  let pokemon_info = b.object(
    properties={
      "name": b.string(),
      "type1": b.string(),
      "type2": b.string(),
      "base_stats": stats_schema_long(b),
    },
    required=["name", "type1", "base_stats"],
  )
  let build_info = b.object(
    properties={
      "nature": b.string(),
      "nature_up": b.string(),
      "nature_down": b.string(),
      "ability": b.string(),
      "item": b.string(),
      "moves": b.array(items=pokemon_move_schema(b), min_items=1, max_items=4),
      "evs": stats_schema_long(b),
      "actual_stats": stats_schema_long(b),
    },
    required=["nature", "nature_up", "nature_down", "ability", "item", "moves", "evs", "actual_stats"],
  )
  b.object(
    properties={
      "version": b.string(),
      "phase": b.number(),
      "pokemon": pokemon_info,
      "build": build_info,
      "damage_calcs": b.array(items=b.any()),
      "updated_at": b.string(),
    },
    required=["pokemon", "build"],
  )
}

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
pub fn validate_team_json(json : Json) -> Result[Unit, Array[String]] {
  let b = @jsonschema.Builder::new()
  let schema = team_schema(b)
  let resolver = try @jsonschema.build_resolver({}) catch {
    _ => return Err(["internal: failed to build schema resolver"])
  }
  let errors = schema.validate(
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
  let schema = pokemon_schema(b)
  let resolver = try @jsonschema.build_resolver({}) catch {
    _ => return Err(["internal: failed to build schema resolver"])
  }
  let errors = schema.validate(
    json,
    resolver~,
    json_path=@jsonschema.JsonPointer::Root,
    schema_path=@jsonschema.JsonPointer::Root,
  )
  let result = format_errors(errors)
  // EV合計510チェック（jsonschemaでは表現不可のビジネスルール）
  match json {
    Object(m) =>
      match m.get("build") {
        Some(Object(build)) =>
          match build.get("evs") {
            Some(Object(ev_obj)) => {
              let mut total = 0
              for _k, v in ev_obj {
                match v {
                  Number(n, ..) => total = total + n.to_int()
                  _ => ()
                }
              }
              if total > 510 {
                result.push("#/build/evs: evs total is \{total}, must be <= 510")
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
