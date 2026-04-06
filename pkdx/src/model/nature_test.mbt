///|
test "nature_from_ja: いじっぱり" {
  match nature_from_ja("いじっぱり") {
    Some(nature) => {
      inspect(nature.name_ja, content="いじっぱり")
      inspect(nature.name_en, content="Adamant")
      inspect(nature.up, content="Some(Atk)")
      inspect(nature.down, content="Some(SpA)")
    }
    None => fail("expected Some")
  }
}

///|
test "nature_from_ja: ようき" {
  match nature_from_ja("ようき") {
    Some(nature) => {
      inspect(nature.up, content="Some(Spe)")
      inspect(nature.down, content="Some(SpA)")
    }
    None => fail("expected Some")
  }
}

///|
test "nature_from_ja: ひかえめ" {
  match nature_from_ja("ひかえめ") {
    Some(nature) => {
      inspect(nature.up, content="Some(SpA)")
      inspect(nature.down, content="Some(Atk)")
    }
    None => fail("expected Some")
  }
}

///|
test "nature_from_ja: neutral nature まじめ" {
  match nature_from_ja("まじめ") {
    Some(nature) => {
      inspect(nature.up, content="None")
      inspect(nature.down, content="None")
    }
    None => fail("expected Some")
  }
}

///|
test "nature_from_ja: unknown returns None" {
  assert_true(nature_from_ja("存在しない") is None)
}

///|
test "all_natures: count is 25" {
  inspect(all_natures().length(), content="25")
}

///|
test "all_natures: all lookups round-trip" {
  let natures = all_natures()
  for i = 0; i < natures.length(); i = i + 1 {
    let n = natures[i]
    assert_true(nature_from_ja(n.name_ja) is Some(_))
  }
}

///|
test "nature_mult_int: boosted stat" {
  match nature_from_ja("いじっぱり") {
    Some(nature) => {
      let (num, den) = nature_mult_int(nature, Atk)
      inspect(num, content="11")
      inspect(den, content="10")
    }
    None => fail("expected Some")
  }
}

///|
test "nature_mult_int: reduced stat" {
  match nature_from_ja("いじっぱり") {
    Some(nature) => {
      let (num, den) = nature_mult_int(nature, SpA)
      inspect(num, content="9")
      inspect(den, content="10")
    }
    None => fail("expected Some")
  }
}

///|
test "nature_mult_int: neutral stat" {
  match nature_from_ja("いじっぱり") {
    Some(nature) => {
      let (num, den) = nature_mult_int(nature, HP)
      inspect(num, content="1")
      inspect(den, content="1")
    }
    None => fail("expected Some")
  }
}

///|
test "stat_index_from_str: all variants" {
  inspect(stat_index_from_str("hp"), content="Some(HP)")
  inspect(stat_index_from_str("atk"), content="Some(Atk)")
  inspect(stat_index_from_str("def"), content="Some(Def)")
  inspect(stat_index_from_str("spa"), content="Some(SpA)")
  inspect(stat_index_from_str("spd"), content="Some(SpD)")
  inspect(stat_index_from_str("spe"), content="Some(Spe)")
  inspect(stat_index_from_str("unknown"), content="None")
}
