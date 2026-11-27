///|
fn dg_gap(a : Double, b : Double) -> Double {
  (a - b).abs()
}

///|
fn dg_dead() -> Combatant {
  dt_status("Dead", 1, 0)
}

///|
fn dg_side(lead : Combatant) -> Array[Combatant] {
  let dead = dg_dead()
  [lead, dead, dead, dead]
}

///|
fn dg_targets(lead : Array[Int]) -> Array[Array[Int]] {
  [lead, [7], [7], [7]]
}

///|
fn dg_names(
  mon : Combatant,
  actions : Array[@doubles.DoubleAction],
) -> Array[String] {
  let out : Array[String] = []
  for action in actions {
    match double_slot_move(mon, action) {
      Some(mv) => out.push(mv.name)
      None => ()
    }
  }
  out
}

///|
fn dg_has(names : Array[String], name : String) -> Bool {
  for n in names {
    if n == name {
      return true
    }
  }
  false
}

///|
test "priority 0 protect does not block a faster hit" {
  let wall = mk_move("まもる", "ノーマル", @model.Status, 0, priority=0)
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let me = dt_mon("Me", "ノーマル", 180, 40, 80, 40, 80, 20, wall)
  let opp = dt_mon("Opp", "ノーマル", 180, 160, 80, 40, 80, 140, hit)
  let (_, my_hp, _) = scripted_value_and_hp(
    new_double_eval(),
    dg_side(me),
    dg_side(opp),
    dg_targets([7]),
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let dmg = double_move_mean(opp, me, hit)
  assert_true(dmg > 0)
  assert_true(my_hp[0] == 180 - dmg)
}

///|
test "protect and detect at priority 4 block and set stall to 1" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let opp = dt_mon("Opp", "ノーマル", 180, 160, 80, 40, 80, 140, hit)
  for name in ["まもる", "みきり"] {
    let wall = mk_move(name, "ノーマル", @model.Status, 0, priority=4)
    let me = dt_mon("Me", "ノーマル", 180, 40, 80, 40, 80, 20, wall)
    let (_, field) = scripted_turn_field(
      new_double_eval(),
      dg_side(me),
      dg_side(opp),
      dg_targets([7]),
      dg_targets([0]),
      Some(@doubles.Use(0)),
      None,
      Some(@doubles.UseOn(0, @doubles.MyLeft)),
      None,
      [],
    )
    assert_true(field.my_hp[0] == 180)
    assert_true(field.stall[0] == 1)
    assert_true(field.shield[0] == 0)
  }
}

///|
test "opening stall makes the next protect succeed with probability 1/3" {
  let wall = mk_move("まもる", "ノーマル", @model.Status, 0, priority=4)
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 90)
  let me = dt_mon("Me", "ノーマル", 200, 40, 70, 40, 70, 30, wall)
  let opp = dt_mon("Opp", "ノーマル", 200, 170, 80, 40, 80, 150, hit)
  let my = dg_side(me)
  let them = dg_side(opp)
  let my_t = dg_targets([7])
  let opp_t = dg_targets([0])
  let (v, _, _) = scripted_value_and_hp_stall(
    new_double_eval(),
    my,
    them,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [1, 0, 0, 0],
  )
  let full = double_terminal(fresh_field(my, them), my, them)
  let hurt_state = fresh_field(my, them)
  let dmg = double_move_mean(opp, me, hit)
  set_hp(hurt_state, @doubles.MyLeft, 200 - dmg)
  let hurt = double_terminal(hurt_state, my, them)
  let expect = (1.0 / 3.0) * full + (2.0 / 3.0) * hurt
  assert_true(dmg > 0 && dmg < 200)
  assert_true(dg_gap(v, expect) < 1.0e-9)
}

///|
test "a non-protect turn and a switch clear stall" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let me = dt_mon("Me", "ノーマル", 180, 100, 80, 40, 80, 80, hit)
  let opp = dt_status("Opp", 10, 180)
  let (_, field) = scripted_turn_field(
    new_double_eval(),
    dg_side(me),
    dg_side(opp),
    dg_targets([0]),
    dg_targets([7]),
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    None,
    Some(@doubles.Use(0)),
    None,
    [1, 0, 0, 0],
  )
  assert_true(field.stall[0] == 0)
  let bench = dt_mon("Bench", "ノーマル", 160, 40, 80, 40, 80, 40, hit)
  let dead = dg_dead()
  let my = [me, dead, bench, dead]
  let (_, switched) = scripted_turn_field(
    new_double_eval(),
    my,
    dg_side(opp),
    dg_targets([0]),
    dg_targets([7]),
    Some(@doubles.BenchTo(0)),
    None,
    Some(@doubles.Use(0)),
    None,
    [1, 0, 0, 0],
  )
  assert_true(switched.pos[0] == 2)
  assert_true(switched.stall[0] == 0)
}

///|
test "kings shield spiky shield and bunker block a tackle" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let opp = dt_mon("Opp", "ノーマル", 160, 150, 80, 40, 80, 120, hit)
  for name in ["キングシールド", "トーチカ"] {
    let wall = mk_move(name, "ノーマル", @model.Status, 0, priority=4)
    let me = dt_mon("Me", "ノーマル", 180, 40, 80, 40, 80, 20, wall)
    let (_, my_hp, opp_hp) = scripted_value_and_hp(
      new_double_eval(),
      dg_side(me),
      dg_side(opp),
      dg_targets([7]),
      dg_targets([0]),
      Some(@doubles.Use(0)),
      None,
      Some(@doubles.UseOn(0, @doubles.MyLeft)),
      None,
    )
    assert_true(my_hp[0] == 180)
    assert_true(opp_hp[0] == 160)
  }
}

///|
test "spiky shield chips a contact hit and magic guard takes none" {
  let wall = mk_move("ニードルガード", "くさ", @model.Status, 0, priority=4)
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let me = dt_mon("Me", "くさ", 184, 40, 80, 40, 80, 20, wall)
  let opp = mk_combatant(
    mk_pokemon("Opp", "ノーマル", "", 160, 150, 80, 40, 80, 120),
    [hit],
  )
  let (_, my_hp, opp_hp) = scripted_value_and_hp(
    new_double_eval(),
    dg_side(me),
    dg_side(opp),
    dg_targets([7]),
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(my_hp[0] == 184)
  assert_true(opp_hp[0] == 160 - 160 / 8)
  let guarded = {
    ..mk_combatant(
      mk_pokemon("Guard", "ノーマル", "", 160, 150, 80, 40, 80, 120),
      [hit],
    ),
    ability: "マジックガード",
  }
  let (_, _, safe_hp) = scripted_value_and_hp(
    new_double_eval(),
    dg_side(me),
    dg_side(guarded),
    dg_targets([7]),
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(safe_hp[0] == 160)
}

///|
test "unseen fist deals a quarter through protect" {
  let wall = mk_move("まもる", "ノーマル", @model.Status, 0, priority=4)
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let me = dt_mon("Me", "ノーマル", 220, 40, 90, 40, 90, 20, wall)
  let opp = {
    ..mk_combatant(
      mk_pokemon("Fist", "ノーマル", "", 180, 170, 80, 40, 80, 130),
      [hit],
    ),
    ability: "ふかしのこぶし",
  }
  let (_, my_hp, _) = scripted_value_and_hp(
    new_double_eval(),
    dg_side(me),
    dg_side(opp),
    dg_targets([7]),
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let full = double_move_mean(opp, me, hit)
  assert_true(my_hp[0] == 220 - @damage.round5(full, 1024))
}

///|
test "feint and shadow force break protect and keep stall" {
  let wall = mk_move("まもる", "ノーマル", @model.Status, 0, priority=4)
  let me = dt_mon("Me", "ノーマル", 200, 40, 80, 40, 80, 20, wall)
  let feint = mk_move("フェイント", "ノーマル", @model.Physical, 30, priority=2)
  let dive = mk_move("ゴーストダイブ", "ゴースト", @model.Physical, 90, priority=0)
  let foe_feint = dt_mon("Feint", "ノーマル", 180, 140, 80, 40, 80, 100, feint)
  let foe_dive = dt_mon("Dive", "ゴースト", 180, 140, 80, 40, 80, 100, dive)
  let (_, feint_field) = scripted_turn_field(
    new_double_eval(),
    dg_side(me),
    dg_side(foe_feint),
    dg_targets([7]),
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [],
  )
  let feint_dmg = double_move_mean(foe_feint, me, feint)
  assert_true(feint_dmg > 0)
  assert_true(feint_field.my_hp[0] == 200 - feint_dmg)
  assert_true(feint_field.stall[0] == 1)
  let (_, dive_field) = scripted_turn_field(
    new_double_eval(),
    dg_side(me),
    dg_side(foe_dive),
    dg_targets([7]),
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    [],
  )
  let dive_dmg = double_move_mean(foe_dive, me, dive)
  assert_true(dive_field.my_hp[0] == 200 - dive_dmg)
  assert_true(dive_field.stall[0] == 1)
}

///|
test "helping hand multiplies the ally power by 1.5 before the formula" {
  let hand = mk_move("てだすけ", "ノーマル", @model.Status, 0, priority=5)
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let helper = dt_mon("Help", "ノーマル", 180, 40, 80, 40, 80, 40, hand)
  let ally = dt_mon("Ally", "ノーマル", 180, 160, 80, 40, 80, 90, hit)
  let foe = dt_status("Foe", 30, 220)
  let dead = dg_dead()
  let my = [helper, ally, dead, dead]
  let opp = dg_side(foe)
  let my_t = [[2], [0], [7], [7]]
  let (_, _, opp_hp) = scripted_value_and_hp(
    new_double_eval(),
    my,
    opp,
    my_t,
    dg_targets([7]),
    Some(@doubles.UseOn(0, @doubles.MyRight)),
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    Some(@doubles.Use(0)),
    None,
  )
  let boosted = helping_hand_move(hit)
  let dmg = double_move_mean(ally, foe, boosted)
  let plain = double_move_mean(ally, foe, hit)
  assert_true(boosted.power == @damage.round5(80, 6144))
  assert_true(dmg > plain)
  assert_true(opp_hp[0] == 220 - dmg)
  let late = mk_move("てだすけ", "ノーマル", @model.Status, 0, priority=0)
  let slow_help = dt_mon("Late", "ノーマル", 180, 40, 80, 40, 80, 10, late)
  let fast_ally = dt_mon("Fast", "ノーマル", 180, 160, 80, 40, 80, 200, hit)
  let (_, _, late_hp) = scripted_value_and_hp(
    new_double_eval(),
    [slow_help, fast_ally, dead, dead],
    opp,
    my_t,
    dg_targets([7]),
    Some(@doubles.UseOn(0, @doubles.MyRight)),
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    Some(@doubles.Use(0)),
    None,
  )
  assert_true(late_hp[0] == 220 - plain)
}

///|
test "wide guard blocks spread moves into the ally side only" {
  let quake = mk_move("じしん", "じめん", @model.Physical, 100)
  let wide_mv = mk_move("ワイドガード", "いわ", @model.Status, 0, priority=3)
  let user = dt_mon("Quake", "じめん", 240, 150, 90, 40, 90, 80, quake)
  let ally = dt_mon("Ally", "いわ", 200, 40, 100, 40, 100, 40, wide_mv)
  let foe = dt_status("Foe", 20, 200)
  let dead = dg_dead()
  let my = [user, ally, dead, dead]
  let opp = [foe, foe, dead, dead]
  let my_t = [[4], [12], [7], [7]]
  let opp_t = [[7], [7], [7], [7]]
  let (_, my_hp, opp_hp) = scripted_value_and_hp(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
  )
  assert_true(my_hp[0] == 240)
  assert_true(my_hp[1] == 200)
  assert_true(opp_hp[0] == 200 - double_move_mean(user, foe, quake))
  let poke = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let single = dt_mon("Single", "ノーマル", 180, 160, 80, 40, 80, 50, poke)
  let (_, poked, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    dg_side(single),
    my_t,
    dg_targets([0]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyRight)),
    None,
  )
  let poke_dmg = double_move_mean(single, ally, poke)
  assert_true(poke_dmg > 0)
  assert_true(poked[1] == 200 - poke_dmg)
}

///|
test "wide guard ignores the protect stall counter and resets it" {
  let quake = mk_move("じしん", "じめん", @model.Physical, 100)
  let wide_mv = mk_move("ワイドガード", "いわ", @model.Status, 0, priority=3)
  let user = dt_mon("Quake", "じめん", 220, 140, 90, 40, 90, 70, quake)
  let ally = dt_mon("Ally", "いわ", 180, 40, 90, 40, 90, 30, wide_mv)
  let dead = dg_dead()
  let my = [user, ally, dead, dead]
  let opp = [dead, dead, dead, dead]
  let my_t = [[4], [12], [7], [7]]
  let opp_t = [[7], [7], [7], [7]]
  let (fresh_v, _, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    None,
    None,
  )
  let (stale_v, _, _) = scripted_value_and_hp_stall(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    None,
    None,
    [0, 6, 0, 0],
  )
  assert_true(dg_gap(fresh_v, stale_v) == 0.0)
  let (_, field) = scripted_turn_field(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    None,
    None,
    [0, 1, 0, 0],
  )
  assert_true(field.my_hp[1] == 180)
  assert_true(field.stall[1] == 0)
  assert_true(field.wide[0] == 0)
}

///|
test "feint removes wide guard for a later spread" {
  let quake = mk_move("じしん", "じめん", @model.Physical, 100)
  let wide_mv = mk_move("ワイドガード", "いわ", @model.Status, 0, priority=3)
  let feint = mk_move("フェイント", "ノーマル", @model.Physical, 30, priority=2)
  let user = dt_mon("Quake", "じめん", 220, 150, 90, 40, 90, 40, quake)
  let ally = dt_mon("Ally", "いわ", 200, 40, 110, 40, 110, 30, wide_mv)
  let foe = dt_mon("Feint", "ノーマル", 180, 130, 80, 40, 80, 90, feint)
  let dead = dg_dead()
  let my = [user, ally, dead, dead]
  let my_t = [[4], [12], [7], [7]]
  let (_, broken, _) = scripted_value_and_hp(
    new_double_eval(),
    my,
    dg_side(foe),
    my_t,
    dg_targets([0]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyRight)),
    None,
  )
  let feint_dmg = double_move_mean(foe, ally, feint)
  let quake_dmg = double_move_mean(user, ally, quake)
  assert_true(feint_dmg > 0 && quake_dmg > 0)
  assert_true(broken[1] == 200 - feint_dmg - quake_dmg)
}

///|
test "leaf prune keeps protect helping hand and wide guard" {
  let weak = dd_surf(40, 100)
  let strong = dd_surf(120, 100)
  let protect = mk_move("まもる", "ノーマル", @model.Status, 0, priority=4)
  let hand = mk_move("てだすけ", "ノーマル", @model.Status, 0, priority=5)
  let wide = mk_move("ワイドガード", "いわ", @model.Status, 0, priority=3)
  let endure = mk_move("こらえる", "ノーマル", @model.Status, 0, priority=4)
  let fast = mk_move("ファストガード", "かくとう", @model.Status, 0, priority=3)
  let ally_sw = mk_move("サイドチェンジ", "エスパー", @model.Status, 0, priority=2)
  let mon = mk_combatant(
    mk_pokemon("Surf", "みず", "", 180, 40, 80, 180, 80, 100),
    [weak, strong, protect, hand, wide, endure, fast, ally_sw],
  )
  let foe = dt_mon(
    "Foe",
    "ノーマル",
    200,
    40,
    80,
    40,
    80,
    40,
    strong,
  )
  let targets = [5, 5, 7, 2, 12, 7, 12, 7]
  let actions : Array[@doubles.DoubleAction] = [
    @doubles.Use(0),
    @doubles.Use(1),
    @doubles.Use(2),
    @doubles.Use(3),
    @doubles.Use(4),
    @doubles.Use(5),
    @doubles.Use(6),
    @doubles.Use(7),
  ]
  let cache = new_double_eval()
  let leaf = prune_slot_actions(cache, mon, targets, actions, [foe], [], true)
  let names = dg_names(mon, leaf)
  assert_true(dg_has(names, "まもる"))
  assert_true(dg_has(names, "てだすけ"))
  assert_true(dg_has(names, "ワイドガード"))
  assert_true(dg_has(names, "こらえる"))
  assert_true(dg_has(names, "ファストガード"))
  assert_true(dg_has(names, "サイドチェンジ"))
  let mut saw_weak = false
  let mut saw_strong = false
  for action in leaf {
    match double_slot_move(mon, action) {
      Some(mv) =>
        if mv.name == "なみのり" && mv.power == 40 {
          saw_weak = true
        } else if mv.name == "なみのり" && mv.power == 120 {
          saw_strong = true
        }
      None => ()
    }
  }
  assert_true(saw_strong && !saw_weak)
  let kept = prune_slot_actions(cache, mon, targets, actions, [foe], [], false)
  let early = dg_names(mon, kept)
  assert_true(dg_has(early, "こらえる"))
  assert_true(dg_has(early, "ファストガード"))
  assert_true(dg_has(early, "サイドチェンジ"))
  let mut early_weak = false
  for action in kept {
    match double_slot_move(mon, action) {
      Some(mv) =>
        if mv.name == "なみのり" && mv.power == 40 {
          early_weak = true
        }
      None => ()
    }
  }
  assert_true(early_weak)
}

///|
test "double_dp keeps protect when a faster move would ko on the next turn" {
  let wall = mk_move("まもる", "ノーマル", @model.Status, 0, priority=4)
  let weak = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let smash = mk_move("たいあたり", "ノーマル", @model.Physical, 250)
  let me = mk_combatant(
    mk_pokemon("Me", "ノーマル", "", 120, 80, 40, 40, 40, 40),
    [wall, weak],
  )
  let opp = mk_combatant(
    mk_pokemon("Opp", "ノーマル", "", 200, 250, 120, 40, 80, 180),
    [smash],
  )
  let only = mk_combatant(
    mk_pokemon("Only", "ノーマル", "", 120, 80, 40, 40, 40, 40),
    [wall],
  )
  let my_t = dg_targets([7, 0])
  let opp_t = dg_targets([0])
  let cache = new_double_eval()
  let config = NashSolverConfig::default()
  let dmg = double_move_mean(opp, me, smash)
  assert_true(dmg >= 120)
  assert_true(double_move_mean(me, opp, weak) > 0)
  let both = double_dp_cell(
    cache, dg_side(me), dg_side(opp), my_t, opp_t, config, 2,
  )
  let wall_only = double_dp_cell(
    cache, dg_side(only), dg_side(opp), dg_targets([7]), opp_t, config, 2,
  )
  assert_true(dg_gap(both, -2.0 / 3.0) < 1.0e-9)
  assert_true(dg_gap(wall_only, both) < 1.0e-9)
}

///|
test "rollout stall matches the two-turn protect line" {
  let wall = mk_move("まもる", "ノーマル", @model.Status, 0, priority=4)
  let smash = mk_move("たいあたり", "ノーマル", @model.Physical, 250)
  let me = dt_mon("Me", "ノーマル", 120, 40, 40, 40, 40, 40, wall)
  let opp = dt_mon("Opp", "ノーマル", 200, 250, 120, 40, 80, 180, smash)
  let my_t = dg_targets([7])
  let opp_t = dg_targets([0])
  let cache = new_double_eval()
  let config = NashSolverConfig::default()
  assert_true(double_move_mean(opp, me, smash) >= 120)
  let dp = double_dp_cell(
    cache, dg_side(me), dg_side(opp), my_t, opp_t, config, 2,
  )
  let rolled = double_scripted_rollout(
    cache,
    dg_side(me),
    dg_side(opp),
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
    seeded_rng(11),
    800,
    2,
    0.0,
  )
  assert_true(dg_gap(dp, -2.0 / 3.0) < 1.0e-9)
  assert_true(dg_gap(rolled, dp) < 0.08)
}

///|
test "a dominated spread stays dominated beside protect" {
  let weak = dd_surf(30, 100)
  let strong = dd_surf(110, 100)
  let wall = mk_move("まもる", "ノーマル", @model.Status, 0, priority=4)
  let with_weak = mk_combatant(
    mk_pokemon("Both", "みず", "", 190, 40, 90, 170, 90, 120),
    [weak, strong, wall],
  )
  let no_weak = mk_combatant(
    mk_pokemon("Strong", "みず", "", 190, 40, 90, 170, 90, 120),
    [strong, wall],
  )
  let ally = dt_mon("Ally", "みず", 180, 40, 90, 40, 90, 80, wall)
  let dead = dg_dead()
  let (status, status_t) = dd_status_side(20)
  let cache = new_double_eval()
  let config = NashSolverConfig::default()
  let rich = double_dp_cell(
    cache,
    [with_weak, ally, dead, dead],
    status,
    [[5, 5, 7], [7], [7], [7]],
    status_t,
    config,
    2,
  )
  let thin = double_dp_cell(
    cache,
    [no_weak, ally, dead, dead],
    status,
    [[5, 7], [7], [7], [7]],
    status_t,
    config,
    2,
  )
  let passive_mon = mk_combatant(
    mk_pokemon("Wall", "みず", "", 190, 40, 90, 170, 90, 120),
    [wall],
  )
  let passive = double_dp_cell(
    cache,
    [passive_mon, ally, dead, dead],
    status,
    [[7], [7], [7], [7]],
    status_t,
    config,
    2,
  )
  assert_true(dg_gap(rich, thin) < 1.0e-9)
  assert_true(rich > passive)
}
