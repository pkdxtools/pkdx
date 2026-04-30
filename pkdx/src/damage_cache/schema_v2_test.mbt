///|
/// Tests for L2 damage cache schema bump.
/// v2 (issue #90): variants[] payload introduced.
/// v3 (issue #91): payoff `compute_mean_damage` rerouted via variants[]
/// instead of legacy `damages` field, requiring full cache invalidation
/// on multi-hit moves.

///|
test "SCHEMA_VERSION is 3 (bumped for #91 payoff variants[] reroute)" {
  inspect(SCHEMA_VERSION, content="3")
}

///|
test "parse_variants_from_json: extracts probability and hits length" {
  let json_str =
    #|{"damages":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],
    #|"percents":[0.5,1,1.5,2,2.5,3,3.5,4,4.5,5,5.5,6,6.5,7,7.5,8],
    #|"min":1,"max":16,"defender_hp":200,"ko":"5発以上",
    #|"variants":[
    #|  {"probability":0.2,"hits_count":1,"total_damages":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]},
    #|  {"probability":0.2,"hits_count":2,"total_damages":[2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2]},
    #|  {"probability":0.6,"hits_count":3,"total_damages":[3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3]}
    #|]}
  let result = parse_variants_from_json(json_str)
  match result {
    Some(variants) => {
      inspect(variants.length(), content="3")
      // probability shape preserved
      let p0 = variants[0].probability
      let delta = if p0 > 0.2 { p0 - 0.2 } else { 0.2 - p0 }
      assert_true(delta < 1.0e-9)
      inspect(variants[0].hits_count, content="1")
      inspect(variants[2].hits_count, content="3")
    }
    None => fail("expected Some(variants)")
  }
}

///|
test "parse_variants_from_json: returns None on missing variants field" {
  let json_str =
    #|{"damages":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],
    #|"min":1,"max":16,"defender_hp":200,"ko":"5発以上"}
  match parse_variants_from_json(json_str) {
    Some(_) => fail("expected None for legacy v1 json")
    None => ()
  }
}

///|
test "parse_variants_from_json: returns None on malformed JSON" {
  let result = parse_variants_from_json("not json")
  match result {
    Some(_) => fail("expected None for malformed json")
    None => ()
  }
}
