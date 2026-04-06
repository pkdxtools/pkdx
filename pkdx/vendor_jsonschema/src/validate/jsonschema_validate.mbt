///|
pub impl Validatable for @types.JsonSchema with validate(
  self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  match self {
    @types.JsonSchema::Const(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::Integer(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::Enum(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::Boolean(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::Ref(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::Null(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::Any(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::Number(c) =>
      Validatable::validate(c, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::String(c) =>
      Validatable::validate(c, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::Array(c) =>
      Validatable::validate(c, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::Object(v) =>
      Validatable::validate(v, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::AllOf(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::OneOf(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
    @types.JsonSchema::AnyOf(s) =>
      Validatable::validate(s, value, resolver~, json_path~, schema_path~)
  }
}

///|
impl Validatable for @types.AnySchema with validate(
  _self,
  _value,
  resolver~,
  json_path~,
  schema_path~,
) {
  ignore((json_path, schema_path, resolver))
  []
}

///|
impl Validatable for @types.NullSchema with validate(
  _self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  ignore((json_path, schema_path, resolver))
  match value {
    Null => []
    _ =>
      [ValidationError::new(value, json_path, schema_path, "Value is not null")]
  }
}

///|
impl Validatable for @types.BooleanSchema with validate(
  _self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  ignore((json_path, schema_path, resolver))
  match value {
    True => []
    False => []
    _ =>
      [
        ValidationError::new(
          value, json_path, schema_path, "Value is not a boolean",
        ),
      ]
  }
}
