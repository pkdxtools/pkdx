///|
/// Two-stage screened-selection pipeline for `TeamPayoffModel::ScreenedSwitchingGame`.
///
/// - Phase A: team-level Monte Carlo rollout over every (k-selection,
///   k-selection) cell (cheap pre-screening signal).
/// - Phase B: solve Nash on the screening matrix, score rows/columns by
///   expected value under the opponent's Nash strategy, retain the top
///   `keep_top_quantile` fraction (`ceil(n * q)`).
/// - Phase C: evaluate only the retained sub-matrix with the full
///   SwitchingGame DP (`switching_game_winrate`).
///
/// `keep_top_quantile >= 1.0` short-circuits to
/// `team_payoff_matrix_switching` for bit-exact parity with the unscreened
/// pipeline.

///|
/// Run the 2-stage pipeline. Returns `(sub_matrix, retained_row_indices,
/// retained_col_indices)` where the indices reference the original
/// `combinations_with_lead(|team|, k)` enumeration (lead-first, backups
/// ascending). Caller is responsible for using these indices to slice the
/// selection labels / strategy vectors down to the retained subset.
pub fn team_payoff_matrix_screened(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  mc_trials : Int,
  mc_seed : UInt64,
  keep_top_quantile : Double,
  refine_turn_limit~ : Int = DP_TURN_LIMIT,
  mc_turn_limit~ : Int = MC_TURN_LIMIT,
  disk~ : @damage_cache.DamageDiskCache? = None,
  progress~ : (ProgressEvent) -> Unit = noop_progress,
  dp_log_every~ : Int = 0,
) -> (@nash.FiniteMatrix, Array[Int], Array[Int]) raise PayoffError {
  let k = pick_count(format)
  let na = team_a.length()
  let nb = team_b.length()
  if na < k || nb < k {
    raise EmptyCombatants
  }
  for c in team_a {
    if c.moves.length() == 0 {
      raise EmptyMoves(c.pokemon.name_ja)
    }
  }
  for c in team_b {
    if c.moves.length() == 0 {
      raise EmptyMoves(c.pokemon.name_ja)
    }
  }
  let sel_a = combinations_with_lead(na, k)
  let sel_b = combinations_with_lead(nb, k)
  let size_a = sel_a.length()
  let size_b = sel_b.length()

  // Short-circuit: keep_top >= 1.0 means retain every row / column, so we can
  // skip the screening pass entirely and delegate to the raw SwitchingGame
  // matrix builder. This guarantees bit-exact parity with the unscreened path
  // (required by the oracle test) and avoids duplicate MC + refine work.
  if keep_top_quantile >= 1.0 {
    let m = team_payoff_matrix_switching(
      team_a,
      team_b,
      format,
      refine_turn_limit,
      disk~,
      progress~,
      dp_log_every~,
    )
    let rows = Array::make(size_a, 0)
    for i in 0..<size_a {
      rows[i] = i
    }
    let cols = Array::make(size_b, 0)
    for j in 0..<size_b {
      cols[j] = j
    }
    return (m, rows, cols)
  }

  // Phase A: full-matrix MC screening. Cell seed = mc_seed XOR cell_idx so
  // each cell's RNG state is independent of enumeration order.
  let phase_a_total = size_a * size_b
  progress(PhaseStart("screening", phase_a_total))
  let screen = Array::make(size_a, ([] : Array[Double]))
  for i in 0..<size_a {
    let row = Array::make(size_b, 0.0)
    for j in 0..<size_b {
      progress(CellStart(sel_a[i], sel_b[j], i, j, "screening"))
      let cell_idx = (i * size_b + j).to_uint64()
      let picked_a = pick_combatants(team_a, sel_a[i])
      let picked_b = pick_combatants(team_b, sel_b[j])
      row[j] = team_monte_carlo_value(
        picked_a, picked_b, mc_trials, mc_seed ^ cell_idx,
        turn_limit=mc_turn_limit,
      )
      progress(CellDone(sel_a[i], sel_b[j], i, j, "screening"))
      progress(PhaseProgress("screening", i * size_b + j + 1, phase_a_total))
    }
    screen[i] = row
  }
  progress(PhaseEnd("screening"))

  // Phase B: Nash-weighted scoring. Solve Nash on the screening matrix and
  // score each selection by its expected value under the opponent's equilibrium
  // strategy. All Nash-support rows achieve the game value (tied at top);
  // non-support rows score strictly less. This guarantees screening never
  // drops a Nash-support selection.
  progress(PhaseStart("nash-scoring", 1))
  let (row_score, col_score) = screen_nash_scores(screen, size_a, size_b)
  let row_keep = retain_top_indices(row_score, keep_top_quantile)
  let col_keep = retain_top_indices(col_score, keep_top_quantile)
  progress(PhaseEnd("nash-scoring"))

  // Phase C: refine the retained sub-matrix with full SwitchingGame DP.
  let phase_c_total = row_keep.length() * col_keep.length()
  progress(PhaseStart("dp-refine", phase_c_total))
  let data = Array::make(row_keep.length(), ([] : Array[Double]))
  for i in 0..<row_keep.length() {
    let row = Array::make(col_keep.length(), 0.0)
    for j in 0..<col_keep.length() {
      progress(
        CellStart(
          sel_a[row_keep[i]], sel_b[col_keep[j]], row_keep[i], col_keep[j],
          "dp-refine",
        ),
      )
      let picked_a = pick_combatants(team_a, sel_a[row_keep[i]])
      let picked_b = pick_combatants(team_b, sel_b[col_keep[j]])
      row[j] = switching_game_winrate(
        picked_a,
        picked_b,
        refine_turn_limit,
        disk~,
        progress~,
        dp_log_every~,
      )
      progress(
        CellDone(
          sel_a[row_keep[i]], sel_b[col_keep[j]], row_keep[i], col_keep[j],
          "dp-refine",
        ),
      )
      progress(
        PhaseProgress(
          "dp-refine", i * col_keep.length() + j + 1, phase_c_total,
        ),
      )
    }
    data[i] = row
  }
  progress(PhaseEnd("dp-refine"))
  let m = match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise EmptyCombatants
  }
  (m, row_keep, col_keep)
}

///|
/// Pure row-range slice of the Phase A (MC screening) matrix. The same
/// `cell_idx = i_global * size_b + j` derivation as
/// `team_payoff_matrix_screened`'s in-process loop is used so concatenating
/// the output of contiguous row ranges reproduces the full screening
/// matrix byte-exact. No progress events; the parent orchestrator is
/// expected to bracket calls with `PhaseStart` / `PhaseEnd`.
///
/// The function is the per-shard worker primitive used by both the
/// future `team_payoff_matrix_screened_parallel` orchestrator and the
/// `__select-shard --phase=screen` subcommand.
pub fn screen_phase_rows(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  mc_trials : Int,
  mc_seed : UInt64,
  row_start : Int,
  row_end : Int,
  mc_turn_limit~ : Int = MC_TURN_LIMIT,
) -> Array[Array[Double]] raise PayoffError {
  let k = pick_count(format)
  let na = team_a.length()
  let nb = team_b.length()
  if na < k || nb < k {
    raise EmptyCombatants
  }
  for c in team_a {
    if c.moves.length() == 0 {
      raise EmptyMoves(c.pokemon.name_ja)
    }
  }
  for c in team_b {
    if c.moves.length() == 0 {
      raise EmptyMoves(c.pokemon.name_ja)
    }
  }
  let sel_a = combinations_with_lead(na, k)
  let sel_b = combinations_with_lead(nb, k)
  let size_b = sel_b.length()
  if row_start < 0 || row_end > sel_a.length() {
    raise EmptyCombatants
  }
  build_row_shard(size_b, row_start, row_end, fn(i_global, j) {
    screen_one_cell(
      team_a,
      team_b,
      sel_a[i_global],
      sel_b[j],
      mc_trials,
      mc_seed,
      i_global * size_b + j,
      mc_turn_limit,
    )
  })
}

///|
/// Pure per-cell MC screening compute. Same value as the inlined cell body
/// inside `team_payoff_matrix_screened`'s Phase A loop and inside
/// `screen_phase_rows`. Extracted so the shard worker can call it directly
/// and emit `CellStart` / `CellDone` events around each call without
/// re-implementing the seed derivation.
pub fn screen_one_cell(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  sel_a_row : Array[Int],
  sel_b_col : Array[Int],
  mc_trials : Int,
  mc_seed : UInt64,
  cell_idx : Int,
  mc_turn_limit : Int,
) -> Double {
  let picked_a = pick_combatants(team_a, sel_a_row)
  let picked_b = pick_combatants(team_b, sel_b_col)
  team_monte_carlo_value(
    picked_a,
    picked_b,
    mc_trials,
    mc_seed ^ cell_idx.to_uint64(),
    turn_limit=mc_turn_limit,
  )
}

///|
/// Pure row-range slice of the Phase C (DP refine) matrix. The retained
/// row / col index arrays from `screen_nash_scores` + `retain_top_indices`
/// are passed in; `row_start..row_end` indexes into `row_keep`.
/// `disk=None` is used inside; the parent orchestrator may optionally
/// pass a real disk cache to its single-process variant via
/// `team_payoff_matrix_screened`. The returned matrix is bit-exact with
/// the disk-enabled path because the disk cache only speeds up lookups
/// and never alters cell values.
pub fn refine_phase_rows(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  refine_turn_limit : Int,
  row_keep : Array[Int],
  col_keep : Array[Int],
  row_start : Int,
  row_end : Int,
) -> Array[Array[Double]] raise PayoffError {
  let k = pick_count(format)
  let na = team_a.length()
  let nb = team_b.length()
  if na < k || nb < k {
    raise EmptyCombatants
  }
  for c in team_a {
    if c.moves.length() == 0 {
      raise EmptyMoves(c.pokemon.name_ja)
    }
  }
  for c in team_b {
    if c.moves.length() == 0 {
      raise EmptyMoves(c.pokemon.name_ja)
    }
  }
  let sel_a = combinations_with_lead(na, k)
  let sel_b = combinations_with_lead(nb, k)
  let n_cols = col_keep.length()
  if row_start < 0 || row_end > row_keep.length() {
    raise EmptyCombatants
  }
  build_row_shard(n_cols, row_start, row_end, fn(i_global, j) {
    refine_one_cell(
      team_a,
      team_b,
      sel_a[row_keep[i_global]],
      sel_b[col_keep[j]],
      refine_turn_limit,
    )
  })
}

///|
/// Pure per-cell DP refine compute. Same value as the inlined cell body
/// inside `team_payoff_matrix_screened`'s Phase C loop and inside
/// `refine_phase_rows`. Extracted so the shard worker can call it directly
/// and emit `CellStart` / `CellDone` events around each call.
///
/// `progress` / `dp_log_every` forward to `switching_game_winrate` so a
/// shard worker can request DP-node tracing without re-implementing the
/// recursion. Default `dp_log_every=0` keeps the no-trace fast path
/// unaffected (no DpNode events fire).
pub fn refine_one_cell(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  sel_a_row : Array[Int],
  sel_b_col : Array[Int],
  refine_turn_limit : Int,
  progress~ : (ProgressEvent) -> Unit = noop_progress,
  dp_log_every~ : Int = 0,
) -> Double {
  let picked_a = pick_combatants(team_a, sel_a_row)
  let picked_b = pick_combatants(team_b, sel_b_col)
  switching_game_winrate(
    picked_a, picked_b, refine_turn_limit, progress~, dp_log_every~,
  )
}

///|
/// Score rows and columns of a screening matrix using Nash equilibrium weights.
/// Row score = expected value under opponent's Nash strategy; all Nash-support
/// rows achieve exactly the game value (tied at top), non-support rows achieve
/// strictly less. Column scores are negated (minimizer perspective).
pub fn screen_nash_scores(
  screen : Array[Array[Double]],
  size_a : Int,
  size_b : Int,
) -> (Array[Double], Array[Double]) raise PayoffError {
  let screen_matrix = match @nash.FiniteMatrix::new(screen) {
    Ok(m) => m
    Err(_) => raise EmptyCombatants
  }
  let screen_lp = try @nash.solve_zero_sum(screen_matrix) catch {
    _ => raise EmptyCombatants
  }
  let (row_nash, col_nash) = match screen_lp {
    Optimal(row_strategy~, col_strategy~, ..) => (row_strategy, col_strategy)
    _ => raise EmptyCombatants
  }
  let row_score = Array::make(size_a, 0.0)
  for i in 0..<size_a {
    let mut s = 0.0
    for j in 0..<size_b {
      s += col_nash.at(j) * screen[i][j]
    }
    row_score[i] = s
  }
  let col_score = Array::make(size_b, 0.0)
  for j in 0..<size_b {
    let mut s = 0.0
    for i in 0..<size_a {
      s += row_nash.at(i) * screen[i][j]
    }
    col_score[j] = -s
  }
  (row_score, col_score)
}

///|
/// Return the indices of the top `ceil(n * quantile)` entries in `scores`,
/// sorted ascending (preserving the original enumeration order of the
/// kept subset, not score order). Ties are broken by the earlier original
/// index. Retains at least 1 entry.
fn retain_top_indices(scores : Array[Double], quantile : Double) -> Array[Int] {
  let n = scores.length()
  if n == 0 {
    return []
  }
  let raw = (n.to_double() * quantile).ceil().to_int()
  let keep = if raw < 1 {
    1
  } else if raw > n {
    n
  } else {
    raw
  }
  // Simple selection: pick top-`keep` by score via an O(n^2) pass — n ≤ 60
  // in practice (6 × C(5,2) lead-aware enumeration), so this stays well under
  // a millisecond.
  let picked = Array::make(n, false)
  for _ in 0..<keep {
    let mut best = -1
    let mut best_score = 0.0
    for i in 0..<n {
      if picked[i] {
        continue
      }
      if best < 0 || scores[i] > best_score {
        best = i
        best_score = scores[i]
      }
    }
    if best >= 0 {
      picked[best] = true
    }
  }
  let out : Array[Int] = []
  for i in 0..<n {
    if picked[i] {
      out.push(i)
    }
  }
  out
}

///|
/// Divide `[0, total)` into `n_shards` contiguous row ranges, returning
/// each as `(row_start, row_end)`. Shards that fall past the end of the
/// range are emitted as empty `(row, row)` slots so callers always get
/// exactly `n_shards` entries (simplifies parent-side bookkeeping).
fn shard_row_ranges(total : Int, n_shards : Int) -> Array[(Int, Int)] {
  if n_shards <= 0 {
    return []
  }
  let base = total / n_shards
  let extra = total % n_shards
  let out = Array::make(n_shards, (0, 0))
  let mut cursor = 0
  for i in 0..<n_shards {
    let size = if i < extra { base + 1 } else { base }
    let start = cursor
    let end_ = cursor + size
    out[i] = (start, end_)
    cursor = end_
  }
  out
}

///|
/// Parse the JSON written by `pkdx __select-shard` into a row-range
/// sub-matrix tuple. The schema is `{"row_start":int, "row_end":int,
/// "matrix":[[double, ...], ...]}` — see `cli_select.mbt::run_select_shard`.
fn parse_shard_output(
  json_text : String,
) -> (Int, Int, Array[Array[Double]]) raise PayoffError {
  let root = try @json.parse(json_text) catch {
    _ => raise EmptyCombatants
  }
  let obj = match root {
    Object(m) => m
    _ => raise EmptyCombatants
  }
  let row_start = match obj.get("row_start") {
    Some(Number(n, ..)) => n.to_int()
    _ => raise EmptyCombatants
  }
  let row_end = match obj.get("row_end") {
    Some(Number(n, ..)) => n.to_int()
    _ => raise EmptyCombatants
  }
  let matrix : Array[Array[Double]] = match obj.get("matrix") {
    Some(Array(arr)) => {
      let m = Array::make(arr.length(), ([] : Array[Double]))
      for i in 0..<arr.length() {
        m[i] = match arr[i] {
          Array(row) => {
            let r = Array::make(row.length(), 0.0)
            for j in 0..<row.length() {
              r[j] = match row[j] {
                Number(d, ..) => d
                _ => raise EmptyCombatants
              }
            }
            r
          }
          _ => raise EmptyCombatants
        }
      }
      m
    }
    _ => raise EmptyCombatants
  }
  (row_start, row_end, matrix)
}

///|
/// Pure builder for the `__select-shard` argv. Extracted from
/// `run_shards_collect` so the wire format (and the turn-limit
/// propagation in particular) can be unit-tested without spawning
/// subprocesses. Any change to the CLI flag surface must be mirrored
/// in `cmd_select_shard_internal` (see `src/main/main.mbt`).
pub fn build_shard_argv(
  exe_path : String,
  phase : String,
  input_path : String,
  output_path : String,
  row_start : Int,
  row_end : Int,
  row_keep_csv : String,
  col_keep_csv : String,
  mc_turn_limit : Int,
  refine_turn_limit : Int,
  progress_mode~ : String = "off",
  progress_every~ : Int = 0,
) -> Array[String] {
  let argv = [
    exe_path,
    "__select-shard",
    "--phase",
    phase,
    "--input",
    input_path,
    "--output",
    output_path,
    "--row-start",
    row_start.to_string(),
    "--row-end",
    row_end.to_string(),
    // Turn limits resolved by the orchestrator are passed through
    // explicitly so the worker never has to re-derive them from the
    // input JSON. Keeps parallel and serial bit-exact even when the
    // caller overrides defaults via the public API.
    "--mc-turn-limit",
    mc_turn_limit.to_string(),
    "--refine-turn-limit",
    refine_turn_limit.to_string(),
  ]
  if row_keep_csv.length() > 0 {
    argv.push("--row-keep")
    argv.push(row_keep_csv)
  }
  if col_keep_csv.length() > 0 {
    argv.push("--col-keep")
    argv.push(col_keep_csv)
  }
  // Only append --progress when non-default; keeps the wire compact and
  // avoids surprising legacy callers that read the argv for golden tests.
  if progress_mode != "off" {
    argv.push("--progress")
    argv.push(progress_mode)
  }
  // `--progress-every` is meaningful only for the `refine` phase (the DP
  // recursion is the source of dp_node events). For `screen` we still
  // pass it through if non-zero so the child's admiral parser does not
  // surprise on an unknown flag; the shard simply ignores it.
  if progress_every > 0 {
    argv.push("--progress-every")
    argv.push(progress_every.to_string())
  }
  argv
}

///|
/// Defensive bounds check used by `run_shards_collect` before writing a
/// shard-produced row into the assembled matrix. Returns `None` for valid
/// indices; otherwise an error message describing the violation so the
/// caller can surface it as `ShardError`.
fn validate_stitch_index(
  shard_id : Int,
  global_row : Int,
  out_n_rows : Int,
) -> String? {
  if global_row < 0 || global_row >= out_n_rows {
    Some(
      "shard " +
      shard_id.to_string() +
      " produced out-of-bounds row index " +
      global_row.to_string() +
      " (expected 0.." +
      out_n_rows.to_string() +
      ")",
    )
  } else {
    None
  }
}

///|
/// Spawn `n_shards` child workers via `@process.run_parallel_shards`,
/// each invoking `__select-shard` with the given phase / row range /
/// retained indices. The parent reads every child's `--output` file
/// after wait, parses the JSON, and stitches the slices into a single
/// matrix indexed by `out[i_global][j]`.
///
/// `out_n_rows` is the total row count of the final matrix
/// (`size_a` for Phase A, `row_keep.length()` for Phase C). The parent
/// pre-allocates an `out_n_rows × cols` placeholder so missing rows
/// (e.g. an empty trailing shard) leave a 0-length row, which would
/// surface as a downstream Nash-shape error rather than a silent miss.
fn run_shards_collect(
  exe_path : String,
  phase : String,
  input_path : String,
  row_ranges : Array[(Int, Int)],
  row_keep_csv : String,
  col_keep_csv : String,
  out_n_rows : Int,
  timeout_ms : Int,
  mc_turn_limit : Int,
  refine_turn_limit : Int,
  progress_mode~ : String = "off",
  progress_every~ : Int = 0,
) -> Array[Array[Double]] raise PayoffError {
  let n_shards = row_ranges.length()
  // Per-shard output files. Created up front so we can clean up reliably.
  let output_paths = Array::make(n_shards, "")
  for i in 0..<n_shards {
    let p = @process.mkstemp_file("pkdx_shard_" + phase + "_out_" + i.to_string())
    output_paths[i] = match p {
      Some(s) => s
      None =>
        raise ShardError(
          "failed to allocate output temp file for shard " + i.to_string(),
        )
    }
  }
  // Build per-shard argv.
  let argvs : Array[Array[String]] = Array::make(n_shards, [])
  for i in 0..<n_shards {
    let (row_start, row_end) = row_ranges[i]
    argvs[i] = build_shard_argv(
      exe_path,
      phase,
      input_path,
      output_paths[i],
      row_start,
      row_end,
      row_keep_csv,
      col_keep_csv,
      mc_turn_limit,
      refine_turn_limit,
      progress_mode=progress_mode,
      progress_every=progress_every,
    )
  }
  let results = try @process.run_parallel_shards(argvs, timeout_ms~) catch {
    e => raise ShardError("run_parallel_shards failed: " + @debug.to_string(e))
  }
  // Stitch.
  let assembled = Array::make(out_n_rows, ([] : Array[Double]))
  let mut shard_err : String? = None
  for i in 0..<n_shards {
    match results[i] {
      Ok => {
        let raw = match @db.read_file(output_paths[i]) {
          Some(s) => s
          None => {
            shard_err = Some("output missing for shard " + i.to_string())
            continue
          }
        }
        let (row_start, _, matrix) = parse_shard_output(raw)
        // Stitch: matrix row `r` belongs at global row `row_start + r`.
        // validate_stitch_index guards against malformed shard output
        // writing outside the assembled matrix (defence in depth — the
        // parent owns the wire contract but a future stride scheme or a
        // corrupted child should not silently corrupt neighbours).
        for r in 0..<matrix.length() {
          let g = row_start + r
          match validate_stitch_index(i, g, out_n_rows) {
            Some(msg) => {
              shard_err = Some(msg)
              break
            }
            None => assembled[g] = matrix[r]
          }
        }
      }
      Exit(code) =>
        shard_err = Some(
          "shard " +
          i.to_string() +
          " exited with code " +
          code.to_string(),
        )
      Failed =>
        shard_err = Some(
          "shard " + i.to_string() + " failed (signal / timeout / spawn)",
        )
    }
  }
  // Clean up the per-shard output files. Best-effort: never propagate
  // unlink failures (e.g. someone else deleted them).
  for i in 0..<n_shards {
    let _ = @db.unlink_file(output_paths[i])
  }
  match shard_err {
    Some(msg) => raise ShardError(msg)
    None => ()
  }
  assembled
}

///|
/// Parallel Phase A + Phase C orchestrator. Mirrors
/// `team_payoff_matrix_screened` but fans out the cell-wise work across
/// `parallel` child `pkdx __select-shard` processes. Bit-exact parity
/// with the in-process path is enforced by `screen_phase_rows` /
/// `refine_phase_rows` keeping the same global-cell-index seed
/// derivation; see `parallel_select_test.mbt`.
///
/// `parallel` must be >= 2 (callers should fall back to the in-process
/// path for `parallel <= 1`). `input_path` is a temporary file holding
/// the *raw input JSON* (the same string `run_select` reads from stdin),
/// shared by all shards.
pub fn team_payoff_matrix_screened_parallel(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  mc_trials : Int,
  mc_seed : UInt64,
  keep_top_quantile : Double,
  parallel : Int,
  input_path : String,
  refine_turn_limit~ : Int = DP_TURN_LIMIT,
  mc_turn_limit~ : Int = MC_TURN_LIMIT,
  progress~ : (ProgressEvent) -> Unit = noop_progress,
  child_progress_mode~ : String = "off",
  child_progress_every~ : Int = 0,
  shard_timeout_ms~ : Int = 7_200_000,
) -> (@nash.FiniteMatrix, Array[Int], Array[Int]) raise PayoffError {
  let k = pick_count(format)
  let na = team_a.length()
  let nb = team_b.length()
  if na < k || nb < k {
    raise EmptyCombatants
  }
  for c in team_a {
    if c.moves.length() == 0 {
      raise EmptyMoves(c.pokemon.name_ja)
    }
  }
  for c in team_b {
    if c.moves.length() == 0 {
      raise EmptyMoves(c.pokemon.name_ja)
    }
  }
  let sel_a = combinations_with_lead(na, k)
  let sel_b = combinations_with_lead(nb, k)
  let size_a = sel_a.length()
  let size_b = sel_b.length()
  let exe_path = match @process.self_exec_path() {
    Some(p) => p
    None =>
      raise ShardError(
        "could not resolve current executable path for shard spawn",
      )
  }
  // mc_trials / mc_seed are intentionally re-read by the child from the
  // JSON file (the input JSON is the source of truth for those). The
  // turn limits, however, must round-trip through CLI flags so the
  // public API parameters are honored even when the input JSON encodes
  // a different value (or no value at all).
  let _ = mc_trials
  let _ = mc_seed

  // ---- Phase A: MC screening fan-out -----------------------------------
  let phase_a_total = size_a * size_b
  progress(PhaseStart("screening", phase_a_total))
  let ranges_a = shard_row_ranges(size_a, parallel)
  // Per-cell `CellStart` / `CellDone` events are emitted by the *children*
  // directly to their inherited stderr when `child_progress_mode != "off"`.
  // The parent only brackets the phase, since multiple shards interleave
  // and the parent cannot meaningfully serialise their progress.
  let screen = run_shards_collect(
    exe_path,
    "screen",
    input_path,
    ranges_a,
    "",
    "",
    size_a,
    shard_timeout_ms,
    mc_turn_limit,
    refine_turn_limit,
    progress_mode=child_progress_mode,
    progress_every=child_progress_every,
  )
  progress(PhaseEnd("screening"))

  // ---- Phase B: Nash scoring on the parent ------------------------------
  progress(PhaseStart("nash-scoring", 1))
  let (row_score, col_score) = screen_nash_scores(screen, size_a, size_b)
  let row_keep = retain_top_indices(row_score, keep_top_quantile)
  let col_keep = retain_top_indices(col_score, keep_top_quantile)
  progress(PhaseEnd("nash-scoring"))

  // ---- Phase C: DP refine fan-out ---------------------------------------
  let phase_c_total = row_keep.length() * col_keep.length()
  progress(PhaseStart("dp-refine", phase_c_total))
  let ranges_c = shard_row_ranges(row_keep.length(), parallel)
  let row_keep_csv = int_array_csv(row_keep)
  let col_keep_csv = int_array_csv(col_keep)
  let refined = run_shards_collect(
    exe_path,
    "refine",
    input_path,
    ranges_c,
    row_keep_csv,
    col_keep_csv,
    row_keep.length(),
    shard_timeout_ms,
    mc_turn_limit,
    refine_turn_limit,
    progress_mode=child_progress_mode,
    progress_every=child_progress_every,
  )
  progress(PhaseEnd("dp-refine"))

  let m = match @nash.FiniteMatrix::new(refined) {
    Ok(m) => m
    Err(_) => raise EmptyCombatants
  }
  (m, row_keep, col_keep)
}

///|
/// Render an `Array[Int]` as a CSV (`"0,3,7,12"`). Empty array yields "".
fn int_array_csv(arr : Array[Int]) -> String {
  let mut s = ""
  for i in 0..<arr.length() {
    if i > 0 {
      s = s + ","
    }
    s = s + arr[i].to_string()
  }
  s
}
