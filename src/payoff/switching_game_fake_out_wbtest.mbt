///|
/// ねこだまし (WAZAINFO_SYN_252)。初行動 (`Some(true)`) なら命中してひるみ、
/// 技を使ったあと (`Some(false)`) は失敗する。省略 (`None`) は従来どおりダメージだけ。

///|
fn fo_move() -> @model.Move {
  { ..flch_move("ねこだまし", "ノーマル", @model.Physical, 40, 100, 100), priority: 3 }
}

///|
fn fo_fresh(my_fresh : Bool?, opp_fresh : Bool?) -> SwitchingGameState {
  { ..flch_state(200, 200, @model.None, @model.None), my_fresh, opp_fresh }
}

///|
test "fresh_after_action: None stays None, a move spends, a switch refreshes" {
  assert_true(fresh_after_action(None, UseMove(0)) == None)
  assert_true(fresh_after_action(None, Switch(1)) == None)
  assert_true(fresh_after_action(Some(true), UseMove(0)) == Some(false))
  assert_true(fresh_after_action(Some(true), Mega(0)) == Some(false))
  assert_true(fresh_after_action(Some(false), Switch(1)) == Some(true))
  assert_true(fresh_after_switch(Some(false), true) == Some(true))
  assert_true(fresh_after_switch(Some(true), false) == Some(false))
  assert_true(fresh_after_switch(None, true) == None)
}

///|
test "fake out when fresh: hits and flinches, then the next turn fails" {
  let my_team = flch_my_first_team(fo_move(), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(fo_fresh(Some(true), Some(true)), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_fresh == Some(false) }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_fresh == Some(false) }), 1.0))
  let again = flch_turn(outs[0].1, my_team, opp_team)
  let opp_after = outs[0].1.opp_hps[0]
  assert_true(flch_close(flch_mass(again, fn(s) { s.opp_hps[0] == opp_after }), 1.0))
  assert_true(flch_close(flch_mass(again, fn(s) { s.my_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(again, fn(s) { s.my_fresh == Some(false) && s.opp_fresh == Some(false) }), 1.0))
}

///|
test "fake out when not fresh: the move fails, it is not a hit without flinch" {
  let my_team = flch_my_first_team(fo_move(), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(fo_fresh(Some(false), Some(true)), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_fresh == Some(false) }), 1.0))
}

///|
test "fake out omitted fresh: deals damage, does not flinch, and stays None" {
  let my_team = flch_my_first_team(fo_move(), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(fo_fresh(None, None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_fresh == None && s.opp_fresh == None }), 1.0))
  let again = flch_turn(outs[0].1, my_team, opp_team)
  assert_true(flch_close(flch_mass(again, fn(s) { s.my_fresh == None && s.opp_fresh == None }), 1.0))
}

///|
test "fake out inner focus: the hit lands and the target still acts" {
  let my_team = flch_my_first_team(fo_move(), "")
  let opp_team = flch_opp_team(flch_tackle(), "せいしんりょく")
  let outs = flch_turn(fo_fresh(Some(true), Some(false)), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "other flinch moves ignore fresh and still flinch at 100" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(fo_fresh(Some(false), Some(false)), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
}

///|
test "switch-in sets fresh for the next turn and does not leak to the other side" {
  let lead = flch_cmb(flch_pokemon("lead", "ノーマル", 200, 80), [flch_tackle()], "")
  let bench = flch_cmb(flch_pokemon("bench", "ノーマル", 200, 80), [fo_move()], "")
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
  let came_in = switched[0].1
  let hp_in = came_in.my_hps[1]
  let next = attempt_turn_with_cache(
    came_in, UseMove(0), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  assert_true(flch_close(flch_mass(next, fn(s) { s.my_hps[1] == hp_in }), 1.0))
  assert_true(flch_close(flch_mass(next, fn(s) { s.opp_hps[0] < came_in.opp_hps[0] }), 1.0))
  assert_true(flch_close(flch_mass(next, fn(s) { s.my_fresh == Some(false) && s.opp_fresh == Some(false) }), 1.0))
  let spent = next[0].1
  let third = attempt_turn_with_cache(
    spent, UseMove(0), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  assert_true(flch_close(flch_mass(third, fn(s) { s.opp_hps[0] == spent.opp_hps[0] }), 1.0))
  assert_true(flch_close(flch_mass(third, fn(s) { s.my_hps[1] < hp_in }), 1.0))
  assert_true(flch_close(flch_mass(third, fn(s) { s.opp_fresh == Some(false) }), 1.0))
}

///|
test "omitted fresh stays None across a switch" {
  let lead = flch_cmb(flch_pokemon("lead", "ノーマル", 200, 80), [flch_tackle()], "")
  let bench = flch_cmb(flch_pokemon("bench", "ノーマル", 200, 80), [fo_move()], "")
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
  }
  let switched = attempt_turn_with_cache(
    start,
    Switch(1),
    UseMove(0),
    [lead, bench],
    flch_opp_team(flch_tackle(), ""),
    new_damage_cache(),
  )
  assert_true(flch_close(flch_mass(switched, fn(s) { s.my_fresh == None && s.opp_fresh == None }), 1.0))
}

///|
test "state cache key: my_fresh Some(true) is distinct from None" {
  let base = ck_state_base()
  let fresh = { ..base, my_fresh: Some(true) }
  assert_distinct_state_keys(base, fresh)
  let opp = { ..base, opp_fresh: Some(false) }
  assert_distinct_state_keys(base, opp)
}

///|
fn fo_object(raw : String) -> Map[String, Json] raise {
  let parsed = @json.parse(raw) catch { _ => fail("json") }
  match parsed {
    Object(m) => m
    _ => fail("object")
  }
}

///|
test "parse_optional_bool: absent is None, true and false are read, other types fail" {
  let absent = fo_object("{}")
  let yes = fo_object("{\"my_fresh\":true,\"opp_fresh\":false}")
  let bad = fo_object("{\"my_fresh\":1}")
  let none = parse_optional_bool(absent, "my_fresh") catch { _ => fail("absent") }
  let mine = parse_optional_bool(yes, "my_fresh") catch { _ => fail("true") }
  let theirs = parse_optional_bool(yes, "opp_fresh") catch { _ => fail("false") }
  assert_true(none == None)
  assert_true(mine == Some(true))
  assert_true(theirs == Some(false))
  let mut rejected = false
  let _bad = parse_optional_bool(bad, "my_fresh") catch {
    _ => {
      rejected = true
      None
    }
  }
  assert_true(rejected)
}

///|
fn fo_gap(a : Double, b : Double) -> Double {
  let d = a - b
  if d < 0.0 { 0.0 - d } else { d }
}

///|
test "fake out DP and MC agree when the battle starts fresh" {
  let mine = [flch_cmb(flch_pokemon("a", "ノーマル", 800, 120), [fo_move()], "")]
  let theirs = [flch_cmb(flch_pokemon("b", "ノーマル", 800, 60), [flch_tackle()], "")]
  let dp = switching_game_winrate(
    mine, theirs, 3, my_fresh=Some(true), opp_fresh=Some(true),
  )
  let dp_none = switching_game_winrate(mine, theirs, 3)
  let mc = team_monte_carlo_value(
    mine, theirs, 2048, 20261112UL, turn_limit=3, my_fresh=Some(true), opp_fresh=Some(true),
  )
  assert_true(fo_gap(dp, dp_none) > 0.02)
  assert_true(fo_gap(dp, mc) < 0.02)
}

///|
test "fake out DP and MC agree after a switch refreshes the incoming mon" {
  let lead = flch_cmb(flch_pokemon("lead", "ノーマル", 0, 50), [flch_tackle()], "")
  let bench = flch_cmb(flch_pokemon("bench", "ノーマル", 800, 120), [fo_move()], "")
  let opp = [flch_cmb(flch_pokemon("b", "ノーマル", 800, 40), [flch_tackle()], "")]
  let dp = switching_game_winrate(
    [lead, bench], opp, 2, my_fresh=Some(false), opp_fresh=Some(true),
  )
  let mc = team_monte_carlo_value(
    [lead, bench],
    opp,
    1024,
    20261112UL,
    turn_limit=2,
    my_fresh=Some(false),
    opp_fresh=Some(true),
  )
  assert_true(fo_gap(dp, mc) < 0.03)
}
