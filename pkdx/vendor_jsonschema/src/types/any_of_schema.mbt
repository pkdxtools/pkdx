///|
pub(all) struct AnyOfSchema {
  schemas : Array[JsonSchema]
} derive(Eq)

///|
impl JsonSchemaSerializable for AnyOfSchema with to_json_schema(self) {
  { "anyOf": self.schemas.map(fn(s) { s.to_json() }) }
}

///|
impl JsonSchemaSerializable for AnyOfSchema with parse(_json) {
  ...
}

///|
test "AnyOfSchema::to_json_schema" {
  let b = Builder::new()
  let schema = b.any_of([b.string(), b.integer()])
  let json = schema.to_json()
  // Check it has anyOf key
  guard json is { "anyOf": _, .. }
}
