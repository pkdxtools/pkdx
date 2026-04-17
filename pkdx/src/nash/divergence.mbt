///|
/// Divergence and exploitability measures for mixed strategies.
///
/// - Row/column player exploitability (one-sided Nash gap).
/// - NashConv: sum of both players' exploitabilities (Lanctot et al. 2017).
/// - KL divergence and L1 distance over probability simplices.
///
/// Reference:
/// - Lanctot et al. (2017) "A Unified Game-Theoretic Approach to Multiagent RL",
///   https://arxiv.org/abs/1711.00832

///|
/// Exploitability gain for the row player against a fixed column strategy.
///
/// `max_i (A q)[i] − pᵀ A q` — how much more the row player could earn by
/// switching to a best response against `q`.
pub fn row_exploitability(
  matrix : FiniteMatrix,
  row : MixedStrategy,
  col : MixedStrategy,
) -> Double {
  let (_, best) = best_response(matrix, Row, fn(j) { col.at(j) })
  best - expected_payoff(row, matrix, col)
}

///|
/// Exploitability gain for the column player against a fixed row strategy.
///
/// `pᵀ A q − min_j (pᵀ A)[j]` — how much the column player could save by
/// switching to a best response against `p`.
pub fn col_exploitability(
  matrix : FiniteMatrix,
  row : MixedStrategy,
  col : MixedStrategy,
) -> Double {
  let (_, best) = best_response(matrix, Col, fn(i) { row.at(i) })
  expected_payoff(row, matrix, col) - best
}

///|
/// NashConv: sum of both players' exploitability gains. Zero iff (row, col)
/// is a Nash equilibrium (up to numerical tolerance).
///
/// For zero-sum games this equals the single-sided `exploitability` defined
/// in `solver.mbt`, because `max_i (Aq)_i − min_j (pᵀA)_j =
/// row_exploitability + col_exploitability` telescopes through the current
/// payoff `pᵀAq`.
pub fn nashconv(
  matrix : FiniteMatrix,
  row : MixedStrategy,
  col : MixedStrategy,
) -> Double {
  row_exploitability(matrix, row, col) + col_exploitability(matrix, row, col)
}

///|
/// KL divergence `D_KL(P ‖ Q) = Σᵢ P[i] · log(P[i] / Q[i])`.
///
/// Requires `P` and `Q` to have the same support shape. Entries with `P[i] = 0`
/// contribute 0 (limit convention). If `Q[i] = 0` while `P[i] > 0`, returns
/// `+∞` (encoded as `Double::infinity`).
pub fn kl_divergence(p : MixedStrategy, q : MixedStrategy) -> Double {
  if p.len() != q.len() {
    return @double.infinity
  }
  let mut total = 0.0
  for i in 0..<p.len() {
    let pi = p.at(i)
    let qi = q.at(i)
    if pi == 0.0 {
      continue
    }
    if qi == 0.0 {
      return @double.infinity
    }
    total += pi * @math.ln(pi / qi)
  }
  total
}

///|
/// L1 distance `‖P − Q‖₁ = Σᵢ |P[i] − Q[i]|`.
pub fn l1_distance(p : MixedStrategy, q : MixedStrategy) -> Double {
  if p.len() != q.len() {
    return @double.infinity
  }
  let mut total = 0.0
  for i in 0..<p.len() {
    total += (p.at(i) - q.at(i)).abs()
  }
  total
}
