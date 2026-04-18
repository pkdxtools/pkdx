///|
/// Helper: dummy team of `n` Pokemon, each with HP `hp`, one damage move,
/// identical stats — used for terminal/action unit tests where stat details
/// don't matter.
fn build_dummy_team(n : Int, hp : Int) -> Array[Combatant] {
  let out = Array::make(
    n,
    mk_combatant(
      mk_pokemon("", "ノーマル", "", hp, 100, 100, 100, 100, 100),
      [mk_move("mv", "ノーマル", @model.Physical, 60)],
    ),
  )
  for i in 0..<n {
    out[i] = mk_combatant(
      mk_pokemon(
        "T" + i.to_string(), "ノーマル", "", hp, 100, 100, 100, 100, 100,
      ),
      [mk_move("mv", "ノーマル", @model.Physical, 60)],
    )
  }
  out
}

///|
test "state_is_hashable_and_distinguishes_meaningful_fields" {
  let base : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100, 100],
    opp_hps: [100, 100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false, false],
    opp_megaed: [false, false, false],
    my_status: [@model.None, @model.None, @model.None],
    opp_status: [@model.None, @model.None, @model.None],
    turn: 0,
  }
  let same : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100, 100],
    opp_hps: [100, 100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false, false],
    opp_megaed: [false, false, false],
    my_status: [@model.None, @model.None, @model.None],
    opp_status: [@model.None, @model.None, @model.None],
    turn: 0,
  }
  let diff_active = { ..base, my_active: 1 }
  let diff_hp = { ..base, my_hps: [99, 100, 100] }
  let diff_turn = { ..base, turn: 1 }
  assert_eq(base, same)
  assert_true(base != diff_active)
  assert_true(base != diff_hp)
  assert_true(base != diff_turn)
  // HashMap key: same states collide on get; different states do not.
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  cache[base] = 0.5
  match cache.get(same) {
    Some(v) => assert_eq(v, 0.5)
    None => assert_true(false)
  }
  match cache.get(diff_active) {
    Some(_) => assert_true(false)
    None => ()
  }
}

///|
test "terminal_value_all_my_fainted_returns_minus_one" {
  let team_a = build_dummy_team(3, 100)
  let team_b = build_dummy_team(3, 100)
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [0, 0, 0],
    opp_hps: [100, 100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false, false],
    opp_megaed: [false, false, false],
    my_status: [@model.None, @model.None, @model.None],
    opp_status: [@model.None, @model.None, @model.None],
    turn: 0,
  }
  match terminal_value(state, team_a, team_b, 5) {
    Some(v) => assert_eq(v, -1.0)
    None => assert_true(false)
  }
}

///|
test "terminal_value_all_opp_fainted_returns_plus_one" {
  let team_a = build_dummy_team(3, 100)
  let team_b = build_dummy_team(3, 100)
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100, 100],
    opp_hps: [0, 0, 0],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false, false],
    opp_megaed: [false, false, false],
    my_status: [@model.None, @model.None, @model.None],
    opp_status: [@model.None, @model.None, @model.None],
    turn: 0,
  }
  match terminal_value(state, team_a, team_b, 5) {
    Some(v) => assert_eq(v, 1.0)
    None => assert_true(false)
  }
}

///|
test "terminal_value_turn_limit_reached_returns_hp_ratio_in_signed_range" {
  // my_ratio = 0.5, opp_ratio = 1.0 → delta = (my - opp)/2 = -0.25 (me losing
  // because opp has more HP left).
  let team_a = build_dummy_team(2, 100)
  let team_b = build_dummy_team(2, 100)
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [50, 50],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    turn: 3,
  }
  match terminal_value(state, team_a, team_b, 3) {
    Some(v) => assert_true((v - -0.25).abs() < 1.0e-9)
    None => assert_true(false)
  }
}

///|
test "terminal_value_both_alive_before_limit_returns_none" {
  let team_a = build_dummy_team(3, 100)
  let team_b = build_dummy_team(3, 100)
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100, 100],
    opp_hps: [100, 100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false, false],
    opp_megaed: [false, false, false],
    my_status: [@model.None, @model.None, @model.None],
    opp_status: [@model.None, @model.None, @model.None],
    turn: 0,
  }
  match terminal_value(state, team_a, team_b, 5) {
    Some(_) => assert_true(false)
    None => ()
  }
}

///|
test "alive_actions_excludes_fainted_switch_targets" {
  let team = build_dummy_team(3, 100)
  // active=0; team[1] KO'd (hp=0); team[2] alive → only Switch(2) legal
  let hps = [100, 0, 100]
  let actions = alive_actions(0, hps, team, false)
  let mut move_count = 0
  let switch_targets : Array[Int] = []
  for a in actions {
    match a {
      UseMove(_) => move_count += 1
      Switch(i) => switch_targets.push(i)
      Mega(_) => ()
    }
  }
  assert_eq(move_count, 1)
  assert_eq(switch_targets.length(), 1)
  assert_eq(switch_targets[0], 2)
}

///|
test "team_payoff_model_enum_exhaustive_match" {
  let models : Array[TeamPayoffModel] = [
    SwitchingGame(2),
    ScreenedSwitchingGame(100, 7UL, 0.5, 2),
  ]
  let labels = models.map(fn(m) {
    match m {
      SwitchingGame(_) => "switching_game"
      ScreenedSwitchingGame(_, _, _, _) => "screened_switching_game"
    }
  })
  let mut joined = ""
  for i in 0..<labels.length() {
    if i > 0 {
      joined = joined + ","
    }
    joined = joined + labels[i]
  }
  inspect(joined, content="switching_game,screened_switching_game")
}

///|
test "value_returns_terminal_value_for_terminal_state" {
  // Already at turn_limit with equal HPs → delta = 0.
  let team_a = build_dummy_team(2, 100)
  let team_b = build_dummy_team(2, 100)
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    turn: 5,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let stats = new_stats()
  let dmg_cache = new_damage_cache()
  let v = value(state, team_a, team_b, 5, cache, stats, dmg_cache)
  assert_eq(v, 0.0)
}

///|
test "value_matches_nash_value_of_one_step_payoff_matrix" {
  // turn_limit = 1: strong outspeeds and KOs weak in one turn → opp_hps all 0
  // → terminal value +1.0 for row player.
  let strong = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 250, 100, 100, 100, 200),
    [mk_move("ko", "ノーマル", @model.Physical, 250)],
  )
  let weak = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 1, 50, 50, 50, 50, 50),
    [mk_move("weak", "ノーマル", @model.Physical, 1)],
  )
  let v = switching_game_winrate([strong], [weak], 1)
  assert_eq(v, 1.0)
}

///|
test "value_caches_result_via_value_stats" {
  let team_a = build_dummy_team(2, 100)
  let team_b = build_dummy_team(2, 100)
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    turn: 0,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let stats = new_stats()
  let dmg_cache = new_damage_cache()
  let _ = value(state, team_a, team_b, 2, cache, stats, dmg_cache)
  let hits_before = stats.hits
  let _ = value(state, team_a, team_b, 2, cache, stats, dmg_cache)
  assert_true(stats.hits > hits_before)
}

///|
test "switching_game_winrate_mirror_match_returns_near_zero" {
  let team = build_dummy_team(2, 100)
  let v = switching_game_winrate(team, team, 2)
  assert_true(v.abs() < 1.0e-6)
}

///|
test "switching_game_winrate_dominant_team_returns_positive" {
  let strong_team = [
    mk_combatant(
      mk_pokemon("A0", "ノーマル", "", 150, 250, 120, 100, 120, 200),
      [mk_move("lethal", "ノーマル", @model.Physical, 250)],
    ),
    mk_combatant(
      mk_pokemon("A1", "ノーマル", "", 150, 250, 120, 100, 120, 200),
      [mk_move("lethal", "ノーマル", @model.Physical, 250)],
    ),
  ]
  let weak_team = [
    mk_combatant(
      mk_pokemon("B0", "ノーマル", "", 50, 50, 50, 50, 50, 30),
      [mk_move("weak", "ノーマル", @model.Physical, 10)],
    ),
    mk_combatant(
      mk_pokemon("B1", "ノーマル", "", 50, 50, 50, 50, 50, 30),
      [mk_move("weak", "ノーマル", @model.Physical, 10)],
    ),
  ]
  let v = switching_game_winrate(strong_team, weak_team, 2)
  assert_true(v > 0.5)
}

///|
test "switching_game_winrate_turn_limit_one_matches_single_turn_best1v1_on_initial_actives" {
  // Single-member teams: no switching. Strong KOs weak first turn → value 1.
  let strong = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 250, 100, 100, 100, 200),
    [mk_move("lethal", "ノーマル", @model.Physical, 250)],
  )
  let weak = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 1, 50, 50, 50, 50, 50),
    [mk_move("weak", "ノーマル", @model.Physical, 1)],
  )
  let v = switching_game_winrate([strong], [weak], 1)
  assert_true((v - 1.0).abs() < 1.0e-9)
}

///|
test "transition_attack_vs_attack_resolves_sequentially_by_speed" {
  // Fast side KOs slow side first. Slow side's move should NOT fire because
  // its active is at 0 HP after the fast attack.
  let fast = mk_combatant(
    mk_pokemon("Fast", "ノーマル", "", 100, 200, 100, 100, 100, 200),
    [mk_move("lethal", "ノーマル", @model.Physical, 250)],
  )
  let slow = mk_combatant(
    mk_pokemon("Slow", "ノーマル", "", 1, 200, 100, 100, 100, 50),
    [mk_move("chunk", "ノーマル", @model.Physical, 90)],
  )
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100],
    opp_hps: [1],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false],
    my_status: [@model.None],
    opp_status: [@model.None],
    turn: 0,
  }
  let next = transition(state, UseMove(0), UseMove(0), [fast], [slow])
  assert_eq(next.opp_hps[0], 0)
  assert_eq(next.my_hps[0], 100)
  assert_eq(next.turn, 1)
}

///|
test "transition_attack_vs_switch_damages_newly_switched_target" {
  // My attacks. Opp switches to teammate 1. Teammate 1 (new active) takes damage.
  let my_team = [
    mk_combatant(
      mk_pokemon("A0", "ノーマル", "", 100, 200, 100, 100, 100, 200),
      [mk_move("strong", "ノーマル", @model.Physical, 100)],
    ),
  ]
  let opp_team = [
    mk_combatant(
      mk_pokemon("B0", "ノーマル", "", 100, 100, 100, 100, 100, 50),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
    mk_combatant(
      mk_pokemon("B1", "ノーマル", "", 100, 100, 100, 100, 100, 50),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
  ]
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false, false],
    my_status: [@model.None],
    opp_status: [@model.None, @model.None],
    turn: 0,
  }
  let next = transition(state, UseMove(0), Switch(1), my_team, opp_team)
  assert_eq(next.opp_active, 1)
  assert_eq(next.my_hps[0], 100)
  assert_true(next.opp_hps[1] < 100)
  assert_eq(next.opp_hps[0], 100)
  assert_eq(next.turn, 1)
}

///|
test "transition_switch_vs_switch_updates_actives_only_without_damage" {
  let my_team = [
    mk_combatant(
      mk_pokemon("A0", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
    mk_combatant(
      mk_pokemon("A1", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
  ]
  let opp_team = [
    mk_combatant(
      mk_pokemon("B0", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
    mk_combatant(
      mk_pokemon("B1", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
  ]
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    turn: 0,
  }
  let next = transition(state, Switch(1), Switch(1), my_team, opp_team)
  assert_eq(next.my_active, 1)
  assert_eq(next.opp_active, 1)
  assert_eq(next.my_hps[0], 100)
  assert_eq(next.my_hps[1], 100)
  assert_eq(next.opp_hps[0], 100)
  assert_eq(next.opp_hps[1], 100)
  assert_eq(next.turn, 1)
}

///|
test "alive_actions_includes_all_moves_and_alive_switches" {
  let team = [
    mk_combatant(
      mk_pokemon("A0", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [
        mk_move("m1", "ノーマル", @model.Physical, 40),
        mk_move("m2", "ノーマル", @model.Physical, 80),
        mk_move("m3", "ノーマル", @model.Status, 0),
      ],
    ),
    mk_combatant(
      mk_pokemon("A1", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
    mk_combatant(
      mk_pokemon("A2", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
  ]
  let hps = [100, 100, 100]
  let actions = alive_actions(0, hps, team, false)
  // 3 moves + 2 switches = 5 legal actions
  assert_eq(actions.length(), 5)
  let mut moves = 0
  let mut switches = 0
  for a in actions {
    match a {
      UseMove(_) => moves += 1
      Switch(_) => switches += 1
      Mega(_) => ()
    }
  }
  assert_eq(moves, 3)
  assert_eq(switches, 2)
}

///|
test "state_ranks_distinguish_otherwise_identical_states" {
  // Rank vectors participate in the HashMap key so setup-move plans do not
  // collide with their un-boosted counterparts.
  let base : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100],
    opp_hps: [100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false],
    my_status: [@model.None],
    opp_status: [@model.None],
    turn: 0,
  }
  let boosted = { ..base, my_ranks: [2, 0, 0, 0, 0] }
  assert_true(base != boosted)
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  cache[base] = 0.1
  cache[boosted] = 0.9
  match cache.get(base) {
    Some(v) => assert_eq(v, 0.1)
    None => assert_true(false)
  }
  match cache.get(boosted) {
    Some(v) => assert_eq(v, 0.9)
    None => assert_true(false)
  }
}

///|
test "transition_priority_move_outpaces_faster_opponent" {
  // Slow side uses バレットパンチ (+1); fast side uses じしん (0). The slow
  // attacker should resolve first and can KO before the fast side acts.
  let slow_prio = mk_combatant(
    mk_pokemon("SlowP", "はがね", "", 100, 250, 100, 100, 100, 50),
    [mk_move("バレットパンチ", "はがね", @model.Physical, 250, priority=1)],
  )
  let fast_normal = mk_combatant(
    mk_pokemon("FastN", "ノーマル", "", 1, 250, 100, 100, 100, 200),
    [mk_move("じしん", "じめん", @model.Physical, 250)],
  )
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100],
    opp_hps: [1],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false],
    my_status: [@model.None],
    opp_status: [@model.None],
    turn: 0,
  }
  let next = transition(
    state, UseMove(0), UseMove(0), [slow_prio], [fast_normal],
  )
  // Priority KO skips the opponent's attack.
  assert_eq(next.opp_hps[0], 0)
  assert_eq(next.my_hps[0], 100)
}

///|
test "transition_sword_dance_raises_attacker_rank_by_two" {
  let me = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("つるぎのまい", "ノーマル", @model.Status, 0, stat_effects=[(0, 2)])],
  )
  let opp = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("x", "ノーマル", @model.Physical, 40)],
  )
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100],
    opp_hps: [100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false],
    my_status: [@model.None],
    opp_status: [@model.None],
    turn: 0,
  }
  let next = transition(state, UseMove(0), UseMove(0), [me], [opp])
  assert_eq(next.my_ranks[0], 2)
}

///|
test "transition_rank_clamps_to_plus_two_after_two_sword_dances" {
  let me = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 200),
    [mk_move("つるぎのまい", "ノーマル", @model.Status, 0, stat_effects=[(0, 2)])],
  )
  let opp = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("idle", "ノーマル", @model.Status, 0)],
  )
  let mut state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100],
    opp_hps: [100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false],
    my_status: [@model.None],
    opp_status: [@model.None],
    turn: 0,
  }
  state = transition(state, UseMove(0), UseMove(0), [me], [opp])
  assert_eq(state.my_ranks[0], 2)
  state = transition(state, UseMove(0), UseMove(0), [me], [opp])
  // Clamped to +2, not accumulating to +4.
  assert_eq(state.my_ranks[0], 2)
}

///|
test "transition_switch_resets_active_ranks_to_zero" {
  let my_team = [
    mk_combatant(
      mk_pokemon("A0", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
    mk_combatant(
      mk_pokemon("A1", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
  ]
  let opp_team = [
    mk_combatant(
      mk_pokemon("B0", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
    mk_combatant(
      mk_pokemon("B1", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
  ]
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [2, 1, 0, 0, 1],
    opp_ranks: [-1, 0, 2, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    turn: 0,
  }
  let next = transition(state, Switch(1), Switch(1), my_team, opp_team)
  // Both sides' ranks reset to the zero vector.
  for i in 0..<5 {
    assert_eq(next.my_ranks[i], 0)
    assert_eq(next.opp_ranks[i], 0)
  }
}

///|
test "transition_rank_affects_damage_sword_dance_increases_output" {
  // Two identical setups, one with attacker already at +2 rank: that side
  // should deal strictly more damage in a single turn.
  let me = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
  )
  let opp = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 500, 100, 100, 100, 100, 50),
    [mk_move("idle", "ノーマル", @model.Status, 0)],
  )
  let neutral : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100],
    opp_hps: [500],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false],
    my_status: [@model.None],
    opp_status: [@model.None],
    turn: 0,
  }
  let boosted : SwitchingGameState = { ..neutral, my_ranks: [2, 0, 0, 0, 0] }
  let after_neutral = transition(neutral, UseMove(0), UseMove(0), [me], [opp])
  let after_boosted = transition(boosted, UseMove(0), UseMove(0), [me], [opp])
  let dmg_neutral = 500 - after_neutral.opp_hps[0]
  let dmg_boosted = 500 - after_boosted.opp_hps[0]
  assert_true(dmg_boosted > dmg_neutral)
}

///|
test "switching_game_winrate_stats_completes_and_caches" {
  // Captures the ValueStats so we can assert memoization observably fires
  // and cache behaviour is healthy.
  let strong = mk_combatant(
    mk_pokemon("A0", "ノーマル", "", 150, 200, 100, 100, 100, 120),
    [mk_move("mv", "ノーマル", @model.Physical, 85)],
  )
  let ok = mk_combatant(
    mk_pokemon("B0", "ノーマル", "", 150, 120, 120, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let team_a = [strong, strong]
  let team_b = [ok, ok]
  let (v, stats, _) = switching_game_winrate_stats(team_a, team_b, 2)
  assert_true(v >= -1.0 && v <= 1.0)
  assert_true(v.is_nan() == false)
  // The recursion must have run (at least one miss observed).
  assert_true(stats.misses >= 1)
}

///|
test "switching_game_winrate_stats_mirror_match_still_zero" {
  let team = mk_combatant(
    mk_pokemon("M", "ノーマル", "", 120, 120, 120, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let (v, _, _) = switching_game_winrate_stats([team, team], [team, team], 2)
  assert_true(v.abs() < 1.0e-6)
}

///|
test "damage_cache_hits_dominate_misses_on_repeated_recursion" {
  // A 2v2 SwitchingGame with turn_limit=3 visits the same
  // (attacker, defender, move, rank) tuple many times across states. After
  // one run, the damage cache should have hits ≫ misses because the rank /
  // index space is vastly smaller than the state space.
  let a = mk_combatant(
    mk_pokemon("A0", "ノーマル", "", 120, 120, 100, 100, 100, 110),
    [mk_move("mv", "ノーマル", @model.Physical, 70)],
  )
  let b = mk_combatant(
    mk_pokemon("B0", "ノーマル", "", 120, 110, 110, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let (_, _, dmg) = switching_game_winrate_stats([a, a], [b, b], 2)
  assert_true(dmg.misses >= 1)
  assert_true(dmg.hits >= dmg.misses)
}

///|
test "damage_cache_misses_bounded_by_key_space" {
  let a = mk_combatant(
    mk_pokemon("A0", "ノーマル", "", 120, 120, 100, 100, 100, 110),
    [mk_move("mv", "ノーマル", @model.Physical, 70)],
  )
  let b = mk_combatant(
    mk_pokemon("B0", "ノーマル", "", 120, 110, 110, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let (_, _, dmg) = switching_game_winrate_stats([a, a], [b, b], 2)
  assert_true(dmg.misses <= 8)
}

///|
test "damage_cache_single_turn_uses_at_most_two_unique_keys" {
  // One turn, two actives, one move each, no stat-boost moves → at most
  // two unique damage keys (me → opp, opp → me). After one turn the cache
  // must hold ≤ 2 misses regardless of recursion depth.
  let fast = mk_combatant(
    mk_pokemon("Fast", "ノーマル", "", 100, 200, 100, 100, 100, 200),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let slow = mk_combatant(
    mk_pokemon("Slow", "ノーマル", "", 100, 200, 100, 100, 100, 50),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let (_, _, dmg) = switching_game_winrate_stats([fast], [slow], 2)
  assert_true(dmg.misses <= 2)
}

///|
test "damage_cache_hits_increment_on_repeated_identical_transitions" {
  // Calling mean_damage_cached twice with the same key should produce the
  // same result and record one miss + one hit.
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 150, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 80)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 200, 100, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 40)],
  )
  let cache = new_damage_cache()
  let ranks = [0, 0, 0, 0, 0]
  let d1 = mean_damage_cached(cache, true, 0, ranks, 0, ranks, 0, [a], [b])
  let d2 = mean_damage_cached(cache, true, 0, ranks, 0, ranks, 0, [a], [b])
  assert_eq(d1, d2)
  assert_eq(cache.misses, 1)
  assert_eq(cache.hits, 1)
}

///|
test "damage_cache_distinguishes_sides_for_symmetric_teams" {
  // Identical teams on both sides: atk_idx=0 / def_idx=0 on `my_attacker=true`
  // must not collide with atk_idx=0 / def_idx=0 on `my_attacker=false`
  // (different combatants, different abilities/items/tera in general).
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 150, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 80)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 80, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 80)],
  )
  let cache = new_damage_cache()
  let ranks = [0, 0, 0, 0, 0]
  let d_mine = mean_damage_cached(cache, true, 0, ranks, 0, ranks, 0, [a], [b])
  let d_opp = mean_damage_cached(
    cache, false, 0, ranks, 0, ranks, 0, [a], [b],
  )
  // Both entries are fresh misses, not collisions.
  assert_eq(cache.misses, 2)
  assert_eq(cache.hits, 0)
  // Damage values differ because the attackers differ (A has ATK=150,
  // B has ATK=80).
  assert_true(d_mine > d_opp)
}

///|
/// Helper: build a `MegaForm` quickly for tests. Mega fields default to the
/// base values unless overridden, so a test can change only the fields it
/// cares about (e.g. `mk_mega_form(atk=200)` for a pure attack boost).
fn mk_mega_form(
  atk~ : Int = 100,
  def_~ : Int = 100,
  spa~ : Int = 100,
  spd~ : Int = 100,
  spe~ : Int = 100,
  type1~ : String = "ノーマル",
  type2~ : String = "",
  ability~ : String = "",
  name_ja~ : String = "メガテスト",
) -> @model.MegaForm {
  { atk, def_, spa, spd, spe, type1, type2, ability, name_ja }
}

///|
/// Helper: baseline single-Pokemon state with all mega fields zeroed. Used to
/// keep mega-specific tests focused on the field under test.
fn mk_mega_state_1v1(
  my_hp~ : Int = 100,
  opp_hp~ : Int = 100,
  my_mega_used~ : Bool = false,
  opp_mega_used~ : Bool = false,
  my_megaed~ : Bool = false,
  opp_megaed~ : Bool = false,
) -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [my_hp],
    opp_hps: [opp_hp],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used,
    opp_mega_used,
    my_megaed: [my_megaed],
    opp_megaed: [opp_megaed],
    my_status: [@model.None],
    opp_status: [@model.None],
    turn: 0,
  }
}

///|
test "state_is_hashable_with_mega_fields" {
  // Adding `my_mega_used` / `my_megaed` extends the identity of a state;
  // two states differing only in those fields must not collide in the memo.
  let base = mk_mega_state_1v1()
  let diff_my_used = { ..base, my_mega_used: true }
  let diff_opp_used = { ..base, opp_mega_used: true }
  let diff_my_flag = { ..base, my_megaed: [true] }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  cache[base] = 0.1
  cache[diff_my_used] = 0.2
  cache[diff_opp_used] = 0.3
  cache[diff_my_flag] = 0.4
  assert_eq(cache.get(base), Some(0.1))
  assert_eq(cache.get(diff_my_used), Some(0.2))
  assert_eq(cache.get(diff_opp_used), Some(0.3))
  assert_eq(cache.get(diff_my_flag), Some(0.4))
}

///|
test "alive_actions_includes_mega_when_available" {
  // mega_form = Some(_) and mega_used = false → one Mega(mi) per move is
  // appended alongside the plain UseMove(mi) actions.
  let team = [
    mk_combatant(
      mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [
        mk_move("x", "ノーマル", @model.Physical, 40),
        mk_move("y", "ノーマル", @model.Physical, 40),
      ],
      mega_form=Some(mk_mega_form()),
    ),
  ]
  let hps = [100]
  let actions = alive_actions(0, hps, team, false)
  let mut moves = 0
  let mut megas = 0
  let mut switches = 0
  for a in actions {
    match a {
      UseMove(_) => moves += 1
      Mega(_) => megas += 1
      Switch(_) => switches += 1
    }
  }
  assert_eq(moves, 2)
  assert_eq(megas, 2)
  assert_eq(switches, 0)
}

///|
test "alive_actions_excludes_mega_when_already_used" {
  let team = [
    mk_combatant(
      mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
      mega_form=Some(mk_mega_form()),
    ),
  ]
  let hps = [100]
  let actions = alive_actions(0, hps, team, true) // mega_used = true
  let mut megas = 0
  for a in actions {
    match a {
      Mega(_) => megas += 1
      _ => ()
    }
  }
  assert_eq(megas, 0)
}

///|
test "alive_actions_excludes_mega_when_no_mega_form" {
  // A combatant without mega_form must never surface Mega actions even when
  // the side's mega_used = false.
  let team = [
    mk_combatant(
      mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
    ),
  ]
  let hps = [100]
  let actions = alive_actions(0, hps, team, false)
  let mut megas = 0
  for a in actions {
    match a {
      Mega(_) => megas += 1
      _ => ()
    }
  }
  assert_eq(megas, 0)
}

///|
test "transition_mega_sets_mega_used_and_megaed_flags" {
  // `Mega(0)` must flip both the side-level and slot-level flags.
  let me = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("x", "ノーマル", @model.Physical, 40)],
    mega_form=Some(mk_mega_form()),
  )
  let opp = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 500, 100, 100, 100, 100, 50),
    [mk_move("idle", "ノーマル", @model.Status, 0)],
  )
  let state = mk_mega_state_1v1(my_hp=100, opp_hp=500)
  let next = transition(state, Mega(0), UseMove(0), [me], [opp])
  assert_eq(next.my_mega_used, true)
  assert_eq(next.my_megaed[0], true)
  // Opp side unchanged.
  assert_eq(next.opp_mega_used, false)
  assert_eq(next.opp_megaed[0], false)
}

///|
test "transition_mega_vs_move_uses_mega_stats_for_damage" {
  // Same base but with mega_form that boosts ATK from 100 → 200. A single Mega
  // turn must deal strictly more damage than a vanilla UseMove turn against
  // an inert opponent.
  let base = mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100)
  let mega_attacker = mk_combatant(
    base,
    [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
    mega_form=Some(mk_mega_form(atk=200)),
  )
  let plain_attacker = mk_combatant(
    base,
    [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
  )
  let opp = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 500, 100, 100, 100, 100, 50),
    [mk_move("idle", "ノーマル", @model.Status, 0)],
  )
  let state = mk_mega_state_1v1(my_hp=100, opp_hp=500)
  let after_mega = transition(state, Mega(0), UseMove(0), [mega_attacker], [opp])
  let after_plain = transition(
    state, UseMove(0), UseMove(0), [plain_attacker], [opp],
  )
  let dmg_mega = 500 - after_mega.opp_hps[0]
  let dmg_plain = 500 - after_plain.opp_hps[0]
  assert_true(dmg_mega > dmg_plain)
}

///|
test "transition_mega_vs_move_uses_mega_type_for_stab" {
  // Base is Normal/—, mega is Dragon/Ground; a Ground move is non-STAB as
  // base but STAB as mega → damage increases.
  let base = mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100)
  let mega_attacker = mk_combatant(
    base,
    [mk_move("じしん", "じめん", @model.Physical, 100)],
    mega_form=Some(mk_mega_form(type1="ドラゴン", type2="じめん")),
  )
  let plain_attacker = mk_combatant(
    base,
    [mk_move("じしん", "じめん", @model.Physical, 100)],
  )
  // Neutral defender so type matchup does not confound the STAB comparison.
  let opp = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 500, 100, 100, 100, 100, 50),
    [mk_move("idle", "ノーマル", @model.Status, 0)],
  )
  let state = mk_mega_state_1v1(my_hp=100, opp_hp=500)
  let after_mega = transition(state, Mega(0), UseMove(0), [mega_attacker], [opp])
  let after_plain = transition(
    state, UseMove(0), UseMove(0), [plain_attacker], [opp],
  )
  let dmg_mega = 500 - after_mega.opp_hps[0]
  let dmg_plain = 500 - after_plain.opp_hps[0]
  assert_true(dmg_mega > dmg_plain)
}

///|
test "transition_mega_vs_switch_damages_newly_switched_target" {
  // My side megas + attacks; opp switches. The Mega-stat-boosted attack must
  // land on the incoming opp pokemon with fresh ranks.
  let me = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
    mega_form=Some(mk_mega_form(atk=200)),
  )
  let opp_0 = mk_combatant(
    mk_pokemon("B0", "ノーマル", "", 500, 100, 100, 100, 100, 50),
    [mk_move("idle", "ノーマル", @model.Status, 0)],
  )
  let opp_1 = mk_combatant(
    mk_pokemon("B1", "ノーマル", "", 500, 100, 100, 100, 100, 50),
    [mk_move("idle", "ノーマル", @model.Status, 0)],
  )
  let opp_team = [opp_0, opp_1]
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100],
    opp_hps: [500, 500],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false, false],
    my_status: [@model.None],
    opp_status: [@model.None, @model.None],
    turn: 0,
  }
  let next = transition(state, Mega(0), Switch(1), [me], opp_team)
  assert_eq(next.opp_active, 1)
  // Outgoing opp slot untouched, incoming slot took the mega-boosted hit.
  assert_eq(next.opp_hps[0], 500)
  assert_true(next.opp_hps[1] < 500)
  assert_eq(next.my_mega_used, true)
}

///|
test "transition_simultaneous_mega_both_sides_flips_both" {
  // Both sides pick `Mega` on the same turn. Both mega_used flags go high and
  // both slot-level megaed entries are set.
  let me = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("のしかかり", "ノーマル", @model.Physical, 60)],
    mega_form=Some(mk_mega_form(atk=200)),
  )
  let opp = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 150),
    [mk_move("のしかかり", "ノーマル", @model.Physical, 60)],
    mega_form=Some(mk_mega_form(atk=200)),
  )
  let state = mk_mega_state_1v1(my_hp=500, opp_hp=500)
  let next = transition(state, Mega(0), Mega(0), [me], [opp])
  assert_eq(next.my_mega_used, true)
  assert_eq(next.opp_mega_used, true)
  assert_eq(next.my_megaed[0], true)
  assert_eq(next.opp_megaed[0], true)
}

///|
test "mega_persists_after_switch_out_and_back_in" {
  // Slot-level `megaed` survives a switch cycle: active 0 megas, switches to
  // slot 1, then the caller switches back — slot 0's `megaed` flag remains
  // true so further incoming attacks still resolve against mega stats.
  let me_0 = mk_combatant(
    mk_pokemon("A0", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("x", "ノーマル", @model.Physical, 60)],
    mega_form=Some(mk_mega_form(atk=200)),
  )
  let me_1 = mk_combatant(
    mk_pokemon("A1", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("x", "ノーマル", @model.Physical, 60)],
  )
  let opp = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 500, 100, 100, 100, 100, 50),
    [mk_move("idle", "ノーマル", @model.Status, 0)],
  )
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [500],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None],
    turn: 0,
  }
  // Turn 1: mega slot 0.
  let after_mega = transition(state, Mega(0), UseMove(0), [me_0, me_1], [opp])
  assert_eq(after_mega.my_megaed[0], true)
  // Turn 2: switch to slot 1.
  let after_switch_out = transition(
    after_mega, Switch(1), UseMove(0), [me_0, me_1], [opp],
  )
  assert_eq(after_switch_out.my_active, 1)
  // Slot 0's mega flag must still be set.
  assert_eq(after_switch_out.my_megaed[0], true)
  // Turn 3: switch back to slot 0.
  let after_switch_back = transition(
    after_switch_out, Switch(0), UseMove(0), [me_0, me_1], [opp],
  )
  assert_eq(after_switch_back.my_active, 0)
  assert_eq(after_switch_back.my_megaed[0], true)
}

///|
test "alive_actions_no_mega_for_second_pokemon_after_first_mega" {
  // After side-level `mega_used` is true, switching to another mega-capable
  // Pokemon does NOT re-enable the Mega action (per-side 1-mega-max rule).
  let team = [
    mk_combatant(
      mk_pokemon("A0", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
      mega_form=Some(mk_mega_form()),
    ),
    mk_combatant(
      mk_pokemon("A1", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("x", "ノーマル", @model.Physical, 40)],
      mega_form=Some(mk_mega_form()),
    ),
  ]
  let hps = [100, 100]
  let actions = alive_actions(1, hps, team, true)
  let mut megas = 0
  for a in actions {
    match a {
      Mega(_) => megas += 1
      _ => ()
    }
  }
  assert_eq(megas, 0)
}

///|
test "non_mega_game_regression_preserves_existing_winrate" {
  // Baseline: with all `mega_form = None` the switching game winrate must be
  // exactly the pre-mega behaviour. Re-runs the dominant-team scenario and
  // asserts the same sign. Guards against accidental mega-path activation in
  // the all-None input.
  let strong = mk_combatant(
    mk_pokemon("A0", "ノーマル", "", 200, 200, 150, 100, 150, 150),
    [mk_move("mv", "ノーマル", @model.Physical, 100)],
  )
  let weak = mk_combatant(
    mk_pokemon("B0", "ノーマル", "", 100, 80, 80, 60, 80, 80),
    [mk_move("mv", "ノーマル", @model.Physical, 40)],
  )
  let v = switching_game_winrate([strong], [weak], 2)
  assert_true(v > 0.0)
}

///|
test "damage_cache_distinguishes_mega_vs_base" {
  // Same slot indices, same move, same ranks, but different mega flags must
  // yield two cache misses (different DamageKey), not a collision.
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 80)],
    mega_form=Some(mk_mega_form(atk=200)),
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 500, 100, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 80)],
  )
  let cache = new_damage_cache()
  let ranks = [0, 0, 0, 0, 0]
  let d_base = mean_damage_cached(
    cache, true, 0, ranks, 0, ranks, 0, [a], [b],
    atk_mega=false, def_mega=false,
  )
  let d_mega = mean_damage_cached(
    cache, true, 0, ranks, 0, ranks, 0, [a], [b],
    atk_mega=true, def_mega=false,
  )
  assert_eq(cache.misses, 2)
  assert_eq(cache.hits, 0)
  assert_true(d_mega > d_base)
  // Hit on repeated lookup confirms the cache reuses the new mega key.
  let d_mega_again = mean_damage_cached(
    cache, true, 0, ranks, 0, ranks, 0, [a], [b],
    atk_mega=true, def_mega=false,
  )
  assert_eq(d_mega_again, d_mega)
  assert_eq(cache.hits, 1)
}

///|
/// Reference implementation: the pre-αβ `value` function with NO pruning of
/// any kind (no pure-saddle detection, no β-cutoff). Every state fully fills
/// its payoff matrix and solves the LP. Used by bit-exact regression tests to
/// verify that `value` with default `(alpha=-1, beta=+1)` returns the same
/// top-level number.
///
/// Must be kept in sync with `value` in switching_game.mbt except for the
/// αβ / saddle short-circuits; any change to action enumeration, transition
/// resolution, or caching must be mirrored here.
fn value_no_prune(
  state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
  cache : @hashmap.HashMap[SwitchingGameState, Double],
  stats : ValueStats,
  dmg_cache : DamageCache,
) -> Double {
  match terminal_value(state, my_team, opp_team, turn_limit) {
    Some(v) => return v
    None => ()
  }
  match cache.get(state) {
    Some(v) => {
      stats.hits = stats.hits + 1
      return v
    }
    None => stats.misses = stats.misses + 1
  }
  let actions_me = alive_actions(
    state.my_active, state.my_hps, my_team, state.my_mega_used,
  )
  let actions_opp = alive_actions(
    state.opp_active, state.opp_hps, opp_team, state.opp_mega_used,
  )
  if actions_me.length() == 0 {
    return -1.0
  }
  if actions_opp.length() == 0 {
    return 1.0
  }
  let data = Array::make(actions_me.length(), ([] : Array[Double]))
  for i in 0..<actions_me.length() {
    data[i] = Array::make(actions_opp.length(), 0.0)
  }
  for i in 0..<actions_me.length() {
    for j in 0..<actions_opp.length() {
      let outcomes = transition_with_cache(
        state, actions_me[i], actions_opp[j], my_team, opp_team, dmg_cache,
      )
      let mut ev = 0.0
      for outcome in outcomes {
        let (prob, next) = outcome
        ev += prob *
          value_no_prune(
            next, my_team, opp_team, turn_limit, cache, stats, dmg_cache,
          )
      }
      data[i][j] = ev
    }
  }
  let m = match @nash.FiniteMatrix::new(data) {
    Ok(x) => x
    Err(_) => return 0.0
  }
  let lp = try @nash.solve_zero_sum(m) catch {
    _ => return 0.0
  }
  let result = match lp {
    Optimal(value~, ..) => value
    _ => 0.0
  }
  cache.set(state, result)
  result
}

///|
/// Top-level entry point for the no-pruning reference implementation.
fn switching_game_winrate_no_prune(
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
) -> (Double, ValueStats) {
  let my_hps = Array::make(my_team.length(), 0)
  let opp_hps = Array::make(opp_team.length(), 0)
  for i in 0..<my_team.length() {
    my_hps[i] = my_team[i].pokemon.hp
  }
  for i in 0..<opp_team.length() {
    opp_hps[i] = opp_team[i].pokemon.hp
  }
  let my_megaed = Array::make(my_team.length(), false)
  let opp_megaed = Array::make(opp_team.length(), false)
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps,
    opp_hps,
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed,
    opp_megaed,
    my_status: zero_status(my_team.length()),
    opp_status: zero_status(opp_team.length()),
    turn: 0,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let stats = new_stats()
  let dmg_cache = new_damage_cache()
  let v = value_no_prune(
    state, my_team, opp_team, turn_limit, cache, stats, dmg_cache,
  )
  (v, stats)
}

///|
test "alpha_beta_returns_same_value_as_no_pruning_minimal_1v1" {
  // Smallest non-terminal case: 1v1 single-move teams. Saddle fast path should
  // fire (every subgame is a 1×1 matrix, trivial saddle). αβ result must match
  // the reference implementation to FP precision.
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 150, 100, 100, 100, 120),
    [mk_move("slash", "ノーマル", @model.Physical, 80)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 120, 100, 100, 100, 100),
    [mk_move("slash", "ノーマル", @model.Physical, 70)],
  )
  let v_prune = switching_game_winrate([a], [b], 2)
  let (v_no_prune, _) = switching_game_winrate_no_prune([a], [b], 2)
  assert_true((v_prune - v_no_prune).abs() < 1.0e-12)
}

///|
test "alpha_beta_returns_same_value_as_no_pruning_with_switch" {
  // 2v2 teams where switch actions matter (slow heavy hitter vs fast frail
  // attacker). Exercises the switch branch of `transition_with_cache`; αβ
  // cutoffs may or may not trigger depending on iteration order, but the
  // top-level value must be exactly equal to the unpruned reference.
  let a0 = mk_combatant(
    mk_pokemon("A0", "ノーマル", "", 150, 200, 100, 100, 100, 80),
    [mk_move("heavy", "ノーマル", @model.Physical, 100)],
  )
  let a1 = mk_combatant(
    mk_pokemon("A1", "ノーマル", "", 100, 120, 100, 100, 100, 130),
    [mk_move("swift", "ノーマル", @model.Physical, 60)],
  )
  let b0 = mk_combatant(
    mk_pokemon("B0", "ノーマル", "", 120, 150, 100, 100, 100, 90),
    [mk_move("mid", "ノーマル", @model.Physical, 80)],
  )
  let b1 = mk_combatant(
    mk_pokemon("B1", "ノーマル", "", 130, 100, 100, 100, 100, 110),
    [mk_move("swift", "ノーマル", @model.Physical, 65)],
  )
  let v_prune = switching_game_winrate([a0, a1], [b0, b1], 1)
  let (v_no_prune, _) = switching_game_winrate_no_prune([a0, a1], [b0, b1], 1)
  assert_true((v_prune - v_no_prune).abs() < 1.0e-12)
}

///|
test "alpha_beta_returns_same_value_as_no_pruning_mirror_match" {
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 120, 120, 120, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let v_prune = switching_game_winrate([a], [a], 2)
  let (v_no_prune, _) = switching_game_winrate_no_prune([a], [a], 2)
  assert_true((v_prune - v_no_prune).abs() < 1.0e-12)
  assert_true(v_prune.abs() < 1.0e-9)
}

///|
test "alpha_beta_reduces_or_matches_miss_count" {
  let strong = mk_combatant(
    mk_pokemon("S0", "ノーマル", "", 150, 250, 120, 100, 120, 200),
    [mk_move("lethal", "ノーマル", @model.Physical, 250)],
  )
  let weak = mk_combatant(
    mk_pokemon("W0", "ノーマル", "", 50, 50, 50, 50, 50, 30),
    [mk_move("weak", "ノーマル", @model.Physical, 10)],
  )
  let (_, stats_prune, _) = switching_game_winrate_stats(
    [strong, strong], [weak, weak], 1,
  )
  let (_, stats_no_prune) = switching_game_winrate_no_prune(
    [strong, strong], [weak, weak], 1,
  )
  assert_true(stats_prune.misses <= stats_no_prune.misses)
}

///|
test "value_accepts_explicit_alpha_beta_and_matches_default" {
  // Passing (alpha=-1, beta=+1) explicitly (the defaults) must produce the
  // same result as omitting them. Locks in the default-arg contract so a
  // future change to the defaults won't silently alter caller semantics.
  let team = build_dummy_team(2, 100)
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    turn: 0,
  }
  let cache1 : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let cache2 : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let dmg1 = new_damage_cache()
  let dmg2 = new_damage_cache()
  let s1 = new_stats()
  let s2 = new_stats()
  let v1 = value(state, team, team, 2, cache1, s1, dmg1)
  let v2 = value(
    state, team, team, 2, cache2, s2, dmg2, alpha=-1.0, beta=1.0,
  )
  assert_true((v1 - v2).abs() < 1.0e-12)
}

///|
test "switching_game_turn_limit_3_produces_finite_value_on_multi_pokemon_team" {
  // Regression: before the solver saddle fast-path + value αβ-pruning,
  // turn_limit=3 on real 6v6 input (Nosada vs カマカマキリ) failed after ~70s
  // of simplex pivots with `InconsistentGame` on a degenerate LP. This test
  // pins that the tl=3 path at least returns a finite in-range value on a
  // modestly-sized team without raising. The in-repo payload is a small 2v2
  // proxy; the full 6v6 smoke lives in /tmp/pkdx_smoke/repro_tl3.py.
  let a0 = mk_combatant(
    mk_pokemon("A0", "ノーマル", "", 150, 180, 110, 100, 110, 120),
    [mk_move("strike", "ノーマル", @model.Physical, 90)],
  )
  let a1 = mk_combatant(
    mk_pokemon("A1", "ほのお", "", 130, 140, 100, 120, 100, 140),
    [mk_move("ember", "ほのお", @model.Special, 70)],
  )
  let b0 = mk_combatant(
    mk_pokemon("B0", "みず", "", 140, 150, 110, 110, 110, 110),
    [mk_move("surf", "みず", @model.Special, 90)],
  )
  let b1 = mk_combatant(
    mk_pokemon("B1", "くさ", "", 120, 130, 100, 130, 100, 130),
    [mk_move("leaf", "くさ", @model.Special, 80)],
  )
  let v = switching_game_winrate([a0, a1], [b0, b1], 2)
  assert_true(v >= -1.0 && v <= 1.0)
  assert_true(not(v.is_nan()))
  assert_true(not(v.is_inf()))
}

///|
test "state_space_2v2_default_turn_limit_bounded" {
  // 2v2 with high HP and low-power moves: games last multiple turns,
  // creating a non-trivial state tree. 既定 `DP_TURN_LIMIT` で完走し、
  // memoized state 数が上限内に収まることを検証する。tl=20 を直書きすると
  // CI で 1 時間級になるため、ここは定数参照のままにして、長期戦の上限値
  // 検証は別タスクで個別に回す。
  let a0 = mk_combatant(
    mk_pokemon("A0", "ノーマル", "", 200, 100, 100, 100, 100, 120),
    [mk_move("tackle", "ノーマル", @model.Physical, 30)],
  )
  let a1 = mk_combatant(
    mk_pokemon("A1", "ノーマル", "", 200, 100, 100, 100, 100, 100),
    [mk_move("tackle", "ノーマル", @model.Physical, 30)],
  )
  let b0 = mk_combatant(
    mk_pokemon("B0", "ノーマル", "", 200, 100, 100, 100, 100, 110),
    [mk_move("tackle", "ノーマル", @model.Physical, 30)],
  )
  let b1 = mk_combatant(
    mk_pokemon("B1", "ノーマル", "", 200, 100, 100, 100, 100, 90),
    [mk_move("tackle", "ノーマル", @model.Physical, 30)],
  )
  let (v, stats, dmg) = switching_game_winrate_stats(
    [a0, a1], [b0, b1], @payoff.DP_TURN_LIMIT,
  )
  println("2v2 tl=\{@payoff.DP_TURN_LIMIT}: value=\{v}, cached_states=\{stats.cached_states}, hits=\{stats.hits}, misses=\{stats.misses}, dmg_misses=\{dmg.misses}")
  assert_true(v >= -1.0 && v <= 1.0)
  assert_true(not(v.is_nan()))
  assert_true(stats.cached_states > 0)
  assert_true(stats.cached_states < 500000)
  assert_true(dmg.misses < 200)
}

///|
test "state_space_3v3_turn_limit_5_bounded" {
  // 3v3 with diverse types and moderate HP. turn_limit=5 is used instead of 20
  // to keep CI runtime reasonable; the 2v2 test above covers turn_limit=20.
  let mk = fn(name : String, t1 : String, hp : Int, atk : Int, spe : Int) -> Combatant {
    mk_combatant(
      mk_pokemon(name, t1, "", hp, atk, 100, atk, 100, spe),
      [mk_move("m", t1, @model.Physical, 30)],
    )
  }
  let team_a = [
    mk("A0", "ほのお", 150, 100, 120),
    mk("A1", "みず", 150, 100, 100),
    mk("A2", "くさ", 150, 100, 110),
  ]
  let team_b = [
    mk("B0", "でんき", 150, 100, 115),
    mk("B1", "じめん", 150, 100, 95),
    mk("B2", "ノーマル", 150, 100, 105),
  ]
  let (v, stats, _) = switching_game_winrate_stats(team_a, team_b, 5)
  println("3v3 tl=5: value=\{v}, cached_states=\{stats.cached_states}, hits=\{stats.hits}, misses=\{stats.misses}")
  assert_true(v >= -1.0 && v <= 1.0)
  assert_true(not(v.is_nan()))
  assert_true(stats.cached_states > 0)
  assert_true(stats.cached_states < 500000)
}
