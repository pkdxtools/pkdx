///|
pub(all) struct ConstSchema {
  value : Json
} derive(Eq)

///|
impl JsonSchemaSerializable for ConstSchema with to_json_schema(self) {
  { "const": self.value.to_json() }
}

///|
impl JsonSchemaSerializable for ConstSchema with parse(_json) {
  ...
}

///|
pub(all) struct EnumSchema {
  values : Array[Json]
} derive(Eq)

///|
impl JsonSchemaSerializable for EnumSchema with to_json_schema(self) {
  { "enum": self.values.to_json() }
}

///|
impl JsonSchemaSerializable for EnumSchema with parse(_json) {
  ...
}
