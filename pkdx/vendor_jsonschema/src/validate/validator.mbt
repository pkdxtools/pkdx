///|
/// Example:
/// ```
/// let jsonschema : Json = { "type": "string" }
/// let validator = build_validator(jsonschema)
/// let _result = validator.validate("hello")
/// ```
pub fn build_validator(raw : Json) -> Validator raise ParseError {
  let schema : @types.JsonSchema = @parser.parse_schema(raw) catch {
    err => raise ParseError::ParserError(err)
  }
  let resolver = Resolver::new(raw)
  Validator::{ schema, resolver }
}

///|
pub struct Validator {
  schema : @types.JsonSchema
  resolver : Resolver
}

///|
/// Create a validator from a pre-built schema (no parsing, no $ref support)
pub fn Validator::from_schema(schema : @types.JsonSchema) -> Validator {
  Validator::{ schema, resolver: Resolver::empty() }
}

///|
pub fn Validator::validate(
  self : Validator,
  input : Json,
) -> Result[Unit, Array[ValidationError]] {
  let errors = Validatable::validate(
    self.schema,
    input,
    resolver=self.resolver,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  if errors.length() == 0 {
    Ok(())
  } else {
    Err(errors)
  }
}

///|
test "build_validator and validate" {
  let schema : Json = {
    "type": "object",
    "properties": { "name": { "type": "string" }, "age": { "type": "integer" } },
    "required": ["name"],
  }
  let validator = build_validator(schema)
  // Valid input
  validator.validate({ "name": "John", "age": 30 }) |> assert_eq(Ok(()))
  // Valid: optional field missing
  validator.validate({ "name": "John" }) |> assert_eq(Ok(()))
  // Invalid: required field missing
  guard validator.validate({ "age": 30 }) is Err(_)
  // Invalid: wrong type
  guard validator.validate({ "name": 123 }) is Err(_)
}

///|
test "build_validator with simple types" {
  // String schema
  let str_validator = build_validator({ "type": "string" })
  str_validator.validate("hello") |> assert_eq(Ok(()))
  guard str_validator.validate(123) is Err(_)
  // Integer schema
  let int_validator = build_validator({ "type": "integer" })
  int_validator.validate(42) |> assert_eq(Ok(()))
  guard int_validator.validate("hello") is Err(_)
}
