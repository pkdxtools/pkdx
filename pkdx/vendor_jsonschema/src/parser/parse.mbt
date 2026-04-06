///|
/// Parse error for schema parsing
pub suberror ParseError {
  InvalidSchema(String)
} derive(Show)

///|
/// Parse JSON into JsonSchema
pub fn parse_schema(json : Json) -> @types.JsonSchema raise ParseError {
  parse_json_schema(json, "#")
}

///|
/// Internal parsing with path tracking
fn parse_json_schema(
  json : Json,
  path : String,
) -> @types.JsonSchema raise ParseError {
  // Handle boolean schemas: true allows everything, false rejects everything
  match json {
    True => return @types.JsonSchema::Any(@types.AnySchema::{  })
    False =>
      return @types.JsonSchema::AllOf({
        schemas: [
          @types.JsonSchema::String(@types.StringSchema::{
            min_length: None,
            max_length: None,
            enum_: None,
            strict_type: Some(true),
          }),
          @types.JsonSchema::Number(@types.NumberSchema::{
            minimum: None,
            maximum: None,
            exclusive_minimum: None,
            exclusive_maximum: None,
            multiple_of: None,
            strict_type: Some(true),
          }),
        ],
      })
    _ => ()
  }
  guard json is Json::Object(obj) else {
    raise ParseError::InvalidSchema("Expected an object at \{path}")
  }

  // Check if schema has multiple concerns that need to be combined with allOf
  let has_type = obj.contains("type")
  let has_any_of = obj.contains("anyOf")
  let has_all_of = obj.contains("allOf")
  let has_one_of = obj.contains("oneOf")
  let has_properties = obj.contains("properties") ||
    obj.contains("required") ||
    obj.contains("additionalProperties")
  let has_items = obj.contains("items") || obj.contains("prefixItems")
  let combinator_count = (if has_any_of { 1 } else { 0 }) +
    (if has_all_of { 1 } else { 0 }) +
    (if has_one_of { 1 } else { 0 })

  // If multiple combinators exist OR type/properties/items + combinator, wrap in allOf
  let needs_allof = combinator_count > 1 ||
    (has_type && combinator_count > 0) ||
    (has_properties && combinator_count > 0) ||
    (has_items && combinator_count > 0)
  if needs_allof {
    let schemas : Array[@types.JsonSchema] = []
    if has_type {
      guard obj.get("type") is Some(type_val) else { () }
      let type_only : Map[String, Json] = {}
      type_only["type"] = type_val
      schemas.push(parse_json_schema(type_only.to_json(), path))
    }
    if has_properties {
      let obj_only : Map[String, Json] = {}
      obj_only["type"] = "object"
      if obj.get("properties") is Some(props_val) {
        obj_only["properties"] = props_val
      }
      if obj.get("required") is Some(req_val) {
        obj_only["required"] = req_val
      }
      if obj.get("additionalProperties") is Some(add_val) {
        obj_only["additionalProperties"] = add_val
      }
      schemas.push(parse_json_schema(obj_only.to_json(), path))
    }
    if has_items {
      let arr_only : Map[String, Json] = {}
      arr_only["type"] = "array"
      if obj.get("items") is Some(items_val) {
        arr_only["items"] = items_val
      }
      if obj.get("prefixItems") is Some(prefix_val) {
        arr_only["prefixItems"] = prefix_val
      }
      schemas.push(parse_json_schema(arr_only.to_json(), path))
    }
    if has_any_of {
      guard obj.get("anyOf") is Some(any_of_val) else { () }
      let any_of_only : Map[String, Json] = {}
      any_of_only["anyOf"] = any_of_val
      schemas.push(parse_json_schema(any_of_only.to_json(), path))
    }
    if has_all_of {
      guard obj.get("allOf") is Some(Array(all_of_schemas)) else { () }
      for schema in all_of_schemas {
        schemas.push(parse_json_schema(schema, "\{path}/allOf"))
      }
    }
    if has_one_of {
      guard obj.get("oneOf") is Some(one_of_val) else { () }
      let one_of_only : Map[String, Json] = {}
      one_of_only["oneOf"] = one_of_val
      schemas.push(parse_json_schema(one_of_only.to_json(), path))
    }
    return @types.JsonSchema::AllOf({ schemas, })
  }
  match obj {
    // Handle type as array: convert to anyOf
    { "type": Array(types), .. } => {
      let schemas : Array[@types.JsonSchema] = []
      for t in types {
        guard t is String(type_name) else { continue }
        let type_json : Json = { "type": type_name }
        let schema = type_name_to_schema(type_name, type_json, path) catch {
          _ => continue
        }
        schemas.push(schema)
      }
      return @types.JsonSchema::AnyOf({ schemas, })
    }
    { "type": "any", .. } => @types.JsonSchema::Any(@types.AnySchema::{  })
    { "const": value, .. } => @types.JsonSchema::Const({ value, })
    { "$ref": String(refstr), .. } => {
      let pointer = @types.JsonPointer::from_string(refstr).unwrap()
      @types.JsonSchema::Ref(@types.RefSchema::{ pointer, })
    }
    { "type": "object", .. } => {
      let s = parse_object_schema(json, path)
      @types.JsonSchema::Object({ ..s, strict_type: Some(true) })
    }
    { "type": "array", .. } => {
      let s = parse_array_schema(json, path)
      @types.JsonSchema::Array({ ..s, strict_type: Some(true) })
    }
    { "type": "null", .. } => @types.JsonSchema::Null(@types.NullSchema::{  })
    { "type": "boolean", .. } =>
      @types.JsonSchema::Boolean(@types.BooleanSchema::{  })
    { "type": "string", .. } => {
      let s = parse_string_schema(json)
      @types.JsonSchema::String({ ..s, strict_type: Some(true) })
    }
    { "type": "number", .. } => {
      let s = parse_number_schema(json)
      @types.JsonSchema::Number({ ..s, strict_type: Some(true) })
    }
    { "type": "integer", .. } => {
      let s = parse_integer_schema(json)
      @types.JsonSchema::Integer({ ..s, strict_type: Some(true) })
    }
    { "anyOf": Array(schemas), .. } =>
      @types.JsonSchema::AnyOf({
        schemas: schemas.map(fn(s) { parse_json_schema(s, "\{path}/anyOf") }),
      })
    { "allOf": Array(schemas), .. } =>
      @types.JsonSchema::AllOf({
        schemas: schemas.map(fn(s) { parse_json_schema(s, "\{path}/allOf") }),
      })
    { "oneOf": Array(schemas), .. } =>
      @types.JsonSchema::OneOf({
        schemas: schemas.mapi(fn(i, s) {
          parse_json_schema(s, "\{path}/oneOf/\{i}")
        }),
        parsed_enumerable: None,
        parsed_nullable: None,
      })
    { "enum": Array(values), .. } =>
      @types.JsonSchema::Enum(@types.EnumSchema::{ values, })
    // Handle schemas without type but with constraints
    { "minimum": _, .. }
    | { "maximum": _, .. }
    | { "exclusiveMinimum": _, .. }
    | { "exclusiveMaximum": _, .. }
    | { "multipleOf": _, .. } => {
      let s = parse_number_schema(json)
      @types.JsonSchema::Number({ ..s, strict_type: None })
    }
    { "minLength": _, .. } | { "maxLength": _, .. } => {
      let s = parse_string_schema(json)
      @types.JsonSchema::String({ ..s, strict_type: None })
    }
    { "minItems": _, .. }
    | { "maxItems": _, .. }
    | { "items": _, .. }
    | { "prefixItems": _, .. } => {
      let s = parse_array_schema(json, path)
      @types.JsonSchema::Array({ ..s, strict_type: None })
    }
    { "properties": _, .. }
    | { "required": _, .. }
    | { "additionalProperties": _, .. } => {
      let s = parse_object_schema(json, path)
      @types.JsonSchema::Object({ ..s, strict_type: None })
    }
    _ => @types.JsonSchema::Any(@types.AnySchema::{  })
  }
}

///|
fn type_name_to_schema(
  type_name : String,
  json : Json,
  path : String,
) -> @types.JsonSchema raise ParseError {
  match type_name {
    "any" => @types.JsonSchema::Any(@types.AnySchema::{  })
    "object" => {
      let s = parse_object_schema(json, path)
      @types.JsonSchema::Object({ ..s, strict_type: Some(true) })
    }
    "array" => {
      let s = parse_array_schema(json, path)
      @types.JsonSchema::Array({ ..s, strict_type: Some(true) })
    }
    "null" => @types.JsonSchema::Null(@types.NullSchema::{  })
    "boolean" => @types.JsonSchema::Boolean(@types.BooleanSchema::{  })
    "string" => {
      let s = parse_string_schema(json)
      @types.JsonSchema::String({ ..s, strict_type: Some(true) })
    }
    "number" => {
      let s = parse_number_schema(json)
      @types.JsonSchema::Number({ ..s, strict_type: Some(true) })
    }
    "integer" => {
      let s = parse_integer_schema(json)
      @types.JsonSchema::Integer({ ..s, strict_type: Some(true) })
    }
    _ => @types.JsonSchema::Any(@types.AnySchema::{  })
  }
}

///|
/// Parse StringSchema from JSON
fn parse_string_schema(json : Json) -> @types.StringSchema {
  guard json is Json::Object(obj) else {
    return @types.StringSchema::{
      min_length: None,
      max_length: None,
      enum_: None,
      strict_type: None,
    }
  }
  let min_length : Int? = match obj.get("minLength") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let max_length : Int? = match obj.get("maxLength") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let enum_ : Array[String]? = match obj.get("enum") {
    Some(Array(arr)) => {
      let strs : Array[String] = []
      for item in arr {
        if item is String(s) {
          strs.push(s)
        }
      }
      Some(strs)
    }
    _ => None
  }
  @types.StringSchema::{ min_length, max_length, enum_, strict_type: None }
}

///|
/// Parse NumberSchema from JSON
fn parse_number_schema(json : Json) -> @types.NumberSchema {
  guard json is Json::Object(obj) else {
    return @types.NumberSchema::{
      minimum: None,
      maximum: None,
      exclusive_minimum: None,
      exclusive_maximum: None,
      multiple_of: None,
      strict_type: None,
    }
  }
  let minimum : Double? = match obj.get("minimum") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  let maximum : Double? = match obj.get("maximum") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  let exclusive_minimum : Double? = match obj.get("exclusiveMinimum") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  let exclusive_maximum : Double? = match obj.get("exclusiveMaximum") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  let multiple_of : Double? = match obj.get("multipleOf") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  @types.NumberSchema::{
    minimum,
    maximum,
    exclusive_minimum,
    exclusive_maximum,
    multiple_of,
    strict_type: None,
  }
}

///|
/// Parse IntegerSchema from JSON
fn parse_integer_schema(json : Json) -> @types.IntegerSchema {
  guard json is Json::Object(obj) else {
    return @types.IntegerSchema::{
      minimum: None,
      maximum: None,
      exclusive_minimum: None,
      exclusive_maximum: None,
      multiple_of: None,
      strict_type: None,
    }
  }
  let minimum : Int? = match obj.get("minimum") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let maximum : Int? = match obj.get("maximum") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let exclusive_minimum : Int? = match obj.get("exclusiveMinimum") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let exclusive_maximum : Int? = match obj.get("exclusiveMaximum") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let multiple_of : Int? = match obj.get("multipleOf") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  @types.IntegerSchema::{
    minimum,
    maximum,
    exclusive_minimum,
    exclusive_maximum,
    multiple_of,
    strict_type: None,
  }
}

///|
/// Parse ArraySchema from JSON
fn parse_array_schema(
  json : Json,
  path : String,
) -> @types.ArraySchema raise ParseError {
  guard json is Json::Object(obj) else {
    return @types.ArraySchema::{
      items: None,
      prefix_items: None,
      contains: None,
      min_contains: None,
      max_contains: None,
      min_items: None,
      max_items: None,
      strict_type: None,
    }
  }
  let items : @types.JsonSchema? = match obj.get("items") {
    Some(v) => Some(parse_json_schema(v, "\{path}/items"))
    _ => None
  }
  let prefix_items : Array[@types.JsonSchema]? = match obj.get("prefixItems") {
    Some(Array(arr)) =>
      Some(
        arr.mapi(fn(i, v) { parse_json_schema(v, "\{path}/prefixItems/\{i}") }),
      )
    _ => None
  }
  let contains : @types.JsonSchema? = match obj.get("contains") {
    Some(v) => Some(parse_json_schema(v, "\{path}/contains"))
    _ => None
  }
  let min_contains : Int? = match obj.get("minContains") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let max_contains : Int? = match obj.get("maxContains") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let min_items : Int? = match obj.get("minItems") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let max_items : Int? = match obj.get("maxItems") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  @types.ArraySchema::{
    items,
    prefix_items,
    contains,
    min_contains,
    max_contains,
    min_items,
    max_items,
    strict_type: None,
  }
}

///|
/// Parse ObjectSchema from JSON
fn parse_object_schema(
  json : Json,
  path : String,
) -> @types.ObjectSchema raise ParseError {
  guard json is Json::Object(obj) else {
    return @types.ObjectSchema::{
      properties: None,
      required: None,
      additional_properties: None,
      strict_type: None,
    }
  }
  let properties : Map[String, @types.JsonSchema]? = match
    obj.get("properties") {
    Some(Object(props_obj)) => {
      let result : Map[String, @types.JsonSchema] = {}
      for k, v in props_obj {
        result[k] = parse_json_schema(v, "\{path}/properties/\{k}")
      }
      Some(result)
    }
    _ => None
  }
  let required : Array[String]? = match obj.get("required") {
    Some(Array(arr)) => {
      let strs : Array[String] = []
      for item in arr {
        if item is String(s) {
          strs.push(s)
        }
      }
      Some(strs)
    }
    _ => None
  }
  let additional_properties : @types.JsonSchema? = match
    obj.get("additionalProperties") {
    Some(True) => None // true means allow any additional properties (default)
    Some(False) => Some(@types.JsonSchema::AllOf({ schemas: [] })) // false rejects all
    Some(v) => Some(parse_json_schema(v, "\{path}/additionalProperties"))
    None => None
  }
  @types.ObjectSchema::{
    properties,
    required,
    additional_properties,
    strict_type: None,
  }
}
