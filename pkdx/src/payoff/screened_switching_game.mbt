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
/// `combinations(|team|, k)` enumeration (ascending). Caller is responsible
/// for using these indices to slice the selection labels / strategy vectors
/// down to the retained subset.
pub fn team_payoff_matrix_screened(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  mc_trials : Int,
  mc_seed : UInt64,
  keep_top_quantile : Double,
  refine_turn_limit~ : Int = DP_TURN_LIMIT,
  mc_turn_limit~ : Int = MC_TURN_LIMIT,
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
  let sel_a = combinations(na, k)
  let sel_b = combinations(nb, k)
  let size_a = sel_a.length()
  let size_b = sel_b.length()

  // Short-circuit: keep_top >= 1.0 means retain every row / column, so we can
  // skip the screening pass entirely and delegate to the raw SwitchingGame
  // matrix builder. This guarantees bit-exact parity with the unscreened path
  // (required by the oracle test) and avoids duplicate MC + refine work.
  if keep_top_quantile >= 1.0 {
    let m = team_payoff_matrix_switching(team_a, team_b, format, refine_turn_limit)
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
  let screen = Array::make(size_a, ([] : Array[Double]))
  for i in 0..<size_a {
    let row = Array::make(size_b, 0.0)
    for j in 0..<size_b {
      let cell_idx = (i * size_b + j).to_uint64()
      let picked_a = pick_combatants(team_a, sel_a[i])
      let picked_b = pick_combatants(team_b, sel_b[j])
      row[j] = team_monte_carlo_value(
        picked_a, picked_b, mc_trials, mc_seed ^ cell_idx,
        turn_limit=mc_turn_limit,
      )
    }
    screen[i] = row
  }

  // Phase B: Nash-weighted scoring. Solve Nash on the screening matrix and
  // score each selection by its expected value under the opponent's equilibrium
  // strategy. All Nash-support rows achieve the game value (tied at top);
  // non-support rows score strictly less. This guarantees screening never
  // drops a Nash-support selection.
  let (row_score, col_score) = screen_nash_scores(screen, size_a, size_b)
  let row_keep = retain_top_indices(row_score, keep_top_quantile)
  let col_keep = retain_top_indices(col_score, keep_top_quantile)

  // Phase C: refine the retained sub-matrix with full SwitchingGame DP.
  let data = Array::make(row_keep.length(), ([] : Array[Double]))
  for i in 0..<row_keep.length() {
    let row = Array::make(col_keep.length(), 0.0)
    for j in 0..<col_keep.length() {
      let picked_a = pick_combatants(team_a, sel_a[row_keep[i]])
      let picked_b = pick_combatants(team_b, sel_b[col_keep[j]])
      row[j] = switching_game_winrate(picked_a, picked_b, refine_turn_limit)
    }
    data[i] = row
  }
  let m = match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise EmptyCombatants
  }
  (m, row_keep, col_keep)
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
  // Simple selection: pick top-`keep` by score via an O(n^2) pass — n ≤ 20
  // in practice (C(6,3)), so this stays under a microsecond.
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
