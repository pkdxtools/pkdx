// builder

///|
/// Schema builder like a zod schema
/// Example usage:
/// ```moon
/// let b = @jsonschema.Builder::new()
/// let schema = b.object(
///   properties={
///     name: b.string(),
///     age: b.number(),
///   },
///   required=["name", "age"],
/// )
/// ```
pub struct Builder {
  priv internal_state : Map[JsonPointer, JsonSchema]
}

///|
pub fn Builder::new() -> Builder {
  // TODO: use with resolver later
  Builder::{ internal_state: Map::new() }
}

///|
pub fn Builder::define_schema(
  self : Builder,
  pointer : JsonPointer,
  schema : JsonSchema,
) -> RefSchema {
  self.internal_state.set(pointer, schema)
  RefSchema::{ pointer, }
}

///|
pub fn Builder::emit_json_schema(_self : Builder) -> Json {
  let raw : Json = {}
  raw
}

///|
/// { "type": "string" }
pub fn Builder::string(
  _self : Builder,
  minLength? : Int,
  maxLength? : Int,
  enum_? : Array[String],
) -> JsonSchema {
  JsonSchema::String({
    min_length: minLength,
    max_length: maxLength,
    enum_,
    strict_type: Some(true),
  })
}

///|
/// { "type": "number" }
pub fn Builder::number(
  _self : Builder,
  minimum? : Double,
  maximum? : Double,
  exclusive_minimum? : Double,
  exclusive_maximum? : Double,
  multiple_of? : Double,
) -> JsonSchema {
  JsonSchema::Number({
    minimum,
    maximum,
    exclusive_minimum,
    exclusive_maximum,
    multiple_of,
    strict_type: Some(true),
  })
}

///|
/// { "type": "integer" }
pub fn Builder::integer(
  _self : Builder,
  minimum? : Int,
  maximum? : Int,
  exclusive_minimum? : Int,
  exclusive_maximum? : Int,
  multiple_of? : Int,
) -> JsonSchema {
  JsonSchema::Integer({
    minimum,
    maximum,
    exclusive_minimum,
    exclusive_maximum,
    multiple_of,
    strict_type: Some(true),
  })
}

///|
/// { "type": "array" }
pub fn Builder::array(
  _self : Builder,
  items? : JsonSchema,
  prefix_items? : Array[JsonSchema],
  contains? : JsonSchema,
  min_contains? : Int,
  max_contains? : Int,
  min_items? : Int,
  max_items? : Int,
) -> JsonSchema {
  JsonSchema::Array({
    items,
    prefix_items,
    contains,
    min_contains,
    max_contains,
    min_items,
    max_items,
    strict_type: Some(true),
  })
}

///|
/// { "type": "null" }
pub fn Builder::null(_self : Builder) -> JsonSchema {
  Null(NullSchema::{  })
}

///|
/// { "type": "boolean" }
pub fn Builder::boolean(_self : Builder) -> JsonSchema {
  Boolean(BooleanSchema::{  })
}

///|
/// { "type": "any" }
pub fn Builder::any(_self : Builder) -> JsonSchema {
  Any(AnySchema::{  })
}

///|
/// { "type": "object" }
pub fn Builder::object(
  _self : Builder,
  properties? : Map[String, JsonSchema],
  required? : Array[String],
  additional_properties? : JsonSchema,
  required_all? : Bool = false,
) -> JsonSchema {
  JsonSchema::Object(ObjectSchema::{
    properties,
    required: if required_all && properties is Some(props) {
      props.keys().to_array() |> Some
    } else {
      required
    },
    additional_properties,
    strict_type: Some(true),
  })
}

///|
/// { "enum": [...] }
pub fn Builder::enum_(_self : Builder, values : Array[Json]) -> JsonSchema {
  JsonSchema::Enum({ values, })
}

///|
/// { "const": value }
pub fn Builder::const_(_self : Builder, value : Json) -> JsonSchema {
  JsonSchema::Const({ value, })
}

///|
/// { "oneOf": [...] }
pub fn Builder::one_of(
  _self : Builder,
  schemas : Array[JsonSchema],
) -> JsonSchema {
  JsonSchema::OneOf({ schemas, parsed_enumerable: None, parsed_nullable: None })
}

///|
/// { "oneOf": [...] }
pub fn Builder::enumerable_one_of(
  self : Builder,
  tag : String,
  schemas : Array[JsonSchema],
  params~ : JsonSchema?,
) -> JsonSchema {
  if params is Some(params) {
    JsonSchema::OneOf({
      schemas: [
        self.const_(tag.to_json()),
        self.array(prefix_items=schemas),
        params,
      ],
      parsed_enumerable: None,
      parsed_nullable: None,
    })
  } else {
    JsonSchema::OneOf({
      schemas: [self.const_(tag.to_json()), self.array(prefix_items=schemas)],
      parsed_enumerable: None,
      parsed_nullable: None,
    })
  }
}

///|
/// { "anyOf": [...] }
pub fn Builder::any_of(
  _self : Builder,
  schemas : Array[JsonSchema],
) -> JsonSchema {
  JsonSchema::AnyOf({ schemas, })
}

///|
/// { "allOf": [...] }
pub fn Builder::all_of(
  _self : Builder,
  schemas : Array[JsonSchema],
) -> JsonSchema {
  JsonSchema::AllOf({ schemas, })
}

///|
/// { "$ref": ... }
pub fn Builder::ref_from_string(
  _self : Builder,
  pointer : String,
) -> JsonSchema {
  let p = JsonPointer::from_string(pointer).unwrap()
  JsonSchema::Ref({ pointer: p })
}

///|
pub fn Builder::ref_(_self : Builder, pointer : JsonPointer) -> JsonSchema {
  JsonSchema::Ref({ pointer, })
}

///|
test "Builder::basic types" {
  let b = Builder::new()
  // Test null
  guard b.null() is JsonSchema::Null(_)
  // Test boolean
  guard b.boolean() is JsonSchema::Boolean(_)
  // Test any
  guard b.any() is JsonSchema::Any(_)
}

///|
test "Builder::string with constraints" {
  let b = Builder::new()
  let schema = b.string(minLength=1, maxLength=10, enum_=["a", "b"])
  guard schema is JsonSchema::String(s) else { panic() }
  assert_eq(s.min_length, Some(1))
  assert_eq(s.max_length, Some(10))
  assert_eq(s.enum_, Some(["a", "b"]))
}

///|
test "Builder::object with required_all" {
  let b = Builder::new()
  let schema = b.object(
    properties={ "a": b.string(), "b": b.integer() },
    required_all=true,
  )
  guard schema is JsonSchema::Object(obj) else { panic() }
  // required_all should set all properties as required
  guard obj.required is Some(req)
  assert_eq(req.length(), 2)
}

///|
test "Builder::define_schema and ref" {
  let b = Builder::new()
  let pointer = JsonPointer::Root.key("definitions").key("MyType")
  let _ = b.define_schema(pointer, b.string())
  let ref_schema = b.ref_(pointer)
  guard ref_schema is JsonSchema::Ref(r)
  assert_eq(r.pointer, pointer)
}
