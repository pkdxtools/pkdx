// JSON Schema types and definitions

///|
priv trait JsonSchemaSerializable {
  parse(Json) -> Result[JsonSchema, String]
  to_json_schema(Self) -> Json
}

///|
/// JsonSchema
pub(all) enum JsonSchema {
  Any(AnySchema)
  Null(NullSchema)
  Boolean(BooleanSchema)
  String(StringSchema)
  Number(NumberSchema)
  Integer(IntegerSchema)
  Array(ArraySchema)
  Object(ObjectSchema)
  AnyOf(AnyOfSchema)
  AllOf(AllOfSchema)
  OneOf(OneOfSchema)
  Ref(RefSchema)
  Enum(EnumSchema)
  Const(ConstSchema)
  // Not(JsonSchema)
  // If(Schema, Schema?, Schema?) // if, then, else
} derive(Eq)

///|
/// Helper function for adding type property to JSON
fn with_type_property(json : Json, type_name : String) -> Json {
  guard json is Json::Object(obj) else { return json }
  let json : Map[String, Json] = { "type": type_name.to_json() }
  for k, v in obj {
    json[k] = v
  }
  return json.to_json()
}

///|
pub impl ToJson for JsonSchema with to_json(self) -> Json {
  match self {
    Any(s) => s.to_json_schema()
    Null(s) => s.to_json_schema()
    Boolean(s) => s.to_json_schema()
    String(s) => s.to_json_schema()
    Number(s) => s.to_json_schema()
    Integer(s) => s.to_json_schema()
    Array(s) => s.to_json_schema()
    Object(s) => s.to_json_schema()
    JsonSchema::AnyOf(s) => s.to_json_schema()
    JsonSchema::AllOf(s) => s.to_json_schema()
    JsonSchema::OneOf(s) => s.to_json_schema()
    Ref(s) => s.to_json_schema()
    Const(s) => s.to_json_schema()
    Enum(s) => s.to_json_schema()
  }
}

///| Primitive types

///|
pub(all) struct AnySchema {} derive(Eq)

///|
impl JsonSchemaSerializable for AnySchema with to_json_schema(_self) {
  { "type": "any" }
}

///|
impl JsonSchemaSerializable for AnySchema with parse(_json) {
  ...
}

///|
pub(all) struct NullSchema {} derive(Eq)

///|
impl JsonSchemaSerializable for NullSchema with to_json_schema(_self) {
  with_type_property({}, "null")
}

///|
impl JsonSchemaSerializable for NullSchema with parse(_json) {
  ...
}

///|
pub(all) struct BooleanSchema {} derive(Eq)

///|
impl JsonSchemaSerializable for BooleanSchema with to_json_schema(_self) {
  with_type_property({}, "boolean")
}

///|
impl JsonSchemaSerializable for BooleanSchema with parse(_json) {
  ...
}
