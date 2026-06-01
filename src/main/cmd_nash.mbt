///|
/// `pkdx nash` — Nash equilibrium solver. Reads a JSON payoff specification
/// from stdin and solves the zero-sum game. Accepts either an explicit
/// matrix or a monocycle character list; rejects inputs that provide both.
fn cmd_nash() -> @admiral.CommandDef {
  let name = "nash"
  let description = "Solve a zero-sum Nash equilibrium or emit a DOT payoff graph"
  let subs : Array[@admiral.CommandDef] = [
    @admiral.command(
      name="solve",
      description="Solve the Nash equilibrium from a payoff JSON on stdin",
      run=Some(fn(_ctx) { run_nash_solve_cmd() }),
    ),
    @admiral.command(
      name="graph",
      description="Emit a Graphviz DOT representation of the payoff matrix",
      options=[
        @admiral.string(
          "threshold",
          description="Edge absolute-value threshold (default 0)",
          default=Some("0"),
        ),
      ],
      run=Some(fn(ctx) { run_nash_graph_cmd(ctx_str(ctx, "threshold")) }),
    ),
  ]
  @admiral.command(
    name~,
    description~,
    subcommands=subs,
    run=Some(parent_help_run(name, description, subs)),
  )
}

///|
fn read_stdin_json() -> String {
  let raw = pkdx_read_stdin()
  if raw.length() == 0 {
    exit_error("No input from stdin")
  }
  raw
}

///|
fn run_nash_solve_cmd() -> Unit {
  let raw = read_stdin_json()
  let out = @payoff.run_nash_solve(raw) catch {
    err => {
      exit_error(nash_cli_error_message(err))
      return
    }
  }
  println(out)
}

///|
fn parse_double(s : String, default : Double) -> Double {
  // Accept simple decimals like "0.5", "-1.25", "0" — delegate to strconv if
  // available; otherwise fall back to integer parsing via existing helper.
  let mut result = 0.0
  let mut i = 0
  let mut negative = false
  if i < s.length() && s[i] == '-' {
    negative = true
    i = i + 1
  }
  let mut has_digit = false
  let mut in_frac = false
  let mut frac_scale = 1.0
  while i < s.length() {
    let c = s[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      let d = (c - 0x30).to_double()
      if in_frac {
        frac_scale = frac_scale * 0.1
        result = result + d * frac_scale
      } else {
        result = result * 10.0 + d
      }
      has_digit = true
    } else if c == 0x2E && !in_frac {
      in_frac = true
    } else {
      break
    }
    i = i + 1
  }
  if !has_digit {
    return default
  }
  if negative {
    -result
  } else {
    result
  }
}

///|
fn run_nash_graph_cmd(threshold_str : String) -> Unit {
  let raw = read_stdin_json()
  let threshold = parse_double(threshold_str, 0.0)
  let out = @payoff.run_nash_graph(raw, threshold) catch {
    err => {
      exit_error(nash_cli_error_message(err))
      return
    }
  }
  println(out)
}

///|
/// Map a `NashCliError` to a human-readable message. Kept inline so we don't
/// need to add a Show impl that leaks internal field layout.
fn nash_cli_error_message(err : @payoff.NashCliError) -> String {
  match err {
    InvalidJson(msg) => "invalid JSON: " + msg
    MissingField(field) => "missing field: " + field
    ConflictingInputs => "both matrix and characters provided; pick one"
    NonSquareMatrix(r, c) =>
      "matrix is not square: " + r.to_string() + "x" + c.to_string()
    LabelCountMismatch(expected, got) =>
      "labels length mismatch: expected " +
      expected.to_string() +
      ", got " +
      got.to_string()
    InfeasibleGame => "game is infeasible"
    UnboundedGame => "game is unbounded"
    InnerError(msg) => "solver error: " + msg
    NashFallbackExhausted(simplex_err~, fp_expl~, mwu_expl~) =>
      "Nash solver failed: simplex error '" +
      simplex_err +
      "', fictitious_play exploitability " +
      fp_expl.to_string() +
      " exceeded tolerance, mwu exploitability " +
      mwu_expl.to_string() +
      " also exceeded tolerance"
  }
}

///|
/// `pkdx select` — selection-optimisation command. Reads a team/opponent JSON
/// bundle from stdin and outputs the mixed-strategy distribution over
/// k-selections.
fn cmd_select() -> @admiral.CommandDef {
  @admiral.command(
    name="select",
    description="Compute Nash-optimal selection distribution from team JSON on stdin",
    options=[
      @admiral.string(
        "progress",
        description="Live progress sink: off | stderr | json (JSON Lines to stderr)",
        default=Some("off"),
      ),
      @admiral.int(
        "progress-every",
        description="Emit a DP-node checkpoint every N cache misses (only with --progress)",
        default=Some(50000),
      ),
      @admiral.string(
        "parallel",
        description="Parallel shards. \"auto\" = nproc (Windows clamped to 64). Default \"1\" (in-process, preserves existing test determinism). PKDX_NO_PARALLEL=1 forces 1.",
        default=Some("1"),
      ),
    ],
    run=Some(fn(ctx) { run_select_cmd(ctx) }),
  )
}

///|
/// Render an `Array[Int]` as `[0,1,2]`-style for stderr / JSON output.
fn format_int_array(arr : Array[Int]) -> String {
  let mut s = "["
  for i in 0..<arr.length() {
    if i > 0 {
      s = s + ","
    }
    s = s + arr[i].to_string()
  }
  s + "]"
}

///|
/// Render a `ProgressEvent` as a single human-readable line for stderr.
/// `t_ms` is the elapsed time since the emitter process started (always 0
/// before the closures wire start_ms in); `pid` lets a downstream analyser
/// distinguish parent vs. child shard streams under parallel fan-out.
fn format_progress_stderr(
  event : @payoff.ProgressEvent,
  t_ms~ : Int64,
  pid~ : Int,
) -> String {
  let prefix = "[progress t=" +
    t_ms.to_string() +
    "ms pid=" +
    pid.to_string() +
    "]"
  match event {
    PhaseStart(name, total) =>
      prefix + " phase=" + name + " start total=" + total.to_string()
    PhaseProgress(name, current, total) =>
      prefix +
      " phase=" +
      name +
      " " +
      current.to_string() +
      "/" +
      total.to_string()
    PhaseEnd(name) => prefix + " phase=" + name + " end"
    CellStart(team_sel, opp_sel, row, col, phase) =>
      prefix +
      " cell phase=" +
      phase +
      " row=" +
      row.to_string() +
      " col=" +
      col.to_string() +
      " team=" +
      format_int_array(team_sel) +
      " opp=" +
      format_int_array(opp_sel)
    CellDone(team_sel, opp_sel, row, col, phase) =>
      prefix +
      " cell-done phase=" +
      phase +
      " row=" +
      row.to_string() +
      " col=" +
      col.to_string() +
      " team=" +
      format_int_array(team_sel) +
      " opp=" +
      format_int_array(opp_sel)
    DpNode(visited, hits, depth, rows, cols, outcomes, classification) =>
      prefix +
      " dp visited=" +
      visited.to_string() +
      " hits=" +
      hits.to_string() +
      " depth=" +
      depth.to_string() +
      " matrix=" +
      rows.to_string() +
      "x" +
      cols.to_string() +
      " outcomes=" +
      outcomes.to_string() +
      " kind=" +
      classification
  }
}

///|
/// Escape a string for safe embedding inside a JSON string literal. Today the
/// progress event string fields (phase name / classification) are controlled
/// constants, but the helper exists so callers do not need to think about it
/// when new string fields show up — see `format_progress_json`.
fn json_escape_string(s : String) -> String {
  let mut out = ""
  for ch in s {
    let code = ch.to_int()
    if ch == '"' {
      out = out + "\\\""
    } else if ch == '\\' {
      out = out + "\\\\"
    } else if ch == '\n' {
      out = out + "\\n"
    } else if ch == '\r' {
      out = out + "\\r"
    } else if ch == '\t' {
      out = out + "\\t"
    } else if ch == '\u{08}' {
      out = out + "\\b"
    } else if ch == '\u{0C}' {
      out = out + "\\f"
    } else if code < 0x20 {
      let hex = "0123456789abcdef"
      let hi = (code >> 4) & 0xF
      let lo = code & 0xF
      out = out +
        "\\u00" +
        hex[hi:hi + 1].to_owned() +
        hex[lo:lo + 1].to_owned()
    } else {
      out = out + ch.to_string()
    }
  }
  out
}

///|
/// Render a `ProgressEvent` as a single JSON object (one line per event,
/// suitable for JSON Lines / `jq -c` consumers). The `cell_start` payload
/// uses `team_indices` / `opp_indices` for the row/column selection arrays —
/// this is the documented public schema for consumers (e.g. the grid
/// visualiser script and downstream agents).
///
/// `t_ms` is the elapsed time (ms) since the emitter process started; `pid`
/// is the emitter process id. Both are prepended to every event so a
/// downstream trace analyser can distinguish parent vs. child streams and
/// reconstruct per-cell wall time as `cell_done.t_ms - cell_start.t_ms`
/// (same-pid pairs only — different shards have independent start_ms).
fn format_progress_json(
  event : @payoff.ProgressEvent,
  t_ms~ : Int64,
  pid~ : Int,
) -> String {
  let head = "\"t_ms\":" +
    t_ms.to_string() +
    ",\"pid\":" +
    pid.to_string() +
    ","
  match event {
    PhaseStart(name, total) =>
      "{" +
      head +
      "\"event\":\"phase_start\",\"phase\":\"" +
      json_escape_string(name) +
      "\",\"total\":" +
      total.to_string() +
      "}"
    PhaseProgress(name, current, total) =>
      "{" +
      head +
      "\"event\":\"phase_progress\",\"phase\":\"" +
      json_escape_string(name) +
      "\",\"current\":" +
      current.to_string() +
      ",\"total\":" +
      total.to_string() +
      "}"
    PhaseEnd(name) =>
      "{" +
      head +
      "\"event\":\"phase_end\",\"phase\":\"" +
      json_escape_string(name) +
      "\"}"
    CellStart(team_sel, opp_sel, row, col, phase) =>
      "{" +
      head +
      "\"event\":\"cell_start\",\"phase\":\"" +
      json_escape_string(phase) +
      "\",\"row\":" +
      row.to_string() +
      ",\"col\":" +
      col.to_string() +
      ",\"team_indices\":" +
      format_int_array(team_sel) +
      ",\"opp_indices\":" +
      format_int_array(opp_sel) +
      "}"
    CellDone(team_sel, opp_sel, row, col, phase) =>
      "{" +
      head +
      "\"event\":\"cell_done\",\"phase\":\"" +
      json_escape_string(phase) +
      "\",\"row\":" +
      row.to_string() +
      ",\"col\":" +
      col.to_string() +
      ",\"team_indices\":" +
      format_int_array(team_sel) +
      ",\"opp_indices\":" +
      format_int_array(opp_sel) +
      "}"
    DpNode(visited, hits, depth, rows, cols, outcomes, classification) =>
      "{" +
      head +
      "\"event\":\"dp_node\",\"visited\":" +
      visited.to_string() +
      ",\"hits\":" +
      hits.to_string() +
      ",\"depth\":" +
      depth.to_string() +
      ",\"rows\":" +
      rows.to_string() +
      ",\"cols\":" +
      cols.to_string() +
      ",\"outcomes\":" +
      outcomes.to_string() +
      ",\"classification\":\"" +
      json_escape_string(classification) +
      "\"}"
  }
}

///|
/// Pick the highest-probability index out of a strategy array. Ties break to
/// the smallest index. Empty arrays are an internal invariant violation but
/// we still tolerate them so stderr emission never panics on the success path.
fn argmax_double(xs : Array[Double]) -> Int {
  if xs.length() == 0 {
    return 0
  }
  let mut best = 0
  let mut best_v = xs[0]
  for i in 1..<xs.length() {
    if xs[i] > best_v {
      best = i
      best_v = xs[i]
    }
  }
  best
}

///|
/// Render a comma-joined string-array snippet (e.g. `ガルーラ,カバルドン`) for
/// the human-readable summary line. JSON-style brackets are intentionally
/// omitted because this lands in `[result] ...` text, not a JSON Line.
fn format_name_csv(names : Array[String]) -> String {
  let mut s = ""
  for i in 0..<names.length() {
    if i > 0 {
      s = s + ","
    }
    s = s + names[i]
  }
  s
}

///|
/// Render a `[\"a\",\"b\"]` JSON array literal. Used by the `summary` JSON
/// Line so consumers can pull selection names without re-running the full
/// result-JSON parse.
fn format_string_array_json(names : Array[String]) -> String {
  let mut s = "["
  for i in 0..<names.length() {
    if i > 0 {
      s = s + ","
    }
    s = s + "\"" + json_escape_string(names[i]) + "\""
  }
  s + "]"
}

///|
/// One-line human-readable summary of a `SelectResult` for `--progress=stderr`.
/// Mirrors the field ordering used by `format_summary_json` so the two
/// channels are trivially correlatable.
fn format_summary_stderr(r : @payoff.SelectResult) -> String {
  let my_i = argmax_double(r.row_strategy)
  let opp_i = argmax_double(r.col_strategy)
  let my_p = if r.row_strategy.length() == 0 {
    0.0
  } else {
    r.row_strategy[my_i]
  }
  let opp_p = if r.col_strategy.length() == 0 {
    0.0
  } else {
    r.col_strategy[opp_i]
  }
  let my_names = if r.selection_names.length() == 0 {
    ([] : Array[String])
  } else {
    r.selection_names[my_i]
  }
  let opp_names = if r.opp_selection_names.length() == 0 {
    ([] : Array[String])
  } else {
    r.opp_selection_names[opp_i]
  }
  "[result] value=" +
  r.value.to_string() +
  " exploitability=" +
  r.exploitability.to_string() +
  " my_best=[" +
  format_name_csv(my_names) +
  "] (p=" +
  my_p.to_string() +
  ") opp_best=[" +
  format_name_csv(opp_names) +
  "] (p=" +
  opp_p.to_string() +
  ")"
}

///|
/// JSON Lines `summary` event matching the viz consumer schema. Emitted as
/// the last stderr event of `pkdx select --progress=json`, after every
/// `cell_done` / `phase_end`, so the viz script can render the final result
/// without re-reading the stdout file the user redirected away.
fn format_summary_json(r : @payoff.SelectResult) -> String {
  let my_i = argmax_double(r.row_strategy)
  let opp_i = argmax_double(r.col_strategy)
  let my_p = if r.row_strategy.length() == 0 {
    0.0
  } else {
    r.row_strategy[my_i]
  }
  let opp_p = if r.col_strategy.length() == 0 {
    0.0
  } else {
    r.col_strategy[opp_i]
  }
  let my_indices = if r.selections.length() == 0 {
    ([] : Array[Int])
  } else {
    r.selections[my_i]
  }
  let opp_indices = if r.opp_selections.length() == 0 {
    ([] : Array[Int])
  } else {
    r.opp_selections[opp_i]
  }
  let my_names = if r.selection_names.length() == 0 {
    ([] : Array[String])
  } else {
    r.selection_names[my_i]
  }
  let opp_names = if r.opp_selection_names.length() == 0 {
    ([] : Array[String])
  } else {
    r.opp_selection_names[opp_i]
  }
  "{\"event\":\"summary\",\"value\":" +
  r.value.to_string() +
  ",\"exploitability\":" +
  r.exploitability.to_string() +
  ",\"my_best_indices\":" +
  format_int_array(my_indices) +
  ",\"my_best_names\":" +
  format_string_array_json(my_names) +
  ",\"my_best_p\":" +
  my_p.to_string() +
  ",\"opp_best_indices\":" +
  format_int_array(opp_indices) +
  ",\"opp_best_names\":" +
  format_string_array_json(opp_names) +
  ",\"opp_best_p\":" +
  opp_p.to_string() +
  "}"
}

///|
/// `pkdx __select-shard` — internal worker for `pkdx select --parallel=N`.
/// Each invocation reads team JSON from `--input`, computes the
/// `[row_start, row_end)` slice of either the Phase A (MC screening) or
/// Phase C (DP refine) sub-matrix, and writes the result JSON to
/// `--output`. Direct use is supported but unstable; the flag surface
/// may change between releases.
fn cmd_select_shard_internal() -> @admiral.CommandDef {
  @admiral.command(
    name="__select-shard",
    description="INTERNAL: parallel select worker, orchestrated by `pkdx select`. Direct invocation is unstable.",
    options=[
      @admiral.string(
        "phase",
        description="\"screen\" (Phase A MC) or \"refine\" (Phase C DP)",
        required=true,
      ),
      @admiral.string(
        "input",
        description="Path to team JSON input file",
        required=true,
      ),
      @admiral.string(
        "output",
        description="Path to write result JSON to",
        required=true,
      ),
      @admiral.int(
        "row-start",
        description="Inclusive start of row range (per-shard slice)",
        required=true,
      ),
      @admiral.int(
        "row-end",
        description="Exclusive end of row range (per-shard slice)",
        required=true,
      ),
      @admiral.string(
        "row-keep",
        description="(refine only) CSV of retained row indices from Phase B",
        default=Some(""),
      ),
      @admiral.string(
        "col-keep",
        description="(refine only) CSV of retained col indices from Phase B",
        default=Some(""),
      ),
      // -1 sentinel = "not provided"; the worker falls back to the
      // JSON-derived value (refine) or MC_TURN_LIMIT default (screen).
      // The orchestrator always passes positive integers, but direct
      // invocation may omit them.
      @admiral.int(
        "mc-turn-limit",
        description="MC screening turn limit override (-1 = use input default)",
        default=Some(-1),
      ),
      @admiral.int(
        "refine-turn-limit",
        description="DP refine turn limit override (-1 = use input default)",
        default=Some(-1),
      ),
      // Progress mode propagated from the parent. The orchestrator passes
      // its own --progress value through so the shard emits matching
      // JSON Lines (cell_start / cell_done) onto its inherited stderr,
      // which surfaces as the parent's stderr stream for the grid viz.
      @admiral.string(
        "progress",
        description="Progress emit mode: off|stderr|json (default: off)",
        default=Some("off"),
      ),
      // DP-node trace gate, mirroring the parent's `--progress-every`. The
      // shard forwards this to `refine_one_cell` so DpNode events fire on
      // every Nth `value()` cache miss. 0 disables (default).
      @admiral.int(
        "progress-every",
        description="Emit DP-node checkpoints every N cache misses (0 disables)",
        default=Some(0),
      ),
    ],
    run=Some(fn(ctx) { run_select_shard_cmd(ctx) }),
  )
}

///|
fn run_select_shard_cmd(ctx : @admiral.Context) -> Unit {
  let phase = ctx_str(ctx, "phase")
  let input_path = ctx_str(ctx, "input")
  let output_path = ctx_str(ctx, "output")
  let row_start = ctx_int(ctx, "row-start")
  let row_end = ctx_int(ctx, "row-end")
  let row_keep = ctx_str(ctx, "row-keep")
  let col_keep = ctx_str(ctx, "col-keep")
  let mc_tl_raw = ctx_int(ctx, "mc-turn-limit")
  let refine_tl_raw = ctx_int(ctx, "refine-turn-limit")
  let mc_override = if mc_tl_raw > 0 { Some(mc_tl_raw) } else { None }
  let refine_override = if refine_tl_raw > 0 {
    Some(refine_tl_raw)
  } else {
    None
  }
  let mode = ctx_str(ctx, "progress")
  // Capture this child's start moment + pid so each emit can stamp the event
  // with elapsed ms and process id. Trace analysers correlate cell_start /
  // cell_done by `(pid, row, col)` since each shard has its own start_ms.
  let start_ns = pkdx_monotonic_ns()
  let pid = pkdx_pid()
  let progress : (@payoff.ProgressEvent) -> Unit = match mode {
    "off" => fn(_e) { () }
    "stderr" =>
      fn(e) {
        let t_ms = (pkdx_monotonic_ns() - start_ns) / 1_000_000L
        pkdx_eprintln(@db.to_c_bytes(format_progress_stderr(e, t_ms~, pid~)))
      }
    "json" =>
      fn(e) {
        let t_ms = (pkdx_monotonic_ns() - start_ns) / 1_000_000L
        pkdx_eprintln(@db.to_c_bytes(format_progress_json(e, t_ms~, pid~)))
      }
    _ => {
      exit_error(
        "unknown --progress mode: " + mode + " (expected off|stderr|json)",
      )
      return
    }
  }
  let progress_every = ctx_int(ctx, "progress-every")
  @payoff.run_select_shard(
    input_path,
    output_path,
    phase,
    row_start,
    row_end,
    row_keep,
    col_keep,
    mc_turn_limit_override=mc_override,
    refine_turn_limit_override=refine_override,
    progress~,
    dp_log_every=progress_every,
  ) catch {
    err => {
      exit_error(nash_cli_error_message(err))
      return
    }
  }
}

///|
fn run_select_cmd(ctx : @admiral.Context) -> Unit {
  let mode = ctx_str(ctx, "progress")
  let log_every = ctx_int(ctx, "progress-every")
  let parallel_flag = ctx_str(ctx, "parallel")
  let parallel = @payoff.resolve_parallel(parallel_flag) catch {
    err => {
      exit_error(nash_cli_error_message(err))
      return
    }
  }
  // Capture the parent's start moment + pid. Children spawned for parallel
  // shards each take their own start_ns at boot (run_select_shard_cmd), so
  // `t_ms` is interpreted *relative to the emitting process*. Downstream
  // trace analysis joins on `pid` to keep streams separated.
  let start_ns = pkdx_monotonic_ns()
  let pid = pkdx_pid()
  let (progress, dp_log_every) : ((@payoff.ProgressEvent) -> Unit, Int) = match
    mode {
    "off" => (fn(_e) { () }, 0)
    "stderr" =>
      (
        fn(e) {
          let t_ms = (pkdx_monotonic_ns() - start_ns) / 1_000_000L
          pkdx_eprintln(@db.to_c_bytes(format_progress_stderr(e, t_ms~, pid~)))
        },
        log_every,
      )
    "json" =>
      (
        fn(e) {
          let t_ms = (pkdx_monotonic_ns() - start_ns) / 1_000_000L
          pkdx_eprintln(@db.to_c_bytes(format_progress_json(e, t_ms~, pid~)))
        },
        log_every,
      )
    _ => {
      exit_error(
        "unknown --progress mode: " + mode + " (expected off|stderr|json)",
      )
      return
    }
  }
  let raw = read_stdin_json()
  // Open the L2 damage cache once so the SwitchingGame DP inside
  // `run_select` can reuse 16-roll results from previous nash sessions.
  // Failure to open is non-fatal — we just fall back to L1-only behavior.
  let disk = match
    @damage_cache.open_or_init(resolve_damage_cache_path(), pkdx_version) {
    Ok(c) => Some(c)
    Err(e) => {
      pkdx_eprintln(
        @db.to_c_bytes(
          "damage_cache: open failed, select will run without L2: " + e,
        ),
      )
      None
    }
  }
  // Parallel children open damage_cache themselves; the parent's disk
  // is dropped for the parallel path so SQLite write contention does
  // not happen. (The shard worker passes disk=None internally.)
  let parent_disk = if parallel > 1 { None } else { disk }
  let result = @payoff.run_select_typed(
    raw,
    disk=parent_disk,
    progress~,
    dp_log_every~,
    parallel~,
    child_progress_mode=mode,
    child_progress_every=dp_log_every,
  ) catch {
    err => {
      match disk {
        Some(c) => @damage_cache.close(c)
        None => ()
      }
      exit_error(nash_cli_error_message(err))
      return
    }
  }
  match disk {
    Some(c) => @damage_cache.close(c)
    None => ()
  }
  // Summary lands on stderr (matching the chosen --progress mode) so a
  // user who has redirected stdout to a result file still sees the
  // value / best-selection at the end of the live viz stream. `off`
  // suppresses summary too — same gate as per-cell progress.
  match mode {
    "stderr" => pkdx_eprintln(@db.to_c_bytes(format_summary_stderr(result)))
    "json" => pkdx_eprintln(@db.to_c_bytes(format_summary_json(result)))
    _ => ()
  }
  println(@payoff.serialize_select_result(result))
}

///|
/// `pkdx meta-divergence` — measure how far a usage distribution is from a
/// self-best-response equilibrium given a symmetric payoff matrix.
fn cmd_meta_divergence() -> @admiral.CommandDef {
  @admiral.command(
    name="meta-divergence",
    description="Report exploitability and per-index regret of a usage distribution",
    run=Some(fn(_ctx) { run_meta_divergence_cmd() }),
  )
}

///|
fn meta_cli_error_message(err : @payoff.MetaCliError) -> String {
  match err {
    InvalidJsonMeta(msg) => "invalid JSON: " + msg
    MissingFieldMeta(field) => "missing field: " + field
    UsageNotNormalised(total) =>
      "usage does not sum to 1 (got " + total.to_string() + ")"
    ShapeMismatch(n, m) =>
      "matrix / usage shape mismatch: " + n.to_string() + " vs " + m.to_string()
  }
}

///|
fn run_meta_divergence_cmd() -> Unit {
  let raw = read_stdin_json()
  let out = @payoff.run_meta_divergence(raw) catch {
    err => {
      exit_error(meta_cli_error_message(err))
      return
    }
  }
  println(out)
}
