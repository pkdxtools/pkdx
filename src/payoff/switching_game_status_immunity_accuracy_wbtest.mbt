///|
/// 無効な変化技は命中分岐を作らず、効果なしにする。
/// 当たる変化技・吸収・ダメージ技の命中は変えない。

///|
fn sia_close(got : Double, want : Double) -> Unit raise {
  assert_true((got - want).abs() < 1.0e-9)
}

///|
fn sia_outs(
  mine : Combatant,
  opp : Combatant,
  state : SwitchingGameState,
) -> Array[(Double, SwitchingGameState)] {
  attempt_turn_with_cache(
    state, UseMove(0), UseMove(0), [mine], [opp], new_damage_cache(),
  )
}

///|
fn sia_wave(acc : Int) -> @model.Move {
  mk_move(
    "でんじは",
    "でんき",
    @model.Status,
    0,
    accuracy=acc,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
}

///|
fn sia_wow(acc : Int) -> @model.Move {
  mk_move(
    "おにび",
    "ほのお",
    @model.Status,
    0,
    accuracy=acc,
    status_effect=Some((@model.BurnKind, 100)),
  )
}

///|
fn sia_toxic(acc : Int) -> @model.Move {
  mk_move(
    "どくどく",
    "どく",
    @model.Status,
    0,
    accuracy=acc,
    status_effect=Some((@model.BadPoisonKind, 100)),
  )
}

///|
fn sia_powder(acc : Int) -> @model.Move {
  mk_move(
    "どくのこな",
    "どく",
    @model.Status,
    0,
    accuracy=acc,
    status_effect=Some((@model.PoisonKind, 100)),
  )
}

///|
fn sia_glare() -> @model.Move {
  mk_move(
    "にらみつける",
    "ノーマル",
    @model.Status,
    0,
    accuracy=90,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
}

///|
fn sia_growl() -> @model.Move {
  mk_move(
    "なきごえ",
    "ノーマル",
    @model.Status,
    0,
    accuracy=90,
    stat_effects=[@model.StatEffect::{ stat: 0, delta: -1, target: 1 }],
  )
}

///|
fn sia_splash() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
fn sia_side(
  name : String,
  type1 : String,
  ability : String,
  mv : @model.Move,
  spe : Int,
) -> Combatant {
  ma_mon(name, type1, ability, [mv], spe)
}

///|
fn sia_bad(s : SwitchingGameState) -> Bool {
  match s.opp_status[0] {
    @model.BadPoison(_) => true
    _ => false
  }
}

///|
test "でんじははしめんに麻痺を付けず、命中分岐も無い" {
  let mine = sia_side("Atk", "でんき", "", sia_wave(90), 120)
  let ground = sia_side("G", "じめん", "", sia_splash(), 80)
  let st = im_state()
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [mine], [ground]), 100)
  let outs = sia_outs(mine, ground, st)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
}

///|
test "でんじははノーマルには命中 90 で麻痺し、でんきには付かない" {
  let mine = sia_side("Atk", "でんき", "", sia_wave(90), 120)
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let st = im_state()
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [mine], [normal]), 90)
  let outs = sia_outs(mine, normal, st)
  sia_close(mm_mass(outs, fn(s) { s.opp_status[0] == @model.Paralyze }), 0.9)
  sia_close(mm_mass(outs, fn(s) { s.opp_status[0] == @model.None }), 0.1)
  let elec = sia_side("E", "でんき", "", sia_splash(), 80)
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [mine], [elec]), 100)
  let blocked = sia_outs(mine, elec, st)
  @debug.assert_eq(blocked.length(), 1)
  @debug.assert_eq(blocked[0].1.opp_status[0], @model.None)
}

///|
test "おにびはほのおに付かず、ノーマルには命中どおりやけどする" {
  let mine = sia_side("Atk", "ゴースト", "", sia_wow(85), 120)
  let fire = sia_side("F", "ほのお", "", sia_splash(), 80)
  let st = im_state()
  let outs = sia_outs(mine, fire, st)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let hit = sia_outs(mine, normal, st)
  sia_close(mm_mass(hit, fn(s) { s.opp_status[0] == @model.Burn }), 0.85)
  sia_close(mm_mass(hit, fn(s) { s.opp_status[0] == @model.None }), 0.15)
}

///|
test "どくどくとどくのこなははがねとどくに付かない" {
  let toxic = sia_side("T", "どく", "", sia_toxic(90), 120)
  let powder = sia_side("P", "くさ", "", sia_powder(75), 120)
  let steel = sia_side("S", "はがね", "", sia_splash(), 80)
  let poison = sia_side("Psn", "どく", "", sia_splash(), 80)
  let st = im_state()
  let ts = sia_outs(toxic, steel, st)
  let tp = sia_outs(toxic, poison, st)
  let ps = sia_outs(powder, steel, st)
  @debug.assert_eq(ts.length(), 1)
  @debug.assert_eq(tp.length(), 1)
  @debug.assert_eq(ps.length(), 1)
  @debug.assert_eq(ts[0].1.opp_status[0], @model.None)
  @debug.assert_eq(tp[0].1.opp_status[0], @model.None)
  @debug.assert_eq(ps[0].1.opp_status[0], @model.None)
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let hit = sia_outs(toxic, normal, st)
  sia_close(mm_mass(hit, sia_bad), 0.9)
  let p_hit = sia_outs(powder, normal, st)
  sia_close(mm_mass(p_hit, fn(s) { s.opp_status[0] == @model.Poison }), 0.75)
}

///|
test "にらみつけるはじめんを麻痺し、なきごえはゴーストの攻撃を下げる" {
  let glare = sia_side("G", "ノーマル", "", sia_glare(), 120)
  let ground = sia_side("Gd", "じめん", "", sia_splash(), 80)
  let st = im_state()
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [glare], [ground]), 90)
  let outs = sia_outs(glare, ground, st)
  sia_close(mm_mass(outs, fn(s) { s.opp_status[0] == @model.Paralyze }), 0.9)
  let growl = sia_side("Gr", "ノーマル", "", sia_growl(), 120)
  let ghost = sia_side("Gh", "ゴースト", "", sia_splash(), 80)
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [growl], [ghost]), 90)
  let drop = sia_outs(growl, ghost, st)
  sia_close(mm_mass(drop, fn(s) { s.opp_ranks[0] == -1 }), 0.9)
  sia_close(mm_mass(drop, fn(s) { s.opp_ranks[0] == 0 }), 0.1)
}

///|
test "いたずらごころの変化技はあくに効かず、自分強化とあく以外は効く" {
  let wow = sia_wow(85)
  let prank = sia_side("P", "ノーマル", "いたずらごころ", wow, 40)
  let dark = sia_side("D", "あく", "", sia_splash(), 200)
  let st = im_state()
  let outs = sia_outs(prank, dark, st)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
  let dance = mk_move(
    "つるぎのまい",
    "ノーマル",
    @model.Status,
    0,
    stat_effects=[@model.StatEffect::{ stat: 0, delta: 2, target: 0 }],
  )
  let dancer = sia_side("Sd", "ノーマル", "いたずらごころ", dance, 40)
  let boosted = sia_outs(dancer, dark, st)
  @debug.assert_eq(boosted.length(), 1)
  @debug.assert_eq(boosted[0].1.my_ranks[0], 2)
  let plain = sia_side("N", "ノーマル", "", wow, 120)
  let burned = sia_outs(plain, dark, st)
  sia_close(mm_mass(burned, fn(s) { s.opp_status[0] == @model.Burn }), 0.85)
}

///|
test "無効な変化技でもへんげんじざいはロックする" {
  let mine = sia_side("P", "ノーマル", "へんげんじざい", sia_wow(85), 120)
  let fire = sia_side("F", "ほのお", "", sia_splash(), 80)
  let outs = sia_outs(mine, fire, im_state())
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.my_protean_locked[0], "ほのお")
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
}

///|
test "へんげんじざいの受け手ででんじはの無効と有効が入れ替わる" {
  let mine = sia_side("Atk", "でんき", "", sia_wave(90), 120)
  let became_ground = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let ground_lock = { ..im_state(), opp_protean_locked: ["じめん", "", ""] }
  let fail = sia_outs(mine, became_ground, ground_lock)
  @debug.assert_eq(fail.length(), 1)
  @debug.assert_eq(fail[0].1.opp_status[0], @model.None)
  let left_electric = sia_side("E", "でんき", "", sia_splash(), 80)
  let normal_lock = { ..im_state(), opp_protean_locked: ["ノーマル", "", ""] }
  let wave100 = sia_side("Atk", "でんき", "", sia_wave(100), 120)
  let land = sia_outs(wave100, left_electric, normal_lock)
  @debug.assert_eq(land.length(), 1)
  @debug.assert_eq(land[0].1.opp_status[0], @model.Paralyze)
}

///|
test "じゅうなんはでんじはを外さず、リーフガードははれのときだけ" {
  let mine = sia_side("Atk", "でんき", "", sia_wave(90), 120)
  let limber = sia_side("L", "ノーマル", "じゅうなん", sia_splash(), 80)
  let st = im_state()
  let outs = sia_outs(mine, limber, st)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
  let leaf = sia_side("G", "ノーマル", "リーフガード", sia_splash(), 80)
  let no_sun = sia_outs(mine, leaf, st)
  sia_close(mm_mass(no_sun, fn(s) { s.opp_status[0] == @model.Paralyze }), 0.9)
  let sun = { ..im_state(), weather: @model.Weather::Sun, weather_turns_left: 5 }
  let shut = sia_outs(mine, leaf, sun)
  @debug.assert_eq(shut.length(), 1)
  @debug.assert_eq(shut[0].1.opp_status[0], @model.None)
}

///|
test "でんじはの無効はメガ後のタイプで決まり、ちくでんは吸収する" {
  let mine = sia_side("Atk", "でんき", "", sia_wave(90), 120)
  let to_ground = ma_mon(
    "Mega",
    "ノーマル",
    "",
    [sia_splash()],
    80,
    mega_type="じめん",
    has_mega=true,
  )
  let gained = ma_turn(mine, to_ground, UseMove(0), Mega(0), im_state())
  @debug.assert_eq(gained.length(), 1)
  @debug.assert_eq(gained[0].1.opp_status[0], @model.None)
  @debug.assert_eq(gained[0].1.opp_megaed[0], true)
  let from_ground = ma_mon(
    "Mega",
    "じめん",
    "",
    [sia_splash()],
    80,
    mega_type="ノーマル",
    has_mega=true,
  )
  let lost = ma_turn(mine, from_ground, UseMove(0), Mega(0), im_state())
  sia_close(mm_mass(lost, fn(s) { s.opp_status[0] == @model.Paralyze }), 0.9)
  let from_elec = ma_mon(
    "Mega",
    "でんき",
    "",
    [sia_splash()],
    80,
    mega_type="ノーマル",
    has_mega=true,
  )
  let sure = sia_side("Atk", "でんき", "", sia_wave(100), 120)
  let landed = ma_turn(sure, from_elec, UseMove(0), Mega(0), im_state())
  @debug.assert_eq(landed.length(), 1)
  @debug.assert_eq(landed[0].1.opp_status[0], @model.Paralyze)
  let volt = sia_side("V", "みず", "ちくでん", sia_splash(), 80)
  let absorbed = sia_outs(mine, volt, im_state())
  @debug.assert_eq(absorbed.length(), 1)
  @debug.assert_eq(absorbed[0].1.opp_status[0], @model.None)
  // state HP 100 + floor(実効最大HP / 4)。base 100 の Standard 実効HPは 204。
  @debug.assert_eq(absorbed[0].1.opp_hps[0], 151)
}

///|
test "いたずらごころでもそうしょくはあくへのねむりごなを吸収する" {
  let spore = mk_move(
    "ねむりごな",
    "くさ",
    @model.Status,
    0,
    accuracy=75,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let mine = sia_side("P", "ノーマル", "いたずらごころ", spore, 40)
  let dark = sia_side("D", "あく", "そうしょく", sia_splash(), 80)
  let outs = sia_outs(mine, dark, im_state())
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
  @debug.assert_eq(outs[0].1.opp_ranks[0], 1)
}

///|
test "でんじはの命中は交代先のタイプで決まる" {
  let mine = [sia_side("Atk", "でんき", "", sia_wave(90), 120)]
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 50)
  let ground = sia_side("G", "じめん", "", sia_splash(), 50)
  let st = im_state(my_hps=[100], opp_hps=[100, 100])
  let into_ground = attempt_turn_with_cache(
    st, UseMove(0), Switch(1), mine, [normal, ground], new_damage_cache(),
  )
  @debug.assert_eq(into_ground.length(), 1)
  @debug.assert_eq(into_ground[0].1.opp_active, 1)
  @debug.assert_eq(into_ground[0].1.opp_status[1], @model.None)
  let into_normal = attempt_turn_with_cache(
    st, UseMove(0), Switch(1), mine, [ground, normal], new_damage_cache(),
  )
  @debug.assert_eq(into_normal.length(), 2)
  sia_close(
    mm_mass(into_normal, fn(s) { s.opp_status[1] == @model.Paralyze }),
    0.9,
  )
  sia_close(mm_mass(into_normal, fn(s) { s.opp_active == 1 }), 1.0)
}

///|
test "相手が外したあとのでんじはもじめんには付かない" {
  let miss = mk_move("はねる", "ノーマル", @model.Status, 0, accuracy=0)
  let mine = sia_side("Slow", "でんき", "", sia_wave(90), 40)
  let ground = sia_side("Fast", "じめん", "", miss, 200)
  let outs = sia_outs(mine, ground, im_state())
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
}

///|
test "MC: 無効な変化技の命中は 100、当たる変化技は技の命中率" {
  let wave = sia_wave(90)
  let wow = sia_wow(85)
  let atk = sia_side("Atk", "ノーマル", "", wave, 100)
  let prank = sia_side("P", "ノーマル", "いたずらごころ", wow, 100)
  let none = @model.Weather::None
  let ground = sia_side("G", "じめん", "", sia_splash(), 80)
  let normal = sia_side("N", "ノーマル", "", sia_splash(), 80)
  let elec = sia_side("E", "でんき", "", sia_splash(), 80)
  let fire = sia_side("F", "ほのお", "", sia_splash(), 80)
  let steel = sia_side("S", "はがね", "", sia_splash(), 80)
  let dark = sia_side("D", "あく", "", sia_splash(), 80)
  let limber = sia_side("L", "ノーマル", "じゅうなん", sia_splash(), 80)
  let leaf = sia_side("Lg", "ノーマル", "リーフガード", sia_splash(), 80)
  @debug.assert_eq(mc_attempt_accuracy(atk, wave, ground, none), 100)
  @debug.assert_eq(mc_attempt_accuracy(atk, wave, normal, none), 90)
  @debug.assert_eq(mc_attempt_accuracy(atk, wave, elec, none), 100)
  @debug.assert_eq(
    mc_attempt_accuracy(atk, wave, normal, none, defender_protean="じめん"),
    100,
  )
  @debug.assert_eq(mc_attempt_accuracy(atk, wow, fire, none), 100)
  @debug.assert_eq(mc_attempt_accuracy(atk, wow, normal, none), 85)
  @debug.assert_eq(mc_attempt_accuracy(atk, sia_toxic(90), steel, none), 100)
  @debug.assert_eq(mc_attempt_accuracy(atk, sia_glare(), ground, none), 90)
  @debug.assert_eq(
    mc_attempt_accuracy(
      atk, sia_growl(), sia_side("Gh", "ゴースト", "", sia_splash(), 80), none,
    ),
    90,
  )
  @debug.assert_eq(mc_attempt_accuracy(prank, wow, dark, none), 100)
  @debug.assert_eq(mc_attempt_accuracy(atk, wow, dark, none), 85)
  @debug.assert_eq(mc_attempt_accuracy(atk, wave, limber, none), 100)
  @debug.assert_eq(mc_attempt_accuracy(atk, wave, leaf, none), 90)
  @debug.assert_eq(
    mc_attempt_accuracy(atk, wave, leaf, @model.Weather::Sun),
    100,
  )
  assert_true(
    mc_status_fail_before_hit(
      wave, None, atk, 100, ground, 100, @model.Field::None, none, "",
    ),
  )
  assert_true(
    !mc_status_fail_before_hit(
      sia_glare(), None, atk, 100, ground, 100, @model.Field::None, none, "",
    ),
  )
}
