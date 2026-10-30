///|
/// Reproducible wall-clock bench for the selection Nash pipeline.
///
/// Algorithm results are unchanged: each case calls the existing
/// `solve_with_fallback` / `team_payoff_matrix_*` entry points. DP node and
/// LP counters come from the gated `dp_profile_*` refs (off unless this
/// runner turns them on). Fixed seeds make values and counter totals
/// repeatable on the same binary.
///
/// Tiers:
/// - `smoke` — tiny matrices and 3v3, suitable for `moon test`
/// - `default` — smoke plus medium matrices, a matched plain/status 4v4 pair,
///   and a shallow 6v6
/// - `full` — default plus production-shaped 6v6 (tl=3 DP and the auto-upgrade
///   screening shape). Opt-in; can run for a long time.
///
/// `select_status_heavy` is the status-branch comparison case: paralysis,
/// burn, poison, bad poison, sleep, and drowsy (every `StatusKind` the payoff
/// layer currently applies) at non-trivial accuracy / chance. Confusion,
/// freeze, and infatuation are not modeled yet; this case is the baseline
/// those future chance nodes should be compared against. Its pair is
/// `select_4v4_tl2` (same roster and move powers, `status_effect` cleared).
///
/// In-process `vm_hwm_kb` is the Linux `VmHWM` of the whole process (high
/// water since startup). `scripts/bench_select.sh` runs one case per process
/// and also records GNU time max RSS.

///|
pub(all) struct SelectBenchRow {
  case_id : String
  tier : String
  repeats : Int
  wall_ms_median : Double
  wall_ms_min : Double
  rows : Int
  cols : Int
  value : Double
  solver : String
  exploitability : Double
  phases : String
  cells : Int
  dp_nodes : Int
  dp_hits : Int
  dp_lp : Int
  dp_lp_fail : Int
  dp_saddle : Int
  dp_pruned : Int
  screen_lp : Int
  vm_hwm_kb : Int
  seed : String
  note : String
}

///|
fn empty_row(
  case_id : String,
  tier : String,
  repeats : Int,
) -> SelectBenchRow {
  {
    case_id,
    tier,
    repeats,
    wall_ms_median: 0.0,
    wall_ms_min: 0.0,
    rows: 0,
    cols: 0,
    value: 0.0,
    solver: "",
    exploitability: 0.0,
    phases: "-",
    cells: 0,
    dp_nodes: 0,
    dp_hits: 0,
    dp_lp: 0,
    dp_lp_fail: 0,
    dp_saddle: 0,
    dp_pruned: 0,
    screen_lp: 0,
    vm_hwm_kb: -1,
    seed: "-",
    note: "",
  }
}

///|
const BENCH_SEED : UInt64 = 42

///|
fn smoke_ids() -> Array[String] {
  ["nash_rps_3", "nash_skew_8", "select_3v3_tl1", "select_screened_3v3"]
}

///|
fn default_only_ids() -> Array[String] {
  [
    "nash_skew_20", "nash_skew_60", "nash_near_copy_20", "nash_degenerate_60", "select_4v4_tl2",
    "select_status_heavy", "select_6v6_tl1", "select_6v6_screened_small",
  ]
}

///|
fn full_only_ids() -> Array[String] {
  ["select_6v6_tl3", "select_6v6_screened_prod"]
}

///|
fn concat_ids(a : Array[String], b : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for id in a {
    out.push(id)
  }
  for id in b {
    out.push(id)
  }
  out
}

///|
/// Case ids included in `tier` (`smoke` / `default` / `full`).
pub fn select_bench_case_ids(tier : String) -> Array[String] raise NashCliError {
  match tier {
    "smoke" => smoke_ids()
    "default" => concat_ids(smoke_ids(), default_only_ids())
    "full" =>
      concat_ids(concat_ids(smoke_ids(), default_only_ids()), full_only_ids())
    _ =>
      raise InvalidJson(
        "select-bench tier must be smoke, default, or full (got '" + tier + "')",
      )
  }
}

///|
fn case_tier(case_id : String) -> String {
  for id in smoke_ids() {
    if id == case_id {
      return "smoke"
    }
  }
  for id in default_only_ids() {
    if id == case_id {
      return "default"
    }
  }
  for id in full_only_ids() {
    if id == case_id {
      return "full"
    }
  }
  ""
}

///|
fn default_repeats(case_id : String) -> Int {
  match case_id {
    "nash_rps_3" => 20
    "nash_skew_8" => 10
    "nash_skew_20" => 5
    "nash_skew_60" => 3
    "nash_near_copy_20" => 3
    "select_3v3_tl1" => 2
    "select_screened_3v3" => 2
    _ => if case_tier(case_id).length() > 0 { 1 } else { 0 }
  }
}

///|
fn splitmix_next(state : UInt64) -> (UInt64, UInt64) {
  let z0 = state + 0x9E3779B97F4A7C15UL
  let mut z = z0
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  let out = z ^ (z >> 31)
  (z0, out)
}

///|
fn fill_skew(n : Int, seed : UInt64) -> Array[Array[Double]] {
  let data = Array::make(n, ([] : Array[Double]))
  for i in 0..<n {
    data[i] = Array::make(n, 0.0)
  }
  let mut st = seed
  for i in 0..<n {
    let mut j = i + 1
    while j < n {
      let (st2, bits) = splitmix_next(st)
      st = st2
      let u = (bits & 0xFFFFFFUL).to_double() / 16777216.0
      let v = u * 2.0 - 1.0
      data[i][j] = v
      data[j][i] = -v
      j = j + 1
    }
  }
  data
}

///|
/// Skew-symmetric base (mixed equilibrium, so the pure-saddle fast path does
/// not apply) plus a 1e-3 row-wise tilt. Copying a whole row onto row 0
/// collapses to a pure saddle and never enters simplex; this tilt keeps the
/// game mixed while making adjacent rows numerically close.
fn fill_near_copy(n : Int, seed : UInt64) -> Array[Array[Double]] {
  let data = fill_skew(n, seed)
  let scale = n.to_double()
  for r in 0..<n {
    for c in 0..<n {
      if r == c {
        continue
      }
      let tilt = 1.0e-3 * (r - c).to_double() / scale
      data[r][c] = data[r][c] + tilt
    }
  }
  data
}

///|
fn matrix_of(
  data : Array[Array[Double]],
) -> @nash.FiniteMatrix raise NashCliError {
  match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise InvalidJson("bench matrix construction failed")
  }
}

///|
fn bench_load_degenerate_fixture() -> @nash.FiniteMatrix raise NashCliError {
  let path = "tests/fixtures/nash_simplex_failure_60x60.json"
  let raw = match @db.read_file(path) {
    Some(s) => s
    None =>
      raise InvalidJson(
        "missing " + path + " (run select-bench from the repo root)",
      )
  }
  let parsed = @json.parse(raw) catch {
    err =>
      raise InvalidJson("fixture JSON parse failed: " + @debug.to_string(err))
  }
  let rows : Array[Array[Double]] = match parsed {
    Array(rs) => {
      let out = Array::make(rs.length(), ([] : Array[Double]))
      for i in 0..<rs.length() {
        match rs[i] {
          Array(cs) => {
            let row = Array::make(cs.length(), 0.0)
            for j in 0..<cs.length() {
              row[j] = match cs[j] {
                Number(n, ..) => n
                _ => raise InvalidJson("fixture cell is not a number")
              }
            }
            out[i] = row
          }
          _ => raise InvalidJson("fixture row is not an array")
        }
      }
      out
    }
    _ => raise InvalidJson("fixture root is not an array")
  }
  matrix_of(rows)
}

///|
fn rps_matrix() -> @nash.FiniteMatrix raise NashCliError {
  matrix_of([[0.0, -1.0, 1.0], [1.0, 0.0, -1.0], [-1.0, 1.0, 0.0]])
}

///|
priv struct PhaseAcc {
  mut screening : Double
  mut nash_scoring : Double
  mut dp_refine : Double
  mut dp_full : Double
  mut select_nash : Double
  mut cells : Int
  mut open_name : String
  mut open_ns : Int64
}

///|
fn fresh_phase_acc() -> PhaseAcc {
  {
    screening: 0.0,
    nash_scoring: 0.0,
    dp_refine: 0.0,
    dp_full: 0.0,
    select_nash: 0.0,
    cells: 0,
    open_name: "",
    open_ns: 0L,
  }
}

///|
fn phase_acc_reset(acc : PhaseAcc) -> Unit {
  acc.screening = 0.0
  acc.nash_scoring = 0.0
  acc.dp_refine = 0.0
  acc.dp_full = 0.0
  acc.select_nash = 0.0
  acc.cells = 0
  acc.open_name = ""
  acc.open_ns = 0L
}

///|
fn phase_acc_close(acc : PhaseAcc) -> Unit {
  if acc.open_name.length() == 0 {
    return
  }
  let dt = @damage_cache.elapsed_ms(acc.open_ns)
  match acc.open_name {
    "screening" => acc.screening = acc.screening + dt
    "nash-scoring" => acc.nash_scoring = acc.nash_scoring + dt
    "dp-refine" => acc.dp_refine = acc.dp_refine + dt
    "dp-full" => acc.dp_full = acc.dp_full + dt
    _ => ()
  }
  acc.open_name = ""
}

///|
fn phase_acc_on(acc : PhaseAcc, ev : ProgressEvent) -> Unit {
  match ev {
    PhaseStart(name, _) => {
      phase_acc_close(acc)
      acc.open_name = name
      acc.open_ns = @damage_cache.now_ns()
    }
    PhaseEnd(_) => phase_acc_close(acc)
    CellDone(_, _, _, _, _) => acc.cells = acc.cells + 1
    _ => ()
  }
}

///|
fn append_phase(buf : String, name : String, ms : Double) -> String {
  if ms <= 0.0 {
    return buf
  }
  let piece = name + "=" + ms.to_string()
  if buf.length() == 0 {
    piece
  } else {
    buf + ";" + piece
  }
}

///|
fn phase_acc_format(acc : PhaseAcc) -> String {
  let mut s = ""
  s = append_phase(s, "screening", acc.screening)
  s = append_phase(s, "nash-scoring", acc.nash_scoring)
  s = append_phase(s, "dp-refine", acc.dp_refine)
  s = append_phase(s, "dp-full", acc.dp_full)
  s = append_phase(s, "select-nash", acc.select_nash)
  if s.length() == 0 {
    "-"
  } else {
    s
  }
}

///|
fn bench_pokemon(i : Int, type1 : String) -> @model.Pokemon {
  let hp = 280
  let atk = 90
  let def_ = 130
  let spa = 90
  let spd = 130
  let spe = 120 - i * 10
  let name = "B" + i.to_string()
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2: "",
    hp,
    atk,
    def_,
    spa,
    spd,
    spe,
    bst: hp + atk + def_ + spa + spd + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
}

///|
fn bench_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
  accuracy : Int,
  status_effect : (@model.StatusKind, Int)?,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
    accuracy,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
  }
}

///|
/// Two moves per slot. Together the first four slots cover every
/// `StatusKind` the payoff layer can inflict today (paralysis, burn, poison,
/// bad poison, sleep, drowsy). Types are chosen so none of those inflictions
/// is type-immune. Chances in (0, 100) and accuracies below 100 are what
/// create chance nodes; 100% inflictions still add a distinct status state
/// on the hit branch.
fn status_moves(i : Int) -> Array[@model.Move] {
  match i % 6 {
    0 =>
      [
        bench_move(
          "10まんボルト",
          "でんき",
          @model.Special,
          20,
          100,
          Some((@model.ParalyzeKind, 30)),
        ),
        bench_move(
          "ねむりごな",
          "くさ",
          @model.Status,
          0,
          75,
          Some((@model.SleepKind, 100)),
        ),
      ]
    1 =>
      [
        bench_move(
          "かえんほうしゃ",
          "ほのお",
          @model.Special,
          20,
          100,
          Some((@model.BurnKind, 30)),
        ),
        bench_move(
          "どくどく",
          "どく",
          @model.Status,
          0,
          90,
          Some((@model.BadPoisonKind, 100)),
        ),
      ]
    2 =>
      [
        bench_move(
          "どくづき",
          "どく",
          @model.Physical,
          20,
          100,
          Some((@model.PoisonKind, 40)),
        ),
        bench_move(
          "あくび",
          "ノーマル",
          @model.Status,
          0,
          85,
          Some((@model.DrowsyKind, 100)),
        ),
      ]
    3 =>
      [
        bench_move(
          "れいとうビーム",
          "こおり",
          @model.Special,
          20,
          100,
          Some((@model.SleepKind, 30)),
        ),
        bench_move(
          "おにび",
          "ほのお",
          @model.Status,
          0,
          85,
          Some((@model.BurnKind, 100)),
        ),
      ]
    4 =>
      [
        bench_move(
          "でんじは",
          "でんき",
          @model.Status,
          0,
          90,
          Some((@model.ParalyzeKind, 100)),
        ),
        bench_move(
          "ヘドロばくだん",
          "どく",
          @model.Special,
          20,
          100,
          Some((@model.PoisonKind, 30)),
        ),
      ]
    _ =>
      [
        bench_move(
          "キノコのほうし",
          "くさ",
          @model.Status,
          0,
          100,
          Some((@model.SleepKind, 30)),
        ),
        bench_move(
          "どくどく",
          "どく",
          @model.Status,
          0,
          90,
          Some((@model.BadPoisonKind, 100)),
        ),
      ]
  }
}

///|
fn strip_status(moves : Array[@model.Move]) -> Array[@model.Move] {
  let out : Array[@model.Move] = []
  for mv in moves {
    out.push({ ..mv, status_effect: None, })
  }
  out
}

///|
/// Status-heavy roster. Slots are ノーマル / みず / かくとう / エスパー /
/// じめん / ひこう — none of でんき・ほのお・はがね・どく — so paralysis,
/// burn, and poison can land. `heavy = false` keeps powers and accuracies
/// and clears `status_effect` (the `select_4v4_tl2` pair).
fn status_roster(n : Int, heavy : Bool) -> Array[Combatant] {
  let types = [
    "ノーマル", "みず", "かくとう", "エスパー", "じめん", "ひこう",
  ]
  let out : Array[Combatant] = []
  for i in 0..<n {
    let moves = if heavy {
      status_moves(i)
    } else {
      strip_status(status_moves(i))
    }
    out.push({
      pokemon: bench_pokemon(i, types[i % types.length()]),
      moves,
      ability: "",
      item: "",
      tera_type: "",
      stat_system: @model.Standard,
      mega_form: None,
      nature: None,
      stat_points: None,
      actual_stats: None,
      ivs: None,
    })
  }
  out
}

///|
/// Shallow scale roster (no status). One or two damaging moves, strict speed
/// order, distinct attacking types. Used for size sweeps that are not the
/// status comparison.
fn scale_roster(n : Int, nmoves : Int) -> Array[Combatant] {
  let types = [
    "ノーマル", "ほのお", "みず", "くさ", "かくとう", "エスパー",
  ]
  let out : Array[Combatant] = []
  for i in 0..<n {
    let moves : Array[@model.Move] = [
      bench_move(
        "たいあたり",
        types[i % types.length()],
        @model.Physical,
        70,
        100,
        None,
      ),
    ]
    if nmoves >= 2 {
      // priority +2 matches しんそく. The synthetic Move does not go through
      // the DB, so the priority has to be set on the struct itself.
      let fast = bench_move(
        "しんそく",
        "ノーマル",
        @model.Physical,
        40,
        100,
        None,
      )
      moves.push({ ..fast, priority: 2, })
    }
    let hp = 160
    let atk = 110
    let def_ = 100
    let spa = 80
    let spd = 90
    let spe = 40 + i * 15
    let name = "S" + i.to_string()
    out.push({
      pokemon: {
        global_no: "0000",
        name_ja: name,
        name_en: name,
        type1: types[i % types.length()],
        type2: "",
        hp,
        atk,
        def_,
        spa,
        spd,
        spe,
        bst: hp + atk + def_ + spa + spd + spe,
        ability1: "",
        ability2: "",
        dream_ability: "",
        weight: 40.0,
        forms: [],
      },
      moves,
      ability: "",
      item: "",
      tera_type: "",
      stat_system: @model.Standard,
      mega_form: None,
      nature: None,
      stat_points: None,
      actual_stats: None,
      ivs: None,
    })
  }
  out
}

///|
/// Solve the selection-level game. `NashFallbackExhausted` is recorded as
/// `solver = "exhausted"` so a later case in the suite still runs. The
/// simplex error text is appended to `note`.
fn solve_outer(
  matrix : @nash.FiniteMatrix,
  acc : PhaseAcc,
  note : String,
) -> (Double, String, Double, String) raise NashCliError {
  let t0 = @damage_cache.now_ns()
  let solved = solve_with_fallback(matrix) catch {
    NashFallbackExhausted(simplex_err~, fp_expl~, mwu_expl~) => {
      acc.select_nash = @damage_cache.elapsed_ms(t0)
      let msg = note +
        " fallback_exhausted simplex=" +
        simplex_err +
        " fp_expl=" +
        fp_expl.to_string() +
        " mwu_expl=" +
        mwu_expl.to_string()
      return (0.0, "exhausted", fp_expl, msg)
    }
    other => raise other
  }
  acc.select_nash = @damage_cache.elapsed_ms(t0)
  (
    solved.value,
    solver_path_string(solved.solver_path),
    solved.exploitability,
    note,
  )
}

///|
fn apply_profile(row : SelectBenchRow) -> SelectBenchRow {
  {
    ..row,
    dp_nodes: dp_profile_nodes.val,
    dp_hits: dp_profile_hits.val,
    dp_lp: dp_profile_lp.val,
    dp_lp_fail: dp_profile_lp_fail.val,
    dp_saddle: dp_profile_saddle.val,
    dp_pruned: dp_profile_pruned.val,
    screen_lp: dp_profile_screen_lp.val,
  }
}

///|
fn read_vm_hwm_kb() -> Int {
  match @db.read_file("/proc/self/status") {
    Some(text) => parse_vm_hwm_kb(text)
    None => -1
  }
}

///|
/// Parse the `VmHWM` kilobyte field from a `/proc/self/status` snapshot.
/// Returns -1 when the field is absent (non-Linux).
pub fn parse_vm_hwm_kb(text : String) -> Int {
  let key = "VmHWM:"
  let mut i = 0
  while i + key.length() <= text.length() {
    let mut matched = true
    let mut k = 0
    while k < key.length() {
      if text[i + k] != key[k] {
        matched = false
        break
      }
      k = k + 1
    }
    if matched {
      let mut j = i + key.length()
      while j < text.length() {
        let c = text[j].to_int()
        if c == 32 || c == 9 {
          j = j + 1
        } else {
          break
        }
      }
      let mut n = 0
      let mut any = false
      while j < text.length() {
        let c = text[j].to_int()
        if c >= 48 && c <= 57 {
          n = n * 10 + (c - 48)
          any = true
          j = j + 1
        } else {
          break
        }
      }
      if any {
        return n
      }
      return -1
    }
    i = i + 1
  }
  -1
}

///|
fn median_min(samples : Array[Double]) -> (Double, Double) {
  if samples.length() == 0 {
    return (0.0, 0.0)
  }
  let sorted : Array[Double] = []
  let mut min_v = samples[0]
  for i in 0..<samples.length() {
    sorted.push(samples[i])
    if samples[i] < min_v {
      min_v = samples[i]
    }
  }
  sorted.sort()
  (sorted[sorted.length() / 2], min_v)
}

///|
priv struct BenchObs {
  mut value : Double
  mut solver : String
  mut expl : Double
  mut rows : Int
  mut cols : Int
  mut phases : String
  mut cells : Int
  mut seed : String
  mut note : String
}

///|
fn fresh_obs() -> BenchObs {
  {
    value: 0.0,
    solver: "",
    expl: 0.0,
    rows: 0,
    cols: 0,
    phases: "-",
    cells: 0,
    seed: "-",
    note: "",
  }
}

///|
fn progress_of(acc : PhaseAcc) -> (ProgressEvent) -> Unit {
  fn(ev) { phase_acc_on(acc, ev) }
}

///|
fn run_matrix_switching(
  team : Array[Combatant],
  opp : Array[Combatant],
  tl : Int,
  acc : PhaseAcc,
  obs : BenchObs,
  seed_label : String,
  note : String,
) -> Unit raise NashCliError {
  phase_acc_reset(acc)
  let matrix = team_payoff_matrix_switching(
    team,
    opp,
    Single,
    tl,
    progress=progress_of(acc),
  ) catch {
    err => raise InnerError(@debug.to_string(err))
  }
  let (value, solver, expl, note2) = solve_outer(matrix, acc, note)
  obs.value = value
  obs.solver = solver
  obs.expl = expl
  obs.rows = matrix.rows()
  obs.cols = matrix.cols()
  obs.phases = phase_acc_format(acc)
  obs.cells = acc.cells
  obs.seed = seed_label
  obs.note = note2
}

///|
fn run_matrix_screened(
  team : Array[Combatant],
  opp : Array[Combatant],
  trials : Int,
  seed : UInt64,
  keep : Double,
  refine_tl : Int,
  mc_tl : Int,
  acc : PhaseAcc,
  obs : BenchObs,
  note : String,
) -> Unit raise NashCliError {
  phase_acc_reset(acc)
  let (matrix, _, _) = team_payoff_matrix_screened(
    team,
    opp,
    Single,
    trials,
    seed,
    keep,
    refine_turn_limit=refine_tl,
    mc_turn_limit=mc_tl,
    progress=progress_of(acc),
  ) catch {
    err => raise InnerError(@debug.to_string(err))
  }
  let (value, solver, expl, note2) = solve_outer(matrix, acc, note)
  obs.value = value
  obs.solver = solver
  obs.expl = expl
  obs.rows = matrix.rows()
  obs.cols = matrix.cols()
  obs.phases = phase_acc_format(acc)
  obs.cells = acc.cells
  obs.seed = seed.to_string()
  obs.note = note2
}

///|
fn run_nash_matrix(
  matrix : @nash.FiniteMatrix,
  acc : PhaseAcc,
  obs : BenchObs,
  seed_label : String,
  note : String,
) -> Unit raise NashCliError {
  phase_acc_reset(acc)
  let (value, solver, expl, note2) = solve_outer(matrix, acc, note)
  obs.value = value
  obs.solver = solver
  obs.expl = expl
  obs.rows = matrix.rows()
  obs.cols = matrix.cols()
  obs.phases = phase_acc_format(acc)
  obs.cells = 0
  obs.seed = seed_label
  obs.note = note2
}

///|
fn execute_case(
  case_id : String,
  acc : PhaseAcc,
  obs : BenchObs,
) -> Unit raise NashCliError {
  match case_id {
    "nash_rps_3" =>
      run_nash_matrix(
        rps_matrix(),
        acc,
        obs,
        "-",
        "rock-paper-scissors; expects simplex",
      )
    "nash_skew_8" =>
      run_nash_matrix(
        matrix_of(fill_skew(8, BENCH_SEED)),
        acc,
        obs,
        "42",
        "skew-symmetric 8x8",
      )
    "nash_skew_20" =>
      run_nash_matrix(
        matrix_of(fill_skew(20, BENCH_SEED)),
        acc,
        obs,
        "42",
        "skew-symmetric 20x20",
      )
    "nash_skew_60" =>
      run_nash_matrix(
        matrix_of(fill_skew(60, BENCH_SEED)),
        acc,
        obs,
        "42",
        "skew-symmetric 60x60 (selection-matrix size)",
      )
    "nash_near_copy_20" =>
      run_nash_matrix(
        matrix_of(fill_near_copy(20, BENCH_SEED)),
        acc,
        obs,
        "42",
        "skew plus 1e-3 tilt; mixed, near-singular rows",
      )
    "nash_degenerate_60" =>
      run_nash_matrix(
        bench_load_degenerate_fixture(),
        acc,
        obs,
        "fixture",
        "tests/fixtures/nash_simplex_failure_60x60.json",
      )
    "select_3v3_tl1" => {
      let team = scale_roster(3, 1)
      run_matrix_switching(
        team, team, 1, acc, obs, "-", "scale roster; moves=1; tl=1; direct SwitchingGame",
      )
    }
    "select_screened_3v3" => {
      let team = scale_roster(3, 1)
      run_matrix_screened(
        team,
        team,
        2,
        BENCH_SEED,
        0.5,
        1,
        1,
        acc,
        obs,
        "trials=2;keep=0.5;refine_tl=1;mc_tl=1; pipeline smoke",
      )
    }
    "select_4v4_tl2" => {
      let team = status_roster(4, false)
      run_matrix_switching(
        team, team, 2, acc, obs, "-", "pair=select_status_heavy; status=none; moves=2; tl=2",
      )
    }
    "select_status_heavy" => {
      let team = status_roster(4, true)
      run_matrix_switching(
        team, team, 2, acc, obs, "-", "pair=select_4v4_tl2; status=para,brn,psn,tox,slp,drowsy; moves=2; tl=2",
      )
    }
    "select_6v6_tl1" => {
      let team = scale_roster(6, 1)
      run_matrix_switching(
        team, team, 1, acc, obs, "-", "60x60 cells; moves=1; tl=1; direct SwitchingGame (no auto-upgrade)",
      )
    }
    "select_6v6_screened_small" => {
      let team = scale_roster(6, 1)
      run_matrix_screened(
        team,
        team,
        8,
        BENCH_SEED,
        0.3,
        1,
        1,
        acc,
        obs,
        "trials=8;keep=0.3;refine_tl=1;mc_tl=1; not production MC_TURN_LIMIT",
      )
    }
    "select_6v6_tl3" => {
      let team = scale_roster(6, 2)
      run_matrix_switching(
        team, team, 3, acc, obs, "-", "60x60; moves=2 (priority +2); tl=3; direct SwitchingGame, below auto-upgrade",
      )
    }
    "select_6v6_screened_prod" => {
      let team = scale_roster(6, 2)
      run_matrix_screened(
        team,
        team,
        AUTO_SCREEN_TRIALS,
        AUTO_SCREEN_SEED,
        AUTO_SCREEN_KEEP_TOP,
        5,
        MC_TURN_LIMIT,
        acc,
        obs,
        "auto-upgrade shape trials=1000 seed=42 keep=0.3 refine_tl=5 mc_tl=5",
      )
    }
    _ => raise InvalidJson("unknown select-bench case: " + case_id)
  }
}

///|
///|
fn dp_profile_off() -> Unit {
  dp_profile_enabled.val = false
}

///|
/// Run one case. `repeats <= 0` uses the case default. `dp_*` columns are the
/// last repeat (counters are deterministic for a fixed seed). Wall time is
/// the median across repeats.
pub fn run_select_bench_case(
  case_id : String,
  repeats? : Int = 0,
) -> SelectBenchRow raise NashCliError {
  let tier = case_tier(case_id)
  if tier.length() == 0 {
    raise InvalidJson("unknown select-bench case: " + case_id)
  }
  let nrep = if repeats > 0 { repeats } else { default_repeats(case_id) }
  let acc = fresh_phase_acc()
  let obs = fresh_obs()
  dp_profile_enabled.val = true
  errdefer dp_profile_off()
  let samples : Array[Double] = []
  let mut i = 0
  while i < nrep {
    dp_profile_reset()
    let t0 = @damage_cache.now_ns()
    execute_case(case_id, acc, obs)
    samples.push(@damage_cache.elapsed_ms(t0))
    i = i + 1
  }
  let (med, min_v) = median_min(samples)
  let row = apply_profile({
    ..empty_row(case_id, tier, nrep),
    wall_ms_median: med,
    wall_ms_min: min_v,
    rows: obs.rows,
    cols: obs.cols,
    value: obs.value,
    solver: obs.solver,
    exploitability: obs.expl,
    phases: obs.phases,
    cells: obs.cells,
    seed: obs.seed,
    note: obs.note,
    vm_hwm_kb: read_vm_hwm_kb(),
  })
  dp_profile_enabled.val = false
  row
}

///|
pub fn format_select_bench_tsv(rows : Array[SelectBenchRow]) -> String {
  let mut out = "case\ttier\trepeats\twall_ms_median\twall_ms_min\trows\tcols\tvalue\tsolver\texploitability\tphases\tcells\tdp_nodes\tdp_hits\tdp_lp\tdp_lp_fail\tdp_saddle\tdp_pruned\tscreen_lp\tvm_hwm_kb\tseed\tnote\n"
  for r in rows {
    out = out +
      r.case_id +
      "\t" +
      r.tier +
      "\t" +
      r.repeats.to_string() +
      "\t" +
      r.wall_ms_median.to_string() +
      "\t" +
      r.wall_ms_min.to_string() +
      "\t" +
      r.rows.to_string() +
      "\t" +
      r.cols.to_string() +
      "\t" +
      r.value.to_string() +
      "\t" +
      r.solver +
      "\t" +
      r.exploitability.to_string() +
      "\t" +
      r.phases +
      "\t" +
      r.cells.to_string() +
      "\t" +
      r.dp_nodes.to_string() +
      "\t" +
      r.dp_hits.to_string() +
      "\t" +
      r.dp_lp.to_string() +
      "\t" +
      r.dp_lp_fail.to_string() +
      "\t" +
      r.dp_saddle.to_string() +
      "\t" +
      r.dp_pruned.to_string() +
      "\t" +
      r.screen_lp.to_string() +
      "\t" +
      r.vm_hwm_kb.to_string() +
      "\t" +
      r.seed +
      "\t" +
      r.note +
      "\n"
  }
  out
}

///|
/// One 3v3 cell of the status roster versus the status-stripped pair, with
/// the DP profile enabled. Used by the smoke test to check that the status
/// case actually expands more nodes than its pair, without running the full
/// 4v4 matrix inside `moon test`.
pub fn profile_status_cell(heavy : Bool) -> (Double, Int, Int) {
  let team = status_roster(3, heavy)
  dp_profile_reset()
  dp_profile_enabled.val = true
  let v = switching_game_winrate(team, team, 2)
  let nodes = dp_profile_nodes.val
  let lp = dp_profile_lp.val
  dp_profile_enabled.val = false
  (v, nodes, lp)
}
