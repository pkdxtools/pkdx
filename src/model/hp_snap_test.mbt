///|
test "matches_snap: None is always true" {
  assert_true(matches_snap(1, HpSnap::NoSnap))
  assert_true(matches_snap(100, HpSnap::NoSnap))
  assert_true(matches_snap(0, HpSnap::NoSnap))
}

///|
test "matches_snap: Leftovers H ≡ 1 (mod 16)" {
  assert_true(matches_snap(1, HpSnap::Leftovers))
  assert_true(matches_snap(17, HpSnap::Leftovers))
  assert_true(matches_snap(33, HpSnap::Leftovers))
  assert_true(matches_snap(161, HpSnap::Leftovers))
  assert_true(!matches_snap(0, HpSnap::Leftovers))
  assert_true(!matches_snap(16, HpSnap::Leftovers))
  assert_true(!matches_snap(32, HpSnap::Leftovers))
  assert_true(!matches_snap(160, HpSnap::Leftovers))
}

///|
test "matches_snap: Residual H ≡ 15 (mod 16)" {
  assert_true(matches_snap(15, HpSnap::Residual))
  assert_true(matches_snap(31, HpSnap::Residual))
  assert_true(matches_snap(47, HpSnap::Residual))
  assert_true(matches_snap(175, HpSnap::Residual))
  assert_true(!matches_snap(16, HpSnap::Residual))
  assert_true(!matches_snap(32, HpSnap::Residual))
  assert_true(!matches_snap(14, HpSnap::Residual))
}

///|
test "matches_snap: Sitrus even HP" {
  assert_true(matches_snap(2, HpSnap::Sitrus))
  assert_true(matches_snap(100, HpSnap::Sitrus))
  assert_true(matches_snap(182, HpSnap::Sitrus))
  assert_true(!matches_snap(1, HpSnap::Sitrus))
  assert_true(!matches_snap(183, HpSnap::Sitrus))
}

///|
test "matches_snap: LifeOrb H ≡ 0 (mod 10)" {
  assert_true(matches_snap(10, HpSnap::LifeOrb))
  assert_true(matches_snap(20, HpSnap::LifeOrb))
  assert_true(matches_snap(200, HpSnap::LifeOrb))
  assert_true(!matches_snap(11, HpSnap::LifeOrb))
  assert_true(!matches_snap(201, HpSnap::LifeOrb))
}

///|
test "hp_snap_from_str: valid values" {
  assert_true(hp_snap_from_str("none") == Some(NoSnap))
  assert_true(hp_snap_from_str("leftovers") == Some(Leftovers))
  assert_true(hp_snap_from_str("residual") == Some(Residual))
  assert_true(hp_snap_from_str("sitrus") == Some(Sitrus))
  assert_true(hp_snap_from_str("lifeorb") == Some(LifeOrb))
}

///|
test "hp_snap_from_str: invalid" {
  assert_true(hp_snap_from_str("unknown") == None)
  assert_true(hp_snap_from_str("") == None)
}
