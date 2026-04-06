///|
impl Validatable for @types.StringSchema with validate(
  self,
  input,
  resolver~,
  json_path~,
  schema_path~,
) {
  ignore(resolver)
  guard input is Json::String(input) else {
    // If strict_type is not Some(true), ignore non-strings
    guard self.strict_type is Some(true) else { return [] }
    return [
      ValidationError::new(
        input, json_path, schema_path, "Value is not a string",
      ),
    ]
  }
  let errors : Array[ValidationError] = []
  let len = input.length()
  if self.min_length is Some(min) && len < min {
    errors.push(
      ValidationError::new(
        input.to_json(),
        json_path,
        schema_path.key("minLength"),
        "String length is less than minimum",
      ),
    )
  }
  if self.max_length is Some(max) && len > max {
    return [
      ValidationError::new(
        input.to_json(),
        json_path,
        schema_path.key("maxLength"),
        "String length is greater than maximum",
      ),
    ]
  }
  if self.enum_ is Some(enum_values) && !enum_values.contains(input) {
    return [
      ValidationError::new(
        input.to_json(),
        json_path,
        schema_path.key("enum"),
        "Value is not in enum",
      ),
    ]
  }
  errors
}

///|
test "StringConstraint::from_json validate and to_json" {
  let json : Json = { "type": "string" }
  let s : @types.JsonSchema = @parser.parse_schema(json)
  let resolver = build_resolver({})
  Validatable::validate(
    s,
    "hell",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  s.to_json() |> assert_eq(json)
}

///|
test "StringConstraint::validate" {
  let b = @types.Builder::new()
  let schema = b.string(minLength=3, maxLength=5)
  let resolver = build_resolver({})
  let err_with_min_err = Validatable::validate(
    schema,
    "h",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  assert_not_eq(err_with_min_err, [])
  Validatable::validate(
    schema,
    "hell",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // not string
  Validatable::validate(
    schema,
    1,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}
