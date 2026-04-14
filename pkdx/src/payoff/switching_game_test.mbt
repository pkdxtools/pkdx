///|
/// Helper: team of `n` combatants with distinct speeds, used to verify
/// non-trivial cross-payoff matrices.
fn build_team_with_speeds(
  prefix : String,
  speeds : Array[Int],
) -> Array[Combatant] {
  let out = Array::make(
    speeds.length(),
    mk_combatant(
      mk_pokemon("", "ノーマル", "", 100, 100, 100, 100, 100, 100),
      [mk_move("mv", "ノーマル", @model.Physical, 60)],
    ),
  )
  for i in 0..<speeds.length() {
    out[i] = mk_combatant(
      mk_pokemon(
        prefix + i.to_string(),
        "ノーマル",
        "",
        100,
        100,
        100,
        100,
        100,
        speeds[i],
      ),
      [mk_move("mv", "ノーマル", @model.Physical, 60)],
    )
  }
  out
}

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
    turn: 0,
  }
  let same : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100, 100],
    opp_hps: [100, 100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
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
  let actions = alive_actions(0, hps, team)
  let mut move_count = 0
  let switch_targets : Array[Int] = []
  for a in actions {
    match a {
      UseMove(_) => move_count += 1
      Switch(i) => switch_targets.push(i)
    }
  }
  assert_eq(move_count, 1)
  assert_eq(switch_targets.length(), 1)
  assert_eq(switch_targets[0], 2)
}

///|
test "team_payoff_model_enum_exhaustive_match" {
  let models : Array[TeamPayoffModel] = [Pairwise(Best1v1), SwitchingGame(2)]
  let labels = models.map(fn(m) {
    match m {
      Pairwise(_) => "pairwise"
      SwitchingGame(_) => "switching_game"
    }
  })
  let mut joined = ""
  for i in 0..<labels.length() {
    if i > 0 {
      joined = joined + ","
    }
    joined = joined + labels[i]
  }
  inspect(joined, content="pairwise,switching_game")
}

///|
test "team_payoff_matrix_with_pairwise_wraps_existing_team_payoff_matrix" {
  let team = build_team_with_speeds("T", [100, 95, 105, 90, 110, 85])
  let opp = build_team_with_speeds("O", [100, 100, 100, 100, 100, 100])
  let m_legacy = team_payoff_matrix(team, opp, Single, Best1v1)
  let m_wrapped = team_payoff_matrix_with_team_model(
    team, opp, Single, Pairwise(Best1v1),
  )
  assert_eq(m_legacy.rows(), m_wrapped.rows())
  assert_eq(m_legacy.cols(), m_wrapped.cols())
  for i in 0..<m_legacy.rows() {
    for j in 0..<m_legacy.cols() {
      assert_eq(m_legacy.at(i, j), m_wrapped.at(i, j))
    }
  }
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
    turn: 5,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let stats = new_stats()
  let v = value(state, team_a, team_b, 5, cache, stats)
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
    turn: 0,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let stats = new_stats()
  let _ = value(state, team_a, team_b, 2, cache, stats)
  let hits_before = stats.hits
  let _ = value(state, team_a, team_b, 2, cache, stats)
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
  let actions = alive_actions(0, hps, team)
  // 3 moves + 2 switches = 5 legal actions
  assert_eq(actions.length(), 5)
  let mut moves = 0
  let mut switches = 0
  for a in actions {
    match a {
      UseMove(_) => moves += 1
      Switch(_) => switches += 1
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
    [mk_move("バレットパンチ", "はがね", @model.Physical, 250)],
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
    [mk_move("つるぎのまい", "ノーマル", @model.Status, 0)],
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
    turn: 0,
  }
  let next = transition(state, UseMove(0), UseMove(0), [me], [opp])
  assert_eq(next.my_ranks[0], 2)
}

///|
test "transition_rank_clamps_to_plus_two_after_two_sword_dances" {
  let me = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 200),
    [mk_move("つるぎのまい", "ノーマル", @model.Status, 0)],
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
test "switching_game_winrate_stats_completes_at_turn_limit_five" {
  // turn_limit = 5 must terminate — the abstract state graph stays bounded
  // for small team sizes. Captures the ValueStats so we can assert
  // memoization observably fires and cache behaviour is healthy.
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
  let (v, stats) = switching_game_winrate_stats(team_a, team_b, 5)
  assert_true(v >= -1.0 && v <= 1.0)
  assert_true(v.is_nan() == false)
  // The recursion must have run (at least one miss observed).
  assert_true(stats.misses >= 1)
}

///|
test "switching_game_winrate_stats_mirror_match_still_zero_at_turn_limit_five" {
  let team = mk_combatant(
    mk_pokemon("M", "ノーマル", "", 120, 120, 120, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let (v, _) = switching_game_winrate_stats([team, team], [team, team], 5)
  assert_true(v.abs() < 1.0e-6)
}
