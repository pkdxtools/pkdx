///|
/// ほろびのうた。付与は 4、ターン終了で 1 減り、1 の終了でひんし。
/// 使わない技はカウントを動かさない。

///|
fn psh_move(name : String, accuracy : Int) -> @model.Move {
  flch_move(name, "ノーマル", @model.Status, 0, accuracy, 0)
}

///|
fn psh_mon(
  name : String,
  type1 : String,
  spe : Int,
  ability : String,
  mv : @model.Move,
) -> Combatant {
  flch_cmb(flch_pokemon(name, type1, 160, spe), [mv], ability)
}

///|
fn psh_pair(my_ab : String, opp_ab : String) -> (Array[Combatant], Array[Combatant]) {
  let song = psh_move("ほろびのうた", 100)
  let me = [psh_mon("a", "みず", 120, my_ab, song)]
  let opp = [psh_mon("b", "ほのお", 40, opp_ab, psh_move("はねる", 100))]
  (me, opp)
}

///|
fn psh_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-12
}

///|
test "perish song is the only move that sets the count" {
  assert_true(is_perish_song("ほろびのうた"))
  assert_true(!is_perish_song("たいあたり"))
  assert_true(!is_perish_song("たがやす"))
  assert_true(!is_perish_song("おちゃかい"))
  let (s, f) = mc_apply_perish(
    flch_tackle(),
    psh_mon("a", "みず", 120, "", flch_tackle()),
    160,
    0,
    psh_mon("b", "ほのお", 40, "", flch_tackle()),
    160,
    0,
    "",
  )
  assert_true(s == 0 && f == 0)
}

///|
test "perish song sets both actives to 4" {
  let (me, opp) = psh_pair("", "")
  let st = flch_state(160, 160, @model.None, @model.None)
  let outs = resolve_attacker_leg(
    ws_from_state(st),
    true,
    me[0].moves[0],
    0,
    false,
    false,
    false,
    me,
    opp,
    new_damage_cache(),
    None,
  )
  assert_true(outs.length() == 1)
  assert_true(psh_close(outs[0].0, 1.0))
  assert_true(outs[0].1.my_perish == 4)
  assert_true(outs[0].1.opp_perish == 4)
  assert_true(outs[0].1.my_hps[0] == 160)
  assert_true(outs[0].1.opp_hps[0] == 160)
}

///|
test "perish song does not refresh a count that is already running" {
  let (me, opp) = psh_pair("", "")
  let st = {
    ..flch_state(160, 160, @model.None, @model.None),
    my_perish: 2,
    opp_perish: 3,
  }
  let outs = perish_song_outcomes(
    st, true, 0, 0, me, opp, me[0].moves[0], false,
  )
  assert_true(outs[0].1.my_perish == 2)
  assert_true(outs[0].1.opp_perish == 3)
}

///|
test "soundproof does not receive perish song, including the user" {
  let song = psh_move("ほろびのうた", 100)
  let splash = psh_move("はねる", 100)
  let singer = [psh_mon("a", "みず", 120, "ぼうおん", song)]
  let foe = [psh_mon("b", "ほのお", 40, "", splash)]
  let st = flch_state(160, 160, @model.None, @model.None)
  let self_block = perish_song_outcomes(
    st, true, 0, 0, singer, foe, song, false,
  )
  assert_true(self_block[0].1.my_perish == 0)
  assert_true(self_block[0].1.opp_perish == 4)
  let deaf = [psh_mon("b", "ほのお", 40, "ぼうおん", splash)]
  let foe_block = perish_song_outcomes(
    st, true, 0, 0, [psh_mon("a", "みず", 120, "", song)], deaf, song, false,
  )
  assert_true(foe_block[0].1.my_perish == 4)
  assert_true(foe_block[0].1.opp_perish == 0)
  let both = perish_song_outcomes(st, true, 0, 0, singer, deaf, song, false)
  assert_true(both[0].1.my_perish == 0 && both[0].1.opp_perish == 0)
}

///|
test "mold breaker pierces the opponent's soundproof only" {
  let song = psh_move("ほろびのうた", 100)
  let splash = psh_move("はねる", 100)
  let st = flch_state(160, 160, @model.None, @model.None)
  let singer = [psh_mon("a", "みず", 120, "かたやぶり", song)]
  let deaf = [psh_mon("b", "ほのお", 40, "ぼうおん", splash)]
  let outs = perish_song_outcomes(st, true, 0, 0, singer, deaf, song, false)
  assert_true(outs[0].1.my_perish == 4)
  assert_true(outs[0].1.opp_perish == 4)
  let self_deaf = [psh_mon("a", "みず", 120, "ぼうおん", song)]
  let still = perish_song_outcomes(
    st, true, 0, 0, self_deaf, deaf, song, false,
  )
  assert_true(still[0].1.my_perish == 0)
  assert_true(still[0].1.opp_perish == 0)
}

///|
test "perish song does not hit a fainted or vanished foe" {
  let (me, opp) = psh_pair("", "")
  let faint = flch_state(160, 0, @model.None, @model.None)
  let dead = perish_song_outcomes(
    faint, true, 0, 0, me, opp, me[0].moves[0], false,
  )
  assert_true(dead[0].1.my_perish == 4)
  assert_true(dead[0].1.opp_perish == 0)
  let fly = psh_move("そらをとぶ", 100)
  let flying = [psh_mon("b", "ひこう", 40, "", fly)]
  let up = { ..flch_state(160, 160, @model.None, @model.None), opp_two_turn: 0 }
  let outs = resolve_attacker_leg(
    ws_from_state(up),
    true,
    me[0].moves[0],
    0,
    false,
    false,
    false,
    me,
    flying,
    new_damage_cache(),
    None,
  )
  assert_true(outs[0].1.my_perish == 4)
  assert_true(outs[0].1.opp_perish == 0)
}

///|
test "protect does not block perish song" {
  let (me, opp) = psh_pair("", "")
  let st = {
    ..flch_state(160, 160, @model.None, @model.None),
    opp_protect: PROTECT_FULL,
  }
  let outs = resolve_attacker_leg(
    ws_from_state(st),
    true,
    me[0].moves[0],
    0,
    false,
    false,
    false,
    me,
    opp,
    new_damage_cache(),
    None,
  )
  assert_true(outs[0].1.my_perish == 4)
  assert_true(outs[0].1.opp_perish == 4)
}

///|
test "accuracy 101 perish song is one certain hit" {
  let song = psh_move("ほろびのうた", 101)
  let me = [psh_mon("a", "みず", 120, "", song)]
  let opp = [psh_mon("b", "ほのお", 40, "", psh_move("はねる", 100))]
  let st = flch_state(160, 160, @model.None, @model.None)
  let outs = attempt_turn_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), me, opp, new_damage_cache(),
  )
  assert_true(outs.length() == 1)
  assert_true(psh_close(outs[0].0, 1.0))
  assert_true(outs[0].1.my_perish == 3)
  assert_true(outs[0].1.opp_perish == 3)
}

///|
test "apply_eot ticks perish and magic guard still faints" {
  let (me, opp) = psh_pair("", "マジックガード")
  let st = {
    ..flch_state(160, 160, @model.None, @model.None),
    my_perish: 4,
    opp_perish: 4,
  }
  let t3 = apply_eot(st, me, opp)
  assert_true(t3.my_perish == 3 && t3.opp_perish == 3)
  assert_true(t3.my_hps[0] == 160 && t3.opp_hps[0] == 160)
  let t2 = apply_eot(t3, me, opp)
  let t1 = apply_eot(t2, me, opp)
  assert_true(t1.my_perish == 1 && t1.opp_perish == 1)
  assert_true(t1.my_hps[0] == 160 && t1.opp_hps[0] == 160)
  let dead = apply_eot(t1, me, opp)
  assert_true(dead.my_hps[0] == 0 && dead.my_perish == 0)
  assert_true(dead.opp_hps[0] == 160 && dead.opp_perish == 1)
}

///|
test "apply_eot with no perish count does not change HP" {
  let (me, opp) = psh_pair("", "マジックガード")
  let st = flch_state(160, 159, @model.None, @model.None)
  let next = apply_eot(st, me, opp)
  assert_true(next.my_hps[0] == 160)
  assert_true(next.opp_hps[0] == 159)
  assert_true(next.my_perish == 0 && next.opp_perish == 0)
}

///|
test "perish double faint follows speed and a tie faints both" {
  let fast = psh_mon("a", "みず", 200, "マジックガード", flch_tackle())
  let slow = psh_mon("b", "ほのお", 40, "マジックガード", flch_tackle())
  let ranks = [0, 0, 0, 0, 0]
  let (hp_m, hp_o, c_m, c_o) = apply_perish_eot_pair(
    1, 1, 160, 160, fast, slow, false, false, ranks, ranks, false, false, false,
    false, false, false,
  )
  assert_true(hp_m == 0 && c_m == 0)
  assert_true(hp_o == 160 && c_o == 1)
  let (hp_m2, hp_o2, c_m2, c_o2) = apply_perish_eot_pair(
    1, 1, 160, 160, slow, fast, false, false, ranks, ranks, false, false, false,
    false, false, false,
  )
  assert_true(hp_m2 == 160 && c_m2 == 1)
  assert_true(hp_o2 == 0 && c_o2 == 0)
  let tied = psh_mon("c", "ノーマル", 80, "", flch_tackle())
  let (ht_m, ht_o, ct_m, ct_o) = apply_perish_eot_pair(
    1, 1, 160, 160, tied, tied, false, false, ranks, ranks, false, false, false,
    false, false, false,
  )
  assert_true(ht_m == 0 && ht_o == 0 && ct_m == 0 && ct_o == 0)
  let (bk_m, bk_o, bk_cm, bk_co) = apply_perish_eot_pair(
    1, 1, 160, 160, fast, slow, false, false, ranks, ranks, false, false, false,
    false, true, true,
  )
  assert_true(bk_m == 0 && bk_o == 0 && bk_cm == 0 && bk_co == 0)
}

///|
test "switching clears only that side's perish count" {
  assert_true(perish_after_switch(4, ActionKind::Switch(1)) == 0)
  assert_true(perish_after_switch(4, ActionKind::UseMove(0)) == 4)
  assert_true(perish_after_switch(0, ActionKind::Switch(1)) == 0)
  let song = psh_move("ほろびのうた", 101)
  let splash = psh_move("はねる", 100)
  let me = [
    psh_mon("a", "みず", 100, "", splash),
    psh_mon("a2", "くさ", 90, "", splash),
  ]
  let opp = [
    psh_mon("b", "ほのお", 80, "", song),
    psh_mon("b2", "でんき", 70, "", splash),
  ]
  let st = { ..rg_state([160, 160], [160, 160]), my_perish: 2, opp_perish: 0 }
  let outs = attempt_turn_with_cache(
    st, ActionKind::Switch(1), ActionKind::UseMove(0), me, opp, new_damage_cache(),
  )
  assert_true(outs.length() == 1)
  assert_true(psh_close(outs[0].0, 1.0))
  assert_true(outs[0].1.my_active == 1)
  assert_true(outs[0].1.my_perish == 3)
  assert_true(outs[0].1.opp_perish == 3)
  assert_true(outs[0].1.my_hps[0] == 160)
}

///|
test "perish does not add a switch block; bind still does" {
  let splash = psh_move("はねる", 100)
  let team = [
    psh_mon("a", "ノーマル", 100, "", splash),
    psh_mon("a2", "ノーマル", 90, "", splash),
  ]
  let bound = alive_actions(
    0, [160, 160], team, false, can_switch=bind_switch_free(4, team[0], false, ""),
  )
  let open = alive_actions(
    0, [160, 160], team, false, can_switch=bind_switch_free(0, team[0], false, ""),
  )
  let mut bound_switch = false
  for a in bound {
    match a {
      Switch(_) => bound_switch = true
      _ => ()
    }
  }
  let mut open_switch = false
  for a in open {
    match a {
      Switch(_) => open_switch = true
      _ => ()
    }
  }
  assert_true(!bound_switch)
  assert_true(open_switch)
}

///|
test "perish count is part of the state cache key" {
  let base = flch_state(160, 160, @model.None, @model.None)
  assert_distinct_state_keys(base, { ..base, my_perish: 4 })
  assert_distinct_state_keys(base, { ..base, opp_perish: 1 })
}

///|
test "protean still locks when perish song is used" {
  let song = psh_move("ほろびのうた", 100)
  let me = [psh_mon("a", "みず", 120, "へんげんじざい", song)]
  let opp = [psh_mon("b", "ほのお", 40, "", psh_move("はねる", 100))]
  let st = flch_state(160, 160, @model.None, @model.None)
  let outs = perish_song_outcomes(st, true, 0, 0, me, opp, song, false)
  assert_true(outs[0].1.my_protean_locked[0] == "ノーマル")
  assert_true(outs[0].1.my_perish == 4)
}

///|
test "perish song 1v1: the faster side loses and MC matches DP" {
  let song = psh_move("ほろびのうた", 100)
  let me = [psh_mon("a", "みず", 120, "", song)]
  let opp = [psh_mon("b", "ほのお", 40, "", song)]
  let dp = switching_game_winrate(me, opp, 8)
  let mc = team_monte_carlo_value(me, opp, 1, 1UL, turn_limit=8)
  assert_true(psh_close(dp, -1.0))
  assert_true(psh_close(mc, -1.0))
  let dp_slow = switching_game_winrate(opp, me, 8)
  let mc_slow = team_monte_carlo_value(opp, me, 1, 7UL, turn_limit=8)
  assert_true(psh_close(dp_slow, 1.0))
  assert_true(psh_close(mc_slow, 1.0))
}
