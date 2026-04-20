// k-selection 列挙 + team-level payoff matrix 構築

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
  disk~ : @damage_cache.DamageDiskCache? = None,
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
      row[j] = switching_game_winrate(picked_a, picked_b, turn_limit, disk~)
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
  disk~ : @damage_cache.DamageDiskCache? = None,
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
      team_payoff_matrix_switching(team_a, team_b, format, turn_limit, disk~)
    }
    ScreenedSwitchingGame(_, _, _, _) =>
      raise UnsupportedFormat(
        "screened_switching_game must be dispatched via compute_select_with_team_model (retained indices required)",
      )
  }
}
