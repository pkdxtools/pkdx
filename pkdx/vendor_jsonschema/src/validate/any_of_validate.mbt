///|
impl Validatable for @types.AnyOfSchema with validate(
  self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  let errors : Array[ValidationError] = []
  let mut passed = 0
  for idx, schema in self.schemas {
    let sub_errors = Validatable::validate(
      schema,
      value,
      json_path~,
      schema_path=schema_path.key("anyOf").index(idx),
      resolver~,
    )
    if sub_errors.length() == 0 {
      passed += 1
    } else {
      errors.append(sub_errors)
    }
  }
  if passed > 0 {
    []
  } else {
    errors.push(
      ValidationError::new(
        value,
        json_path,
        schema_path.key("anyOf"),
        "Value does not match any schema in anyOf",
      ),
    )
    errors
  }
}

///|
test "AnyOfSchema::validate" {
  let b = @types.Builder::new()
  let schema = b.any_of([b.string(), b.integer()])
  let resolver = build_resolver({})
  // Valid: matches first schema (string)
  Validatable::validate(
    schema,
    "hello",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Valid: matches second schema (integer)
  Validatable::validate(
    schema,
    42,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: matches neither
  Validatable::validate(
    schema,
    3.14,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}
