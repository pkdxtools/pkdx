///|
pub(all) struct AllOfSchema {
  schemas : Array[JsonSchema]
} derive(Eq)

///|
impl JsonSchemaSerializable for AllOfSchema with to_json_schema(self) {
  { "allOf": self.schemas.map(fn(s) { s.to_json() }) }
}

///|
impl JsonSchemaSerializable for AllOfSchema with parse(_json) {
  ...
}

///|
test "AllOfSchema::to_json_schema" {
  let b = Builder::new()
  let schema = b.all_of([b.integer(minimum=0), b.integer(maximum=100)])
  let json = schema.to_json()
  // Check it has allOf key
  guard json is { "allOf": _, .. }
}
