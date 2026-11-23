///|
/// こだわりスカーフ (ITEMNAME_287 / ITEMINFO_SYN_287) の素早さと技固定。
/// ハチマキ / メガネ / チョッキは itemname に無いので、ここではスカーフだけ。

///|
fn ch_move(name : String, type_ : String, power : Int) -> @model.Move {
  flch_move(name, type_, @model.Physical, power, 100, 0)
}

///|
fn ch_scarf(mon : Combatant) -> Combatant {
  { ..mon, item: "こだわりスカーフ" }
}

///|
fn ch_mass_choice(
  outs : Array[(Double, SwitchingGameState)],
  want : Int,
) -> Double {
  let mut total = 0.0
  for item in outs {
    let (p, s) = item
    if s.my_choice == want {
      total = total + p
    }
  }
  total
}

///|
test "choice scarf speed is floor of 1.5 after stages and identity otherwise" {
  assert_true(speed_after_choice_scarf(100, "こだわりスカーフ", false) == 150)
  assert_true(speed_after_choice_scarf(101, "こだわりスカーフ", false) == 151)
  assert_true(speed_after_choice_scarf(100, "こだわりスカーフ", true) == 100)
  assert_true(speed_after_choice_scarf(100, "こだわりハチマキ", false) == 100)
  assert_true(speed_after_choice_scarf(100, "こだわりメガネ", false) == 100)
  assert_true(speed_after_choice_scarf(100, "とつげきチョッキ", false) == 100)
  assert_true(speed_after_choice_scarf(100, "", false) == 100)
  assert_true(!holds_choice_scarf("こだわりハチマキ"))
  assert_true(holds_choice_scarf("こだわりスカーフ"))
}

///|
test "choice lock follows the selected move, switch, recharge, and item loss" {
  assert_true(
    choice_lock_after_action(-1, UseMove(1), "こだわりスカーフ", false, false) ==
      1,
  )
  assert_true(
    choice_lock_after_action(0, Mega(1), "こだわりスカーフ", false, false) == 1,
  )
  assert_true(
    choice_lock_after_action(1, Switch(0), "こだわりスカーフ", false, false) ==
      -1,
  )
  assert_true(
    choice_lock_after_action(1, UseMove(0), "こだわりスカーフ", false, true) ==
      1,
  )
  assert_true(
    choice_lock_after_action(-1, UseMove(0), "こだわりスカーフ", false, true) ==
      -1,
  )
  assert_true(choice_lock_after_action(1, UseMove(0), "こだわりスカーフ", true, false) == -1)
  assert_true(choice_lock_after_action(1, UseMove(0), "きあいのハチマキ", false, false) == -1)
  assert_true(effective_choice_lock("きあいのハチマキ", false, 1) == -1)
  assert_true(effective_choice_lock("こだわりスカーフ", true, 1) == -1)
  assert_true(effective_choice_lock("こだわりスカーフ", false, 1) == 1)
}

///|
test "alive_actions keeps every move unless a scarf lock is live" {
  let bolt = ch_move("10まんボルト", "でんき", 80)
  let quake = ch_move("じしん", "じめん", 80)
  let plain = flch_cmb(flch_pokemon("a", "ノーマル", 200, 100), [bolt, quake], "")
  let scarf = ch_scarf(plain)
  let hps = [200]
  let open = alive_actions(0, hps, [plain], false)
  // スカーフ以外の古い index は effective が -1 にし、行動列は既定と同じ。
  let stale_lock = effective_choice_lock(plain.item, false, 1)
  let stale = alive_actions(0, hps, [plain], false, choice_lock=stale_lock)
  assert_true(stale_lock == -1)
  assert_true(open.length() == stale.length())
  for i = 0; i < open.length(); i = i + 1 {
    assert_true(open[i] == stale[i])
  }
  let unlocked = alive_actions(0, hps, [scarf], false, choice_lock=-1)
  assert_true(unlocked.length() == open.length())
  let locked = alive_actions(0, hps, [scarf], false, choice_lock=0)
  assert_true(locked.length() == 1)
  match locked[0] {
    UseMove(0) => ()
    _ => assert_true(false)
  }
}

///|
test "move order applies scarf after stages and before paralysis" {
  let mv = ch_move("たいあたり", "ノーマル", 40)
  let ranks = [0, 0, 0, 0, 0]
  let scarf = ch_scarf(
    flch_cmb(flch_pokemon("fast", "ノーマル", 200, 100), [mv], ""),
  )
  let bare = flch_cmb(flch_pokemon("fast", "ノーマル", 200, 100), [mv], "")
  let opp = flch_cmb(flch_pokemon("slow", "ノーマル", 200, 140), [mv], "")
  let scarf_first = move_turn_sign(
    scarf, ranks, mv, false, false, 200, opp, ranks, mv, false, false, 200,
  )
  let bare_second = move_turn_sign(
    bare, ranks, mv, false, false, 200, opp, ranks, mv, false, false, 200,
  )
  let consumed_second = move_turn_sign(
    scarf, ranks, mv, false, false, 200, opp, ranks, mv, false, false, 200,
    me_item_consumed=true,
  )
  let slower = flch_cmb(flch_pokemon("slow", "ノーマル", 200, 80), [mv], "")
  let para_second = move_turn_sign(
    scarf, ranks, mv, false, true, 200, slower, ranks, mv, false, false, 200,
  )
  let healthy_first = move_turn_sign(
    scarf, ranks, mv, false, false, 200, slower, ranks, mv, false, false, 200,
  )
  assert_true(scarf_first > 0)
  assert_true(bare_second < 0)
  assert_true(consumed_second < 0)
  assert_true(para_second < 0)
  assert_true(healthy_first > 0)
}

///|
test "a scarf use locks that move and a switch or a lost item clears it" {
  let bolt = ch_move("10まんボルト", "でんき", 80)
  let quake = ch_move("じしん", "じめん", 80)
  let status = flch_move("てだすけ", "ノーマル", @model.Status, 0, 100, 0)
  let me = ch_scarf(
    flch_cmb(flch_pokemon("a", "ノーマル", 200, 200), [bolt, quake], ""),
  )
  let bench = flch_cmb(flch_pokemon("b", "ノーマル", 200, 50), [quake], "")
  let opp = flch_cmb(flch_pokemon("c", "ノーマル", 200, 50), [status], "")
  let st = flch_state(200, 200, @model.None, @model.None)
  let locked = attempt_turn_with_cache(
    st, UseMove(1), UseMove(0), [me], [opp], new_damage_cache(),
  )
  assert_true(ch_mass_choice(locked, 1) == 1.0)
  let again = {
    ..st,
    my_choice: 1,
  }
  let acts = alive_actions(
    0,
    again.my_hps,
    [me],
    false,
    choice_lock=effective_choice_lock(me.item, false, again.my_choice),
  )
  assert_true(acts.length() == 1)
  let two = {
    ..st,
    my_choice: 0,
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
    two, Switch(1), UseMove(0), [me, bench], [opp], new_damage_cache(),
  )
  assert_true(ch_mass_choice(switched, -1) == 1.0)
  let spent = {
    ..st,
    my_choice: 0,
    my_item_consumed: [true],
  }
  let cleared = attempt_turn_with_cache(
    spent, UseMove(1), UseMove(0), [me], [opp], new_damage_cache(),
  )
  assert_true(ch_mass_choice(cleared, -1) == 1.0)
  let recharge = {
    ..st,
    my_choice: 1,
    my_must_recharge: [true],
  }
  let held = attempt_turn_with_cache(
    recharge, UseMove(0), UseMove(0), [me], [opp], new_damage_cache(),
  )
  assert_true(ch_mass_choice(held, 1) == 1.0)
}

///|
test "a failing fake out stays selectable when it is the locked move" {
  let fake = flch_move("ねこだまし", "ノーマル", @model.Physical, 40, 100, 100)
  let tackle = ch_move("たいあたり", "ノーマル", 40)
  let status = flch_move("てだすけ", "ノーマル", @model.Status, 0, 100, 0)
  let me = ch_scarf(
    flch_cmb(flch_pokemon("a", "ノーマル", 200, 200), [fake, tackle], ""),
  )
  let opp = flch_cmb(flch_pokemon("c", "ノーマル", 200, 50), [status], "")
  let st = {
    ..flch_state(200, 200, @model.None, @model.None),
    my_choice: 0,
    my_fresh: Some(false),
  }
  let acts = alive_actions(
    0, st.my_hps, [me], false, choice_lock=0,
  )
  let mut saw_fake = false
  let mut saw_other = false
  for act in acts {
    match act {
      UseMove(0) => saw_fake = true
      UseMove(_) | Mega(_) => saw_other = true
      Switch(_) => ()
    }
  }
  assert_true(saw_fake && !saw_other)
  let outs = attempt_turn_with_cache(
    st, UseMove(0), UseMove(0), [me], [opp], new_damage_cache(),
  )
  let mut mass = 0.0
  for item in outs {
    let (p, s) = item
    if s.my_choice == 0 && s.opp_hps[0] == 200 {
      mass = mass + p
    }
  }
  assert_true(mass == 1.0)
}

///|
fn ch_drop_teams() -> (Array[Combatant], Array[Combatant], Array[Combatant]) {
  // 物理でんきは初手の期待値が高く、命中後に攻撃 -2。次のターンは特攻じめんの方が高い。
  // 相手は 1 体のままなので、MC の greedy も交代先を見ずに技を選ぶ。
  let bolt = {
    ..ch_move("10まんボルト", "でんき", 80),
    stat_effects: [@model.StatEffect::{ stat: 0, delta: -2, target: 0 }],
  }
  let earth = flch_move("だいちのちから", "じめん", @model.Special, 110, 100, 0)
  let status = flch_move("てだすけ", "ノーマル", @model.Status, 0, 100, 0)
  let poke = flch_pokemon("lead", "ノーマル", 200, 200)
  let scarf = ch_scarf(flch_cmb(poke, [bolt, earth], ""))
  let bare = flch_cmb(poke, [bolt, earth], "")
  let water = flch_cmb(flch_pokemon("water", "みず", 400, 40), [status], "")
  ([scarf], [bare], [water])
}

///|
test "scarf lock lowers the value once the first move drops attack" {
  let (scarf, bare, opp) = ch_drop_teams()
  let st = flch_state(200, 400, @model.None, @model.None)
  let cache_s : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap(
    [],
  )
  let cache_b : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap(
    [],
  )
  let v_scarf = value(
    st, scarf, opp, 2, cache_s, new_stats(), new_damage_cache(),
  )
  let v_bare = value(st, bare, opp, 2, cache_b, new_stats(), new_damage_cache())
  assert_true(v_scarf < v_bare)
  let mc_scarf = team_rollout(
    scarf, opp, seeded_rng(3UL), turn_limit=2, epsilon=0.0,
  )
  let mc_bare = team_rollout(
    bare, opp, seeded_rng(3UL), turn_limit=2, epsilon=0.0,
  )
  assert_true(mc_scarf < mc_bare)
}

///|
test "mc greedy stays on the locked move and otherwise picks the stronger one" {
  let weak = ch_move("ひっかく", "ノーマル", 40)
  let strong = ch_move("はかいこうせん", "ノーマル", 150)
  let bolt = ch_move("10まんボルト", "でんき", 80)
  let active = flch_cmb(flch_pokemon("a", "ノーマル", 200, 100), [weak, strong], "")
  let foe = flch_cmb(flch_pokemon("c", "じめん", 200, 50), [weak], "")
  let rng = seeded_rng(5UL)
  match
    greedy_team_action(
      0, [active], [200], [0, 0, 0, 0, 0], 0, [foe], [0, 0, 0, 0, 0], rng, 0.0,
    ) {
    Some(TmUseMove(1)) => ()
    _ => assert_true(false)
  }
  let locked = ch_scarf(
    flch_cmb(flch_pokemon("a", "ノーマル", 200, 100), [bolt, strong], ""),
  )
  for _i = 0; _i < 20; _i = _i + 1 {
    match
      greedy_team_action(
        0,
        [locked],
        [200],
        [0, 0, 0, 0, 0],
        0,
        [foe],
        [0, 0, 0, 0, 0],
        rng,
        1.0,
        choice_lock=0,
      ) {
      Some(TmUseMove(0)) => ()
      _ => assert_true(false)
    }
  }
}
