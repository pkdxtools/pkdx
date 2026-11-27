///|
fn ds_four(
  a : Combatant,
  b : Combatant,
  c : Combatant,
  d : Combatant,
) -> Array[Combatant] {
  [a, b, c, d]
}

///|
fn ds_gap(a : Double, b : Double) -> Double {
  (a - b).abs()
}

///|
fn ds_actor(
  is_me : Bool,
  squad : Int,
  slot : @doubles.DoubleSlot,
  move_idx : Int,
  code : Int,
  chosen : @doubles.DoubleSlot?,
  priority : Int,
  speed : Int,
) -> DoubleActor {
  {
    is_me,
    squad,
    slot,
    move_idx,
    target_code: code,
    chosen,
    priority,
    speed,
  }
}

///|
test "fast guard blocks priority plus one and not a normal tackle" {
  let fast_mv = mk_move("ファストガード", "かくとう", @model.Status, 0, priority=3)
  let quick = mk_move("たいあたり", "ノーマル", @model.Physical, 80, priority=1)
  let plain = mk_move("たいあたり", "ノーマル", @model.Physical, 80, priority=0)
  let me = dt_mon("Me", "かくとう", 190, 40, 90, 40, 90, 20, fast_mv)
  let quick_foe = dt_mon("Quick", "ノーマル", 180, 160, 80, 40, 80, 40, quick)
  let plain_foe = dt_mon("Plain", "ノーマル", 180, 160, 80, 40, 80, 40, plain)
  let my = dg_side(me)
  let my_t = dg_targets([12])
  let (_, blocked, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    dg_side(quick_foe),
    my_t,
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let (_, hit, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    dg_side(plain_foe),
    my_t,
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let dmg = double_move_mean(plain_foe, me, plain)
  assert_true(dmg > 0 && dmg < 190)
  assert_true(blocked[0] == 190)
  assert_true(hit[0] == 190 - dmg)
}

///|
test "fast guard uses effective priority, including gale wings and prankster" {
  let fast_mv = mk_move("ファストガード", "かくとう", @model.Status, 0, priority=3)
  let air = mk_move("エアスラッシュ", "ひこう", @model.Special, 75, priority=0)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 80, priority=0)
  let wave = mk_move("でんじは", "でんき", @model.Status, 0, priority=0)
  let me = dt_mon("Me", "かくとう", 190, 40, 100, 40, 100, 20, fast_mv)
  let winged = de_mon(
    "Wing",
    "ひこう",
    170,
    40,
    70,
    150,
    70,
    30,
    air,
    ability="はやてのつばさ",
  )
  let plain = de_mon("Plain", "ひこう", 170, 40, 70, 150, 70, 30, air)
  let prank = de_mon(
    "Prank",
    "ノーマル",
    170,
    160,
    70,
    40,
    70,
    30,
    tackle,
    ability="いたずらごころ",
  )
  let my = dg_side(me)
  let my_t = dg_targets([12])
  let opp_t = dg_targets([0])
  let (_, from_wing, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    dg_side(winged),
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let (_, from_plain, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    dg_side(plain),
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let (_, from_prank, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    dg_side(prank),
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let air_dmg = double_move_mean(plain, me, air)
  let tackle_dmg = double_move_mean(prank, me, tackle)
  assert_true(air_dmg > 0 && tackle_dmg > 0)
  assert_true(double_actor_priority(winged, air) == 1)
  assert_true(double_actor_priority(plain, air) == 0)
  assert_true(double_actor_priority(prank, wave) == 1)
  assert_true(double_actor_priority(prank, tackle) == 0)
  assert_true(from_wing[0] == 190)
  assert_true(from_plain[0] == 190 - air_dmg)
  assert_true(from_prank[0] == 190 - tackle_dmg)
}

///|
test "fast guard ignores protect stall and feint removes it" {
  let fast_mv = mk_move("ファストガード", "かくとう", @model.Status, 0, priority=3)
  let quick = mk_move("たいあたり", "ノーマル", @model.Physical, 70, priority=1)
  let feint = mk_move("フェイント", "ノーマル", @model.Physical, 30, priority=2)
  let me = dt_mon("Me", "かくとう", 220, 40, 80, 40, 80, 10, fast_mv)
  let foe = dt_mon("Foe", "ノーマル", 180, 140, 80, 40, 80, 20, quick)
  let my = dg_side(me)
  let my_t = dg_targets([12])
  let opp_t = dg_targets([0])
  let (fresh_v, _, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    dg_side(foe),
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let (stale_v, _, _) = scripted_value_and_hp_stall(
    new_double_eval(),
    my,
    dg_side(foe),
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [6, 0, 0, 0],
  )
  let (_, field) = scripted_turn_field(
    new_double_eval(),
    my,
    dg_side(foe),
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [1, 0, 0, 0],
  )
  assert_true(ds_gap(fresh_v, stale_v) == 0.0)
  assert_true(field.my_hp[0] == 220)
  assert_true(field.stall[0] == 0)
  assert_true(field.fast[0] == 0)
  let breaker = dt_mon("Feint", "ノーマル", 160, 130, 70, 40, 70, 90, feint)
  let partner = dt_mon("Quick", "ノーマル", 160, 150, 70, 40, 70, 40, quick)
  let dead = dg_dead()
  let (_, broken, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    ds_four(breaker, partner, dead, dead),
    my_t,
    [[0], [0], [7], [7]],
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
  )
  let feint_dmg = double_move_mean(breaker, me, feint)
  let quick_dmg = double_move_mean(partner, me, quick)
  assert_true(feint_dmg > 0 && quick_dmg > 0)
  assert_true(feint_dmg + quick_dmg < 220)
  assert_true(broken[0] == 220 - feint_dmg - quick_dmg)
}

///|
test "unseen fist deals one quarter through fast guard" {
  let fast_mv = mk_move("ファストガード", "かくとう", @model.Status, 0, priority=3)
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80, priority=1)
  let me = dt_mon("Me", "かくとう", 200, 40, 90, 40, 90, 10, fast_mv)
  let fist = de_mon(
    "Fist",
    "かくとう",
    180,
    170,
    80,
    40,
    80,
    30,
    hit,
    ability="ふかしのこぶし",
  )
  let (_, hp, _) = scripted_value_and_hp(
    new_double_eval(),
    dg_side(me),
    dg_side(fist),
    dg_targets([12]),
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let full = double_move_mean(fist, me, hit)
  let quarter = @damage.round5(full, 1024)
  assert_true(full > quarter && quarter > 0)
  assert_true(hp[0] == 200 - quarter)
}

///|
test "endure leaves 1 hp after a chip and shares protect stall" {
  let endure = mk_move("こらえる", "ノーマル", @model.Status, 0, priority=4)
  let chip_mv = mk_move("たいあたり", "ノーマル", @model.Physical, 40, priority=1)
  let mid = mk_move("たいあたり", "ノーマル", @model.Physical, 80, priority=0)
  let ko_mv = mk_move("たいあたり", "ノーマル", @model.Physical, 200, priority=0)
  let me = dt_mon("Me", "みず", 100, 40, 50, 40, 50, 15, endure)
  let chipper = dt_mon("Chip", "かくとう", 180, 100, 80, 40, 80, 80, chip_mv)
  let finisher = dt_mon("Mid", "かくとう", 180, 100, 80, 40, 80, 40, mid)
  let smasher = dt_mon("Smash", "かくとう", 180, 250, 80, 40, 80, 40, ko_mv)
  let dead = dg_dead()
  let my = dg_side(me)
  let my_t = dg_targets([7])
  let chip = double_move_mean(chipper, me, chip_mv)
  let blow = double_move_mean(finisher, me, mid)
  let ko_dmg = double_move_mean(smasher, me, ko_mv)
  assert_true(chip > 0 && chip < 100)
  assert_true(blow < 100 && chip + blow >= 100)
  assert_true(ko_dmg >= 100)
  let (_, hp, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    ds_four(chipper, finisher, dead, dead),
    my_t,
    [[0], [0], [7], [7]],
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
  )
  assert_true(hp[0] == 1)
  let (_, only_chip, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    dg_side(chipper),
    my_t,
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(only_chip[0] == 100 - chip)
  let smash_side = dg_side(smasher)
  let (_, held) = scripted_turn_field(
    new_double_eval(),
    my,
    smash_side,
    my_t,
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [],
  )
  assert_true(held.my_hp[0] == 1)
  assert_true(held.stall[0] == 1)
  let ko_state = fresh_field(my, smash_side)
  set_hp(ko_state, @doubles.MyLeft, 0)
  let ko = double_terminal(ko_state, my, smash_side)
  let (mixed, _, _) = scripted_value_and_hp_stall(
    new_double_eval(),
    my,
    smash_side,
    my_t,
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [1, 0, 0, 0],
  )
  let lived = fresh_field(my, smash_side)
  set_hp(lived, @doubles.MyLeft, 1)
  let live_v = double_terminal(lived, my, smash_side)
  let expect = (1.0 / 3.0) * live_v + (2.0 / 3.0) * ko
  assert_true(ds_gap(mixed, expect) < 1.0e-9)
}

///|
test "ally switch sends a chosen target into the pokemon now there" {
  let swap_mv = mk_move("サイドチェンジ", "エスパー", @model.Status, 0, priority=2)
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80, priority=0)
  let frail = dt_mon("Frail", "ノーマル", 90, 40, 40, 40, 40, 30, swap_mv)
  let bulky = dt_mon("Bulky", "ノーマル", 220, 40, 180, 40, 180, 20, hit)
  let foe = dt_mon("Foe", "ノーマル", 180, 170, 80, 40, 80, 10, hit)
  let dead = dg_dead()
  let my = ds_four(frail, bulky, dead, dead)
  let opp = dg_side(foe)
  let my_t = [[7], [0], [7], [7]]
  let opp_t = dg_targets([0])
  let frail_dmg = double_move_mean(foe, frail, hit)
  let bulky_dmg = double_move_mean(foe, bulky, hit)
  assert_true(frail_dmg >= 90)
  assert_true(bulky_dmg > 0 && bulky_dmg < 220)
  let (_, field) = scripted_turn_field(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [],
  )
  assert_true(field.pos[0] == 1 && field.pos[1] == 0)
  assert_true(field.my_hp[0] == 90)
  assert_true(field.my_hp[1] == 220 - bulky_dmg)
  assert_true(field.sw_stall[1] == 1)
  assert_true(field.sw_stall[0] == 0)
  assert_true(field.stall[0] == 0 && field.stall[1] == 0)
  let (stale_v, _, _) = scripted_value_and_hp_stall(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [6, 0, 0, 0],
  )
  let (fresh_v, _, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(ds_gap(stale_v, fresh_v) == 0.0)
  let swapped_v = double_terminal(field, my, opp)
  let (_, failed) = scripted_turn_field(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [],
    opening_switch=[1, 0, 0, 0],
  )
  assert_true(failed.pos[0] == 0)
  assert_true(failed.my_hp[0] == 0)
  assert_true(failed.sw_stall[0] == 0)
  let fail_v = double_terminal(failed, my, opp)
  let (mixed, _, _) = scripted_value_and_hp_stall(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [],
    opening_switch=[1, 0, 0, 0],
  )
  let expect = (1.0 / 3.0) * swapped_v + (2.0 / 3.0) * fail_v
  assert_true(ds_gap(mixed, expect) < 1.0e-9)
}

///|
test "ally switch with no living ally does not move and still arms the counter" {
  let swap_mv = mk_move("サイドチェンジ", "エスパー", @model.Status, 0, priority=2)
  let me = dt_mon("Me", "エスパー", 160, 40, 80, 40, 80, 40, swap_mv)
  let (_, field) = scripted_turn_field(
    new_double_eval(),
    dg_side(me),
    dg_side(dt_status("Opp", 10, 160)),
    dg_targets([7]),
    dg_targets([7]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.Use(0)),
    None,
    [],
  )
  assert_true(field.pos[0] == 0 && field.pos[1] == 1)
  assert_true(field.sw_stall[0] == 1)
  assert_true(field.my_hp[0] == 160)
}

///|
test "follow me follows the body and a faster fake out hits before the swap" {
  let follow = mk_move("このゆびとまれ", "ノーマル", @model.Status, 0, priority=2)
  let swap_mv = mk_move("サイドチェンジ", "エスパー", @model.Status, 0, priority=2)
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 70, priority=0)
  let fake = mk_move("ねこだまし", "ノーマル", @model.Physical, 40, priority=3)
  let frail = dt_mon("Frail", "ノーマル", 160, 40, 50, 40, 50, 200, follow)
  let bulky = dt_mon("Bulky", "ノーマル", 220, 40, 160, 40, 160, 40, swap_mv)
  let foe = dt_mon("Foe", "ノーマル", 180, 150, 80, 40, 80, 10, hit)
  let dead = dg_dead()
  let my = ds_four(frail, bulky, dead, dead)
  let opp = dg_side(foe)
  let my_t = [[7], [7], [7], [7]]
  let opp_t = dg_targets([0])
  let on_frail = double_move_mean(foe, frail, hit)
  let on_bulky = double_move_mean(foe, bulky, hit)
  assert_true(on_frail > 0 && on_frail < 160)
  assert_true(on_bulky > 0 && on_bulky != on_frail)
  let (_, drew) = scripted_turn_field(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [],
  )
  assert_true(drew.pos[0] == 1 && drew.pos[1] == 0)
  assert_true(drew.my_hp[0] == 160 - on_frail)
  assert_true(drew.my_hp[1] == 220)
  let splash = de_splash()
  let still = dt_mon("Still", "ノーマル", 160, 40, 50, 40, 50, 80, splash)
  let (_, plain) = scripted_turn_field(
    new_double_eval(),
    ds_four(still, bulky, dead, dead),
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [],
  )
  let bulky_from_still = double_move_mean(foe, bulky, hit)
  assert_true(plain.my_hp[0] == 160)
  assert_true(plain.my_hp[1] == 220 - bulky_from_still)
  let faker = dt_mon("Fake", "ノーマル", 180, 140, 80, 40, 80, 10, fake)
  let fake_dmg = double_move_mean(faker, frail, fake)
  assert_true(fake_dmg > 0 && fake_dmg < 160)
  let (_, early) = scripted_turn_field(
    new_double_eval(),
    my,
    dg_side(faker),
    my_t,
    dg_targets([0]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [],
  )
  assert_true(early.pos[0] == 1)
  assert_true(early.my_hp[0] == 160 - fake_dmg)
  assert_true(early.my_hp[1] == 220)
}

///|
test "rollout resolves fast guard and ally switch on the sampled path" {
  let fast_mv = mk_move("ファストガード", "かくとう", @model.Status, 0, priority=3)
  let quick = mk_move("たいあたり", "ノーマル", @model.Physical, 80, priority=1)
  let swap_mv = mk_move("サイドチェンジ", "エスパー", @model.Status, 0, priority=2)
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80, priority=0)
  let me = dt_mon("Me", "かくとう", 180, 40, 90, 40, 90, 20, fast_mv)
  let foe = dt_mon("Foe", "ノーマル", 160, 150, 80, 40, 80, 40, quick)
  let cache = new_double_eval()
  let rng = seeded_rng(3)
  let blocked = fresh_field(dg_side(me), dg_side(foe))
  resolve_actor_sampled(
    cache,
    blocked,
    ds_actor(true, 0, @doubles.MyLeft, 0, 12, None, 3, 10),
    rng,
    dg_side(me),
    dg_side(foe),
  )
  resolve_actor_sampled(
    cache,
    blocked,
    ds_actor(
      false,
      0,
      @doubles.FoeLeft,
      0,
      0,
      Some(@doubles.MyLeft),
      1,
      40,
    ),
    rng,
    dg_side(me),
    dg_side(foe),
  )
  assert_true(blocked.my_hp[0] == 180)
  let frail = dt_mon("Frail", "ノーマル", 80, 40, 40, 40, 40, 30, swap_mv)
  let bulky = dt_mon("Bulky", "ノーマル", 200, 40, 160, 40, 160, 20, hit)
  let striker = dt_mon("Hit", "ノーマル", 180, 160, 80, 40, 80, 10, hit)
  let dead = dg_dead()
  let my = ds_four(frail, bulky, dead, dead)
  let opp = dg_side(striker)
  let swapped = fresh_field(my, opp)
  resolve_actor_sampled(
    cache,
    swapped,
    ds_actor(true, 0, @doubles.MyLeft, 0, 7, None, 2, 30),
    rng,
    my,
    opp,
  )
  resolve_actor_sampled(
    cache,
    swapped,
    ds_actor(
      false,
      0,
      @doubles.FoeLeft,
      0,
      0,
      Some(@doubles.MyLeft),
      0,
      10,
    ),
    rng,
    my,
    opp,
  )
  let bulky_dmg = double_move_mean(striker, bulky, hit)
  assert_true(bulky_dmg > 0 && bulky_dmg < 200)
  assert_true(swapped.pos[0] == 1 && swapped.pos[1] == 0)
  assert_true(swapped.my_hp[0] == 80)
  assert_true(swapped.my_hp[1] == 200 - bulky_dmg)
  let scripted = {
    let (v, _, _) = scripted_value_and_hp(
      cache,
      my,
      opp,
      [[7], [0], [7], [7]],
      dg_targets([0]),
      Some(@doubles.Use(0)),
      None,
      Some(@doubles.UseOn(0, @doubles.MyLeft)),
      None,
    )
    v
  }
  let rolled = double_scripted_rollout(
    cache,
    my,
    opp,
    [[7], [0], [7], [7]],
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    seeded_rng(5),
    1,
    1,
    0.0,
  )
  assert_true(ds_gap(scripted, rolled) < 1.0e-9)
}

///|
test "double_dp keeps endure and a dominated hit does not change the value" {
  let endure = mk_move("こらえる", "ノーマル", @model.Status, 0, priority=4)
  let weak = mk_move("たいあたり", "ノーマル", @model.Physical, 20)
  let strong = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let smash = mk_move("たいあたり", "ノーマル", @model.Physical, 200)
  let fast = mk_move("ファストガード", "かくとう", @model.Status, 0, priority=3)
  let swap_mv = mk_move("サイドチェンジ", "エスパー", @model.Status, 0, priority=2)
  let with_endure = mk_combatant(
    mk_pokemon("Live", "ノーマル", "", 110, 80, 40, 40, 40, 30),
    [endure, strong],
  )
  let no_endure = mk_combatant(
    mk_pokemon("Live", "ノーマル", "", 110, 80, 40, 40, 40, 30),
    [strong],
  )
  let rich = mk_combatant(
    mk_pokemon("Rich", "ノーマル", "", 180, 40, 90, 40, 90, 50),
    [weak, strong, fast, endure, swap_mv],
  )
  let thin = mk_combatant(
    mk_pokemon("Rich", "ノーマル", "", 180, 40, 90, 40, 90, 50),
    [strong, fast, endure, swap_mv],
  )
  let opp = dt_mon("Opp", "ノーマル", 220, 250, 120, 40, 80, 140, smash)
  let wall = dt_mon("Wall", "ノーマル", 200, 40, 80, 40, 80, 20, fast)
  let dead = dg_dead()
  let cache = new_double_eval()
  let config = NashSolverConfig::default()
  assert_true(double_move_mean(opp, with_endure, smash) >= 110)
  let lived = double_dp_cell(
    cache,
    dg_side(with_endure),
    dg_side(opp),
    [[7, 0], [7], [7], [7]],
    dg_targets([0]),
    config,
    2,
  )
  let fainted = double_dp_cell(
    cache,
    dg_side(no_endure),
    dg_side(opp),
    [[0], [7], [7], [7]],
    dg_targets([0]),
    config,
    2,
  )
  assert_true(fainted == -1.0)
  assert_true(lived > fainted)
  let rich_v = double_dp_cell(
    cache,
    ds_four(rich, wall, dead, dead),
    dg_side(dt_status("Quiet", 5, 200)),
    [[0, 0, 12, 7, 7], [12], [7], [7]],
    dg_targets([7]),
    config,
    2,
  )
  let thin_v = double_dp_cell(
    cache,
    ds_four(thin, wall, dead, dead),
    dg_side(dt_status("Quiet", 5, 200)),
    [[0, 12, 7, 7], [12], [7], [7]],
    dg_targets([7]),
    config,
    2,
  )
  assert_true(ds_gap(rich_v, thin_v) < 1.0e-9)
  let actions : Array[@doubles.DoubleAction] = [
    @doubles.UseOn(0, @doubles.FoeLeft),
    @doubles.UseOn(1, @doubles.FoeLeft),
    @doubles.Use(2),
    @doubles.Use(3),
    @doubles.Use(4),
  ]
  let leaf = prune_slot_actions(
    cache,
    rich,
    [0, 0, 12, 7, 7],
    actions,
    [wall],
    [],
    true,
  )
  let names = dg_names(rich, leaf)
  assert_true(dg_has(names, "ファストガード"))
  assert_true(dg_has(names, "こらえる"))
  assert_true(dg_has(names, "サイドチェンジ"))
  let mut saw_weak = false
  let mut saw_strong = false
  for action in leaf {
    match double_slot_move(rich, action) {
      Some(mv) =>
        if mv.name == "たいあたり" && mv.power == 20 {
          saw_weak = true
        } else if mv.name == "たいあたり" && mv.power == 80 {
          saw_strong = true
        }
      None => ()
    }
  }
  assert_true(saw_strong && !saw_weak)
}
