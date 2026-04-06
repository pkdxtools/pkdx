///|
/// OneOf schema
pub(all) struct OneOfSchema {
  schemas : Array[JsonSchema]
  parsed_nullable : JsonSchema?
  parsed_enumerable : Array[Enumerable]?
} derive(Eq)

///|
impl JsonSchemaSerializable for OneOfSchema with to_json_schema(self) {
  { "oneOf": self.schemas.map(fn(s) { s.to_json() }) }
}

///|
impl JsonSchemaSerializable for OneOfSchema with parse(_json) {
  ...
}

///|
pub(all) struct Enumerable {
  // variant tag
  tag : String
  // positional types
  positionals : Array[JsonSchema]?
  // named parameters
  params : Map[String, JsonSchema]?
} derive(Eq)

///|
pub fn Enumerable::new(
  tag : String,
  positionals : Array[JsonSchema]?,
  // should be Object with properties
  params : Map[String, JsonSchema]?,
) -> Enumerable {
  { tag, positionals, params }
}

///|
pub fn Enumerable::parse_enumerable(schema : OneOfSchema) -> Array[Enumerable]? {
  let parsed : Array[Enumerable] = []
  for schema in schema.schemas {
    match schema {
      // {"const": "A"}
      Const(s) if s.value is String(tag_value) =>
        parsed.push(Enumerable::new(tag_value, None, None))
      // [{"const": "A"}, { "type": "array", .. }]
      Array(
        {
          prefix_items: Some([JsonSchema::Const({ value: String(tag_value) })]),
          ..,
        }
      ) => parsed.push(Enumerable::new(tag_value, None, None))
      // [{"const": "A"}, ..]
      Array(
        {
          prefix_items: Some(
            [Const({ value: String(tag_value) }), .. child_schemas]
          ),
          ..,
        }
      ) => {
        let matched = match child_schemas.to_array() {
          [] => { tag: tag_value, positionals: None, params: None }
          [.. positionals, Object(v)] =>
            {
              tag: tag_value,
              positionals: positionals.to_array() |> Some,
              params: v.properties,
            }
          [.. positionals] =>
            {
              tag: tag_value,
              positionals: positionals.to_array() |> Some,
              params: None,
            }
        }
        parsed.push(matched)
      }
      _ => ()
    }
  }
  return Some(parsed)
}

///|
/// detect nullable enumerable by [ <Schema>, {"type": "null"}]
pub fn OneOfSchema::parse_nullable(schema : OneOfSchema) -> JsonSchema? {
  match schema.schemas {
    [s, JsonSchema::Null(_)] | [JsonSchema::Null(_), s] => return Some(s)
    _ => return None
  }
}
