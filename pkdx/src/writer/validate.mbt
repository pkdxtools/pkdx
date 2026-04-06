///|
fn stats_schema(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
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
fn move_with_accuracy_schema(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
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
      "base_stats": stats_schema(b),
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
fn nature_schema(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "name": b.string(),
      "plus": b.string(),
      "minus": b.string(),
    },
    required_all=true,
  )
}

///|
fn pokemon_schema(b : @jsonschema.Builder) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "name": b.string(),
      "types": b.array(items=b.string(), min_items=1, max_items=2),
      "nature": nature_schema(b),
      "ability": b.string(),
      "item": b.string(),
      "base_stats": stats_schema(b),
      "evs": stats_schema(b),
      "actual_stats": stats_schema(b),
      "moves": b.array(
        items=move_with_accuracy_schema(b),
        min_items=1,
        max_items=4,
      ),
      "damage_calcs": b.array(items=b.any()),
      "filename": b.string(),
    },
    required_all=true,
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
      match m.get("evs") {
        Some(Object(ev_obj)) => {
          let mut total = 0
          for _k, v in ev_obj {
            match v {
              Number(n, ..) => total = total + n.to_int()
              _ => ()
            }
          }
          if total > 510 {
            result.push("#/evs: evs total is \{total}, must be <= 510")
          }
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
