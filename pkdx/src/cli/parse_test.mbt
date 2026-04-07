///|
test "parse_args: init-cache --pokemon" {
  let result = parse_args(["pkdx", "init-cache", "--pokemon"])
  guard result is Ok(InitCache(kind=Pokemon)) else {
    fail("Expected InitCache(Pokemon), got \{result}")
  }
}

///|
test "parse_args: init-cache --team" {
  let result = parse_args(["pkdx", "init-cache", "--team"])
  guard result is Ok(InitCache(kind=Team)) else {
    fail("Expected InitCache(Team), got \{result}")
  }
}

///|
test "parse_args: init-cache without flags errors" {
  let result = parse_args(["pkdx", "init-cache"])
  guard result is Err(msg) else {
    fail("Expected Err, got \{result}")
  }
  inspect(msg.contains("--team"), content="true")
}

///|
test "parse_args: init-cache mutual exclusion errors" {
  let result = parse_args(["pkdx", "init-cache", "--team", "--pokemon"])
  guard result is Err(msg) else {
    fail("Expected Err, got \{result}")
  }
  inspect(msg.contains("choose one"), content="true")
}
