///|
impl Validatable for @types.RefSchema with validate(
  self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  match resolver.resolve(self.pointer) {
    Some(resolved_schema) => {
      let errors = Validatable::validate(
        resolved_schema,
        value,
        json_path~,
        schema_path=schema_path.key("$ref"),
        resolver~,
      )
      errors
    }
    None =>
      [
        ValidationError::new(
          value,
          json_path,
          schema_path.key("$ref"),
          "Failed to resolve reference '\{self.pointer}'",
        ),
      ]
  }
}

///|
test "RefSchema::validate resolves reference" {
  let raw : Json = {
    "definitions": { "MyString": { "type": "string" } },
    "type": "object",
    "properties": { "name": { "$ref": "#/definitions/MyString" } },
  }
  let b = @types.Builder::new()
  let schema = b.ref_from_string("#/definitions/MyString")
  let resolver = build_resolver(raw)
  // Valid: string matches referenced schema
  Validatable::validate(
    schema,
    "hello",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: number doesn't match string schema
  Validatable::validate(
    schema,
    123,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}

///|
test "RefSchema::validate unresolved reference" {
  let b = @types.Builder::new()
  let schema = b.ref_from_string("#/definitions/NotFound")
  let resolver = build_resolver({})
  // Unresolved reference should error
  Validatable::validate(
    schema,
    "anything",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}
