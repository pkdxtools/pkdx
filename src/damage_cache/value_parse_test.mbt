///|
test "parse_damages_from_json: typical format_damage output" {
  let json = "{\"attacker\":\"ガブリアス\",\"defender\":\"バンギラス\",\"damages\":[100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115],\"min\":100,\"max\":115}"
  match parse_damages_from_json(json) {
    Some(arr) => {
      assert_eq(arr.length(), 16)
      assert_eq(arr[0], 100)
      assert_eq(arr[15], 115)
    }
    None => fail("expected Some with 16 damages")
  }
}

///|
test "parse_damages_from_json: missing damages field returns None" {
  let json = "{\"attacker\":\"ガブリアス\"}"
  match parse_damages_from_json(json) {
    Some(_) => fail("expected None")
    None => ()
  }
}

///|
test "parse_damages_from_json: malformed JSON returns None" {
  match parse_damages_from_json("not json") {
    Some(_) => fail("expected None")
    None => ()
  }
}

///|
test "parse_damages_from_json: non-numeric damages returns None" {
  let json = "{\"damages\":[\"not\",\"numbers\"]}"
  match parse_damages_from_json(json) {
    Some(_) => fail("expected None")
    None => ()
  }
}

///|
test "mean_of_damages: matches compute_mean_damage integer division" {
  let damages : Array[Int] = [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115]
  // sum = 1720, 1720 / 16 = 107
  assert_eq(mean_of_damages(damages), 107)
}

///|
test "mean_of_damages: empty array returns 0" {
  let damages : Array[Int] = []
  assert_eq(mean_of_damages(damages), 0)
}
