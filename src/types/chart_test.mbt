///|
test "get_effectiveness: single type super effective" {
  let fire = type_from_jp("ほのお").unwrap()
  let grass = type_from_jp("くさ").unwrap()
  inspect(get_effectiveness(fire, grass), content="2")
}

///|
test "get_effectiveness: single type not very effective" {
  let fire = type_from_jp("ほのお").unwrap()
  let water = type_from_jp("みず").unwrap()
  inspect(get_effectiveness(fire, water), content="0.5")
}

///|
test "get_effectiveness: single type immune" {
  let ground = type_from_jp("じめん").unwrap()
  let flying = type_from_jp("ひこう").unwrap()
  inspect(get_effectiveness(ground, flying), content="0")
}

///|
test "get_dual_effectiveness: ground vs flying/steel is immune" {
  let ground = type_from_jp("じめん").unwrap()
  let flying = type_from_jp("ひこう").unwrap()
  let steel = type_from_jp("はがね").unwrap()
  inspect(get_dual_effectiveness(ground, flying, Some(steel)), content="0")
}

///|
test "get_dual_effectiveness: fire vs flying/steel is 2x" {
  // ほのお -> ひこう = 1x, ほのお -> はがね = 2x → 1 * 2 = 2x
  let fire = type_from_jp("ほのお").unwrap()
  let flying = type_from_jp("ひこう").unwrap()
  let steel = type_from_jp("はがね").unwrap()
  inspect(get_dual_effectiveness(fire, flying, Some(steel)), content="2")
}

///|
test "get_dual_effectiveness: ice vs ground/flying is 4x" {
  let ice = type_from_jp("こおり").unwrap()
  let ground = type_from_jp("じめん").unwrap()
  let flying = type_from_jp("ひこう").unwrap()
  inspect(get_dual_effectiveness(ice, ground, Some(flying)), content="4")
}

///|
test "get_dual_effectiveness: single type fallback" {
  let fire = type_from_jp("ほのお").unwrap()
  let grass = type_from_jp("くさ").unwrap()
  inspect(get_dual_effectiveness(fire, grass, None), content="2")
}

///|
test "get_dual_effectiveness: electric vs ground/water immune" {
  let electric = type_from_jp("でんき").unwrap()
  let ground = type_from_jp("じめん").unwrap()
  let water = type_from_jp("みず").unwrap()
  inspect(get_dual_effectiveness(electric, ground, Some(water)), content="0")
}

///|
test "get_dual_effectiveness: fighting vs ghost/dark immune" {
  let fighting = type_from_jp("かくとう").unwrap()
  let ghost = type_from_jp("ゴースト").unwrap()
  let dark = type_from_jp("あく").unwrap()
  inspect(get_dual_effectiveness(fighting, ghost, Some(dark)), content="0")
}

///|
test "type_from_jp: valid types" {
  inspect(type_from_jp("ほのお"), content="Some(Fire)")
  inspect(type_from_jp("ひこう"), content="Some(Flying)")
  inspect(type_from_jp("はがね"), content="Some(Steel)")
}

///|
test "type_from_jp: unknown type returns None" {
  inspect(type_from_jp("でたらめ"), content="None")
  inspect(type_from_jp(""), content="None")
}
