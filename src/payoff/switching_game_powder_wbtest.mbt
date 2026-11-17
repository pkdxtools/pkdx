///|
/// 粉技はくさタイプと特性ぼうじんに効かない。命中分岐は作らず、効果もない。
/// そうしょくは先に吸収する。粉以外の変化技の命中は変えない。
/// 集合は champout `waza.json` classification 6。

///|
fn pwd_sleep(acc : Int) -> @model.Move {
  mk_move(
    "ねむりごな",
    "くさ",
    @model.Status,
    0,
    accuracy=acc,
    status_effect=Some((@model.SleepKind, 100)),
  )
}

///|
fn pwd_stun(acc : Int) -> @model.Move {
  mk_move(
    "しびれごな",
    "くさ",
    @model.Status,
    0,
    accuracy=acc,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
}

///|
fn pwd_cotton() -> @model.Move {
  mk_move(
    "わたほうし",
    "くさ",
    @model.Status,
    0,
    accuracy=100,
    stat_effects=[@model.StatEffect::{ stat: 4, delta: -2, target: 1 }],
  )
}

///|
fn pwd_named(name : String, acc : Int) -> @model.Move {
  mk_move(
    name,
    "むし",
    @model.Status,
    0,
    accuracy=acc,
    stat_effects=[@model.StatEffect::{ stat: 4, delta: -1, target: 1 }],
  )
}

///|
fn pwd_asleep(s : SwitchingGameState) -> Bool {
  match s.opp_status[0] {
    @model.Sleep(_) => true
    _ => false
  }
}

///|
fn pwd_paralyzed(s : SwitchingGameState) -> Bool {
  s.opp_status[0] == @model.Paralyze
}

///|
fn pwd_poisoned(s : SwitchingGameState) -> Bool {
  s.opp_status[0] == @model.Poison
}

///|
fn pwd_dual(type1 : String, type2 : String) -> Combatant {
  let c = sia_side("D", type1, "", sia_splash(), 80)
  let p = { ..c.pokemon, type2 }
  { ..c, pokemon: p }
}

///|
test "powder_move_blocked: くさとぼうじんだけ" {
  assert_true(powder_move_blocked("ねむりごな", "くさ", "", ""))
  assert_true(powder_move_blocked("しびれごな", "みず", "くさ", ""))
  assert_true(powder_move_blocked("どくのこな", "ノーマル", "", "ぼうじん"))
  assert_true(powder_move_blocked("キノコのほうし", "くさ", "どく", "ぼうじん"))
  assert_true(!powder_move_blocked("ねむりごな", "ノーマル", "", ""))
  assert_true(!powder_move_blocked("ねむりごな", "ほのお", "どく", ""))
  assert_true(!powder_move_blocked("どくどく", "くさ", "", ""))
  assert_true(!powder_move_blocked("おにび", "くさ", "", "ぼうじん"))
  assert_true(!powder_move_blocked("あくび", "くさ", "", ""))
  assert_true(!powder_move_blocked("わたげ", "くさ", "", "ぼうじん"))
  assert_true(!powder_move_blocked("", "くさ", "", "ぼうじん"))
}

///|
test "ねむりごなはくさに眠らず、ノーマルには命中 75" {
  let mine = sia_side("Atk", "ノーマル", "", pwd_sleep(75), 120)
  let grass = sia_side("G", "くさ", "", sia_splash(), 80)
  let dual = pwd_dual("みず", "くさ")
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let st = im_state()
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [mine], [grass]), 100)
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [mine], [normal]), 75)
  let blocked = sia_outs(mine, grass, st)
  @debug.assert_eq(blocked.length(), 1)
  @debug.assert_eq(blocked[0].1.opp_status[0], @model.None)
  let dual_outs = sia_outs(mine, dual, st)
  @debug.assert_eq(dual_outs.length(), 1)
  @debug.assert_eq(dual_outs[0].1.opp_status[0], @model.None)
  let hit = sia_outs(mine, normal, st)
  sia_close(mm_mass(hit, pwd_asleep), 0.75)
  sia_close(mm_mass(hit, fn(s) { s.opp_status[0] == @model.None }), 0.25)
}

///|
test "しびれごなはくさに麻痺せず、でんきには粉以外の理由で付かない" {
  let mine = sia_side("Atk", "くさ", "", pwd_stun(75), 120)
  let grass = sia_side("G", "くさ", "", sia_splash(), 80)
  let elec = sia_side("E", "でんき", "", sia_splash(), 80)
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let st = im_state()
  let blocked = sia_outs(mine, grass, st)
  @debug.assert_eq(blocked.length(), 1)
  @debug.assert_eq(blocked[0].1.opp_status[0], @model.None)
  let electric = sia_outs(mine, elec, st)
  @debug.assert_eq(electric.length(), 1)
  @debug.assert_eq(electric[0].1.opp_status[0], @model.None)
  let hit = sia_outs(mine, normal, st)
  sia_close(mm_mass(hit, pwd_paralyzed), 0.75)
  sia_close(mm_mass(hit, fn(s) { s.opp_status[0] == @model.None }), 0.25)
}

///|
test "どくのこなはくさに毒を付けず、どくどくはくさにも命中する" {
  let powder = sia_side("P", "くさ", "", sia_powder(75), 120)
  let grass = sia_side("G", "くさ", "", sia_splash(), 80)
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let st = im_state()
  let blocked = sia_outs(powder, grass, st)
  @debug.assert_eq(blocked.length(), 1)
  @debug.assert_eq(blocked[0].1.opp_status[0], @model.None)
  let hit = sia_outs(powder, normal, st)
  sia_close(mm_mass(hit, pwd_poisoned), 0.75)
  let toxic = sia_side("T", "どく", "", sia_toxic(90), 120)
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [toxic], [grass]), 90)
  let tox = sia_outs(toxic, grass, st)
  sia_close(mm_mass(tox, sia_bad), 0.9)
  sia_close(mm_mass(tox, fn(s) { s.opp_status[0] == @model.None }), 0.1)
}

///|
test "キノコのほうしはくさに眠らず、ノーマルは眠る" {
  let spore = mk_move(
    "キノコのほうし",
    "くさ",
    @model.Status,
    0,
    accuracy=100,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let mine = sia_side("Atk", "くさ", "", spore, 120)
  let st = im_state()
  let grass = sia_outs(mine, sia_side("G", "くさ", "", sia_splash(), 80), st)
  @debug.assert_eq(grass.length(), 1)
  @debug.assert_eq(grass[0].1.opp_status[0], @model.None)
  let normal = sia_outs(mine, sia_side("N", "ノーマル", "", sia_splash(), 80), st)
  @debug.assert_eq(normal.length(), 1)
  assert_true(pwd_asleep(normal[0].1))
}

///|
test "わたほうしはくさの素早さを下げない" {
  let mine = sia_side("Atk", "くさ", "", pwd_cotton(), 120)
  let st = im_state()
  let grass = sia_outs(mine, sia_side("G", "くさ", "", sia_splash(), 80), st)
  @debug.assert_eq(grass.length(), 1)
  @debug.assert_eq(grass[0].1.opp_ranks[4], 0)
  let normal = sia_outs(mine, sia_side("N", "ノーマル", "", sia_splash(), 80), st)
  @debug.assert_eq(normal.length(), 1)
  @debug.assert_eq(normal[0].1.opp_ranks[4], -2)
}

///|
test "いかりのこな・まほうのこな・ふんじんはくさだと命中分岐が無い" {
  let grass = sia_side("G", "くさ", "", sia_splash(), 80)
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let st = im_state()
  for name in ["いかりのこな", "まほうのこな", "ふんじん"] {
    let mine = sia_side("Atk", "むし", "", pwd_named(name, 90), 120)
    @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [mine], [grass]), 100)
    let blocked = sia_outs(mine, grass, st)
    @debug.assert_eq(blocked.length(), 1)
    @debug.assert_eq(blocked[0].1.opp_ranks[4], 0)
    @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [mine], [normal]), 90)
    let hit = sia_outs(mine, normal, st)
    sia_close(mm_mass(hit, fn(s) { s.opp_ranks[4] == -1 }), 0.9)
    sia_close(mm_mass(hit, fn(s) { s.opp_ranks[4] == 0 }), 0.1)
  }
}

///|
test "ぼうじんは粉だけを止め、どくどくとおにびは命中する" {
  let coat = sia_side("C", "ノーマル", "ぼうじん", sia_splash(), 80)
  let st = im_state()
  let sleep = sia_side("A", "くさ", "", pwd_sleep(75), 120)
  let outs = sia_outs(sleep, coat, st)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
  let toxic = sia_side("T", "どく", "", sia_toxic(90), 120)
  let tox = sia_outs(toxic, coat, st)
  sia_close(mm_mass(tox, sia_bad), 0.9)
  let wow = sia_side("W", "ほのお", "", sia_wow(85), 120)
  let burned = sia_outs(wow, coat, st)
  sia_close(mm_mass(burned, fn(s) { s.opp_status[0] == @model.Burn }), 0.85)
}

///|
test "そうしょくのくさはねむりごなを吸収し、どくのこなは吸収せず粉で失敗する" {
  let sap = sia_side("S", "くさ", "そうしょく", sia_splash(), 80)
  let st = im_state()
  let sleep = sia_side("A", "ノーマル", "", pwd_sleep(75), 120)
  let absorbed = sia_outs(sleep, sap, st)
  @debug.assert_eq(absorbed.length(), 1)
  @debug.assert_eq(absorbed[0].1.opp_status[0], @model.None)
  @debug.assert_eq(absorbed[0].1.opp_ranks[0], 1)
  // champout では どくのこな のタイプはどく。そうしょくは吸わない。
  let powder = sia_side("P", "どく", "", sia_powder(75), 120)
  let blocked = sia_outs(powder, sap, st)
  @debug.assert_eq(blocked.length(), 1)
  @debug.assert_eq(blocked[0].1.opp_status[0], @model.None)
  @debug.assert_eq(blocked[0].1.opp_ranks[0], 0)
}

///|
test "へんげんじざいの受け手でねむりごなのくさ無効が入れ替わる" {
  let mine = sia_side("Atk", "ノーマル", "", pwd_sleep(75), 120)
  let became = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let grass_lock = { ..im_state(), opp_protean_locked: ["くさ", "", ""] }
  let fail = sia_outs(mine, became, grass_lock)
  @debug.assert_eq(fail.length(), 1)
  @debug.assert_eq(fail[0].1.opp_status[0], @model.None)
  let left = sia_side("G", "くさ", "", sia_splash(), 80)
  let fire_lock = { ..im_state(), opp_protean_locked: ["ほのお", "", ""] }
  let sure = sia_side("Atk", "ノーマル", "", pwd_sleep(100), 120)
  let land = sia_outs(sure, left, fire_lock)
  @debug.assert_eq(land.length(), 1)
  assert_true(pwd_asleep(land[0].1))
}

///|
test "粉がくさに効かなくてもへんげんじざいはロックする" {
  let mine = sia_side("P", "ノーマル", "へんげんじざい", pwd_sleep(75), 120)
  let grass = sia_side("G", "くさ", "", sia_splash(), 80)
  let outs = sia_outs(mine, grass, im_state())
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.my_protean_locked[0], "くさ")
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
}

///|
test "ねむりごなの無効はメガ後のタイプと特性で決まる" {
  let mine = sia_side("Atk", "ノーマル", "", pwd_sleep(75), 120)
  let to_grass = ma_mon(
    "Mega",
    "ノーマル",
    "",
    [sia_splash()],
    80,
    mega_type="くさ",
    has_mega=true,
  )
  let gained = ma_turn(mine, to_grass, UseMove(0), Mega(0), im_state())
  @debug.assert_eq(gained.length(), 1)
  @debug.assert_eq(gained[0].1.opp_status[0], @model.None)
  @debug.assert_eq(gained[0].1.opp_megaed[0], true)
  let from_grass = ma_mon(
    "Mega",
    "くさ",
    "",
    [sia_splash()],
    80,
    mega_type="ノーマル",
    has_mega=true,
  )
  let lost = ma_turn(mine, from_grass, UseMove(0), Mega(0), im_state())
  sia_close(mm_mass(lost, pwd_asleep), 0.75)
  let to_coat = ma_mon(
    "Mega",
    "ノーマル",
    "",
    [sia_splash()],
    80,
    mega_ability="ぼうじん",
    mega_type="ほのお",
    has_mega=true,
  )
  let coat = ma_turn(mine, to_coat, UseMove(0), Mega(0), im_state())
  @debug.assert_eq(coat.length(), 1)
  @debug.assert_eq(coat[0].1.opp_status[0], @model.None)
  let drop_coat = ma_mon(
    "Mega",
    "ノーマル",
    "ぼうじん",
    [sia_splash()],
    80,
    mega_ability="",
    mega_type="ほのお",
    has_mega=true,
  )
  let opened = ma_turn(mine, drop_coat, UseMove(0), Mega(0), im_state())
  sia_close(mm_mass(opened, pwd_asleep), 0.75)
}

///|
test "ねむりごなの命中は交代先のタイプで決まる" {
  let mine = [sia_side("Atk", "ノーマル", "", pwd_sleep(75), 120)]
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 50)
  let grass = sia_side("G", "くさ", "", sia_splash(), 50)
  let st = im_state(my_hps=[100], opp_hps=[100, 100])
  let into_grass = attempt_turn_with_cache(
    st,
    UseMove(0),
    Switch(1),
    mine,
    [normal, grass],
    new_damage_cache(),
  )
  @debug.assert_eq(into_grass.length(), 1)
  @debug.assert_eq(into_grass[0].1.opp_active, 1)
  @debug.assert_eq(into_grass[0].1.opp_status[1], @model.None)
  let into_normal = attempt_turn_with_cache(
    st,
    UseMove(0),
    Switch(1),
    mine,
    [grass, normal],
    new_damage_cache(),
  )
  @debug.assert_eq(into_normal.length(), 2)
  sia_close(
    mm_mass(into_normal, fn(s) {
      match s.opp_status[1] {
        @model.Sleep(_) => true
        _ => false
      }
    }),
    0.75,
  )
  sia_close(mm_mass(into_normal, fn(s) { s.opp_active == 1 }), 1.0)
}

///|
test "あくびとおにびはくさでも命中する" {
  let yawn = mk_move(
    "あくび",
    "ノーマル",
    @model.Status,
    0,
    accuracy=100,
    status_effect=Some((@model.DrowsyKind, 100)),
  )
  let grass = sia_side("G", "くさ", "", sia_splash(), 80)
  let st = im_state()
  let yawner = sia_side("Y", "ノーマル", "", yawn, 120)
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [yawner], [grass]), 100)
  let outs = sia_outs(yawner, grass, st)
  @debug.assert_eq(outs.length(), 1)
  match outs[0].1.opp_status[0] {
    @model.Drowsy(_) => ()
    _ => assert_true(false)
  }
  let wow = sia_side("W", "ほのお", "", sia_wow(85), 120)
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [wow], [grass]), 85)
  let burned = sia_outs(wow, grass, st)
  sia_close(mm_mass(burned, fn(s) { s.opp_status[0] == @model.Burn }), 0.85)
  let screech = pwd_named("いやなおと", 90)
  let drop = sia_side("S", "ノーマル", "", screech, 120)
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [drop], [grass]), 90)
  let ranks = sia_outs(drop, grass, st)
  sia_close(mm_mass(ranks, fn(s) { s.opp_ranks[4] == -1 }), 0.9)
}

///|
test "MC: 粉技の命中はくさとぼうじんで 100、それ以外は技の命中率" {
  let sleep = pwd_sleep(75)
  let atk = sia_side("Atk", "ノーマル", "", sleep, 100)
  let none = @model.Weather::None
  let grass = sia_side("G", "くさ", "", sia_splash(), 80)
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let coat = sia_side("C", "ほのお", "ぼうじん", sia_splash(), 80)
  let dual = pwd_dual("ほのお", "くさ")
  @debug.assert_eq(mc_attempt_accuracy(atk, sleep, grass, none), 100)
  @debug.assert_eq(mc_attempt_accuracy(atk, sleep, normal, none), 75)
  @debug.assert_eq(mc_attempt_accuracy(atk, sleep, coat, none), 100)
  @debug.assert_eq(mc_attempt_accuracy(atk, sleep, dual, none), 100)
  @debug.assert_eq(
    mc_attempt_accuracy(atk, sleep, normal, none, defender_protean="くさ"),
    100,
  )
  @debug.assert_eq(
    mc_attempt_accuracy(atk, sleep, grass, none, defender_protean="ほのお"),
    75,
  )
  @debug.assert_eq(mc_attempt_accuracy(atk, sia_toxic(90), grass, none), 90)
  // ぼうじんの受け手がほのおだと、おにびは粉ではなくやけど無効で 100 になる。
  let coat_n = sia_side("Cn", "ノーマル", "ぼうじん", sia_splash(), 80)
  @debug.assert_eq(mc_attempt_accuracy(atk, sia_wow(85), coat_n, none), 85)
  assert_true(
    mc_status_fail_before_hit(
      sleep, None, atk, 100, grass, 100, @model.Field::None, none, "",
    ),
  )
  assert_true(
    mc_status_fail_before_hit(
      sleep, None, atk, 100, coat, 100, @model.Field::None, none, "",
    ),
  )
  assert_true(
    !mc_status_fail_before_hit(
      sleep, None, atk, 100, normal, 100, @model.Field::None, none, "",
    ),
  )
  assert_true(
    !mc_status_fail_before_hit(
      sia_toxic(90), None, atk, 100, grass, 100, @model.Field::None, none, "",
    ),
  )
  assert_true(
    mc_status_fail_before_hit(
      sleep,
      None,
      atk,
      100,
      normal,
      100,
      @model.Field::None,
      none,
      "くさ",
    ),
  )
}
