///|
impl Validatable for @types.NumberSchema with validate(
  self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  ignore(resolver)
  guard value is Number(input, ..) else {
    // If strict_type is not Some(true), ignore non-numbers
    guard self.strict_type is Some(true) else { return [] }
    return [
      ValidationError::new(
        value, json_path, schema_path, "Value is not a number",
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
  if multiple_of is Some(divisor) && divisor != 0.0 {
    let remainder = input % divisor
    // Check if remainder is effectively zero (accounting for floating point precision)
    let abs_remainder = if remainder < 0.0 { -remainder } else { remainder }
    let epsilon = 0.0000000001
    if abs_remainder > epsilon && divisor - abs_remainder > epsilon {
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
test "NumberSchema::validate basic" {
  let b = @types.Builder::new()
  let schema = b.number()
  let resolver = build_resolver({})
  // Valid number
  Validatable::validate(
    schema,
    3.14,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Not a number
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
test "NumberSchema::validate with min/max" {
  let b = @types.Builder::new()
  let schema = b.number(minimum=0.0, maximum=10.0)
  let resolver = build_resolver({})
  // Valid: within range
  Validatable::validate(
    schema,
    5.0,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: below minimum
  Validatable::validate(
    schema,
    -1.0,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
  // Invalid: above maximum
  Validatable::validate(
    schema,
    11.0,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}

///|
test "NumberSchema::validate with exclusive min/max" {
  let b = @types.Builder::new()
  let schema = b.number(exclusive_minimum=0.0, exclusive_maximum=10.0)
  let resolver = build_resolver({})
  // Valid: strictly within range
  Validatable::validate(
    schema,
    5.0,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: equals exclusive minimum
  Validatable::validate(
    schema,
    0.0,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
  // Invalid: equals exclusive maximum
  Validatable::validate(
    schema,
    10.0,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}
