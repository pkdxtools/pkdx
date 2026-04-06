///|
pub fn build_resolver(root_json : Json) -> Resolver raise ParseError {
  Resolver::new(root_json)
}

///|
/// Create an empty resolver (no $ref support)
pub fn Resolver::empty() -> Resolver {
  Resolver::{ resolver_map: {} }
}

///|
pub struct Resolver {
  priv resolver_map : Map[@types.JsonPointer, @types.JsonSchema]
}

///|
pub fn Resolver::new(root_json : Json) -> Resolver raise ParseError {
  let resolver_map : Map[@types.JsonPointer, @types.JsonSchema] = {}
  let using_refs = collect_refs(root_json)
  for ref_expr in using_refs {
    guard @types.JsonPointer::from_string(ref_expr) is Ok(pointer) else {
      raise ParseError::PointerParseError(ref_expr)
    }
    match pointer.access(root_json) {
      Some(json) =>
        try {
          let schema : @types.JsonSchema = @parser.parse_schema(json)
          resolver_map.set(pointer, schema)
        } catch {
          err => raise ParseError::ParserError(err)
        }
      None => ()
    }
  }
  Resolver::{ resolver_map, }
}

///|
pub fn Resolver::resolve(
  self : Resolver,
  pointer : @types.JsonPointer,
) -> @types.JsonSchema? {
  self.resolver_map.get(pointer)
}

///|
pub fn Resolver::has(self : Resolver, ref_expr : @types.JsonPointer) -> Bool {
  self.resolver_map.contains(ref_expr)
}

///|
pub fn Resolver::get_refs(self : Resolver) -> Array[@types.JsonPointer] {
  self.resolver_map.keys().to_array()
}

///|
/// get $ref references in json
pub fn collect_refs(json : Json) -> Set[String] {
  let set : Set[String] = Set::new()
  match json {
    Object(obj) =>
      for key, value in obj {
        if key == "$ref" && value is String(s) {
          set.add(s)
        } else {
          let newset = collect_refs(value)
          for s in newset {
            set.add(s)
          }
        }
      }
    Array(arr) =>
      for item in arr {
        let newset = collect_refs(item)
        for s in newset {
          set.add(s)
        }
      }
    _ => ()
  }
  set
}

///|
test "collect_refs" {
  let json : Json = {
    "type": "object",
    "properties": {
      "name": { "type": "string" },
      "age": { "$ref": "#/definitions/PositiveInteger" },
      "friends": {
        "type": "array",
        "items": { "$ref": "#/definitions/Person" },
      },
    },
    "definitions": {
      "Person": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "age": { "$ref": "#/definitions/PositiveInteger" },
        },
      },
      "PositiveInteger": { "type": "integer", "minimum": 0 },
    },
  }
  let refs = collect_refs(json)
  assert_eq(
    refs,
    Set::from_array(["#/definitions/PositiveInteger", "#/definitions/Person"]),
  )
}
