///|
/// まもる系。champout `50e7233` の wazainfo と特性本文。
/// 連続率の下限 1/729 と 1/4 の丸めは本文に無いので Showdown / round5。

///|
fn pr_move(
  name : String,
  category : @model.MoveCategory,
  power : Int,
  priority : Int,
) -> @model.Move {
  { ..flch_move(name, "ノーマル", category, power, 100, 0), priority }
}

///|
fn pr_protect(name : String) -> @model.Move {
  pr_move(name, @model.Status, 0, 4)
}

///|
fn pr_wall(mv : @model.Move) -> Array[Combatant] {
  [flch_cmb(flch_pokemon("wall", "ノーマル", 200, 60), [mv], "")]
}

///|
fn pr_hit(mv : @model.Move, ability : String) -> Array[Combatant] {
  [flch_cmb(flch_pokemon("hit", "ノーマル", 200, 120), [mv], ability)]
}

///|
fn pr_turn(
  state : SwitchingGameState,
  wall : Array[Combatant],
  hit : Array[Combatant],
) -> Array[(Double, SwitchingGameState)] {
  attempt_turn_with_cache(
    state, UseMove(0), UseMove(0), wall, hit, new_damage_cache(),
  )
}

///|
fn pr_base() -> SwitchingGameState {
  flch_state(200, 200, @model.None, @model.None)
}

///|
test "protect names: available guards only" {
  assert_true(is_protect_move("まもる"))
  assert_true(is_protect_move("みきり"))
  assert_true(is_protect_move("キングシールド"))
  assert_true(is_protect_move("ニードルガード"))
  assert_true(is_protect_move("トーチカ"))
  assert_true(!is_protect_move("こらえる"))
  assert_true(!is_protect_move("ワイドガード"))
  assert_true(!is_protect_move("ファストガード"))
  assert_true(!is_protect_move("ブロッキング"))
  assert_true(!is_protect_move("スレッドトラップ"))
  assert_true(!is_protect_move("かえんのまもり"))
  assert_true(!is_protect_move("シャドーダイブ"))
  assert_true(!is_protect_move("フェイント"))
  assert_true(!is_protect_move("ゴーストダイブ"))
  assert_true(!is_protect_move("たいあたり"))
  @debug.assert_eq(stall_denominator(0), 1)
  @debug.assert_eq(stall_denominator(1), 3)
  @debug.assert_eq(stall_denominator(6), 729)
  @debug.assert_eq(stall_denominator(9), 729)
  @debug.assert_eq(stall_next(0), 1)
  @debug.assert_eq(stall_next(6), 6)
}

///|
test "protect priority blocks a faster tackle and sets stall" {
  let wall = pr_wall(pr_protect("まもる"))
  let hit = pr_hit(flch_tackle(), "")
  let outs = pr_turn(pr_base(), wall, hit)
  @debug.assert_eq(outs.length(), 1)
  let s = outs[0].1
  @debug.assert_eq(s.my_hps[0], 200)
  @debug.assert_eq(s.my_stall, 1)
  @debug.assert_eq(s.my_protect, 0)
  @debug.assert_eq(s.opp_stall, 0)
  @debug.assert_eq(s.opp_hps[0], 200)
}

///|
test "detect matches protect, and a turn without protect leaves stall at 0" {
  let wall = pr_wall(pr_protect("みきり"))
  let hit = pr_hit(flch_tackle(), "")
  let s = pr_turn(pr_base(), wall, hit)[0].1
  @debug.assert_eq(s.my_hps[0], 200)
  @debug.assert_eq(s.my_stall, 1)
  let plain = pr_turn(pr_base(), pr_hit(flch_tackle(), ""), pr_wall(flch_tackle()))
  @debug.assert_eq(plain.length(), 1)
  @debug.assert_eq(plain[0].1.my_stall, 0)
  @debug.assert_eq(plain[0].1.opp_stall, 0)
  @debug.assert_eq(plain[0].1.my_protect, 0)
}

///|
test "consecutive protect is one third, then a skipped turn resets" {
  let protect = pr_protect("まもる")
  let tackle = flch_tackle()
  let wall = [
    flch_cmb(flch_pokemon("wall", "ノーマル", 200, 60), [protect, tackle], ""),
  ]
  let hit = pr_hit(tackle, "")
  let s1 = pr_turn(pr_base(), wall, hit)[0].1
  @debug.assert_eq(s1.my_stall, 1)
  let outs = pr_turn(s1, wall, hit)
  let blocked = flch_mass(outs, fn(s) { s.my_hps[0] == 200 && s.my_stall == 2 })
  let failed = flch_mass(outs, fn(s) { s.my_hps[0] < 200 && s.my_stall == 0 })
  assert_true(flch_close(blocked, 1.0 / 3.0))
  assert_true(flch_close(failed, 2.0 / 3.0))
  let skipped = attempt_turn_with_cache(
    s1, UseMove(1), UseMove(0), wall, hit, new_damage_cache(),
  )[0].1
  @debug.assert_eq(skipped.my_stall, 0)
  let again = attempt_turn_with_cache(
    skipped, UseMove(0), UseMove(0), wall, hit, new_damage_cache(),
  )
  @debug.assert_eq(again.length(), 1)
  @debug.assert_eq(again[0].1.my_hps[0], skipped.my_hps[0])
  @debug.assert_eq(again[0].1.my_stall, 1)
}

///|
test "spiky shield chips a contact hit, not feint, not long reach, not magic guard" {
  let spiky = pr_protect("ニードルガード")
  let wall = pr_wall(spiky)
  let tack = pr_turn(pr_base(), wall, pr_hit(flch_tackle(), ""))[0].1
  @debug.assert_eq(tack.my_hps[0], 200)
  let chip = spiky_chip("", effective_hp(pr_hit(flch_tackle(), "")[0]))
  @debug.assert_eq(tack.opp_hps[0], 200 - chip)
  let feint = pr_move("フェイント", @model.Physical, 30, 2)
  let broke = pr_turn(pr_base(), wall, pr_hit(feint, ""))[0].1
  assert_true(broke.my_hps[0] < 200)
  @debug.assert_eq(broke.opp_hps[0], 200)
  let reach = pr_turn(pr_base(), wall, pr_hit(flch_tackle(), "えんかく"))[0].1
  @debug.assert_eq(reach.my_hps[0], 200)
  @debug.assert_eq(reach.opp_hps[0], 200)
  let guarded = pr_turn(pr_base(), wall, pr_hit(flch_tackle(), "マジックガード"))[0].1
  @debug.assert_eq(guarded.my_hps[0], 200)
  @debug.assert_eq(guarded.opp_hps[0], 200)
}

///|
test "baneful bunker poisons on contact and skips steel or immunity" {
  let wall = pr_wall(pr_protect("トーチカ"))
  let poisoned = pr_turn(pr_base(), wall, pr_hit(flch_tackle(), ""))[0].1
  @debug.assert_eq(poisoned.my_hps[0], 200)
  @debug.assert_eq(poisoned.opp_status[0], @model.Poison)
  let steel_mon = flch_cmb(
    flch_pokemon("steel", "はがね", 200, 120),
    [flch_tackle()],
    "",
  )
  let steel = pr_turn(pr_base(), wall, [steel_mon])[0].1
  @debug.assert_eq(steel.opp_status[0], @model.None)
  let immune = pr_turn(pr_base(), wall, pr_hit(flch_tackle(), "めんえき"))[0].1
  @debug.assert_eq(immune.opp_status[0], @model.None)
  @debug.assert_eq(immune.my_hps[0], 200)
}

///|
test "kings shield blocks attacks and lowers attack, but not a status move" {
  let wall = pr_wall(pr_protect("キングシールド"))
  let blocked = pr_turn(pr_base(), wall, pr_hit(flch_tackle(), ""))[0].1
  @debug.assert_eq(blocked.my_hps[0], 200)
  @debug.assert_eq(blocked.opp_ranks[0], -1)
  let clear = pr_turn(pr_base(), wall, pr_hit(flch_tackle(), "クリアボディ"))[0].1
  @debug.assert_eq(clear.my_hps[0], 200)
  @debug.assert_eq(clear.opp_ranks[0], 0)
  let glare = {
    ..pr_move("にらみつける", @model.Status, 0, 0),
    stat_effects: [{ stat: 0, delta: -1, target: 1 }],
  }
  let through = pr_turn(pr_base(), wall, pr_hit(glare, ""))[0].1
  @debug.assert_eq(through.my_ranks[0], -1)
  let full = pr_wall(pr_protect("まもる"))
  let stopped = pr_turn(pr_base(), full, pr_hit(glare, ""))[0].1
  @debug.assert_eq(stopped.my_ranks[0], 0)
}

///|
test "tearful look lands through protect" {
  let tear = {
    ..pr_move("なみだめ", @model.Status, 0, 0),
    stat_effects: [
      { stat: 0, delta: -1, target: 1 },
      { stat: 2, delta: -1, target: 1 },
    ],
  }
  let s = pr_turn(pr_base(), pr_wall(pr_protect("まもる")), pr_hit(tear, ""))[0].1
  @debug.assert_eq(s.my_ranks[0], -1)
  @debug.assert_eq(s.my_ranks[2], -1)
  @debug.assert_eq(s.my_stall, 1)
}

///|
test "unseen fist and drill deal a quarter and still take spiky chip" {
  let wall = pr_wall(pr_protect("ニードルガード"))
  let open = pr_turn(pr_base(), pr_wall(flch_tackle()), pr_hit(flch_tackle(), ""))[0].1
  let full_loss = 200 - open.my_hps[0]
  let fist = pr_turn(
    pr_base(), wall, pr_hit(flch_tackle(), "ふかしのこぶし"),
  )[0].1
  let drill = pr_turn(
    pr_base(), wall, pr_hit(flch_tackle(), "かんつうドリル"),
  )[0].1
  let quarter = @damage.round5(full_loss, 1024)
  @debug.assert_eq(200 - fist.my_hps[0], quarter)
  @debug.assert_eq(200 - drill.my_hps[0], quarter)
  let chip = spiky_chip("", effective_hp(pr_hit(flch_tackle(), "")[0]))
  @debug.assert_eq(fist.opp_hps[0], 200 - chip)
  assert_true(quarter > 0 && quarter < full_loss)
}

///|
test "ghost dive release breaks protect after the charge turn" {
  let dive = pr_move("ゴーストダイブ", @model.Physical, 90, 0)
  let wall = pr_hit(dive, "")
  let shield = pr_wall(pr_protect("まもる"))
  let s1 = pr_turn(pr_base(), wall, shield)[0].1
  @debug.assert_eq(s1.opp_hps[0], 200)
  @debug.assert_eq(s1.my_two_turn, 0)
  @debug.assert_eq(s1.opp_stall, 1)
  let outs = pr_turn(s1, wall, shield)
  let pierced = flch_mass(outs, fn(s) { s.opp_hps[0] < 200 && s.opp_stall == 2 })
  assert_true(flch_close(pierced, 1.0 / 3.0))
  let all_hit = flch_mass(outs, fn(s) { s.opp_hps[0] < 200 })
  assert_true(flch_close(all_hit, 1.0))
}

///|
test "crash and steel beam still hurt the user when protect blocks" {
  let wall = pr_wall(pr_protect("まもる"))
  let crash = pr_move("とびひざげり", @model.Physical, 130, 0)
  let beam = pr_move("てっていこうせん", @model.Special, 140, 0)
  let crashed = pr_turn(pr_base(), wall, pr_hit(crash, ""))[0].1
  @debug.assert_eq(crashed.my_hps[0], 200)
  assert_true(crashed.opp_hps[0] < 200)
  let beamed = pr_turn(pr_base(), wall, pr_hit(beam, ""))[0].1
  @debug.assert_eq(beamed.my_hps[0], 200)
  assert_true(beamed.opp_hps[0] < 200)
  let safe = pr_turn(pr_base(), wall, pr_hit(crash, "マジックガード"))[0].1
  @debug.assert_eq(safe.opp_hps[0], 200)
  @debug.assert_eq(safe.my_hps[0], 200)
}

///|
test "confusion and attract can stop protect before it goes up" {
  let wall = pr_wall(pr_protect("まもる"))
  let hit = pr_hit(flch_tackle(), "")
  let confused = { ..pr_base(), my_confusion: 3 }
  let outs = pr_turn(confused, wall, hit)
  let held = flch_mass(outs, fn(s) { s.my_hps[0] == 200 })
  assert_true(flch_close(held, 2.0 / 3.0))
  let user = {
    ..flch_cmb(flch_pokemon("wall", "ノーマル", 200, 60), [pr_protect("まもる")], ""),
    gender: Gender::Male,
  }
  let foe = {
    ..flch_cmb(flch_pokemon("hit", "ノーマル", 200, 120), [flch_tackle()], ""),
    gender: Gender::Female,
  }
  let attracted = { ..pr_base(), my_attract: 1 }
  let aouts = pr_turn(attracted, [user], [foe])
  let free = flch_mass(aouts, fn(s) { s.my_hps[0] == 200 })
  assert_true(flch_close(free, 0.5))
}

///|
test "bind does not stop protect, and a switch keeps only the stayer's stall" {
  let bound = { ..pr_base(), my_bind: 2 }
  let s = pr_turn(bound, pr_wall(pr_protect("まもる")), pr_hit(flch_tackle(), ""))[0].1
  @debug.assert_eq(s.my_stall, 1)
  @debug.assert_eq(stall_after_switch(4, Switch(1)), 0)
  @debug.assert_eq(stall_after_switch(4, UseMove(0)), 4)
  let opp = [
    flch_cmb(flch_pokemon("a", "ノーマル", 200, 120), [flch_tackle()], ""),
    flch_cmb(flch_pokemon("b", "ノーマル", 200, 80), [flch_tackle()], ""),
  ]
  let st = {
    ..pr_base(),
    my_stall: 1,
    opp_hps: [180, 180],
    opp_status: [@model.StatusCondition::None, @model.StatusCondition::None],
    opp_must_recharge: [false, false],
    opp_megaed: [false, false],
    opp_item_consumed: [false, false],
    opp_disguise_busted: [false, false],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
  }
  let switched = attempt_turn_with_cache(
    st, UseMove(0), Switch(1), pr_wall(pr_protect("まもる")), opp, new_damage_cache(),
  )[0].1
  @debug.assert_eq(switched.opp_active, 1)
  @debug.assert_eq(switched.my_stall, 2)
  @debug.assert_eq(switched.my_hps[0], 200)
}

///|
test "state cache key: stall and protect are distinct" {
  let base = pr_base()
  assert_distinct_state_keys(base, { ..base, my_stall: 1 })
  assert_distinct_state_keys(base, { ..base, opp_protect: PROTECT_SPIKY })
}

///|
test "mc protect blocks before the damage roll and quarters contact" {
  let wall = pr_wall(pr_protect("ニードルガード"))[0]
  let hit = pr_hit(flch_tackle(), "")[0]
  let rng = seeded_rng(3UL)
  let hps = [200]
  let status = [@model.StatusCondition::None]
  let (hp, _dmg, _bust, immune) = team_perform_attack(
    hit, wall, 200, flch_tackle(), rng, [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
    defender_guard=PROTECT_SPIKY,
    contact_hps=hps,
    contact_status=status,
    contact_slot=0,
  )
  assert_true(immune)
  @debug.assert_eq(hp, 200)
  let chip = spiky_chip("", effective_hp(hit))
  @debug.assert_eq(hps[0], 200 - chip)
  let fist = pr_hit(flch_tackle(), "ふかしのこぶし")[0]
  let open = team_perform_attack(
    fist, wall, 200, flch_tackle(), seeded_rng(9UL), [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
  )
  let quartered = team_perform_attack(
    fist, wall, 200, flch_tackle(), seeded_rng(9UL), [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
    defender_guard=PROTECT_FULL,
  )
  @debug.assert_eq(200 - quartered.0, @damage.round5(200 - open.0, 1024))
  let io = [0, 0]
  let _ = team_perform_attack(
    wall, hit, 200, pr_protect("まもる"), seeded_rng(1UL),
    [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], protect_io=io,
  )
  @debug.assert_eq(io[0], 1)
  @debug.assert_eq(io[1], PROTECT_FULL)
  let prot = pr_protect("まもる")
  let quick = pr_move("でんこうせっか", @model.Physical, 40, 1)
  let foe = pr_hit(flch_tackle(), "")[0]
  assert_true(!mc_psychic_priority_blocked(prot, @model.Field::Psychic, foe))
  assert_true(mc_psychic_priority_blocked(quick, @model.Field::Psychic, foe))
}

///|
test "protect parity: a first protect versus tackle matches DP and MC" {
  let frail = flch_pokemon("wall", "ノーマル", 20, 60)
  let wall = [flch_cmb(frail, [pr_protect("まもる")], "")]
  let open_wall = [flch_cmb(frail, [flch_tackle()], "")]
  let hit = pr_hit(flch_tackle(), "")
  let dp = switching_game_winrate(wall, hit, 1)
  let mc = team_monte_carlo_value(wall, hit, 8, 74007UL, turn_limit=1)
  assert_true((dp - mc).abs() < 0.001)
  let open = switching_game_winrate(open_wall, hit, 1)
  assert_true((dp - open).abs() > 0.2)
}
