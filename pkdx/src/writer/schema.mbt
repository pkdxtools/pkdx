///|
fn nullable(
  b : @jsonschema.Builder,
  schema : @jsonschema.JsonSchema,
) -> @jsonschema.JsonSchema {
  b.one_of([schema, b.null()])
}

///|
fn strict_string(
  b : @jsonschema.Builder,
  strict~ : Bool,
) -> @jsonschema.JsonSchema {
  if strict {
    b.string(minLength=1)
  } else {
    nullable(b, b.string())
  }
}

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
fn move_schema(
  b : @jsonschema.Builder,
  strict~ : Bool = true,
) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "name": strict_string(b, strict~),
      "type": b.string(),
      "category": b.string(),
      "power": b.number(),
    },
    required=["name", "type", "category"],
  )
}

///|
fn pokemon_move_schema(
  b : @jsonschema.Builder,
  strict~ : Bool = true,
) -> @jsonschema.JsonSchema {
  b.object(
    properties={
      "name": strict_string(b, strict~),
      "type": b.string(),
      "category": b.string(),
      "power": b.number(),
      "accuracy": b.number(),
    },
    required=["name", "type", "category"],
  )
}

///|
fn member_schema(
  b : @jsonschema.Builder,
  strict~ : Bool = true,
) -> @jsonschema.JsonSchema {
  let moves_min = if strict { 4 } else { 0 }
  b.object(
    properties={
      "name": b.string(),
      "types": b.array(items=b.string(), min_items=1, max_items=2),
      "base_stats": stats_schema_short(b),
      "ability": b.string(),
      "item": b.string(),
      "role": b.string(),
      "moves": b.array(
        items=move_schema(b, strict~),
        min_items=moves_min,
        max_items=4,
      ),
    },
    required_all=true,
  )
}

///|
pub fn team_schema(
  b : @jsonschema.Builder,
  strict~ : Bool = true,
) -> @jsonschema.JsonSchema {
  let members_min = if strict { 1 } else { 0 }
  let battle_format = if strict {
    b.string(enum_=["singles", "doubles"])
  } else {
    nullable(b, b.string())
  }
  b.object(
    properties={
      "battle_format": battle_format,
      "mechanics": strict_string(b, strict~),
      "version": strict_string(b, strict~),
      "phase": b.number(),
      "members": b.array(
        items=member_schema(b, strict~),
        min_items=members_min,
        max_items=6,
      ),
      "coverage": b.array(items=b.any()),
      "defense_matrix": b.array(items=b.any()),
      "matchup_plans": b.array(items=b.any()),
      "strengths": b.array(items=b.string()),
      "weaknesses": b.array(items=b.string()),
      "updated_at": b.string(),
    },
    required=[
      "battle_format", "mechanics", "version", "members", "coverage",
      "defense_matrix", "matchup_plans", "strengths", "weaknesses",
    ],
  )
}

///|
pub fn pokemon_schema(
  b : @jsonschema.Builder,
  strict~ : Bool = true,
) -> @jsonschema.JsonSchema {
  let pokemon_info = b.object(
    properties={
      "name": b.string(),
      "name_en": b.string(),
      "globalNo": b.string(),
      "type1": b.string(),
      "type2": b.string(),
      "base_stats": stats_schema_long(b),
      "abilities": b.object(
        properties={
          "ability1": b.string(),
          "ability2": b.string(),
          "dream_ability": b.string(),
        },
      ),
    },
    required=["name", "type1", "base_stats"],
  )
  let moves_min = if strict { 1 } else { 0 }
  let build_info = b.object(
    properties={
      "nature": strict_string(b, strict~),
      "nature_up": strict_string(b, strict~),
      "nature_down": strict_string(b, strict~),
      "ability": strict_string(b, strict~),
      "item": strict_string(b, strict~),
      "moves": b.array(
        items=pokemon_move_schema(b, strict~),
        min_items=moves_min,
        max_items=4,
      ),
      "evs": stats_schema_long(b),
      "actual_stats": stats_schema_long(b),
    },
    required=[
      "nature", "nature_up", "nature_down", "ability", "item", "moves", "evs",
      "actual_stats",
    ],
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
pub fn generate_placeholder(schema : @jsonschema.JsonSchema) -> Json {
  match schema {
    String(s) =>
      match s.enum_ {
        Some(values) if values.length() > 0 => values[0].to_json()
        _ => "".to_json()
      }
    Number(_) | Integer(_) => (0 : Int).to_json()
    Boolean(_) => false.to_json()
    Null(_) => Json::null()
    Any(_) => Json::null()
    Const(c) => c.value
    Enum(_) => Json::null()
    Array(_) => ([] : Array[Json]).to_json()
    Object(obj) =>
      match obj.properties {
        Some(props) => {
          let map : Map[String, Json] = {}
          props.each(fn(key, child_schema) {
            map.set(key, generate_placeholder(child_schema))
          })
          map.to_json()
        }
        None => ({} : Map[String, Json]).to_json()
      }
    OneOf(one_of) =>
      match @jsonschema.OneOfSchema::parse_nullable(one_of) {
        Some(_) => Json::null()
        None =>
          if one_of.schemas.length() > 0 {
            generate_placeholder(one_of.schemas[0])
          } else {
            Json::null()
          }
      }
    AnyOf(any_of) =>
      if any_of.schemas.length() > 0 {
        generate_placeholder(any_of.schemas[0])
      } else {
        Json::null()
      }
    AllOf(_) => Json::null()
    Ref(_) => Json::null()
  }
}

///|
/// breed用: 技4枠をnullプレースホルダで明示的にパッチ
fn patch_pokemon_moves(json : Json) -> Json {
  guard json is Object(root) else { return json }
  guard root.get("build") is Some(Object(build)) else { return json }
  fn fresh_move() -> Json {
    {
      "name": Json::null(),
      "type": "",
      "category": "",
      "power": 0,
      "accuracy": 0,
    }
  }

  build.set("moves", [fresh_move(), fresh_move(), fresh_move(), fresh_move()])
  json
}

///|
pub fn generate_team_placeholder() -> Json {
  let b = @jsonschema.Builder::new()
  let schema = team_schema(b, strict=false)
  generate_placeholder(schema)
}

///|
pub fn generate_pokemon_placeholder() -> Json {
  let b = @jsonschema.Builder::new()
  let schema = pokemon_schema(b, strict=false)
  let json = generate_placeholder(schema)
  patch_pokemon_moves(json)
}
