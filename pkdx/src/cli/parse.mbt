///|
pub enum OutputFormat {
  Json
  Table
} derive(Show)

///|
/// Parse `--format` value into OutputFormat. Defaults to Table on unknown.
pub fn parse_output_format(s : String) -> OutputFormat {
  match s {
    "json" => Json
    "table" => Table
    _ => Table
  }
}

///|
fn split_string(s : String, sep : Char) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let sep_int = sep.to_int()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == sep_int {
      if i > start {
        parts.push(s[start:i].to_string())
      }
      start = i + 1
    }
  }
  if start < s.length() {
    parts.push(s[start:].to_string())
  }
  parts
}

///|
fn parse_int_str(s : String, default : Int) -> Int {
  let mut result = 0
  let mut i = 0
  let mut negative = false
  if i < s.length() && s[i] == '-' {
    negative = true
    i = i + 1
  }
  let mut has_digit = false
  while i < s.length() {
    let c = s[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      result = result * 10 + (c - 0x30)
      has_digit = true
    } else {
      break
    }
    i = i + 1
  }
  if !has_digit {
    return default
  }
  if negative {
    -result
  } else {
    result
  }
}

///|
/// Split a comma-separated string into an array of substrings. Public so that
/// callers (e.g. main) can reuse the same splitter that `parse_fixed_ev` uses.
pub fn split_csv(s : String) -> Array[String] {
  split_string(s, ',')
}

///|
/// Parse `--fixed-ev` value into six slots. `_` marks a slot as an optimization target
/// and is represented by -1 in the output array. Non-integer tokens return Err.
pub fn parse_fixed_ev(s : String) -> Result[FixedArray[Int], String] {
  let parts = split_string(s, ',')
  if parts.length() != 6 {
    return Err(
      "--fixed-ev must have 6 comma-separated values (H,A,B,C,D,S); got " +
      parts.length().to_string(),
    )
  }
  let out : FixedArray[Int] = FixedArray::make(6, 0)
  for i = 0; i < 6; i = i + 1 {
    let tok = parts[i]
    if tok == "_" {
      out[i] = -1
    } else {
      // parse_int_str returns default on parse failure — guard by scanning digits explicitly
      let mut all_digits = tok.length() > 0
      for j = 0; j < tok.length(); j = j + 1 {
        let c = tok[j].to_int()
        if c < 0x30 || c > 0x39 {
          all_digits = false
        }
      }
      if not(all_digits) {
        return Err("invalid --fixed-ev token: " + tok)
      }
      out[i] = parse_int_str(tok, 0)
    }
  }
  Ok(out)
}
