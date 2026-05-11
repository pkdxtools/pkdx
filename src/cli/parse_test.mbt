///|
test "normalize_argv: empty input becomes --help (bare pkdx)" {
  // Regression: previously `pkdx` (no args) errored with
  // "no command specified" because admiral has no built-in fallback.
  let out = normalize_argv([])
  inspect(out.length(), content="1")
  inspect(out[0], content="--help")
}

///|
test "normalize_argv: 'help' subcommand becomes --help" {
  // Regression: `pkdx help` used to print usage. admiral does not register
  // `help` as a subcommand of pkdx, so without this shim it would error.
  let out = normalize_argv(["help"])
  inspect(out.length(), content="1")
  inspect(out[0], content="--help")
}

///|
test "normalize_argv: 'version' subcommand becomes --version" {
  // Regression: `pkdx version` used to print the version. Same reasoning as
  // the `help` case above.
  let out = normalize_argv(["version"])
  inspect(out.length(), content="1")
  inspect(out[0], content="--version")
}

///|
test "normalize_argv: real subcommand passes through unchanged" {
  let input = ["query", "ガブリアス", "--format", "json"]
  let out = normalize_argv(input)
  inspect(out.length(), content="4")
  inspect(out[0], content="query")
  inspect(out[1], content="ガブリアス")
  inspect(out[2], content="--format")
  inspect(out[3], content="json")
}

///|
test "normalize_argv: write teams subcommand passes through" {
  // Coverage for the new `write teams` (vs old `write --teams`) routing.
  let out = normalize_argv(["write", "teams", "--date", "2026-04-08", "--axis", "ガブリアス"])
  inspect(out.length(), content="6")
  inspect(out[0], content="write")
  inspect(out[1], content="teams")
}

///|
test "normalize_argv: init-cache team subcommand passes through" {
  // Coverage for the new `init-cache team` (vs old `init-cache --team`) routing.
  let out = normalize_argv(["init-cache", "team"])
  inspect(out.length(), content="2")
  inspect(out[0], content="init-cache")
  inspect(out[1], content="team")
}

///|
test "normalize_argv: --help flag passes through unchanged" {
  let out = normalize_argv(["--help"])
  inspect(out.length(), content="1")
  inspect(out[0], content="--help")
}

///|
test "parse_fixed_ev: _ placeholder slots" {
  let result = parse_fixed_ev("_,0,_,0,_,252")
  guard result is Ok(arr) else { fail("Expected Ok, got \{result}") }
  inspect(arr[0], content="-1")
  inspect(arr[1], content="0")
  inspect(arr[2], content="-1")
  inspect(arr[3], content="0")
  inspect(arr[4], content="-1")
  inspect(arr[5], content="252")
}

///|
test "parse_fixed_ev: all numeric" {
  let result = parse_fixed_ev("252,0,4,0,252,0")
  guard result is Ok(arr) else { fail("Expected Ok, got \{result}") }
  inspect(arr[0], content="252")
  inspect(arr[1], content="0")
  inspect(arr[2], content="4")
  inspect(arr[3], content="0")
  inspect(arr[4], content="252")
  inspect(arr[5], content="0")
}

///|
test "parse_fixed_ev: wrong length errors" {
  let result = parse_fixed_ev("252,0,4")
  guard result is Err(_) else { fail("Expected Err, got \{result}") }
}

///|
test "parse_fixed_ev: invalid token errors" {
  let result = parse_fixed_ev("252,abc,0,0,0,0")
  guard result is Err(_) else { fail("Expected Err, got \{result}") }
}

///|
test "parse_output_format" {
  inspect(parse_output_format("json"), content="Json")
  inspect(parse_output_format("table"), content="Table")
  inspect(parse_output_format("garbage"), content="Table")
}

///|
test "parse_int: basic" {
  inspect(parse_int("0", 99), content="0")
  inspect(parse_int("42", 99), content="42")
  inspect(parse_int("252", 99), content="252")
}

///|
test "parse_int: negative" {
  inspect(parse_int("-1", 99), content="-1")
  inspect(parse_int("-2147483648", 0), content="-2147483648")
}

///|
test "parse_int: empty and invalid fall back to default" {
  inspect(parse_int("", 31), content="31")
  inspect(parse_int("abc", 31), content="31")
  inspect(parse_int("-", 31), content="31")
}

///|
test "parse_int: stops at first non-digit after digits" {
  // matches old parse_int_from_str behavior: "12abc" -> 12
  inspect(parse_int("12abc", 0), content="12")
}

///|
test "parse_csv_ints: empty string fills defaults" {
  let arr = parse_csv_ints("", 31, 6)
  inspect(arr[0], content="31")
  inspect(arr[5], content="31")
}

///|
test "parse_csv_ints: comma-separated six values" {
  let arr = parse_csv_ints("0,252,0,0,4,252", 0, 6)
  inspect(arr[0], content="0")
  inspect(arr[1], content="252")
  inspect(arr[2], content="0")
  inspect(arr[3], content="0")
  inspect(arr[4], content="4")
  inspect(arr[5], content="252")
}

///|
test "parse_csv_ints: single value broadcasts" {
  // `--iv 31` shorthand: one value applied to all slots
  let arr = parse_csv_ints("31", 0, 6)
  for i = 0; i < 6; i = i + 1 {
    inspect(arr[i], content="31")
  }
}

///|
test "parse_csv_ints: invalid token falls back to default_val" {
  let arr = parse_csv_ints("252,abc,0,0,0,0", 7, 6)
  inspect(arr[0], content="252")
  inspect(arr[1], content="7")
}

///|
test "parse_csv_ints: fewer tokens than count leaves tail at default" {
  let arr = parse_csv_ints("1,2,3", 9, 6)
  inspect(arr[0], content="1")
  inspect(arr[1], content="2")
  inspect(arr[2], content="3")
  inspect(arr[3], content="9")
  inspect(arr[4], content="9")
  inspect(arr[5], content="9")
}

///|
test "parse_csv_ints: extra tokens beyond count are ignored" {
  let arr = parse_csv_ints("1,2,3,4,5,6,7,8", 0, 6)
  inspect(arr[0], content="1")
  inspect(arr[5], content="6")
}

///|
test "split_csv: basic" {
  let parts = split_csv("ほのお,みず,くさ")
  inspect(parts.length(), content="3")
  inspect(parts[0], content="ほのお")
  inspect(parts[1], content="みず")
  inspect(parts[2], content="くさ")
}

///|
test "split_csv: single element" {
  let parts = split_csv("ドラゴン")
  inspect(parts.length(), content="1")
  inspect(parts[0], content="ドラゴン")
}

///|
test "split_csv: empty string yields empty array" {
  let parts = split_csv("")
  inspect(parts.length(), content="0")
}
