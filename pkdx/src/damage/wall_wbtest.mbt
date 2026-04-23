///|
/// Whitebox tests for `wall_applies` and `is_wall_bypass_ability`. Fail until
/// `wall.mbt` is implemented.

///|
test "wall_applies: NoWall never applies" {
  inspect(wall_applies(@model.Wall::NoWall, true), content="false")
  inspect(wall_applies(@model.Wall::NoWall, false), content="false")
}

///|
test "wall_applies: Reflect only on physical" {
  inspect(wall_applies(@model.Wall::Reflect, true), content="true")
  inspect(wall_applies(@model.Wall::Reflect, false), content="false")
}

///|
test "wall_applies: LightScreen only on special" {
  inspect(wall_applies(@model.Wall::LightScreen, true), content="false")
  inspect(wall_applies(@model.Wall::LightScreen, false), content="true")
}

///|
test "wall_applies: AuroraVeil on both categories" {
  inspect(wall_applies(@model.Wall::AuroraVeil, true), content="true")
  inspect(wall_applies(@model.Wall::AuroraVeil, false), content="true")
}

///|
test "wall bypass: mold breaker family flags" {
  inspect(is_wall_bypass_ability("かたやぶり"), content="true")
  inspect(is_wall_bypass_ability("すりぬけ"), content="true")
  inspect(is_wall_bypass_ability("ターボブレイズ"), content="true")
  inspect(is_wall_bypass_ability("テラボルテージ"), content="true")
}

///|
test "wall bypass: unrelated abilities do not bypass" {
  inspect(is_wall_bypass_ability(""), content="false")
  inspect(is_wall_bypass_ability("いかく"), content="false")
  inspect(is_wall_bypass_ability("マルチスケイル"), content="false")
}
