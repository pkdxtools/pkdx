///|
/// であいがしら (WAZAINFO_SYN_660)。初行動 (`Some(true)`) なら命中する。
/// 技を使ったあと (`Some(false)`) は失敗する。省略 (`None`) は失敗しない。
/// ひるみは無い。ねこだまし と同じ fresh を使い、ねこだまし のひるみは壊さない。

///|
fn fi_move() -> @model.Move {
  { ..flch_move("であいがしら", "むし", @model.Physical, 100, 100, 0), priority: 2 }
}

///|
fn fi_fresh(my_fresh : Bool?, opp_fresh : Bool?) -> SwitchingGameState {
  { ..flch_state(200, 200, @model.None, @model.None), my_fresh, opp_fresh }
}

///|
fn fi_gap(a : Double, b : Double) -> Double {
  let d = a - b
  if d < 0.0 { 0.0 - d } else { d }
}

///|
test "first_impression_fails: Some(true) and None connect, Some(false) fails" {
  let fi = fi_move()
  let fo = fo_move()
  assert_true(!first_impression_fails(fi, Some(true)))
  assert_true(first_impression_fails(fi, Some(false)))
  assert_true(!first_impression_fails(fi, None))
  assert_true(!first_impression_fails(fo, Some(false)))
  assert_true(!fake_out_fails(fi, Some(false)))
  // ひるみは発明しない。ねこだまし の初行動ひるみはそのまま。
  assert_true(flinch_chance_if_fresh(fi, Some(true)) == 0)
  assert_true(flinch_chance_if_fresh(fi, Some(false)) == 0)
  assert_true(flinch_chance_if_fresh(fi, None) == 0)
  assert_true(flinch_chance_if_fresh(fo, Some(true)) == 100)
  assert_true(flinch_chance_if_fresh(fo, Some(false)) == 0)
}

///|
test "first impression when fresh: hits and does not flinch, then the next turn fails" {
  let my_team = flch_my_first_team(fi_move(), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(fi_fresh(Some(true), Some(true)), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_fresh == Some(false) }), 1.0))
  let again = flch_turn(outs[0].1, my_team, opp_team)
  let opp_after = outs[0].1.opp_hps[0]
  let my_after = outs[0].1.my_hps[0]
  assert_true(flch_close(flch_mass(again, fn(s) { s.opp_hps[0] == opp_after }), 1.0))
  assert_true(flch_close(flch_mass(again, fn(s) { s.my_hps[0] < my_after }), 1.0))
  assert_true(flch_close(flch_mass(again, fn(s) { s.my_fresh == Some(false) }), 1.0))
}

///|
test "first impression when not fresh: the move fails entirely" {
  let my_team = flch_my_first_team(fi_move(), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(fi_fresh(Some(false), Some(true)), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_fresh == Some(false) }), 1.0))
}

///|
test "first impression omitted fresh: deals damage and stays None" {
  let my_team = flch_my_first_team(fi_move(), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(fi_fresh(None, None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_fresh == None && s.opp_fresh == None }), 1.0))
  let again = flch_turn(outs[0].1, my_team, opp_team)
  let opp_after = outs[0].1.opp_hps[0]
  assert_true(flch_close(flch_mass(again, fn(s) { s.opp_hps[0] < opp_after }), 1.0))
  assert_true(flch_close(flch_mass(again, fn(s) { s.my_fresh == None && s.opp_fresh == None }), 1.0))
}

///|
test "first impression reads the user's fresh, not the foe's" {
  let mine = [flch_cmb(flch_pokemon("slow", "ノーマル", 200, 60), [flch_tackle()], "")]
  let theirs = [flch_cmb(flch_pokemon("bug", "むし", 200, 120), [fi_move()], "")]
  let landed = flch_turn(fi_fresh(Some(false), Some(true)), mine, theirs)
  assert_true(flch_close(flch_mass(landed, fn(s) { s.my_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(landed, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  let failed = flch_turn(fi_fresh(Some(true), Some(false)), mine, theirs)
  assert_true(flch_close(flch_mass(failed, fn(s) { s.my_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(failed, fn(s) { s.opp_hps[0] < 200 }), 1.0))
}

///|
test "switch-in: the first first-impression succeeds and the next one fails" {
  let lead = flch_cmb(flch_pokemon("lead", "ノーマル", 200, 80), [flch_tackle()], "")
  let bench = flch_cmb(flch_pokemon("bench", "むし", 200, 80), [fi_move()], "")
  let my_team = [lead, bench]
  let opp_team = flch_opp_team(flch_tackle(), "")
  let start = {
    ..flch_state(200, 200, @model.None, @model.None),
    my_hps: [200, 200],
    my_megaed: [false, false],
    my_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    my_item_consumed: [false, false],
    my_disguise_busted: [false, false],
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    my_fresh: Some(false),
    opp_fresh: Some(true),
  }
  let switched = attempt_turn_with_cache(
    start, Switch(1), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  assert_true(flch_close(flch_mass(switched, fn(s) { s.my_active == 1 }), 1.0))
  assert_true(flch_close(flch_mass(switched, fn(s) { s.my_fresh == Some(true) }), 1.0))
  assert_true(flch_close(flch_mass(switched, fn(s) { s.opp_fresh == Some(false) }), 1.0))
  assert_true(flch_close(flch_mass(switched, fn(s) { s.my_hps[1] < 200 && s.my_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(switched, fn(s) { s.opp_hps[0] == 200 }), 1.0))
  let came_in = switched[0].1
  let hp_in = came_in.my_hps[1]
  let next = attempt_turn_with_cache(
    came_in, UseMove(0), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  assert_true(flch_close(flch_mass(next, fn(s) { s.opp_hps[0] < came_in.opp_hps[0] }), 1.0))
  assert_true(flch_close(flch_mass(next, fn(s) { s.my_hps[1] < hp_in }), 1.0))
  assert_true(flch_close(flch_mass(next, fn(s) { s.my_fresh == Some(false) && s.opp_fresh == Some(false) }), 1.0))
  let spent = next[0].1
  let third = attempt_turn_with_cache(
    spent, UseMove(0), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  assert_true(flch_close(flch_mass(third, fn(s) { s.opp_hps[0] == spent.opp_hps[0] }), 1.0))
  assert_true(flch_close(flch_mass(third, fn(s) { s.my_hps[1] < spent.my_hps[1] }), 1.0))
}

///|
test "fake out and first impression share fresh and fake out still flinches" {
  let my_team = flch_my_first_team(fo_move(), "")
  let opp_team = flch_opp_team(fi_move(), "")
  let outs = flch_turn(fi_fresh(Some(true), Some(true)), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_fresh == Some(false) && s.opp_fresh == Some(false) }), 1.0))
  let spent = outs[0].1
  let again = flch_turn(spent, my_team, opp_team)
  assert_true(flch_close(flch_mass(again, fn(s) { s.my_hps[0] == spent.my_hps[0] && s.opp_hps[0] == spent.opp_hps[0] }), 1.0))
}

///|
test "first impression DP and MC agree on a fresh success and on a spent fail" {
  let mine = [flch_cmb(flch_pokemon("a", "むし", 800, 120), [fi_move()], "")]
  let theirs = [flch_cmb(flch_pokemon("b", "ノーマル", 800, 60), [flch_tackle()], "")]
  let dp_hit = switching_game_winrate(
    mine, theirs, 3, my_fresh=Some(true), opp_fresh=Some(true),
  )
  let dp_fail = switching_game_winrate(
    mine, theirs, 3, my_fresh=Some(false), opp_fresh=Some(false),
  )
  let dp_none = switching_game_winrate(mine, theirs, 3)
  let mc_hit = team_monte_carlo_value(
    mine, theirs, 2048, 20261113UL, turn_limit=3, my_fresh=Some(true), opp_fresh=Some(true),
  )
  let mc_fail = team_monte_carlo_value(
    mine,
    theirs,
    2048,
    20261113UL,
    turn_limit=3,
    my_fresh=Some(false),
    opp_fresh=Some(false),
  )
  // None は毎ターン当たる。Some(true) は初手だけ。Some(false) は当たらない。
  assert_true(dp_none > dp_hit + 0.02)
  assert_true(dp_hit > dp_fail + 0.02)
  assert_true(fi_gap(dp_hit, mc_hit) < 0.03)
  assert_true(fi_gap(dp_fail, mc_fail) < 0.03)
}
