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
  // seeded_rng wraps Rand::chacha8 with a 32-byte seed; it must not abort.
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
test "simulate_battle_single_turn_ko_returns_one_for_attacker_victory" {
  // Attacker: huge power + speed. Defender: HP 1 → certain one-shot KO.
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 200, 100, 100, 100, 150),
    [mk_move("strong", "ノーマル", @model.Physical, 250)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 1, 50, 50, 50, 50, 50),
    [mk_move("weak", "ノーマル", @model.Physical, 1)],
  )
  let rng = seeded_rng(0UL)
  assert_eq(simulate_battle(a, b, rng), 1.0)
}

///|
test "simulate_battle_speed_determines_first_attacker" {
  // Identical attack/defense, only speed differs. Mutually lethal moves → the
  // faster side KOs first and wins.
  let fast = mk_combatant(
    mk_pokemon("Fast", "ノーマル", "", 100, 200, 100, 100, 100, 200),
    [mk_move("lethal", "ノーマル", @model.Physical, 250)],
  )
  let slow = mk_combatant(
    mk_pokemon("Slow", "ノーマル", "", 100, 200, 100, 100, 100, 50),
    [mk_move("lethal", "ノーマル", @model.Physical, 250)],
  )
  let rng = seeded_rng(42UL)
  assert_eq(simulate_battle(fast, slow, rng), 1.0)
}

///|
test "simulate_battle_hits_safety_turn_limit_when_no_damage_dealt" {
  // Both sides only have status moves → no HP change → turn_limit → draw.
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("status_a", "ノーマル", @model.Status, 0)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("status_b", "ノーマル", @model.Status, 0)],
  )
  let rng = seeded_rng(0UL)
  assert_eq(simulate_battle(a, b, rng, turn_limit=10), 0.5)
}

///|
test "monte_carlo_winrate_matches_best1v1_on_sure_ko_matchup" {
  // A is fast, high ATK, with a lethal move; B is HP 1 with negligible ATK.
  // Best1v1 = 1.0 is certain; MC should converge to ≈ 1.0 within ±0.05.
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 150, 250, 100, 100, 100, 200),
    [mk_move("lethal", "ノーマル", @model.Physical, 250)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 1, 50, 50, 50, 50, 50),
    [mk_move("flick", "ノーマル", @model.Physical, 1)],
  )
  let mc = monte_carlo_winrate(a, b, 1000, 42UL)
  assert_true((mc - 1.0).abs() < 0.05)
}

///|
test "monte_carlo_winrate_in_close_matchup_stays_in_valid_range" {
  // Mirror combatants — MC value can fall anywhere in [0, 1] but must be
  // finite and within bounds.
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 120, 100, 100, 100, 100, 100),
    [mk_move("mid", "ノーマル", @model.Physical, 60)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 120, 100, 100, 100, 100, 100),
    [mk_move("mid", "ノーマル", @model.Physical, 60)],
  )
  let mc = monte_carlo_winrate(a, b, 200, 7UL)
  assert_true(mc >= 0.0 && mc <= 1.0)
  assert_true(mc.is_nan() == false)
}

///|
test "monte_carlo_winrate_deterministic_same_seed" {
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 80)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 80)],
  )
  let v1 = monte_carlo_winrate(a, b, 100, 99UL)
  let v2 = monte_carlo_winrate(a, b, 100, 99UL)
  assert_eq(v1, v2)
}

///|
test "from_combatants_with_monte_carlo_produces_antisymmetric_matrix" {
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 120, 80, 80, 80, 80, 80),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let c = mk_combatant(
    mk_pokemon("C", "ノーマル", "", 80, 120, 120, 120, 120, 120),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let m = from_combatants([a, b, c], MonteCarloSim(50, 123UL))
  for i in 0..<3 {
    for j in 0..<3 {
      assert_true((m.at(i, j) + m.at(j, i)).abs() < 1.0e-9)
    }
  }
}

///|
test "from_combatants_with_monte_carlo_diagonal_is_zero" {
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 120, 80, 80, 80, 80, 80),
    [mk_move("mv", "ノーマル", @model.Physical, 60)],
  )
  let m = from_combatants([a, b], MonteCarloSim(50, 123UL))
  assert_eq(m.at(0, 0), 0.0)
  assert_eq(m.at(1, 1), 0.0)
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
