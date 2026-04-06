///|
pub(all) struct ArraySchema {
  items : JsonSchema?
  prefix_items : Array[JsonSchema]?
  contains : JsonSchema?
  min_contains : Int?
  max_contains : Int?
  min_items : Int?
  max_items : Int?
  strict_type : Bool? // Some(true) if "type": "array" was explicitly specified
} derive(Eq)

///|
pub impl ToJson for ArraySchema with to_json(self) {
  let obj : Map[String, Json] = {}
  if self.items is Some(v) {
    obj["items"] = v.to_json()
  }
  if self.prefix_items is Some(v) {
    obj["prefixItems"] = v.to_json()
  }
  if self.contains is Some(v) {
    obj["contains"] = v.to_json()
  }
  if self.min_contains is Some(v) {
    obj["minContains"] = v.to_json()
  }
  if self.max_contains is Some(v) {
    obj["maxContains"] = v.to_json()
  }
  if self.min_items is Some(v) {
    obj["minItems"] = v.to_json()
  }
  if self.max_items is Some(v) {
    obj["maxItems"] = v.to_json()
  }
  // Exclude strict_type from JSON output
  obj.to_json()
}

///|
impl JsonSchemaSerializable for ArraySchema with to_json_schema(self) {
  with_type_property(self.to_json(), "array")
}

///|
impl JsonSchemaSerializable for ArraySchema with parse(_json) {
  ...
}
