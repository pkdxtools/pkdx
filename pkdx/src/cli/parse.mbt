///|
pub enum OutputFormat {
  Json
  Table
} derive(Show)

///|
/// Normalize the user-supplied CLI args (i.e. `argv` minus the program name)
/// into the form admiral expects, preserving the legacy entry points that the
/// hand-rolled parser used to handle:
///
///   * bare invocation       (`pkdx`)         -> `["--help"]`
///   * legacy help subcmd    (`pkdx help`)    -> `["--help"]`
///   * legacy version subcmd (`pkdx version`) -> `["--version"]`
///
/// Without this shim `admiral` raises `no command specified` for the bare
/// invocation, and rejects `help` / `version` as unknown subcommands.
/// Anything else is returned unchanged so admiral handles it natively.
pub fn normalize_argv(args : Array[String]) -> Array[String] {
  if args.length() == 0 {
    return ["--help"]
  }
  match args[0] {
    "help" => ["--help"]
    "version" => ["--version"]
    _ => args
  }
}

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
/// Parse a string of ASCII digits into an Int. Leading `-` is accepted.
/// Returns `default` if the string is empty or contains any non-digit character
/// before the first non-digit (partial-prefix parses are not supported — callers
/// that need stricter behavior should validate the token themselves).
pub fn parse_int(s : String, default : Int) -> Int {
  parse_int_str(s, default)
}

///|
/// Parse an HP ratio string into a (num, den) pair. Accepted forms:
///   "50%" | "100%" → (n, 100)
///   "1/2" | "3/4"  → explicit fraction
///   ""             → (2, 2) (= full)
/// Unparseable input falls back to (2, 2). Callers only need `num * 2 <= den`
/// semantics, so the exact denominator doesn't matter beyond truthfulness.
pub fn parse_hp_ratio(s : String) -> (Int, Int) {
  if s.length() == 0 {
    return (2, 2)
  }
  // "N%" form: drop the trailing '%' and parse as (N, 100).
  let last = s[s.length() - 1]
  if last == '%' {
    let head = s[0:s.length() - 1].to_string()
    let n = parse_int_str(head, -1)
    if n < 0 {
      return (2, 2)
    }
    return (n, 100)
  }
  // "N/D" form.
  let mut slash_idx = -1
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == '/' {
      slash_idx = i
      break
    }
  }
  if slash_idx <= 0 {
    return (2, 2)
  }
  let num_str = s[0:slash_idx].to_string()
  let den_str = s[slash_idx + 1:s.length()].to_string()
  let num = parse_int_str(num_str, -1)
  let den = parse_int_str(den_str, -1)
  if num < 0 || den <= 0 {
    (2, 2)
  } else {
    (num, den)
  }
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
/// Parse a comma-separated list of integers into a fixed-size array of length
/// `count`. If `s` is empty, every slot is filled with `default_val`. If `s`
/// has no comma, the single value is broadcast to every slot (matching the
/// `--iv 31` shorthand behavior). Individual tokens that fail to parse fall
/// back to `default_val`. Extra tokens beyond `count` are ignored.
pub fn parse_csv_ints(
  s : String,
  default_val : Int,
  count : Int,
) -> FixedArray[Int] {
  let result : FixedArray[Int] = FixedArray::make(count, default_val)
  if s.length() == 0 {
    return result
  }
  let mut has_comma = false
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ',' {
      has_comma = true
      break
    }
  }
  if has_comma {
    let mut idx = 0
    let mut start = 0
    for i = 0; i <= s.length(); i = i + 1 {
      if i == s.length() || s[i] == ',' {
        if idx < count && i > start {
          result[idx] = parse_int_str(s[start:i].to_string(), default_val)
        }
        idx = idx + 1
        start = i + 1
      }
    }
  } else {
    let val = parse_int_str(s, default_val)
    for i = 0; i < count; i = i + 1 {
      result[i] = val
    }
  }
  result
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
