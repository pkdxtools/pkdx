///|
pub(all) struct StringSchema {
  min_length : Int?
  max_length : Int?
  enum_ : Array[String]?
  strict_type : Bool? // Some(true) if "type": "string" was explicitly specified
} derive(Eq)

///|
pub impl ToJson for StringSchema with to_json(self) {
  let obj : Map[String, Json] = {}
  if self.min_length is Some(v) {
    obj["minLength"] = v.to_json()
  }
  if self.max_length is Some(v) {
    obj["maxLength"] = v.to_json()
  }
  if self.enum_ is Some(v) {
    obj["enum"] = v.to_json()
  }
  // Exclude strict_type from JSON output
  obj.to_json()
}

///|
impl JsonSchemaSerializable for StringSchema with to_json_schema(self) {
  with_type_property(self.to_json(), "string")
}

///|
impl JsonSchemaSerializable for StringSchema with parse(_json) {
  ...
}
