///|
/// はやてがえし (WAZAINFO_SYN_918)。相手の選択が priority > 0 の技のときだけ
/// 成功し、命中すれば既存のひるみ経路でひるむ。priority <= 0 と交代は失敗する。
///
/// まもる などの変化先制はゲート helper だけを見る。Protect は payoff が
/// 技を止めない (`max_hp_recoil.mbt`) ので、ターン解決で「守って無効」は
/// 正直にテストできない。

///|
fn uh_move() -> @model.Move {
  {
    ..flch_move("はやてがえし", "かくとう", @model.Physical, 65, 100, 100),
    priority: 3,
  }
}

///|
fn uh_at(name : String, priority : Int) -> @model.Move {
  { ..flch_move(name, "ノーマル", @model.Physical, 40, 100, 0), priority }
}

///|
fn uh_status(name : String, priority : Int) -> @model.Move {
  { ..flch_move(name, "ノーマル", @model.Status, 0, 100, 0), priority }
}

///|
fn uh_gap(a : Double, b : Double) -> Double {
  let d = a - b
  if d < 0.0 { 0.0 - d } else { d }
}

///|
test "upper_hand_fails: priority > 0 connects, including a status move" {
  let uh = uh_move()
  let bite = flch_bite(30)
  assert_true(!upper_hand_fails(uh, Some(uh_at("でんこうせっか", 1))))
  assert_true(!upper_hand_fails(uh, Some(uh_at("しんそく", 2))))
  assert_true(!upper_hand_fails(uh, Some(uh_at("ねこだまし", 3))))
  // まもる は変化技だが priority 4。Protect 自体は未モデルなので helper だけ。
  assert_true(!upper_hand_fails(uh, Some(uh_status("まもる", 4))))
  assert_true(upper_hand_fails(uh, Some(uh_at("たいあたり", 0))))
  assert_true(upper_hand_fails(uh, Some(uh_at("トリックルーム", -6))))
  assert_true(upper_hand_fails(uh, None))
  assert_true(!upper_hand_fails(bite, None))
  assert_true(!upper_hand_fails(bite, Some(uh_at("たいあたり", 0))))
}

///|
test "flinch_chance_vs_choice: a failing Upper Hand does not defer a flinch" {
  let uh = uh_move()
  let quick = uh_at("でんこうせっか", 1)
  let tackle = uh_at("たいあたり", 0)
  assert_true(flinch_chance_vs_choice(uh, None, Some(quick)) == 100)
  assert_true(flinch_chance_vs_choice(uh, None, Some(tackle)) == 0)
  assert_true(flinch_chance_vs_choice(uh, None, None) == 0)
  assert_true(flinch_chance_vs_choice(flch_bite(30), Some(false), Some(tackle)) == 30)
}

///|
test "upper hand flinches when the foe selected a priority move" {
  let my_team = flch_my_first_team(uh_move(), "")
  let start = flch_state(200, 200, @model.None, @model.None)
  let names = ["でんこうせっか", "しんそく", "ねこだまし"]
  let prios = [1, 2, 3]
  for i = 0; i < names.length(); i = i + 1 {
    let opp_team = flch_opp_team(uh_at(names[i], prios[i]), "")
    let outs = flch_turn(start, my_team, opp_team)
    assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
    assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
  }
}

///|
test "upper hand fails entirely against a priority-0 move" {
  let my_team = flch_my_first_team(uh_move(), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "upper hand vs switch fails and does not hit the incoming mon" {
  let my_team = flch_my_first_team(uh_move(), "")
  let lead = flch_cmb(flch_pokemon("lead", "ノーマル", 200, 80), [flch_tackle()], "")
  let bench = flch_cmb(flch_pokemon("bench", "ノーマル", 200, 80), [flch_tackle()], "")
  let start = {
    ..flch_state(200, 200, @model.None, @model.None),
    opp_hps: [200, 200],
    opp_megaed: [false, false],
    opp_status: [@model.None, @model.None],
    opp_must_recharge: [false, false],
    opp_item_consumed: [false, false],
    opp_disguise_busted: [false, false],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
  }
  let outs = attempt_turn_with_cache(
    start, UseMove(0), Switch(1), my_team, [lead, bench], new_damage_cache(),
  )
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_active == 1 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] == 200 && s.opp_hps[1] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
}

///|
test "upper hand vs inner focus: the hit lands and the target still acts" {
  let my_team = flch_my_first_team(uh_move(), "")
  let opp_team = flch_opp_team(uh_at("でんこうせっか", 1), "せいしんりょく")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "upper hand still hits a sleeping foe who selected a priority move" {
  let my_team = flch_my_first_team(uh_move(), "")
  let opp_team = flch_opp_team(uh_at("でんこうせっか", 1), "")
  let outs = flch_turn(
    flch_state(200, 200, @model.None, @model.Sleep(2)),
    my_team,
    opp_team,
  )
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
}

///|
test "upper hand still hits a recharging foe who selected a priority move" {
  let my_team = flch_my_first_team(uh_move(), "")
  let opp_team = flch_opp_team(uh_at("でんこうせっか", 1), "")
  let start = {
    ..flch_state(200, 200, @model.None, @model.None),
    opp_must_recharge: [true],
  }
  let outs = flch_turn(start, my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
}

///|
test "upper hand with flinch_chance 0 does not invent a flinch" {
  let weak = { ..uh_move(), flinch_chance: 0 }
  let my_team = flch_my_first_team(weak, "")
  let fail_outs = flch_turn(
    flch_state(200, 200, @model.None, @model.None),
    my_team,
    flch_opp_team(flch_tackle(), ""),
  )
  assert_true(flch_close(flch_mass(fail_outs, fn(s) { s.opp_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(fail_outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
  let hit = flch_turn(
    flch_state(200, 200, @model.None, @model.None),
    my_team,
    flch_opp_team(uh_at("でんこうせっか", 1), ""),
  )
  assert_true(flch_close(flch_mass(hit, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(hit, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "upper hand DP and MC agree on a priority move and on a normal move" {
  let mine = [flch_cmb(flch_pokemon("a", "ノーマル", 1000, 120), [uh_move()], "")]
  let quick = [
    flch_cmb(flch_pokemon("b", "ノーマル", 1000, 60), [uh_at("でんこうせっか", 1)], ""),
  ]
  let tackle = [flch_cmb(flch_pokemon("c", "ノーマル", 1000, 60), [flch_tackle()], "")]
  let dp_quick = switching_game_winrate(mine, quick, 2)
  let mc_quick = team_monte_carlo_value(mine, quick, 1024, 20261113UL, turn_limit=2)
  assert_true(uh_gap(dp_quick, mc_quick) < 0.03)
  let dp_tackle = switching_game_winrate(mine, tackle, 2)
  let mc_tackle = team_monte_carlo_value(mine, tackle, 1024, 20261113UL, turn_limit=2)
  assert_true(uh_gap(dp_tackle, mc_tackle) < 0.03)
  assert_true(dp_quick - dp_tackle > 0.02)
}
