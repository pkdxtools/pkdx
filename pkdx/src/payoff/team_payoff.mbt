///|
/// Team payoff: given two 6-Pokemon teams and a battle format (single = 3-pick,
/// double = 4-pick), enumerate all k-selections from each side in lexicographic
/// order and compute a selection-level zero-sum payoff matrix, where each cell
/// is the Nash value of the inner k×k character payoff sub-matrix.
///
/// The inner character payoff is derived from `winrate(·, ·, PayoffModel)`
/// rescaled to [-1, +1], and the outer matrix cell is the minimax value of
/// simultaneous k-pick commitment.

///|
pub(all) enum BattleFormat {
  Single
  Double
} derive(Show, Eq)

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
/// Rectangular cross-team payoff `A[i, j] = 2·winrate(team_a[i], team_b[j]) − 1`.
pub fn cross_payoff(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  model : PayoffModel,
) -> @nash.FiniteMatrix raise PayoffError {
  cross_payoff_with_meta(team_a, team_b, model, new_move_meta_cache())
}

///|
/// Meta-cache-aware variant of `cross_payoff`.
pub fn cross_payoff_with_meta(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  model : PayoffModel,
  meta_cache : MoveMetaCache,
) -> @nash.FiniteMatrix raise PayoffError {
  let na = team_a.length()
  let nb = team_b.length()
  if na == 0 || nb == 0 {
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
  let data = Array::make(na, ([] : Array[Double]))
  for i in 0..<na {
    let row = Array::make(nb, 0.0)
    for j in 0..<nb {
      row[j] = 2.0 * winrate_with_meta(
          team_a[i], team_b[j], model, meta_cache,
        ) -
        1.0
    }
    data[i] = row
  }
  match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise EmptyCombatants
  }
}

///|
/// Extract the row/col sub-matrix `M[rows, cols]` from a finite matrix.
fn sub_matrix(
  m : @nash.FiniteMatrix,
  rows : Array[Int],
  cols : Array[Int],
) -> @nash.FiniteMatrix {
  let data = Array::make(rows.length(), ([] : Array[Double]))
  for i in 0..<rows.length() {
    let r = Array::make(cols.length(), 0.0)
    for j in 0..<cols.length() {
      r[j] = m.at(rows[i], cols[j])
    }
    data[i] = r
  }
  match @nash.FiniteMatrix::new(data) {
    Ok(m2) => m2
    Err(_) => abort("sub_matrix construction failed")
  }
}

///|
/// Inner-Nash value of a payoff sub-matrix. `0.0` if LP is infeasible or
/// unbounded (should not happen for ±1 / 0 inputs, which are always bounded).
fn inner_nash_value(m : @nash.FiniteMatrix) -> Double {
  let lp = try @nash.solve_zero_sum(m) catch {
    _ => @nash.LpResult::Infeasible
  }
  match lp {
    Optimal(value~, ..) => value
    _ => 0.0
  }
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
/// Team-level payoff matrix using `SwitchingGame(turn_limit)`. Each cell is
/// the Nash value of the extensive-form game between the two selected
/// sub-teams.
fn team_payoff_matrix_switching(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  turn_limit : Int,
  meta_cache : MoveMetaCache,
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
  let sel_a = combinations(na, k)
  let sel_b = combinations(nb, k)
  let size_a = sel_a.length()
  let size_b = sel_b.length()
  let data = Array::make(size_a, ([] : Array[Double]))
  for i in 0..<size_a {
    let row = Array::make(size_b, 0.0)
    for j in 0..<size_b {
      let picked_a = pick_combatants(team_a, sel_a[i])
      let picked_b = pick_combatants(team_b, sel_b[j])
      row[j] = switching_game_winrate_with_meta(
        picked_a, picked_b, turn_limit, meta_cache,
      )
    }
    data[i] = row
  }
  match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise EmptyCombatants
  }
}

///|
/// Build the selection-level team payoff matrix under the given
/// `TeamPayoffModel`. `Pairwise(m)` delegates to the legacy
/// `team_payoff_matrix` for backward compatibility;
/// `SwitchingGame(turn_limit)` evaluates selection-vs-selection as an
/// extensive-form game with switching.
pub fn team_payoff_matrix_with_team_model(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  team_model : TeamPayoffModel,
) -> @nash.FiniteMatrix raise PayoffError {
  team_payoff_matrix_with_team_model_and_meta(
    team_a, team_b, format, team_model, new_move_meta_cache(),
  )
}

///|
/// Meta-cache-aware dispatcher. Threads `meta_cache` into both the
/// pairwise and switching branches.
pub fn team_payoff_matrix_with_team_model_and_meta(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  team_model : TeamPayoffModel,
  meta_cache : MoveMetaCache,
) -> @nash.FiniteMatrix raise PayoffError {
  match team_model {
    Pairwise(model) =>
      team_payoff_matrix_with_meta(team_a, team_b, format, model, meta_cache)
    SwitchingGame(turn_limit) =>
      team_payoff_matrix_switching(
        team_a, team_b, format, turn_limit, meta_cache,
      )
  }
}

///|
/// Build the selection-level team payoff matrix. Rows/cols enumerate
/// k-combinations of `team_a` / `team_b` in lexicographic order; each cell is
/// the Nash value of the inner k×k sub-matrix.
pub fn team_payoff_matrix(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  model : PayoffModel,
) -> @nash.FiniteMatrix raise PayoffError {
  team_payoff_matrix_with_meta(
    team_a, team_b, format, model, new_move_meta_cache(),
  )
}

///|
/// Meta-cache-aware variant of `team_payoff_matrix`.
pub fn team_payoff_matrix_with_meta(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
  format : BattleFormat,
  model : PayoffModel,
  meta_cache : MoveMetaCache,
) -> @nash.FiniteMatrix raise PayoffError {
  let k = pick_count(format)
  let na = team_a.length()
  let nb = team_b.length()
  if na < k || nb < k {
    raise EmptyCombatants
  }
  let individual = cross_payoff_with_meta(team_a, team_b, model, meta_cache)
  let sel_a = combinations(na, k)
  let sel_b = combinations(nb, k)
  let size_a = sel_a.length()
  let size_b = sel_b.length()
  let data = Array::make(size_a, ([] : Array[Double]))
  for i in 0..<size_a {
    let row = Array::make(size_b, 0.0)
    for j in 0..<size_b {
      let sub = sub_matrix(individual, sel_a[i], sel_b[j])
      row[j] = inner_nash_value(sub)
    }
    data[i] = row
  }
  match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise EmptyCombatants
  }
}
