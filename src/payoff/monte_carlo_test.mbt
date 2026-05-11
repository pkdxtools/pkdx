///|
/// Tests for the shared Monte Carlo rollout helpers (`seed_to_bytes`,
/// `seeded_rng`, `pick_best_move`, `rollout_pick_move`). The standalone
/// pairwise simulator (`simulate_battle` / `monte_carlo_winrate`) and the
/// `from_combatants(MonteCarloSim)` matrix builder have been removed.

///|
test "seed_to_bytes_encodes_uint64_little_endian_with_zero_padding" {
  let b = seed_to_bytes(0x0102030405060708UL)
  assert_eq(b.length(), 32)
  assert_eq(b[0], b'\x08')
  assert_eq(b[1], b'\x07')
  assert_eq(b[2], b'\x06')
  assert_eq(b[3], b'\x05')
  assert_eq(b[4], b'\x04')
  assert_eq(b[5], b'\x03')
  assert_eq(b[6], b'\x02')
  assert_eq(b[7], b'\x01')
  for i in 8..<32 {
    assert_eq(b[i], b'\x00')
  }
}

///|
test "rand_chacha8_accepts_32_byte_seed_and_produces_output" {
  let rng = seeded_rng(0UL)
  let n = rng.int(limit=100)
  assert_true(n >= 0 && n < 100)
}

///|
test "seeded_rng_same_seed_same_int_sequence" {
  let rng1 = seeded_rng(42UL)
  let rng2 = seeded_rng(42UL)
  for _ in 0..<16 {
    assert_eq(rng1.int(limit=16), rng2.int(limit=16))
  }
}

///|
test "seeded_rng_different_seeds_yield_different_sequences" {
  let rng1 = seeded_rng(1UL)
  let rng2 = seeded_rng(2UL)
  let mut diff = 0
  for _ in 0..<100 {
    if rng1.int(limit=16) != rng2.int(limit=16) {
      diff += 1
    }
  }
  assert_true(diff >= 80)
}

///|
test "seeded_rng_int_output_within_range" {
  let rng = seeded_rng(123UL)
  for _ in 0..<1000 {
    let n = rng.int(limit=16)
    assert_true(n >= 0 && n < 16)
  }
}

///|
test "pick_best_move_selects_highest_average_damage_and_excludes_power_zero" {
  let atk = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 150, 100, 100, 100, 100),
    [
      mk_move("status", "ノーマル", @model.Status, 0),
      mk_move("weak", "ノーマル", @model.Physical, 40),
      mk_move("strong", "ノーマル", @model.Physical, 120),
    ],
  )
  let dfn = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("anything", "ノーマル", @model.Physical, 80)],
  )
  match pick_best_move(atk, dfn) {
    Some(idx) => assert_eq(idx, 2)
    None => assert_true(false)
  }
}

///|
test "rollout_pick_move_epsilon_one_samples_uniformly_across_all_moves" {
  let atk = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [
      mk_move("つるぎのまい", "ノーマル", @model.Status, 0, stat_effects=[@model.StatEffect::{ stat: 0, delta: 2, target: 0 }]),
      mk_move("weak", "ノーマル", @model.Physical, 40),
      mk_move("strong", "ノーマル", @model.Physical, 120),
    ],
  )
  let dfn = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("x", "ノーマル", @model.Physical, 80)],
  )
  let rng = seeded_rng(123UL)
  let seen = Array::make(3, false)
  for _ in 0..<50 {
    match rollout_pick_move(atk, dfn, rng, 1.0) {
      Some(i) => seen[i] = true
      None => assert_true(false)
    }
  }
  for s in seen {
    assert_true(s)
  }
}

///|
test "rollout_pick_move_epsilon_zero_always_picks_greedy_damaging_move" {
  let atk = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 150, 100, 100, 100, 100),
    [
      mk_move("つるぎのまい", "ノーマル", @model.Status, 0, stat_effects=[@model.StatEffect::{ stat: 0, delta: 2, target: 0 }]),
      mk_move("weak", "ノーマル", @model.Physical, 40),
      mk_move("strong", "ノーマル", @model.Physical, 120),
    ],
  )
  let dfn = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("x", "ノーマル", @model.Physical, 80)],
  )
  let rng = seeded_rng(456UL)
  for _ in 0..<20 {
    match rollout_pick_move(atk, dfn, rng, 0.0) {
      Some(i) => assert_eq(i, 2)
      None => assert_true(false)
    }
  }
}

///|
test "rollout_pick_move_status_only_moveset_still_returns_some" {
  let atk = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [
      mk_move("つるぎのまい", "ノーマル", @model.Status, 0, stat_effects=[@model.StatEffect::{ stat: 0, delta: 2, target: 0 }]),
      mk_move("りゅうのまい", "ノーマル", @model.Status, 0, stat_effects=[@model.StatEffect::{ stat: 0, delta: 1, target: 0 }, @model.StatEffect::{ stat: 4, delta: 1, target: 0 }]),
    ],
  )
  let dfn = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("x", "ノーマル", @model.Physical, 80)],
  )
  let rng = seeded_rng(789UL)
  match rollout_pick_move(atk, dfn, rng, 0.0) {
    Some(i) => assert_true(i >= 0 && i < 2)
    None => assert_true(false)
  }
}
