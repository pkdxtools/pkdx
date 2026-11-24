///|
/// 壁 (リフレクター / ひかりのかべ / オーロラベール) の DP と MC。
/// 数値は champout `50e7233` の技説明。シングルは半減。

///|
fn scr_mon(
  name : String,
  spe : Int,
  moves : Array[@model.Move],
  ability? : String = "",
  item? : String = "",
) -> Combatant {
  {
    ..rg_combatant(mk_pokemon(name, "ノーマル", "", 200, 160, 100, 160, 100, spe)),
    moves,
    ability,
    item,
  }
}

///|
fn scr_pair(a : Combatant, b : Combatant) -> (Array[Combatant], Array[Combatant]) {
  ([a, a], [b, b])
}

///|
fn scr_hp_of(
  outs : Array[(Double, SwitchingGameState)],
  mine : Bool,
) -> Int {
  let (_, s) = outs[0]
  if mine {
    s.my_hps[s.my_active]
  } else {
    s.opp_hps[s.opp_active]
  }
}

///|
test "screen move sets five turns, light clay eight, aurora only in snow" {
  let reflect = mk_move("リフレクター", "エスパー", @model.Status, 0, accuracy=101)
  let light = mk_move("ひかりのかべ", "エスパー", @model.Status, 0, accuracy=101)
  let veil = mk_move("オーロラベール", "こおり", @model.Status, 0, accuracy=101)
  let user = scr_mon("User", 100, [reflect], item="ひかりのねんど")
  let st = flch_state(
    200, 200, @model.StatusCondition::None, @model.StatusCondition::None,
  )
  let (_, set_reflect) = screen_use_outcomes(st, true, 0, [user], reflect, false)[0]
  @debug.assert_eq(set_reflect.my_reflect, 8)
  let (_, no_clay) = screen_use_outcomes(st, true, 0, [user], reflect, true)[0]
  @debug.assert_eq(no_clay.my_reflect, 5)
  let bare = scr_mon("Bare", 100, [light])
  let (_, set_light) = screen_use_outcomes(st, false, 0, [bare], light, false)[0]
  @debug.assert_eq(set_light.opp_light, 5)
  let (_, dry) = screen_use_outcomes(st, true, 0, [bare], veil, false)[0]
  @debug.assert_eq(dry.my_aurora, 0)
  let snow = { ..st, weather: @model.Weather::Snow, weather_turns_left: 5 }
  let (_, iced) = screen_use_outcomes(snow, true, 0, [bare], veil, false)[0]
  @debug.assert_eq(iced.my_aurora, 5)
  @debug.assert_eq(screen_wall(0, 0, 0, @model.Physical, "", "たいあたり"), @model.Wall::NoWall)
  @debug.assert_eq(
    screen_wall(5, 0, 5, @model.Physical, "", "たいあたり"),
    @model.Wall::Reflect,
  )
  @debug.assert_eq(
    screen_wall(0, 0, 5, @model.Special, "", "はかいこうせん"),
    @model.Wall::AuroraVeil,
  )
  @debug.assert_eq(
    screen_wall(5, 5, 5, @model.Physical, "すりぬけ", "たいあたり"),
    @model.Wall::NoWall,
  )
  let kept = shatter_defender_state(set_reflect, true, reflect)
  @debug.assert_eq(kept.my_reflect, 8)
}

///|
test "reflect cuts physical damage and not special, then survives a switch" {
  let reflect = mk_move("リフレクター", "エスパー", @model.Status, 0, accuracy=101)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let beam = mk_move("はかいこうせん", "ノーマル", @model.Special, 80)
  let fast = scr_mon("Fast", 200, [reflect])
  let slow_phys = scr_mon("SlowP", 40, [tackle])
  let slow_spc = scr_mon("SlowS", 40, [beam])
  let splash_fast = scr_mon("Splash", 200, [splash])
  let cache = new_damage_cache()
  let st = rg_state([200, 200], [200, 200])
  let (my_r, opp_p) = scr_pair(fast, slow_phys)
  let screened = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my_r, opp_p, cache,
  )
  let (my_s, _) = scr_pair(splash_fast, slow_phys)
  let open = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my_s, opp_p, cache,
  )
  let hp_screen = scr_hp_of(screened, true)
  let hp_open = scr_hp_of(open, true)
  assert_true(hp_screen > hp_open)
  @debug.assert_eq(screened[0].1.my_reflect, 5)
  let (my_r2, opp_sp) = scr_pair(fast, slow_spc)
  let (my_s2, _) = scr_pair(splash_fast, slow_spc)
  let sp_screen = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my_r2, opp_sp, cache,
  )
  let sp_open = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my_s2, opp_sp, cache,
  )
  @debug.assert_eq(scr_hp_of(sp_screen, true), scr_hp_of(sp_open, true))
  let up = { ..st, my_reflect: 3, opp_light: 4 }
  let (bench, _) = scr_pair(splash_fast, slow_phys)
  let switched = transition_with_cache(
    up, ActionKind::Switch(1), ActionKind::Switch(1), bench, bench, cache,
  )
  @debug.assert_eq(switched[0].1.my_active, 1)
  @debug.assert_eq(switched[0].1.my_reflect, 3)
  @debug.assert_eq(switched[0].1.opp_light, 4)
  let ticked = apply_eot(switched[0].1, bench, bench)
  @debug.assert_eq(ticked.my_reflect, 2)
  @debug.assert_eq(ticked.opp_light, 3)
  let last = apply_eot({ ..st, my_aurora: 1 }, bench, bench)
  @debug.assert_eq(last.my_aurora, 0)
}

///|
test "light screen and aurora veil reduce the matching category" {
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let beam = mk_move("はかいこうせん", "ノーマル", @model.Special, 80)
  let fast = scr_mon("Fast", 200, [splash])
  let slow_p = scr_mon("SlowP", 40, [tackle])
  let slow_s = scr_mon("SlowS", 40, [beam])
  let cache = new_damage_cache()
  let open = rg_state([200, 200], [200, 200])
  let light = { ..open, my_light: 5 }
  let (me, opp_s) = scr_pair(fast, slow_s)
  let (me2, opp_p) = scr_pair(fast, slow_p)
  let sp_open = transition_with_cache(
    open, ActionKind::UseMove(0), ActionKind::UseMove(0), me, opp_s, cache,
  )
  let sp_wall = transition_with_cache(
    light, ActionKind::UseMove(0), ActionKind::UseMove(0), me, opp_s, cache,
  )
  assert_true(scr_hp_of(sp_wall, true) > scr_hp_of(sp_open, true))
  let ph_open = transition_with_cache(
    open, ActionKind::UseMove(0), ActionKind::UseMove(0), me2, opp_p, cache,
  )
  let ph_light = transition_with_cache(
    light, ActionKind::UseMove(0), ActionKind::UseMove(0), me2, opp_p, cache,
  )
  @debug.assert_eq(scr_hp_of(ph_light, true), scr_hp_of(ph_open, true))
  let snow = { ..open, weather: @model.Weather::Snow, weather_turns_left: 5, my_aurora: 5 }
  let aur_p = transition_with_cache(
    snow, ActionKind::UseMove(0), ActionKind::UseMove(0), me2, opp_p, cache,
  )
  let aur_s = transition_with_cache(
    snow, ActionKind::UseMove(0), ActionKind::UseMove(0), me, opp_s, cache,
  )
  let snow_open_p = transition_with_cache(
    { ..snow, my_aurora: 0 },
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    me2,
    opp_p,
    cache,
  )
  let snow_open_s = transition_with_cache(
    { ..snow, my_aurora: 0 },
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    me,
    opp_s,
    cache,
  )
  assert_true(scr_hp_of(aur_p, true) > scr_hp_of(snow_open_p, true))
  assert_true(scr_hp_of(aur_s, true) > scr_hp_of(snow_open_s, true))
}

///|
test "brick break removes the wall before damage; infiltrator ignores it" {
  let brick = mk_move("かわらわり", "かくとう", @model.Physical, 75)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 75)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let fangs = mk_move("サイコファング", "エスパー", @model.Physical, 85)
  let bull = mk_move("レイジングブル", "ノーマル", @model.Physical, 90)
  let defog = mk_move("きりばらい", "ひこう", @model.Status, 0)
  let me = scr_mon("Me", 200, [brick])
  let foe = scr_mon("Foe", 40, [splash])
  let cache = new_damage_cache()
  let walled = { ..rg_state([200, 200], [200, 200]), opp_reflect: 5, opp_light: 5, opp_aurora: 5 }
  let (mine, opp) = scr_pair(me, foe)
  let broken = transition_with_cache(
    walled, ActionKind::UseMove(0), ActionKind::UseMove(0), mine, opp, cache,
  )
  let open = transition_with_cache(
    rg_state([200, 200], [200, 200]),
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    mine,
    opp,
    cache,
  )
  @debug.assert_eq(scr_hp_of(broken, false), scr_hp_of(open, false))
  @debug.assert_eq(broken[0].1.opp_reflect, 0)
  @debug.assert_eq(broken[0].1.opp_light, 0)
  @debug.assert_eq(broken[0].1.opp_aurora, 0)
  let infiltrator = scr_mon("In", 200, [tackle], ability="すりぬけ")
  let plain = scr_mon("Plain", 200, [tackle])
  let (inf, _) = scr_pair(infiltrator, foe)
  let (pln, _) = scr_pair(plain, foe)
  let through = transition_with_cache(
    walled, ActionKind::UseMove(0), ActionKind::UseMove(0), inf, opp, cache,
  )
  let raw = transition_with_cache(
    rg_state([200, 200], [200, 200]),
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    pln,
    opp,
    cache,
  )
  @debug.assert_eq(scr_hp_of(through, false), scr_hp_of(raw, false))
  @debug.assert_eq(through[0].1.opp_reflect, 5)
  for name_mv in [fangs, bull, defog] {
    let user = scr_mon("Br", 200, [name_mv])
    let (side, _) = scr_pair(user, foe)
    let out = transition_with_cache(
      walled, ActionKind::UseMove(0), ActionKind::UseMove(0), side, opp, cache,
    )
    @debug.assert_eq(out[0].1.opp_reflect, 0)
    @debug.assert_eq(out[0].1.opp_aurora, 0)
  }
}

///|
test "a missed brick break still removes screens; a missed tackle does not" {
  let brick = mk_move("かわらわり", "かくとう", @model.Physical, 75, accuracy=50)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 75, accuracy=50)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let me_b = scr_mon("Br", 200, [brick])
  let me_t = scr_mon("Tk", 200, [tackle])
  let foe = scr_mon("Foe", 40, [splash])
  let st = { ..rg_state([200, 200], [200, 200]), opp_reflect: 5 }
  let cache = new_damage_cache()
  let (mb, opp) = scr_pair(me_b, foe)
  let (mt, _) = scr_pair(me_t, foe)
  // attempt_turn は命中を分岐し、ターン終了で壁を 1 減らす。外れでも割れていれば 0。
  let broke = attempt_turn_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), mb, opp, cache,
  )
  let kept = attempt_turn_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), mt, opp, cache,
  )
  assert_true(broke.length() > 1)
  assert_true(kept.length() > 1)
  for item in broke {
    let (_, s) = item
    @debug.assert_eq(s.opp_reflect, 0)
  }
  for item in kept {
    let (_, s) = item
    @debug.assert_eq(s.opp_reflect, 4)
  }
}

///|
test "protect blocks a screen, and mc applies the same wall" {
  let reflect = mk_move("リフレクター", "エスパー", @model.Status, 0, accuracy=101)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let user = scr_mon("User", 100, [reflect], item="ひかりのねんど")
  let foe = scr_mon("Foe", 100, [tackle])
  let st = flch_state(
    200, 200, @model.StatusCondition::None, @model.StatusCondition::None,
  )
  let guarded = { ..st, opp_protect: PROTECT_FULL }
  let ws = ws_from_state(guarded)
  let blocked = resolve_attacker_leg(
    ws, true, reflect, 0, false, false, false, [user], [foe], new_damage_cache(), None,
  )
  @debug.assert_eq(blocked[0].1.my_reflect, 0)
  let buf = [0, 0, 0, 0, 0, 0]
  let rng = seeded_rng(1UL)
  let ranks = [0, 0, 0, 0, 0]
  let _ = team_perform_attack(
    user, foe, 200, reflect, rng, ranks, ranks, screen_io=buf,
  )
  @debug.assert_eq(buf[0], 8)
  let snow_user = scr_mon("Veil", 100, [
    mk_move("オーロラベール", "こおり", @model.Status, 0, accuracy=101),
  ])
  let veil = snow_user.moves[0]
  let dry = [0, 0, 0, 0, 0, 0]
  let _ = team_perform_attack(
    snow_user,
    foe,
    200,
    veil,
    seeded_rng(1UL),
    ranks,
    ranks,
    weather=@model.Weather::Rain,
    screen_io=dry,
  )
  @debug.assert_eq(dry[2], 0)
  let iced = [0, 0, 0, 0, 0, 0]
  let _ = team_perform_attack(
    snow_user,
    foe,
    200,
    veil,
    seeded_rng(1UL),
    ranks,
    ranks,
    weather=@model.Weather::Snow,
    screen_io=iced,
  )
  @debug.assert_eq(iced[2], 5)
  let open_hp = team_perform_attack(
    foe,
    user,
    200,
    tackle,
    seeded_rng(7UL),
    ranks,
    ranks,
    attacker_is_own=false,
  ).0
  let walled_buf = [5, 0, 0, 0, 0, 0]
  let walled_hp = team_perform_attack(
    foe,
    user,
    200,
    tackle,
    seeded_rng(7UL),
    ranks,
    ranks,
    attacker_is_own=false,
    screen_io=walled_buf,
  ).0
  let bare_hp = team_perform_attack(
    foe,
    user,
    200,
    tackle,
    seeded_rng(7UL),
    ranks,
    ranks,
    attacker_is_own=false,
    screen_io=[0, 0, 0, 0, 0, 0],
  ).0
  @debug.assert_eq(open_hp, bare_hp)
  assert_true(walled_hp > open_hp)
  let expect_open = best_expected_damage(foe, user, ranks, ranks)
  let expect_wall = best_expected_damage(
    foe, user, ranks, ranks, def_reflect=5,
  )
  assert_true(expect_wall < expect_open)
}
