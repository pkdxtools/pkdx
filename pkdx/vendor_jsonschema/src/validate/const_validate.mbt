///|
impl Validatable for @types.ConstSchema with validate(
  self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  ignore(resolver)
  if value != self.value {
    [
      ValidationError::new(
        value,
        json_path,
        schema_path,
        "Value does not match constant value \{self.value}",
      ),
    ]
  } else {
    []
  }
}

///|
impl Validatable for @types.EnumSchema with validate(
  self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  ignore(resolver)
  if !self.values.contains(value) {
    [
      ValidationError::new(
        value,
        json_path,
        schema_path,
        "\{value} is not in \{self.values}",
      ),
    ]
  } else {
    []
  }
}

///|
test "ConstSchema::validate" {
  let b = @types.Builder::new()
  let schema = b.const_("hello")
  let resolver = build_resolver({})
  // Valid: matches const
  Validatable::validate(
    schema,
    "hello",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: does not match
  Validatable::validate(
    schema,
    "world",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}

///|
test "EnumSchema::validate" {
  let b = @types.Builder::new()
  let schema = b.enum_(["red", "green", "blue"])
  let resolver = build_resolver({})
  // Valid: value in enum
  Validatable::validate(
    schema,
    "red",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: value not in enum
  Validatable::validate(
    schema,
    "yellow",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}
