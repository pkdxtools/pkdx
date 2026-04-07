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
test "parse_args: hbd minimal" {
  let result = parse_args(["pkdx", "hbd", "ガブリアス"])
  guard result is Ok(Hbd(name~, top~, phys_weight~, spec_weight~, hp_snap~, ..)) else {
    fail("Expected Hbd, got \{result}")
  }
  inspect(name, content="ガブリアス")
  inspect(top, content="1")
  inspect(phys_weight, content="1")
  inspect(spec_weight, content="1")
  inspect(hp_snap, content="none")
}

///|
test "parse_args: hbd all flags" {
  let result = parse_args([
    "pkdx", "hbd", "ガブリアス",
    "--fixed-ev", "_,0,_,0,_,252",
    "--nature", "ようき",
    "--hp-snap", "leftovers",
    "--phys-weight", "2",
    "--spec-weight", "1",
    "--top", "5",
  ])
  guard result is Ok(Hbd(fixed_ev~, nature~, hp_snap~, phys_weight~, spec_weight~, top~, ..)) else {
    fail("Expected Hbd, got \{result}")
  }
  inspect(fixed_ev, content="_,0,_,0,_,252")
  inspect(nature, content="ようき")
  inspect(hp_snap, content="leftovers")
  inspect(phys_weight, content="2")
  inspect(spec_weight, content="1")
  inspect(top, content="5")
}
