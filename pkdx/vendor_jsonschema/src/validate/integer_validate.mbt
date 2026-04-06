///|
impl Validatable for @types.IntegerSchema with validate(
  self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  ignore(resolver)
  guard value is Number(input, ..) && input == input.to_int().to_double() else {
    // If strict_type is not Some(true), ignore non-integers
    guard self.strict_type is Some(true) else { return [] }
    return [
      ValidationError::new(
        value, json_path, schema_path, "Value is not an integer",
      ),
    ]
  }
  let {
    minimum,
    maximum,
    exclusive_minimum,
    exclusive_maximum,
    multiple_of,
    ..,
  } = self
  let errors : Array[ValidationError] = []
  let input : Int = input.to_int()
  if multiple_of is Some(divisor) && divisor != 0 {
    if input % divisor != 0 {
      errors.push(
        ValidationError::new(
          value,
          json_path,
          schema_path.key("multipleOf"),
          "Value is not a multiple of the specified divisor",
        ),
      )
    }
  }
  if minimum is Some(min) && input < min {
    errors.push(
      ValidationError::new(
        value,
        json_path,
        schema_path.key("minimum"),
        "Value is less than minimum",
      ),
    )
  }
  if maximum is Some(max) && input > max {
    errors.push(
      ValidationError::new(
        value,
        json_path,
        schema_path.key("maximum"),
        "Value is greater than maximum",
      ),
    )
  }
  if exclusive_maximum is Some(max) && input >= max {
    errors.push(
      ValidationError::new(
        value,
        json_path,
        schema_path.key("exclusiveMaximum"),
        "Value is not less than exclusive maximum",
      ),
    )
  }
  if exclusive_minimum is Some(min) && input <= min {
    errors.push(
      ValidationError::new(
        value,
        json_path,
        schema_path.key("exclusiveMinimum"),
        "Value is not greater than exclusive minimum",
      ),
    )
  }
  errors
}

///|
test "IntegerSchema::validate basic" {
  let b = @types.Builder::new()
  let schema = b.integer()
  let resolver = build_resolver({})
  // Valid integer
  Validatable::validate(
    schema,
    42,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Float is not integer
  Validatable::validate(
    schema,
    3.14,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
  // String is not integer
  Validatable::validate(
    schema,
    "hello",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}

///|
test "IntegerSchema::validate with min/max" {
  let b = @types.Builder::new()
  let schema = b.integer(minimum=0, maximum=100)
  let resolver = build_resolver({})
  // Valid: within range
  Validatable::validate(
    schema,
    50,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: below minimum
  Validatable::validate(
    schema,
    -1,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
  // Invalid: above maximum
  Validatable::validate(
    schema,
    101,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}

///|
test "IntegerSchema::validate with exclusive bounds" {
  let b = @types.Builder::new()
  let schema = b.integer(exclusive_minimum=0, exclusive_maximum=10)
  let resolver = build_resolver({})
  // Valid: strictly within range
  Validatable::validate(
    schema,
    5,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: equals exclusive minimum
  Validatable::validate(
    schema,
    0,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
  // Invalid: equals exclusive maximum
  Validatable::validate(
    schema,
    10,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}
