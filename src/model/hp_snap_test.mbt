///|
test "matches_snap: None is always true" {
  inspect(matches_snap(1, HpSnap::NoSnap), content="true")
  inspect(matches_snap(100, HpSnap::NoSnap), content="true")
  inspect(matches_snap(0, HpSnap::NoSnap), content="true")
}

///|
test "matches_snap: Leftovers H ≡ 1 (mod 16)" {
  inspect(matches_snap(1, HpSnap::Leftovers), content="true")
  inspect(matches_snap(17, HpSnap::Leftovers), content="true")
  inspect(matches_snap(33, HpSnap::Leftovers), content="true")
  inspect(matches_snap(161, HpSnap::Leftovers), content="true")
  inspect(matches_snap(0, HpSnap::Leftovers), content="false")
  inspect(matches_snap(16, HpSnap::Leftovers), content="false")
  inspect(matches_snap(32, HpSnap::Leftovers), content="false")
  inspect(matches_snap(160, HpSnap::Leftovers), content="false")
}

///|
test "matches_snap: Residual H ≡ 15 (mod 16)" {
  inspect(matches_snap(15, HpSnap::Residual), content="true")
  inspect(matches_snap(31, HpSnap::Residual), content="true")
  inspect(matches_snap(47, HpSnap::Residual), content="true")
  inspect(matches_snap(175, HpSnap::Residual), content="true")
  inspect(matches_snap(16, HpSnap::Residual), content="false")
  inspect(matches_snap(32, HpSnap::Residual), content="false")
  inspect(matches_snap(14, HpSnap::Residual), content="false")
}

///|
test "matches_snap: Sitrus even HP" {
  inspect(matches_snap(2, HpSnap::Sitrus), content="true")
  inspect(matches_snap(100, HpSnap::Sitrus), content="true")
  inspect(matches_snap(182, HpSnap::Sitrus), content="true")
  inspect(matches_snap(1, HpSnap::Sitrus), content="false")
  inspect(matches_snap(183, HpSnap::Sitrus), content="false")
}

///|
test "matches_snap: LifeOrb H ≡ 0 (mod 10)" {
  inspect(matches_snap(10, HpSnap::LifeOrb), content="true")
  inspect(matches_snap(20, HpSnap::LifeOrb), content="true")
  inspect(matches_snap(200, HpSnap::LifeOrb), content="true")
  inspect(matches_snap(11, HpSnap::LifeOrb), content="false")
  inspect(matches_snap(201, HpSnap::LifeOrb), content="false")
}

///|
test "hp_snap_from_str: valid values" {
  inspect(hp_snap_from_str("none"), content="Some(NoSnap)")
  inspect(hp_snap_from_str("leftovers"), content="Some(Leftovers)")
  inspect(hp_snap_from_str("residual"), content="Some(Residual)")
  inspect(hp_snap_from_str("sitrus"), content="Some(Sitrus)")
  inspect(hp_snap_from_str("lifeorb"), content="Some(LifeOrb)")
}

///|
test "hp_snap_from_str: invalid" {
  inspect(hp_snap_from_str("unknown"), content="None")
  inspect(hp_snap_from_str(""), content="None")
}
