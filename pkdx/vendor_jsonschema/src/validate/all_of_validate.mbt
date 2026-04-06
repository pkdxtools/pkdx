///|
impl Validatable for @types.AllOfSchema with validate(
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
      resolver~,
      json_path~,
      schema_path=schema_path.key("oneOf").index(idx),
    )
    if sub_errors.length() == 0 {
      passed += 1
    } else {
      errors.append(sub_errors)
    }
  }
  if passed == self.schemas.length() {
    []
  } else {
    errors.push(
      ValidationError::new(
        value,
        json_path,
        schema_path.key("allOf"),
        "Value does not match exactly one schema in allOf",
      ),
    )
    errors
  }
}

///|
test "AllOfSchema::validate" {
  let b = @types.Builder::new()
  // Must be an integer between 0 and 100
  let schema = b.all_of([b.integer(minimum=0), b.integer(maximum=100)])
  let resolver = build_resolver({})
  // Valid: satisfies all constraints
  Validatable::validate(
    schema,
    50,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: fails minimum constraint
  Validatable::validate(
    schema,
    -10,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
  // Invalid: fails maximum constraint
  Validatable::validate(
    schema,
    150,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}
