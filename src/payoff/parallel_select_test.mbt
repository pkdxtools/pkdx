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
  @debug.assert_eq(full.length(), size_a)
  for i in 0..<size_a {
    @debug.assert_eq(full[i].length(), size_b)
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
      @debug.assert_eq(full[i][j], expected)
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
    @debug.assert_eq(head.length() + tail.length(), full.length())
    for i in 0..<head.length() {
      for j in 0..<head[i].length() {
        @debug.assert_eq(head[i][j], full[i][j])
      }
    }
    for i in 0..<tail.length() {
      for j in 0..<tail[i].length() {
        @debug.assert_eq(tail[i][j], full[split + i][j])
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
  @debug.assert_eq(empty1.length(), 0)
  @debug.assert_eq(empty2.length(), 0)
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
      @debug.assert_eq(r1[i][j], r2[i][j])
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
  @debug.assert_eq(full.length(), row_keep.length())
  for i in 0..<row_keep.length() {
    @debug.assert_eq(full[i].length(), col_keep.length())
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
      @debug.assert_eq(full[i][j], expected)
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
    @debug.assert_eq(head.length() + tail.length(), full.length())
    for i in 0..<head.length() {
      for j in 0..<head[i].length() {
        @debug.assert_eq(head[i][j], full[i][j])
      }
    }
    for i in 0..<tail.length() {
      for j in 0..<tail[i].length() {
        @debug.assert_eq(tail[i][j], full[split + i][j])
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
  @debug.assert_eq(v_none, v_some)
}

///|
test "build_shard_argv: orchestrator-resolved turn limits land in the shard CLI" {
  // Regression: an earlier revision of `team_payoff_matrix_screened_parallel`
  // accepted `mc_turn_limit~` / `refine_turn_limit~` but never forwarded
  // them to the shard children, so the public API silently disagreed with
  // the serial path whenever a caller passed non-default limits. Pin the
  // wire format here so the regression cannot return without a test
  // failure.
  let argv_screen = build_shard_argv(
    "/some/pkdx", "screen", "/tmp/in.json", "/tmp/out0.json", 0, 5, "", "",
    7, 9,
  )
  let mut saw_mc = false
  let mut saw_refine = false
  for i in 0..<argv_screen.length() {
    if argv_screen[i] == "--mc-turn-limit" {
      saw_mc = true
      @debug.assert_eq(argv_screen[i + 1], "7")
    }
    if argv_screen[i] == "--refine-turn-limit" {
      saw_refine = true
      @debug.assert_eq(argv_screen[i + 1], "9")
    }
  }
  assert_true(saw_mc)
  assert_true(saw_refine)
  let argv_refine = build_shard_argv(
    "/some/pkdx", "refine", "/tmp/in.json", "/tmp/out1.json", 0, 3,
    "0,1,2", "3,4,5", 7, 9,
  )
  // refine inherits the same flag pair (orchestrator passes both phases
  // the same resolved limits; children pick the relevant one).
  let mut saw_mc_r = false
  let mut saw_refine_r = false
  let mut saw_row_keep = false
  let mut saw_col_keep = false
  for i in 0..<argv_refine.length() {
    if argv_refine[i] == "--mc-turn-limit" {
      saw_mc_r = true
      @debug.assert_eq(argv_refine[i + 1], "7")
    }
    if argv_refine[i] == "--refine-turn-limit" {
      saw_refine_r = true
      @debug.assert_eq(argv_refine[i + 1], "9")
    }
    if argv_refine[i] == "--row-keep" {
      saw_row_keep = true
      @debug.assert_eq(argv_refine[i + 1], "0,1,2")
    }
    if argv_refine[i] == "--col-keep" {
      saw_col_keep = true
      @debug.assert_eq(argv_refine[i + 1], "3,4,5")
    }
  }
  assert_true(saw_mc_r)
  assert_true(saw_refine_r)
  assert_true(saw_row_keep)
  assert_true(saw_col_keep)
}

///|
test "run_select_shard: --mc-turn-limit override beats the JSON-derived value" {
  // End-to-end worker test: build a JSON input encoding refine_tl = 2,
  // invoke the worker with `mc_turn_limit_override=Some(3)` (the value
  // the orchestrator would resolve from `mc_turn_limit~`), and assert
  // the resulting matrix matches `screen_phase_rows` invoked with that
  // same explicit override — proving the override CLI path the parent
  // uses is honored end-to-end inside the worker. The override differs
  // from `MC_TURN_LIMIT` so a regression where the worker silently
  // falls back to the default would diverge.
  let team = build_parity_team("A", 100)
  let opp = build_parity_team("B", 105)
  let mc_trials = 16
  let mc_seed : UInt64 = 4242UL
  let mc_override = 3
  // Note: `MC_TURN_LIMIT` (= MC default) ≠ mc_override so a buggy worker
  // that ignored the CLI flag would yield a different matrix than the
  // direct call below.
  let input_json =
    "{\"team\":" +
    parity_team_json(team, "A") +
    ",\"opponent\":" +
    parity_team_json(opp, "B") +
    ",\"format\":\"single\"" +
    ",\"team_payoff_model\":\"screened_switching_game:" +
    mc_trials.to_string() +
    ":" +
    mc_seed.to_string() +
    ":0.5:2\"}"
  let in_path = "pkdx_parallel_test_in.json"
  let out_path = "pkdx_parallel_test_out.json"
  let _ = @db.unlink_file(in_path)
  let _ = @db.unlink_file(out_path)
  match @db.write_file_str(in_path, input_json) {
    Ok(_) => ()
    Err(e) => fail("write_file_str failed: " + e)
  }
  // Worker rows 0..3 of the screen matrix using the override.
  try run_select_shard(
    in_path,
    out_path,
    "screen",
    0,
    3,
    "",
    "",
    mc_turn_limit_override=Some(mc_override),
    refine_turn_limit_override=None,
  ) catch {
    err => fail("run_select_shard raised: " + @debug.to_string(err))
  }
  let raw = match @db.read_file(out_path) {
    Some(s) => s
    None => {
      let _ = @db.unlink_file(in_path)
      fail("missing worker output")
    }
  }
  let worker_matrix = parse_test_shard_matrix(raw)
  let expected = try screen_phase_rows(
    team, opp, Single, mc_trials, mc_seed, 0, 3, mc_turn_limit=mc_override,
  ) catch {
    err => {
      let _ = @db.unlink_file(in_path)
      let _ = @db.unlink_file(out_path)
      fail("screen_phase_rows raised: " + @debug.to_string(err))
    }
  }
  @debug.assert_eq(worker_matrix.length(), expected.length())
  for i in 0..<expected.length() {
    @debug.assert_eq(worker_matrix[i].length(), expected[i].length())
    for j in 0..<expected[i].length() {
      @debug.assert_eq(worker_matrix[i][j], expected[i][j])
    }
  }
  // And confirm the override actually changes the output: re-run with
  // None override (= MC_TURN_LIMIT default) and check it diverges from
  // the override result. If MC_TURN_LIMIT happened to equal mc_override
  // the assertion below would always pass, defeating the regression
  // gate — guard against that explicitly.
  assert_true(MC_TURN_LIMIT != mc_override)
  try run_select_shard(
    in_path,
    out_path,
    "screen",
    0,
    3,
    "",
    "",
    mc_turn_limit_override=None,
    refine_turn_limit_override=None,
  ) catch {
    err => fail("run_select_shard raised (default): " + @debug.to_string(err))
  }
  let raw2 = match @db.read_file(out_path) {
    Some(s) => s
    None => {
      let _ = @db.unlink_file(in_path)
      fail("missing worker output (default)")
    }
  }
  let default_matrix = parse_test_shard_matrix(raw2)
  let _ = @db.unlink_file(in_path)
  let _ = @db.unlink_file(out_path)
  // At least one cell must differ — otherwise the override is a no-op.
  let mut any_diff = false
  for i in 0..<default_matrix.length() {
    for j in 0..<default_matrix[i].length() {
      if default_matrix[i][j] != worker_matrix[i][j] {
        any_diff = true
      }
    }
  }
  assert_true(any_diff)
}

///|
test "run_select_shard: --refine-turn-limit override beats the JSON-derived value" {
  // Mirrors the screen-phase test for the DP refine phase. JSON encodes
  // refine_tl = 2; the orchestrator resolves a different value (4) and
  // we expect the worker matrix to match `refine_phase_rows` at 4, not
  // at 2.
  let team = build_parity_team("A", 100)
  let opp = build_parity_team("B", 105)
  let mc_trials = 16
  let mc_seed : UInt64 = 4242UL
  let json_refine_tl = 2
  let override_refine_tl = 4
  let input_json =
    "{\"team\":" +
    parity_team_json(team, "A") +
    ",\"opponent\":" +
    parity_team_json(opp, "B") +
    ",\"format\":\"single\"" +
    ",\"team_payoff_model\":\"screened_switching_game:" +
    mc_trials.to_string() +
    ":" +
    mc_seed.to_string() +
    ":0.5:" +
    json_refine_tl.to_string() +
    "\"}"
  let in_path = "pkdx_parallel_test_refine_in.json"
  let out_path = "pkdx_parallel_test_refine_out.json"
  let _ = @db.unlink_file(in_path)
  let _ = @db.unlink_file(out_path)
  match @db.write_file_str(in_path, input_json) {
    Ok(_) => ()
    Err(e) => fail("write_file_str failed: " + e)
  }
  let row_keep = [0, 5, 13]
  let col_keep = [1, 2]
  try run_select_shard(
    in_path,
    out_path,
    "refine",
    0,
    row_keep.length(),
    "0,5,13",
    "1,2",
    mc_turn_limit_override=None,
    refine_turn_limit_override=Some(override_refine_tl),
  ) catch {
    err => fail("run_select_shard raised: " + @debug.to_string(err))
  }
  let raw = match @db.read_file(out_path) {
    Some(s) => s
    None => {
      let _ = @db.unlink_file(in_path)
      fail("missing worker output")
    }
  }
  let worker_matrix = parse_test_shard_matrix(raw)
  let expected_override = try refine_phase_rows(
    team,
    opp,
    Single,
    override_refine_tl,
    row_keep,
    col_keep,
    0,
    row_keep.length(),
  ) catch {
    err => {
      let _ = @db.unlink_file(in_path)
      let _ = @db.unlink_file(out_path)
      fail("refine_phase_rows raised: " + @debug.to_string(err))
    }
  }
  @debug.assert_eq(worker_matrix.length(), expected_override.length())
  for i in 0..<expected_override.length() {
    @debug.assert_eq(worker_matrix[i].length(), expected_override[i].length())
    for j in 0..<expected_override[i].length() {
      @debug.assert_eq(worker_matrix[i][j], expected_override[i][j])
    }
  }
  let _ = @db.unlink_file(in_path)
  let _ = @db.unlink_file(out_path)
  // Sanity: the JSON-encoded value must differ from the override so
  // this test would actually fail under the buggy-orchestrator path
  // that ignored its `refine_turn_limit~` argument.
  assert_true(json_refine_tl != override_refine_tl)
}

///|
/// Render the parity-team `Combatant` array as the JSON shape `pkdx
/// select` accepts on stdin. Only encodes the fields used by the
/// downstream MC / DP code paths so the test stays small.
fn parity_team_json(team : Array[Combatant], prefix : String) -> String {
  let mut s = "["
  for i in 0..<team.length() {
    if i > 0 {
      s = s + ","
    }
    let c = team[i]
    s = s + "{"
    s = s + "\"name\":\"" + prefix + i.to_string() + "\""
    s = s + ",\"type1\":\"" + c.pokemon.type1 + "\""
    s = s + ",\"type2\":\"" + c.pokemon.type2 + "\""
    s = s + ",\"hp\":" + c.pokemon.hp.to_string()
    s = s + ",\"atk\":" + c.pokemon.atk.to_string()
    s = s + ",\"def\":" + c.pokemon.def_.to_string()
    s = s + ",\"spa\":" + c.pokemon.spa.to_string()
    s = s + ",\"spd\":" + c.pokemon.spd.to_string()
    s = s + ",\"spe\":" + c.pokemon.spe.to_string()
    s = s + ",\"ability\":\"\""
    s = s + ",\"item\":\"\""
    s = s + ",\"tera\":\"\""
    s = s + ",\"moves\":["
    for j in 0..<c.moves.length() {
      if j > 0 {
        s = s + ","
      }
      let m = c.moves[j]
      s = s + "{"
      s = s + "\"name\":\"" + m.name + "\""
      s = s + ",\"type\":\"" + m.type_ + "\""
      let cat = match m.category {
        @model.Physical => "物理"
        @model.Special => "特殊"
        @model.Status => "変化"
      }
      s = s + ",\"category\":\"" + cat + "\""
      s = s + ",\"power\":" + m.power.to_string()
      s = s + "}"
    }
    s = s + "]"
    s = s + "}"
  }
  s + "]"
}

///|
/// Parse the worker output JSON `{"row_start":Int, "row_end":Int,
/// "matrix":[[Double, ...], ...]}` into the matrix payload. The
/// `parse_shard_output` private helper inside the payoff package is
/// not visible from this blackbox test file; this is a minimal
/// inline mirror that aborts loudly on any shape mismatch so a
/// regression in the worker output schema becomes obvious instead
/// of silently zero-filling the matrix.
fn parse_test_shard_matrix(json_text : String) -> Array[Array[Double]] {
  let root = try @json.parse(json_text) catch {
    e => abort("worker output is not valid JSON: " + e.to_string())
  } noraise {
    j => j
  }
  let obj = match root {
    Object(m) => m
    _ => abort("worker output top-level must be an object")
  }
  let arr = match obj.get("matrix") {
    Some(Array(a)) => a
    _ => abort("worker output missing matrix")
  }
  let out = Array::make(arr.length(), ([] : Array[Double]))
  for i in 0..<arr.length() {
    let row = match arr[i] {
      Array(r) => r
      _ => abort("worker output matrix row must be an array")
    }
    let r = Array::make(row.length(), 0.0)
    for j in 0..<row.length() {
      r[j] = match row[j] {
        Number(d, ..) => d
        _ => abort("worker output matrix cell must be a number")
      }
    }
    out[i] = r
  }
  out
}

///|
test "build_shard_argv: --progress is appended only when progress_mode != off" {
  // Default ("off") must not extend the argv. The viz-aware orchestrator
  // appends `--progress <mode>` when it has been asked to surface child
  // events; non-viz callers (and the existing tests) should keep the
  // original 12-flag wire format unchanged.
  let argv_off = build_shard_argv(
    "/some/pkdx", "screen", "/tmp/in.json", "/tmp/out.json", 0, 5, "", "",
    7, 9,
  )
  let mut saw_off = false
  for i in 0..<argv_off.length() {
    if argv_off[i] == "--progress" {
      saw_off = true
    }
  }
  assert_false(saw_off)
  let argv_json = build_shard_argv(
    "/some/pkdx", "screen", "/tmp/in.json", "/tmp/out.json", 0, 5, "", "",
    7, 9, progress_mode="json",
  )
  let mut saw_json = false
  for i in 0..<argv_json.length() {
    if argv_json[i] == "--progress" {
      saw_json = true
      @debug.assert_eq(argv_json[i + 1], "json")
    }
  }
  assert_true(saw_json)
  let argv_stderr = build_shard_argv(
    "/some/pkdx", "refine", "/tmp/in.json", "/tmp/out.json", 0, 5,
    "0,1,2", "0,1,2", 7, 9, progress_mode="stderr",
  )
  let mut saw_stderr = false
  for i in 0..<argv_stderr.length() {
    if argv_stderr[i] == "--progress" {
      saw_stderr = true
      @debug.assert_eq(argv_stderr[i + 1], "stderr")
    }
  }
  assert_true(saw_stderr)
}

///|
test "run_select_shard: emits one CellStart and one CellDone per cell, in order" {
  // Drive the shard worker with a small row range and a collecting
  // progress callback; assert per-cell pair-up and matching coordinates
  // in CellStart-then-CellDone order. Guards against future refactors of
  // the cell loop that might double-fire, swap the order, or drop events.
  let team = build_parity_team("A", 100)
  let opp = build_parity_team("B", 105)
  let mc_trials = 4
  let mc_seed : UInt64 = 7UL
  let mc_tl = 2
  let input_json =
    "{\"team\":" +
    parity_team_json(team, "A") +
    ",\"opponent\":" +
    parity_team_json(opp, "B") +
    ",\"format\":\"single\"" +
    ",\"team_payoff_model\":\"screened_switching_game:" +
    mc_trials.to_string() +
    ":" +
    mc_seed.to_string() +
    ":0.5:2\"}"
  let in_path = "pkdx_progress_test_in.json"
  let out_path = "pkdx_progress_test_out.json"
  let _ = @db.unlink_file(in_path)
  let _ = @db.unlink_file(out_path)
  match @db.write_file_str(in_path, input_json) {
    Ok(_) => ()
    Err(e) => fail("write_file_str failed: " + e)
  }
  let starts : Array[(Int, Int)] = []
  let dones : Array[(Int, Int)] = []
  let order : Array[String] = []
  let collector : (ProgressEvent) -> Unit = fn(e) {
    match e {
      CellStart(_, _, r, c, _) => {
        starts.push((r, c))
        order.push("S:" + r.to_string() + "," + c.to_string())
      }
      CellDone(_, _, r, c, _) => {
        dones.push((r, c))
        order.push("D:" + r.to_string() + "," + c.to_string())
      }
      _ => ()
    }
  }
  try run_select_shard(
    in_path,
    out_path,
    "screen",
    0,
    2,
    "",
    "",
    mc_turn_limit_override=Some(mc_tl),
    refine_turn_limit_override=None,
    progress=collector,
  ) catch {
    err => {
      let _ = @db.unlink_file(in_path)
      let _ = @db.unlink_file(out_path)
      fail("run_select_shard raised: " + @debug.to_string(err))
    }
  }
  let _ = @db.unlink_file(in_path)
  let _ = @db.unlink_file(out_path)
  @debug.assert_eq(starts.length(), dones.length())
  assert_true(starts.length() > 0)
  // Each CellStart-CellDone pair lands at the same (row,col) and in the
  // sequence S,D,S,D,... because the shard worker is single-threaded.
  for i in 0..<starts.length() {
    let (sr, sc) = starts[i]
    let (dr, dc) = dones[i]
    @debug.assert_eq(sr, dr)
    @debug.assert_eq(sc, dc)
    @debug.assert_eq(order[i * 2], "S:" + sr.to_string() + "," + sc.to_string())
    @debug.assert_eq(order[i * 2 + 1], "D:" + sr.to_string() + "," + sc.to_string())
  }
}
