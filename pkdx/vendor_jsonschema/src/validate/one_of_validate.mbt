///|
impl Validatable for @types.OneOfSchema with validate(
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
      schema_path=schema_path.key("oneOf").index(idx),
      resolver~,
    )
    if sub_errors.length() == 0 {
      passed += 1
    } else {
      errors.append(sub_errors)
    }
  }
  if passed == 1 {
    []
  } else {
    errors.push(
      ValidationError::new(
        value,
        json_path,
        schema_path.key("oneOf"),
        "Value does not match exactly one schema in oneOf",
      ),
    )
    errors
  }
}

///|
test "validate enum" {
  let b = @types.Builder::new()
  let reschema = b.one_of([
    b.array(prefix_items=[b.const_("A"), b.integer(), b.string()]),
    b.array(prefix_items=[b.const_("B"), b.number()]),
    b.array(prefix_items=[b.const_("C"), b.integer()]),
    b.const_("D"),
    b.array(prefix_items=[
      b.const_("Paramed"),
      b.object(properties={ "a": b.integer() }, required=["a"]),
    ]),
  ])
  let resolver = build_resolver({})
  Validatable::validate(
    reschema,
    "Not match",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
  Validatable::validate(
    reschema,
    "D",
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  Validatable::validate(
    reschema,
    ["A", 1, "str"],
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  Validatable::validate(
    reschema,
    ["B", 3.14],
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
}
