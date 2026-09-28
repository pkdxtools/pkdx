///|
test "get_effectiveness: single type super effective" {
  let fire = @types.type_from_jp("ほのお").unwrap()
  let grass = @types.type_from_jp("くさ").unwrap()
  @debug.debug_inspect(@types.get_effectiveness(fire, grass), content="2")
}

///|
test "get_effectiveness: single type not very effective" {
  let fire = @types.type_from_jp("ほのお").unwrap()
  let water = @types.type_from_jp("みず").unwrap()
  @debug.debug_inspect(@types.get_effectiveness(fire, water), content="0.5")
}

///|
test "get_effectiveness: single type immune" {
  let ground = @types.type_from_jp("じめん").unwrap()
  let flying = @types.type_from_jp("ひこう").unwrap()
  @debug.debug_inspect(@types.get_effectiveness(ground, flying), content="0")
}

///|
test "get_dual_effectiveness: ground vs flying/steel is immune" {
  let ground = @types.type_from_jp("じめん").unwrap()
  let flying = @types.type_from_jp("ひこう").unwrap()
  let steel = @types.type_from_jp("はがね").unwrap()
  @debug.debug_inspect(
    @types.get_dual_effectiveness(ground, flying, Some(steel)),
    content="0",
  )
}

///|
test "get_dual_effectiveness: fire vs flying/steel is 2x" {
  // ほのお -> ひこう = 1x, ほのお -> はがね = 2x → 1 * 2 = 2x
  let fire = @types.type_from_jp("ほのお").unwrap()
  let flying = @types.type_from_jp("ひこう").unwrap()
  let steel = @types.type_from_jp("はがね").unwrap()
  @debug.debug_inspect(
    @types.get_dual_effectiveness(fire, flying, Some(steel)),
    content="2",
  )
}

///|
test "get_dual_effectiveness: ice vs ground/flying is 4x" {
  let ice = @types.type_from_jp("こおり").unwrap()
  let ground = @types.type_from_jp("じめん").unwrap()
  let flying = @types.type_from_jp("ひこう").unwrap()
  @debug.debug_inspect(
    @types.get_dual_effectiveness(ice, ground, Some(flying)),
    content="4",
  )
}

///|
test "get_dual_effectiveness: single type fallback" {
  let fire = @types.type_from_jp("ほのお").unwrap()
  let grass = @types.type_from_jp("くさ").unwrap()
  @debug.debug_inspect(@types.get_dual_effectiveness(fire, grass, None), content="2")
}

///|
test "get_dual_effectiveness: electric vs ground/water immune" {
  let electric = @types.type_from_jp("でんき").unwrap()
  let ground = @types.type_from_jp("じめん").unwrap()
  let water = @types.type_from_jp("みず").unwrap()
  @debug.debug_inspect(
    @types.get_dual_effectiveness(electric, ground, Some(water)),
    content="0",
  )
}

///|
test "get_dual_effectiveness: fighting vs ghost/dark immune" {
  let fighting = @types.type_from_jp("かくとう").unwrap()
  let ghost = @types.type_from_jp("ゴースト").unwrap()
  let dark = @types.type_from_jp("あく").unwrap()
  @debug.debug_inspect(
    @types.get_dual_effectiveness(fighting, ghost, Some(dark)),
    content="0",
  )
}

///|
test "type_from_jp: valid types" {
  @debug.debug_inspect(@types.type_from_jp("ほのお"), content="Some(Fire)")
  @debug.debug_inspect(@types.type_from_jp("ひこう"), content="Some(Flying)")
  @debug.debug_inspect(@types.type_from_jp("はがね"), content="Some(Steel)")
}

///|
test "type_from_jp: unknown type returns None" {
  assert_true(@types.type_from_jp("でたらめ") == None)
  assert_true(@types.type_from_jp("") == None)
}
