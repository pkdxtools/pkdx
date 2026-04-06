///|
/// JsonSchema compilation errors
pub suberror ParseError {
  ParserError(@parser.ParseError)
  PointerParseError(String)
  InvalidSchema(String)
}

///|
pub struct ValidationError {
  json_path : @types.JsonPointer
  schema_path : @types.JsonPointer
  message : String
  children : Array[ValidationError]?
} derive(Eq, Show)

///|
pub fn ValidationError::new(
  _input : Json,
  json_path : @types.JsonPointer,
  schema_path : @types.JsonPointer,
  message : String,
  children? : Array[ValidationError],
) -> ValidationError {
  ValidationError::{ json_path, schema_path, message, children }
}
