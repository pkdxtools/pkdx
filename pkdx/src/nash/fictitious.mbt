///|
/// Iterative learning solvers for two-player zero-sum games.
///
/// - `fictitious_play`: Brown (1951) / Robinson (1951). Each player best-responds
///   to the opponent's empirical frequency; the empirical frequencies converge
///   to Nash in zero-sum games.
/// - `mwu`: Multiplicative Weights Update (Freund & Schapire 1999). Regret is
///   bounded by O(sqrt(T log n)); time-averaged strategies converge to Nash.
///
/// References:
/// - Robinson (1951) "An iterative method of solving a game", Annals of Math 54.
/// - Freund & Schapire (1999), *Games Econ. Behav.* 29, DOI:10.1006/game.1999.0738.

///|
fn argmax_row_response(matrix : FiniteMatrix, q : Array[Double]) -> Int {
  let (idx, _) = best_response(matrix, Row, fn(j) { q[j] })
  idx
}

///|
fn argmin_col_response(matrix : FiniteMatrix, p : Array[Double]) -> Int {
  let (idx, _) = best_response(matrix, Col, fn(i) { p[i] })
  idx
}

///|
fn normalize(counts : Array[Int]) -> Array[Double] {
  let mut total = 0
  for v in counts {
    total += v
  }
  let denom = total.to_double()
  let out = Array::make(counts.length(), 0.0)
  if denom > 0.0 {
    for i in 0..<counts.length() {
      out[i] = counts[i].to_double() / denom
    }
  }
  out
}

///|
/// Fictitious play for a zero-sum matrix game.
///
/// Returns time-averaged row and column mixed strategies after `iterations`
/// rounds. The first round uses deterministic index-0 actions for tie-breaking.
pub fn fictitious_play(
  matrix : FiniteMatrix,
  iterations : Int,
) -> (MixedStrategy, MixedStrategy) {
  let rows = matrix.rows()
  let cols = matrix.cols()
  let p_count = Array::make(rows, 0)
  let q_count = Array::make(cols, 0)
  // Seed round 1 with action 0 for both.
  p_count[0] = 1
  q_count[0] = 1
  for _t in 1..<iterations {
    let q_emp = normalize(q_count)
    let p_emp = normalize(p_count)
    let best_row = argmax_row_response(matrix, q_emp)
    let best_col = argmin_col_response(matrix, p_emp)
    p_count[best_row] = p_count[best_row] + 1
    q_count[best_col] = q_count[best_col] + 1
  }
  let p = match MixedStrategy::new(normalize(p_count)) {
    Ok(s) => s
    Err(_) => MixedStrategy::uniform(rows)
  }
  let q = match MixedStrategy::new(normalize(q_count)) {
    Ok(s) => s
    Err(_) => MixedStrategy::uniform(cols)
  }
  (p, q)
}

///|
/// Multiplicative Weights Update solver for a zero-sum matrix game.
///
/// `eta` is the learning rate; `sqrt(log(max(rows,cols)) / iterations)` is a
/// standard choice. Returns time-averaged strategies.
pub fn mwu(
  matrix : FiniteMatrix,
  iterations : Int,
  eta : Double,
) -> (MixedStrategy, MixedStrategy) {
  let rows = matrix.rows()
  let cols = matrix.cols()
  let w_row = Array::make(rows, 1.0)
  let w_col = Array::make(cols, 1.0)
  // Scale payoffs to [0, 1] for stable exp updates.
  let mut min_e = matrix.at(0, 0)
  let mut max_e = matrix.at(0, 0)
  for r in 0..<rows {
    for c in 0..<cols {
      let v = matrix.at(r, c)
      if v < min_e {
        min_e = v
      }
      if v > max_e {
        max_e = v
      }
    }
  }
  let span = if max_e > min_e { max_e - min_e } else { 1.0 }
  let p_sum = Array::make(rows, 0.0)
  let q_sum = Array::make(cols, 0.0)
  for _t in 0..<iterations {
    let mut sw_row = 0.0
    for i in 0..<rows {
      sw_row += w_row[i]
    }
    let mut sw_col = 0.0
    for j in 0..<cols {
      sw_col += w_col[j]
    }
    let p = Array::make(rows, 0.0)
    for i in 0..<rows {
      p[i] = w_row[i] / sw_row
      p_sum[i] = p_sum[i] + p[i]
    }
    let q = Array::make(cols, 0.0)
    for j in 0..<cols {
      q[j] = w_col[j] / sw_col
      q_sum[j] = q_sum[j] + q[j]
    }
    // Row player: reward r[i] = Σ_j (A[i,j] − min_e) / span · q[j] ∈ [0, 1].
    for i in 0..<rows {
      let mut gain = 0.0
      for j in 0..<cols {
        gain += (matrix.at(i, j) - min_e) / span * q[j]
      }
      w_row[i] = w_row[i] * @math.exp(eta * gain)
    }
    // Col player: loss l[j] = Σ_i (A[i,j] − min_e) / span · p[i] ∈ [0, 1].
    for j in 0..<cols {
      let mut loss = 0.0
      for i in 0..<rows {
        loss += (matrix.at(i, j) - min_e) / span * p[i]
      }
      w_col[j] = w_col[j] * @math.exp(-eta * loss)
    }
  }
  let t = iterations.to_double()
  let p_avg = Array::make(rows, 0.0)
  for i in 0..<rows {
    p_avg[i] = p_sum[i] / t
  }
  let q_avg = Array::make(cols, 0.0)
  for j in 0..<cols {
    q_avg[j] = q_sum[j] / t
  }
  let p = match MixedStrategy::new(p_avg) {
    Ok(s) => s
    Err(_) => MixedStrategy::uniform(rows)
  }
  let q = match MixedStrategy::new(q_avg) {
    Ok(s) => s
    Err(_) => MixedStrategy::uniform(cols)
  }
  (p, q)
}
