///|
/// @json.JsonPath-like API
pub(all) enum JsonPointer {
  /// ObjectRoot
  Root
  /// Key Access
  Key(JsonPointer, key~ : String)
  /// Index Access
  Index(JsonPointer, index~ : Int)
} derive(Eq, Hash)

///|
pub fn JsonPointer::index(self : JsonPointer, index : Int) -> JsonPointer {
  Index(self, index~)
}

///|
pub fn JsonPointer::key(self : JsonPointer, key : String) -> JsonPointer {
  Key(self, key~)
}

///|
pub impl Show for JsonPointer with output(self, logger) {
  match self {
    Root => logger.write_string("#")
    Key(p, key~) =>
      logger..write_object(p)..write_string("/")..write_string(key)
    Index(p, index~) =>
      logger..write_object(p)..write_string("/")..write_object(index)
  }
}

///|
pub fn JsonPointer::access(self : JsonPointer, json : Json) -> Json? {
  match self {
    Root => Some(json)
    Key(parent, key~) =>
      match parent.access(json) {
        Some(Object(obj)) => obj.get(key)
        _ => None
      }
    Index(parent, index~) =>
      match parent.access(json) {
        Some(Array(arr)) =>
          if index >= 0 && index < arr.length() {
            Some(arr[index])
          } else {
            None
          }
        _ => None
      }
  }
}

///|
/// Parse JSON Pointer string into JsonPointer
pub fn JsonPointer::from_string(
  pointer : String,
) -> Result[JsonPointer, String] {
  try {
    if pointer == "#" || pointer == "" {
      return Ok(Root)
    }
    let normalized = if pointer.has_prefix("#/") {
      pointer[2:].to_string()
    } else if pointer.has_prefix("#") {
      pointer[1:].to_string()
    } else if pointer.has_prefix("/") {
      pointer[1:].to_string()
    } else {
      pointer
    }

    // Split by / and build path
    let parts = normalized.split("/")
    let mut path = Root
    for part in parts {
      if part == "" {
        continue
      }
      let part_str = part.to_string()

      // Check if this is a number (array index)
      let is_digit = fn(c : Char) -> Bool { c >= '0' && c <= '9' }
      let is_number = part_str.length() > 0 && part_str.iter().all(is_digit)
      if is_number {
        let mut num = 0
        for ch in part_str.iter() {
          num = num * 10 + (ch.to_int() - '0'.to_int())
        }
        path = path.index(num)
      } else {
        let unescaped = part_str
          .replace(old="~1", new="/")
          .replace(old="~0", new="~")
        path = path.key(unescaped)
      }
    }
    path |> Ok
  } catch {
    _ => Err("Failed to parse pointer")
  }
}

///|
test "JsonPointer::access" {
  let path = Root.key("foo").index(0).key("bar")
  assert_eq(path.to_string(), "#/foo/0/bar")
  let pointer = Root.key("foo").index(0).key("bar")
  let json : Json = { "foo": [{ "bar": 42 }] }
  let resolved = pointer.access(json).unwrap()
  assert_eq(resolved, 42)
}

///|
test "JsonPointer::from_string" {
  let path1 = JsonPointer::from_string("#/foo/0/bar").unwrap()
  let expected1 = Root.key("foo").index(0).key("bar")
  assert_eq(path1, expected1)
  let path2 = JsonPointer::from_string("/foo/bar").unwrap()
  let expected2 = Root.key("foo").key("bar")
  assert_eq(path2, expected2)
  let path3 = JsonPointer::from_string("#").unwrap()
  assert_eq(path3, Root)
  let path4 = JsonPointer::from_string("").unwrap()
  assert_eq(path4, Root)
  let path5 = JsonPointer::from_string("#/foo~1bar/0").unwrap()
  let expected5 = Root.key("foo/bar").index(0)
  assert_eq(path5, expected5)
  let path6 = JsonPointer::from_string("#/foo~0bar").unwrap()
  let expected6 = Root.key("foo~bar")
  assert_eq(path6, expected6)
}

///|
test "JsonPointer::from_json_pointer" {
  let result = JsonPointer::from_string("#/abc/items/0/def")
  result |> inspect(content="Ok(#/abc/items/0/def)")
}
