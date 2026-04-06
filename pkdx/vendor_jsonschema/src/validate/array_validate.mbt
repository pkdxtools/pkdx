///|
impl Validatable for @types.ArraySchema with validate(
  self,
  value,
  resolver~,
  json_path~,
  schema_path~,
) {
  guard value is Array(array) else {
    // If strict_type is not Some(true), ignore non-arrays
    guard self.strict_type is Some(true) else { return [] }
    return [
      ValidationError::new(
        value, json_path, schema_path, "Value is not an array",
      ),
    ]
  }
  let errors : Array[ValidationError] = []
  let len = array.length()

  // Min items
  if self.min_items is Some(min) && len < min {
    errors.push(
      ValidationError::new(
        value,
        json_path,
        schema_path.key("minItems"),
        "Array length is less than minimum",
      ),
    )
  }

  // Max items
  if self.max_items is Some(max) && len > max {
    errors.push(
      ValidationError::new(
        value,
        json_path,
        schema_path.key("maxItems"),
        "Array length is greater than maximum",
      ),
    )
  }
  // Determine the starting index for items validation
  // When prefixItems is present, items only applies to indices beyond prefixItems
  let items_start_index = match self.prefix_items {
    Some(prefix) => prefix.length()
    None => 0
  }

  // check prefixItems first
  if self.prefix_items is Some(prefix_items) {
    let prefix_len = prefix_items.length()
    let check_len = if len < prefix_len { len } else { prefix_len }
    for idx = 0; idx < check_len; idx = idx + 1 {
      let item_schema = prefix_items[idx]
      let item_value = array[idx]
      let child_errors = Validatable::validate(
        item_schema,
        item_value,
        resolver~,
        json_path=json_path.index(idx),
        schema_path=schema_path.key("prefixItems").index(idx),
      )
      errors.append(child_errors)
    }
  }

  // check items (only for indices beyond prefixItems)
  if self.items is Some(item_schema) {
    for i = items_start_index; i < len; i = i + 1 {
      let item = array[i]
      let child_errors = Validatable::validate(
        item_schema,
        item,
        resolver~,
        json_path=json_path.index(i),
        schema_path=schema_path.key("items"),
      )
      errors.append(child_errors)
    }
  }
  errors
}

///|
test "ArraySchema::validate basic" {
  let b = @types.Builder::new()
  let schema = b.array()
  let resolver = build_resolver({})
  // Valid array
  let arr : Json = [1, 2, 3]
  Validatable::validate(
    schema,
    arr,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Not an array
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
test "ArraySchema::validate with min/max items" {
  let b = @types.Builder::new()
  let schema = b.array(min_items=2, max_items=4)
  let resolver = build_resolver({})
  // Valid: within range
  let arr3 : Json = [1, 2, 3]
  Validatable::validate(
    schema,
    arr3,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: too few items
  let arr1 : Json = [1]
  Validatable::validate(
    schema,
    arr1,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
  // Invalid: too many items
  let arr5 : Json = [1, 2, 3, 4, 5]
  Validatable::validate(
    schema,
    arr5,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}

///|
test "ArraySchema::validate with items schema" {
  let b = @types.Builder::new()
  let schema = b.array(items=b.string())
  let resolver = build_resolver({})
  // Valid: all items are strings
  let arr_valid : Json = ["a", "b", "c"]
  Validatable::validate(
    schema,
    arr_valid,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_eq([])
  // Invalid: contains non-string
  let arr_invalid : Json = ["a", 123, "c"]
  Validatable::validate(
    schema,
    arr_invalid,
    resolver~,
    json_path=@types.JsonPointer::Root,
    schema_path=@types.JsonPointer::Root,
  )
  |> assert_not_eq([])
}
