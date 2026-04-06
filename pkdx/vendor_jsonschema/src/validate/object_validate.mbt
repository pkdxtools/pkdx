///|
impl Validatable for @types.ObjectSchema with validate(
  self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  guard value is Object(obj) else {
    // If strict_type is not Some(true), ignore non-objects
    guard self.strict_type is Some(true) else { return [] }
    return [
      ValidationError::new(
        value, json_path, schema_path, "Value is not an object",
      ),
    ]
  }
  let errors : Array[ValidationError] = []

  // Required properties - direct iteration without intermediate array
  if self.required is Some(required_keys) {
    for key in required_keys {
      if not(obj.contains(key)) {
        errors.push(
          ValidationError::new(
            value,
            json_path.key(key),
            schema_path.key("required"),
            "Required property is missing",
          ),
        )
      }
    }
  }

  // Properties validation
  if self.properties is Some(props) {
    for prop_name, child_schema in props {
      if obj.get(prop_name) is Some(child_value) {
        let child_errors = Validatable::validate(
          child_schema,
          child_value,
          json_path=json_path.key(prop_name),
          schema_path=schema_path.key("properties").key(prop_name),
          resolver~,
        )
        errors.append(child_errors)
      }
    }
  }

  // Validate additional properties only if additionalProperties schema is specified
  if self.additional_properties is Some(schema) {
    for key, child_value in obj {
      // Skip if key is in properties
      let in_properties = match self.properties {
        Some(props) => props.contains(key)
        None => false
      }
      if not(in_properties) {
        let child_errors = Validatable::validate(
          schema,
          child_value,
          json_path=json_path.key(key),
          schema_path=schema_path.key("additionalProperties"),
          resolver~,
        )
        errors.append(child_errors)
      }
    }
  }
  errors
}

///|
test "ObjectSchema::validate basic" {
  let b = @types.Builder::new()
  // Object with any additional properties allowed
  let schema = b.object(additional_properties=b.any())
  let resolver = build_resolver({})
  // Valid object
  Validatable::validate(
    schema,
    { "a": 1, "b": 2 },
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Not an object
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
test "ObjectSchema::validate with required" {
  let b = @types.Builder::new()
  let schema = b.object(properties={ "name": b.string(), "age": b.integer() }, required=[
    "name", "age",
  ])
  let resolver = build_resolver({})
  // Valid: all required present
  Validatable::validate(
    schema,
    { "name": "John", "age": 30 },
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: missing required field
  Validatable::validate(
    schema,
    { "name": "John" },
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}

///|
test "ObjectSchema::validate properties" {
  let b = @types.Builder::new()
  let schema = b.object(properties={ "count": b.integer(minimum=0) }, required=[
    "count",
  ])
  let resolver = build_resolver({})
  // Valid: property matches schema
  Validatable::validate(
    schema,
    { "count": 5 },
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: property violates schema
  Validatable::validate(
    schema,
    { "count": -1 },
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}
