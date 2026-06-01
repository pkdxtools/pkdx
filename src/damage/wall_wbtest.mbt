///|
/// Whitebox tests for `wall_applies` and `is_wall_bypass_ability`. Fail until
/// `wall.mbt` is implemented.

///|
test "wall_applies: NoWall never applies" {
  assert_true(!wall_applies(@model.Wall::NoWall, true))
  assert_true(!wall_applies(@model.Wall::NoWall, false))
}

///|
test "wall_applies: Reflect only on physical" {
  assert_true(wall_applies(@model.Wall::Reflect, true))
  assert_true(!wall_applies(@model.Wall::Reflect, false))
}

///|
test "wall_applies: LightScreen only on special" {
  assert_true(!wall_applies(@model.Wall::LightScreen, true))
  assert_true(wall_applies(@model.Wall::LightScreen, false))
}

///|
test "wall_applies: AuroraVeil on both categories" {
  assert_true(wall_applies(@model.Wall::AuroraVeil, true))
  assert_true(wall_applies(@model.Wall::AuroraVeil, false))
}

///|
test "wall bypass: mold breaker family flags" {
  assert_true(is_wall_bypass_ability("かたやぶり"))
  assert_true(is_wall_bypass_ability("すりぬけ"))
  assert_true(is_wall_bypass_ability("ターボブレイズ"))
  assert_true(is_wall_bypass_ability("テラボルテージ"))
}

///|
test "wall bypass: unrelated abilities do not bypass" {
  assert_true(!is_wall_bypass_ability(""))
  assert_true(!is_wall_bypass_ability("いかく"))
  assert_true(!is_wall_bypass_ability("マルチスケイル"))
}
