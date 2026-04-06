///|
pub(all) struct RefSchema {
  pointer : JsonPointer
} derive(Eq)

///|
impl JsonSchemaSerializable for RefSchema with to_json_schema(self) {
  { "$ref": self.pointer.to_string() }
}

///|
impl JsonSchemaSerializable for RefSchema with parse(json) {
  guard json is { "$ref": String(refstr), .. } else {
    return Err("Expected string for RefSchema".to_string())
  }
  let pointer = JsonPointer::from_string(refstr).unwrap()
  RefSchema::{ pointer, } |> JsonSchema::Ref |> Ok
}
