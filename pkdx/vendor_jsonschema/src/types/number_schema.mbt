///|
pub(all) struct NumberSchema {
  minimum : Double?
  maximum : Double?
  exclusive_minimum : Double?
  exclusive_maximum : Double?
  multiple_of : Double?
  strict_type : Bool? // Some(true) if "type": "number" was explicitly specified
} derive(Eq)

///|
pub impl ToJson for NumberSchema with to_json(self) {
  let obj : Map[String, Json] = {}
  if self.minimum is Some(v) {
    obj["minimum"] = v.to_json()
  }
  if self.maximum is Some(v) {
    obj["maximum"] = v.to_json()
  }
  if self.exclusive_minimum is Some(v) {
    obj["exclusiveMinimum"] = v.to_json()
  }
  if self.exclusive_maximum is Some(v) {
    obj["exclusiveMaximum"] = v.to_json()
  }
  if self.multiple_of is Some(v) {
    obj["multipleOf"] = v.to_json()
  }
  // Exclude strict_type from JSON output
  obj.to_json()
}

///|
impl JsonSchemaSerializable for NumberSchema with to_json_schema(self) {
  with_type_property(self.to_json(), "number")
}

///|
impl JsonSchemaSerializable for NumberSchema with parse(_json) {
  ...
}
