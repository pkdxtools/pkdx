/// Oracle tests for the row-range phase APIs introduced for the
/// parallel `pkdx select` orchestrator. These run entirely in-process
/// (no subprocess) so they are CI-stable and act as a hard parity
/// contract that the subprocess path must respect.

///|
/// Build a 6-combatant team with deterministic stats. Speeds differ so
/// the underlying SwitchingGame DP has a real ordering structure to
/// reason about (otherwise every cell would tie at 0.5 and parity
/// checks become uninteresting).
fn build_parity_team(prefix : String, hp_base : Int) -> Array[Combatant] {
  let out = Array::make(6, mk_combatant(mk_pokemon("placeholder", "", "", 1, 1, 1, 1, 1, 1), []))
  for i in 0..<6 {
    let hp = hp_base + i * 5
    let atk = 95 + i * 3
    let def_ = 80 + i * 2
    let spa = 70
    let spd = 75
    let spe = 110 - i * 5
    out[i] = mk_combatant(
      mk_pokemon(prefix + i.to_string(), "ノーマル", "", hp, atk, def_, spa, spd, spe),
      [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
    )
  }
  out
}

///|
test "screen_phase_rows: full range matches in-process Phase A reconstruction" {
  // Reproduce the Phase A loop inline (the same math team_payoff_matrix_screened
  // uses) and assert the pure phase function produces identical cells.
  let team_a = build_parity_team("A", 100)
  let team_b = build_parity_team("B", 105)
  let mc_trials = 64
  let mc_seed : UInt64 = 7UL
  let size_a = combinations_with_lead(6, 3).length()
  let size_b = combinations_with_lead(6, 3).length()
  let full = screen_phase_rows(team_a, team_b, Single, mc_trials, mc_seed, 0, size_a, mc_turn_limit=3)
  assert_eq(full.length(), size_a)
  for i in 0..<size_a {
    assert_eq(full[i].length(), size_b)
  }
  // Reproduce inline cell-by-cell to bound parity to the math, not to
  // the loop shape.
  let sel_a = combinations_with_lead(6, 3)
  let sel_b = combinations_with_lead(6, 3)
  for i in 0..<size_a {
    for j in 0..<size_b {
      let cell_idx = (i * size_b + j).to_uint64()
      let picked_a = Array::make(sel_a[i].length(), team_a[0])
      for p in 0..<sel_a[i].length() {
        picked_a[p] = team_a[sel_a[i][p]]
      }
      let picked_b = Array::make(sel_b[j].length(), team_b[0])
      for p in 0..<sel_b[j].length() {
        picked_b[p] = team_b[sel_b[j][p]]
      }
      let expected = team_monte_carlo_value(
        picked_a, picked_b, mc_trials, mc_seed ^ cell_idx, turn_limit=3,
      )
      assert_eq(full[i][j], expected)
    }
  }
}

///|
test "screen_phase_rows: shard concatenation reproduces full matrix bit-exact" {
  let team_a = build_parity_team("A", 100)
  let team_b = build_parity_team("B", 105)
  let mc_trials = 64
  let mc_seed : UInt64 = 11UL
  let size_a = combinations_with_lead(6, 3).length()
  let full = screen_phase_rows(team_a, team_b, Single, mc_trials, mc_seed, 0, size_a, mc_turn_limit=3)

  // Walk a handful of (k_split) values and confirm the concatenation of
  // [0, k) and [k, size_a) lines up with the full matrix exactly.
  for split in [1, size_a / 2, size_a / 2 + 1, size_a - 1] {
    let head = screen_phase_rows(team_a, team_b, Single, mc_trials, mc_seed, 0, split, mc_turn_limit=3)
    let tail = screen_phase_rows(team_a, team_b, Single, mc_trials, mc_seed, split, size_a, mc_turn_limit=3)
    assert_eq(head.length() + tail.length(), full.length())
    for i in 0..<head.length() {
      for j in 0..<head[i].length() {
        assert_eq(head[i][j], full[i][j])
      }
    }
    for i in 0..<tail.length() {
      for j in 0..<tail[i].length() {
        assert_eq(tail[i][j], full[split + i][j])
      }
    }
  }
}

///|
test "screen_phase_rows: shard count > row count yields empty trailing slices" {
  // size_a = 60 in the canonical 6v6 enumeration; we pick a few ranges
  // that go beyond size_a to confirm the helper degrades cleanly.
  let team_a = build_parity_team("A", 100)
  let team_b = build_parity_team("B", 105)
  let size_a = combinations_with_lead(6, 3).length()
  let empty1 = screen_phase_rows(team_a, team_b, Single, 16, 1UL, size_a, size_a, mc_turn_limit=3)
  let empty2 = screen_phase_rows(team_a, team_b, Single, 16, 1UL, 5, 5, mc_turn_limit=3)
  assert_eq(empty1.length(), 0)
  assert_eq(empty2.length(), 0)
}

///|
test "screen_phase_rows: mc_seed UInt64::MAX xor cell_idx stays stable across runs" {
  // The seed XOR derivation must not depend on the order of evaluation,
  // and overflow on UInt64 is well-defined wrap-around. Two runs with
  // the same seed must return byte-identical matrices regardless of how
  // many rows we slice at a time.
  let team_a = build_parity_team("A", 100)
  let team_b = build_parity_team("B", 105)
  let max_seed : UInt64 = (0UL).reinterpret_as_int64().reinterpret_as_uint64() - 1UL
  let size_a = combinations_with_lead(6, 3).length()
  let r1 = screen_phase_rows(team_a, team_b, Single, 16, max_seed, 0, size_a, mc_turn_limit=3)
  let r2 = screen_phase_rows(team_a, team_b, Single, 16, max_seed, 0, size_a, mc_turn_limit=3)
  for i in 0..<size_a {
    for j in 0..<r1[i].length() {
      assert_eq(r1[i][j], r2[i][j])
    }
  }
}

///|
test "refine_phase_rows: full retained range matches per-cell switching_game_winrate" {
  let team_a = build_parity_team("A", 100)
  let team_b = build_parity_team("B", 105)
  let sel_a = combinations_with_lead(6, 3)
  let sel_b = combinations_with_lead(6, 3)
  // Use a small retained subset so the test stays fast.
  let row_keep = [0, 5, 13]
  let col_keep = [1, 2]
  let refine_tl = 2
  let full = refine_phase_rows(team_a, team_b, Single, refine_tl, row_keep, col_keep, 0, row_keep.length())
  assert_eq(full.length(), row_keep.length())
  for i in 0..<row_keep.length() {
    assert_eq(full[i].length(), col_keep.length())
    for j in 0..<col_keep.length() {
      let picked_a = Array::make(sel_a[row_keep[i]].length(), team_a[0])
      for p in 0..<sel_a[row_keep[i]].length() {
        picked_a[p] = team_a[sel_a[row_keep[i]][p]]
      }
      let picked_b = Array::make(sel_b[col_keep[j]].length(), team_b[0])
      for p in 0..<sel_b[col_keep[j]].length() {
        picked_b[p] = team_b[sel_b[col_keep[j]][p]]
      }
      let expected = switching_game_winrate(picked_a, picked_b, refine_tl)
      assert_eq(full[i][j], expected)
    }
  }
}

///|
test "refine_phase_rows: shard concatenation reproduces full retained matrix" {
  let team_a = build_parity_team("A", 100)
  let team_b = build_parity_team("B", 105)
  let row_keep = [0, 3, 7, 12, 19, 25]
  let col_keep = [2, 4]
  let refine_tl = 2
  let full = refine_phase_rows(team_a, team_b, Single, refine_tl, row_keep, col_keep, 0, row_keep.length())
  for split in [1, 3, row_keep.length() - 1] {
    let head = refine_phase_rows(team_a, team_b, Single, refine_tl, row_keep, col_keep, 0, split)
    let tail = refine_phase_rows(team_a, team_b, Single, refine_tl, row_keep, col_keep, split, row_keep.length())
    assert_eq(head.length() + tail.length(), full.length())
    for i in 0..<head.length() {
      for j in 0..<head[i].length() {
        assert_eq(head[i][j], full[i][j])
      }
    }
    for i in 0..<tail.length() {
      for j in 0..<tail[i].length() {
        assert_eq(tail[i][j], full[split + i][j])
      }
    }
  }
}

///|
test "switching_game_winrate: disk=None vs disk=Some are bit-exact" {
  // Plan correctness depends on the parallel shards passing disk=None
  // (since the SQLite handle is single-process). Pin the invariant so a
  // future change to the L2 cache that subtly alters values cannot slip
  // past the parallel parity gate.
  let team_a = [
    mk_combatant(
      mk_pokemon("A", "ノーマル", "", 110, 130, 90, 70, 75, 100),
      [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
    ),
    mk_combatant(
      mk_pokemon("B", "ノーマル", "", 100, 110, 80, 70, 80, 90),
      [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
    ),
  ]
  let team_b = [
    mk_combatant(
      mk_pokemon("X", "ノーマル", "", 105, 100, 100, 70, 75, 95),
      [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
    ),
    mk_combatant(
      mk_pokemon("Y", "ノーマル", "", 100, 95, 95, 70, 75, 85),
      [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
    ),
  ]
  let path = "pkdx_parallel_l2_parity.sqlite"
  let _ = @db.unlink_file(path)
  guard @damage_cache.open_or_init(path, "0.4.10") is Ok(disk) else {
    fail("open_or_init failed")
  }
  let v_none = switching_game_winrate(team_a, team_b, 3)
  let v_some = switching_game_winrate(team_a, team_b, 3, disk=Some(disk))
  @damage_cache.close(disk)
  let _ = @db.unlink_file(path)
  assert_eq(v_none, v_some)
}
