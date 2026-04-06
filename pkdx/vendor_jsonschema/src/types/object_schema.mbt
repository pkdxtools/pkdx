///|
pub(all) struct ObjectSchema {
  properties : Map[String, JsonSchema]?
  required : Array[String]?
  additional_properties : JsonSchema?
  strict_type : Bool? // Some(true) if "type": "object" was explicitly specified
} derive(Eq)

///|
pub impl ToJson for ObjectSchema with to_json(self) {
  let obj : Map[String, Json] = {}
  if self.properties is Some(v) {
    obj["properties"] = v.to_json()
  }
  if self.required is Some(v) {
    obj["required"] = v.to_json()
  }
  if self.additional_properties is Some(v) {
    obj["additionalProperties"] = v.to_json()
  }
  // Exclude strict_type from JSON output
  obj.to_json()
}

///|
impl JsonSchemaSerializable for ObjectSchema with to_json_schema(self) {
  with_type_property(self.to_json(), "object")
}

///|
impl JsonSchemaSerializable for ObjectSchema with parse(_json) {
  ...
}
