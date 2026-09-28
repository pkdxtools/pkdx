///|
test "matches_snap: None is always true" {
  assert_true(@model.matches_snap(1, @model.HpSnap::NoSnap))
  assert_true(@model.matches_snap(100, @model.HpSnap::NoSnap))
  assert_true(@model.matches_snap(0, @model.HpSnap::NoSnap))
}

///|
test "matches_snap: Leftovers H ≡ 1 (mod 16)" {
  assert_true(@model.matches_snap(1, @model.HpSnap::Leftovers))
  assert_true(@model.matches_snap(17, @model.HpSnap::Leftovers))
  assert_true(@model.matches_snap(33, @model.HpSnap::Leftovers))
  assert_true(@model.matches_snap(161, @model.HpSnap::Leftovers))
  assert_true(!@model.matches_snap(0, @model.HpSnap::Leftovers))
  assert_true(!@model.matches_snap(16, @model.HpSnap::Leftovers))
  assert_true(!@model.matches_snap(32, @model.HpSnap::Leftovers))
  assert_true(!@model.matches_snap(160, @model.HpSnap::Leftovers))
}

///|
test "matches_snap: Residual H ≡ 15 (mod 16)" {
  assert_true(@model.matches_snap(15, @model.HpSnap::Residual))
  assert_true(@model.matches_snap(31, @model.HpSnap::Residual))
  assert_true(@model.matches_snap(47, @model.HpSnap::Residual))
  assert_true(@model.matches_snap(175, @model.HpSnap::Residual))
  assert_true(!@model.matches_snap(16, @model.HpSnap::Residual))
  assert_true(!@model.matches_snap(32, @model.HpSnap::Residual))
  assert_true(!@model.matches_snap(14, @model.HpSnap::Residual))
}

///|
test "matches_snap: Sitrus even HP" {
  assert_true(@model.matches_snap(2, @model.HpSnap::Sitrus))
  assert_true(@model.matches_snap(100, @model.HpSnap::Sitrus))
  assert_true(@model.matches_snap(182, @model.HpSnap::Sitrus))
  assert_true(!@model.matches_snap(1, @model.HpSnap::Sitrus))
  assert_true(!@model.matches_snap(183, @model.HpSnap::Sitrus))
}

///|
test "matches_snap: LifeOrb H ≡ 0 (mod 10)" {
  assert_true(@model.matches_snap(10, @model.HpSnap::LifeOrb))
  assert_true(@model.matches_snap(20, @model.HpSnap::LifeOrb))
  assert_true(@model.matches_snap(200, @model.HpSnap::LifeOrb))
  assert_true(!@model.matches_snap(11, @model.HpSnap::LifeOrb))
  assert_true(!@model.matches_snap(201, @model.HpSnap::LifeOrb))
}

///|
test "hp_snap_from_str: valid values" {
  assert_true(@model.hp_snap_from_str("none") == Some(NoSnap))
  assert_true(@model.hp_snap_from_str("leftovers") == Some(Leftovers))
  assert_true(@model.hp_snap_from_str("residual") == Some(Residual))
  assert_true(@model.hp_snap_from_str("sitrus") == Some(Sitrus))
  assert_true(@model.hp_snap_from_str("lifeorb") == Some(LifeOrb))
}

///|
test "hp_snap_from_str: invalid" {
  assert_true(@model.hp_snap_from_str("unknown") == None)
  assert_true(@model.hp_snap_from_str("") == None)
}
