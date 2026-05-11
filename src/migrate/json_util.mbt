///|
/// JSON accessors tuned to the migration workload. All migrations read
/// either a top-level array of entries (`data.json`) or a nested object
/// (`LegendsZA.json`) and pluck fields by name; these helpers keep the
/// per-field match expressions tight.

///|
pub fn get_field(obj : Map[String, Json], key : String) -> Json? {
  obj.get(key)
}

///|
/// String field, returning "" when missing or non-string. Matches Ruby's
/// `entry['x'].to_s` (nil → "") behaviour that the original migrations
/// rely on before the `== ''` check.
pub fn str_field(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// String field as Option. Returns None for missing *and* for empty
/// string — matches the migration idiom `x.to_s == '' ? nil : x`.
pub fn str_opt(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(s)) => if s.length() == 0 { None } else { Some(s) }
    _ => None
  }
}

///|
/// Integer field. Missing or non-number returns the provided default.
pub fn int_field(obj : Map[String, Json], key : String, default : Int) -> Int {
  match obj.get(key) {
    Some(Number(n, ..)) => n.to_int()
    _ => default
  }
}

///|
pub fn bool_field(obj : Map[String, Json], key : String) -> Bool {
  match obj.get(key) {
    Some(True) => true
    _ => false
  }
}

///|
pub fn array_field(obj : Map[String, Json], key : String) -> Array[Json] {
  match obj.get(key) {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// Expect the top-level JSON to be an array. Used by 002/003/004/006/008/010
/// which all read `[ {...}, {...}, ... ]`.
pub fn expect_array(json : Json) -> Result[Array[Json], String] {
  match json {
    Array(a) => Ok(a)
    _ => Err("expected top-level JSON array")
  }
}

///|
pub fn expect_object(json : Json) -> Result[Map[String, Json], String] {
  match json {
    Object(m) => Ok(m)
    _ => Err("expected top-level JSON object")
  }
}
