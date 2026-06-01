// k-selection 列挙 + team-level payoff matrix 構築

///|
pub(all) enum BattleFormat {
  Single
  Double
} derive(Debug, Eq)

///|
fn pick_count(format : BattleFormat) -> Int {
  match format {
    Single => 3
    Double => 4
  }
}

///|
/// Enumerate k-element subsets of `[0, n)` in lexicographic order.
/// Returns an empty array if `k <= 0` or `k > n`.
pub fn combinations(n : Int, k : Int) -> Array[Array[Int]] {
  let result : Array[Array[Int]] = []
  if k <= 0 || k > n {
    return result
  }
  let idx = Array::make(k, 0)
  for i in 0..<k {
    idx[i] = i
  }
  while true {
    let snap = Array::make(k, 0)
    for i in 0..<k {
      snap[i] = idx[i]
    }
    result.push(snap)
    let mut i = k - 1
    while i >= 0 && idx[i] == n - k + i {
      i = i - 1
    }
    if i < 0 {
      break
    }
    idx[i] = idx[i] + 1
    for j in (i + 1)..<k {
      idx[j] = idx[j - 1] + 1
    }
  }
  result
}

///|
/// Enumerate ordered k-tuples from `[0, n)` where the first element is the
/// designated lead (先頭選出) and the remaining `k − 1` elements form a
/// distinct subset of `[0, n) \ {lead}` in ascending order. Total count is
/// `n × C(n − 1, k − 1)` (e.g. `n=6, k=3 → 60`).
///
/// Backups are kept order-free (sorted ascending) because every alive teammate
/// is a symmetric `Switch(_)` target in the SwitchingGame / team rollout, so
/// permuting backups produces game-theoretically identical actions.
///
/// Outer loop is `lead`, inner loop iterates the lex order of the
/// `(k − 1)`-subsets of the remaining indices, so the enumeration is stable
/// across runs and friendly to callers that index into it by `lead × strides
/// + offset`.
pub fn combinations_with_lead(n : Int, k : Int) -> Array[Array[Int]] {
  let result : Array[Array[Int]] = []
  if k <= 0 || k > n {
    return result
  }
  for lead in 0..<n {
    let rest_count = n - 1
    let rest_k = k - 1
    if rest_k == 0 {
      result.push([lead])
      continue
    }
    // Map a fictional index space [0, n-1) onto [0, n) skipping `lead`.
    let map_back = Array::make(rest_count, 0)
    let mut p = 0
    for i in 0..<n {
      if i == lead {
        continue
      }
      map_back[p] = i
      p = p + 1
    }
    let backups = combinations(rest_count, rest_k)
    for sub in backups {
      let snap = Array::make(k, 0)
      snap[0] = lead
      for j in 0..<rest_k {
        snap[j + 1] = map_back[sub[j]]
      }
      result.push(snap)
    }
  }
  result
}

///|
/// Build a row-range slice of an `Array[Array[Double]]` payoff matrix by
/// invoking `cell_fn(i_global, j)` for every cell in `[row_start, row_end)
/// × [0, size_b)`. Shared by `screen_phase_rows` (Phase A) and
/// `refine_phase_rows` (Phase C); the same helper will fit a future
/// shard-parallelised `team_payoff_matrix_switching` without changes.
///
/// The closure is given `i_global` (already offset by `row_start`) so
/// callers do not need to translate indices manually; the parent
/// orchestrator can fan out non-overlapping row ranges and concatenate
/// the returned sub-matrices to reproduce the full matrix bit-exactly,
/// as long as `cell_fn` itself is pure and deterministic.
pub fn build_row_shard(
  size_b : Int,
  row_start : Int,
  row_end : Int,
  cell_fn : (Int, Int) -> Double,
) -> Array[Array[Double]] {
  if row_end <= row_start {
    return []
  }
  let n_rows = row_end - row_start
  let result = Array::make(n_rows, ([] : Array[Double]))
  for i in 0..<n_rows {
    let i_global = row_start + i
    let row = Array::make(size_b, 0.0)
    for j in 0..<size_b {
      row[j] = cell_fn(i_global, j)
    }
    result[i] = row
  }
  result
}

///|
/// Pick the combatants at `indices` from `team`, preserving order.
fn pick_combatants(
  team : Array[Combatant],
  indices : Array[Int],
) -> Array[Combatant] {
  let out = Array::make(indices.length(), team[0])
  for i in 0..<indices.length() {
    out[i] = team[indices[i]]
  }
  out
}

///|
/// Team-level payoff matrix using SwitchingGame DP. Each cell is the Nash
/// value of the extensive-form game between the two selected sub-teams.
pub fn team_payoff_matrix_switching(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  turn_limit : Int,
  disk? : @damage_cache.DamageDiskCache? = None,
  progress? : (ProgressEvent) -> Unit = noop_progress,
  dp_log_every? : Int = 0,
) -> @nash.FiniteMatrix raise PayoffError {
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
  let total = size_a * size_b
  progress(PhaseStart("dp-full", total))
  let data = Array::make(size_a, ([] : Array[Double]))
  for i in 0..<size_a {
    let row = Array::make(size_b, 0.0)
    for j in 0..<size_b {
      progress(CellStart(sel_a[i], sel_b[j], i, j, "dp-full"))
      let picked_a = pick_combatants(team_a, sel_a[i])
      let picked_b = pick_combatants(team_b, sel_b[j])
      row[j] = switching_game_winrate(
        picked_a,
        picked_b,
        turn_limit,
        disk~,
        progress~,
        dp_log_every~,
      )
      progress(CellDone(sel_a[i], sel_b[j], i, j, "dp-full"))
      progress(PhaseProgress("dp-full", i * size_b + j + 1, total))
    }
    data[i] = row
  }
  progress(PhaseEnd("dp-full"))
  match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise EmptyCombatants
  }
}

///|
/// Build the selection-level team payoff matrix under the given
/// `TeamPayoffModel`.
///
/// - `SwitchingGame` evaluates selection-vs-selection as an extensive-form
///   game with switching (turn_limit = `DP_TURN_LIMIT`).
/// - `ScreenedSwitchingGame(...)` cannot be dispatched here because its
///   retained row/column indices must flow back to the caller
///   (`compute_select_with_team_model`). Use
///   `team_payoff_matrix_screened` directly for that variant.
pub fn team_payoff_matrix_with_team_model(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  team_model : TeamPayoffModel,
  disk? : @damage_cache.DamageDiskCache? = None,
  progress? : (ProgressEvent) -> Unit = noop_progress,
  dp_log_every? : Int = 0,
) -> @nash.FiniteMatrix raise PayoffError {
  match team_model {
    SwitchingGame(turn_limit) => {
      match format {
        Double =>
          raise UnsupportedFormat(
            "switching_game does not support double format (single-active model only)",
          )
        Single => ()
      }
      team_payoff_matrix_switching(
        team_a,
        team_b,
        format,
        turn_limit,
        disk~,
        progress~,
        dp_log_every~,
      )
    }
    ScreenedSwitchingGame(_, _, _, _) =>
      raise UnsupportedFormat(
        "screened_switching_game must be dispatched via compute_select_with_team_model (retained indices required)",
      )
  }
}
