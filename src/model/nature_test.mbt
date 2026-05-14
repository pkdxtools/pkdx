///|
test "nature_from_ja: いじっぱり" {
  match nature_from_ja("いじっぱり") {
    Some(nature) => {
      assert_true(nature.name_ja == "いじっぱり")
      assert_true(nature.name_en == "Adamant")
      assert_true(nature.up == Some(Atk))
      assert_true(nature.down == Some(SpA))
    }
    None => fail("expected Some")
  }
}

///|
test "nature_from_ja: ようき" {
  match nature_from_ja("ようき") {
    Some(nature) => {
      assert_true(nature.up == Some(Spe))
      assert_true(nature.down == Some(SpA))
    }
    None => fail("expected Some")
  }
}

///|
test "nature_from_ja: ひかえめ" {
  match nature_from_ja("ひかえめ") {
    Some(nature) => {
      assert_true(nature.up == Some(SpA))
      assert_true(nature.down == Some(Atk))
    }
    None => fail("expected Some")
  }
}

///|
test "nature_from_ja: neutral nature まじめ" {
  match nature_from_ja("まじめ") {
    Some(nature) => {
      assert_true(nature.up == None)
      assert_true(nature.down == None)
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
  @debug.debug_inspect(all_natures().length(), content="25")
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
      @debug.debug_inspect(num, content="11")
      @debug.debug_inspect(den, content="10")
    }
    None => fail("expected Some")
  }
}

///|
test "nature_mult_int: reduced stat" {
  match nature_from_ja("いじっぱり") {
    Some(nature) => {
      let (num, den) = nature_mult_int(nature, SpA)
      @debug.debug_inspect(num, content="9")
      @debug.debug_inspect(den, content="10")
    }
    None => fail("expected Some")
  }
}

///|
test "nature_mult_int: neutral stat" {
  match nature_from_ja("いじっぱり") {
    Some(nature) => {
      let (num, den) = nature_mult_int(nature, HP)
      @debug.debug_inspect(num, content="1")
      @debug.debug_inspect(den, content="1")
    }
    None => fail("expected Some")
  }
}

///|
test "stat_index_from_str: all variants" {
  assert_true(stat_index_from_str("hp") == Some(HP))
  assert_true(stat_index_from_str("atk") == Some(Atk))
  assert_true(stat_index_from_str("def") == Some(Def))
  assert_true(stat_index_from_str("spa") == Some(SpA))
  assert_true(stat_index_from_str("spd") == Some(SpD))
  assert_true(stat_index_from_str("spe") == Some(Spe))
  assert_true(stat_index_from_str("unknown") == None)
}
