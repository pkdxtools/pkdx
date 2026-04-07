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
