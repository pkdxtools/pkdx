///|
/// Public API for zero-sum two-player matrix game Nash equilibrium.
///
/// Reduces the game to an LP via the standard shift-and-normalize technique
/// (Dantzig 1951): shift the payoff matrix so all entries are positive, solve
/// the primal LP `min Σyᵢ s.t. A'ᵀy ≥ 1, y ≥ 0` and the dual LP
/// `max Σxⱼ s.t. A'x ≤ 1, x ≥ 0`, then recover mixed strategies via
/// `pᵢ = yᵢ / Σy`, `qⱼ = xⱼ / Σx`, and value `v = 1/Σy − shift`.
///
/// Reference: Ferguson, *Game Theory* Part II §4.

///|
pub suberror SolverError {
  /// Propagated from the underlying simplex solver.
  SimplexFailure(SimplexError)
  /// Zero-sum LP returned Infeasible/Unbounded unexpectedly (should never
  /// occur for a finite matrix game; indicates a numerical issue).
  InconsistentGame(String)
} derive(Show)

///|
/// Find the minimum entry of a FiniteMatrix.
fn min_entry(matrix : FiniteMatrix) -> Double {
  let mut m = matrix.at(0, 0)
  for r in 0..<matrix.rows() {
    for c in 0..<matrix.cols() {
      let v = matrix.at(r, c)
      if v < m {
        m = v
      }
    }
  }
  m
}

///|
/// Tolerance for pure-saddle-point detection in `solve_zero_sum`. A game has a
/// pure saddle iff `maxmin == minmax` (von Neumann); when the gap is below this
/// tolerance we return the pure-strategy equilibrium directly instead of
/// routing through the shift-and-normalise LP path. This is both a speedup
/// (no simplex iterations on matrices that are trivially resolved) and a
/// robustness fix: highly degenerate LPs (many near-identical rows/columns)
/// can cause the two-phase tableau simplex to make numerically bad pivots and
/// emit a negative strategy component, which `sanitize_strategy` then rejects
/// as `InconsistentGame`. The pure-saddle fast path sidesteps the simplex
/// entirely for that class of inputs.
const SADDLE_TOL : Double = 1.0e-10

///|
/// Pure-strategy saddle point of a finite zero-sum matrix if one exists.
///
/// Returns `Some((i*, j*, v))` when `max_i min_j A[i,j] == min_j max_i A[i,j]`
/// within `SADDLE_TOL`; `v` is that saddle value and `(i*, j*)` are the first
/// row / column that attain it. Returns `None` when the gap is strictly
/// positive (i.e. a truly mixed equilibrium is required).
fn detect_pure_saddle(matrix : FiniteMatrix) -> (Int, Int, Double)? {
  let rows = matrix.rows()
  let cols = matrix.cols()
  // Row-minima with argmin.
  let mut best_row = 0
  let mut best_row_min = matrix.at(0, 0)
  // Initialize best_row_min to row 0's min.
  for c in 0..<cols {
    let v = matrix.at(0, c)
    if v < best_row_min {
      best_row_min = v
    }
  }
  for r in 1..<rows {
    let mut row_min = matrix.at(r, 0)
    for c in 1..<cols {
      let v = matrix.at(r, c)
      if v < row_min {
        row_min = v
      }
    }
    if row_min > best_row_min {
      best_row_min = row_min
      best_row = r
    }
  }
  // Col-maxima with argmax... actually argmin of col_max.
  let mut best_col = 0
  let mut best_col_max = matrix.at(0, 0)
  for r in 0..<rows {
    let v = matrix.at(r, 0)
    if v > best_col_max {
      best_col_max = v
    }
  }
  for c in 1..<cols {
    let mut col_max = matrix.at(0, c)
    for r in 1..<rows {
      let v = matrix.at(r, c)
      if v > col_max {
        col_max = v
      }
    }
    if col_max < best_col_max {
      best_col_max = col_max
      best_col = c
    }
  }
  let gap = best_col_max - best_row_min
  if gap <= SADDLE_TOL {
    // Saddle value: arithmetic mean avoids biasing toward either bound when
    // the gap is ≤ 0 due to FP noise. The true value lies in [best_row_min,
    // best_col_max].
    let value = (best_row_min + best_col_max) / 2.0
    return Some((best_row, best_col, value))
  }
  None
}

///|
/// Build a pure `MixedStrategy` concentrated at index `idx` of length `n`.
fn pure_strategy(n : Int, idx : Int) -> MixedStrategy raise SolverError {
  let probs = Array::make(n, 0.0)
  probs[idx] = 1.0
  match MixedStrategy::new(probs) {
    Ok(s) => s
    Err(e) =>
      raise InconsistentGame("pure strategy build failed: " + e.to_string())
  }
}

///|
/// Solve the zero-sum game for the row player's mixed strategy by LP.
///
/// Input: positive-entry matrix A' (m × n).
/// Output: length-m vector y ≥ 0 with Σy = S, where 1/S is the shifted value.
/// The primal LP is `min Σyᵢ s.t. A'ᵀy ≥ 1`, encoded as `max −Σyᵢ s.t. −A'ᵀy ≤ −1`.
fn solve_row_lp(
  shifted : Array[Array[Double]],
  rows : Int,
  cols : Int,
) -> Array[Double] raise SolverError {
  // c_lp: length rows, all -1 (maximize -Σy)
  let c_lp = Array::make(rows, -1.0)
  // a_lp: cols × rows matrix, a_lp[j][i] = -shifted[i][j]
  let a_lp = Array::make(cols, ([] : Array[Double]))
  for j in 0..<cols {
    let row = Array::make(rows, 0.0)
    for i in 0..<rows {
      row[i] = -shifted[i][j]
    }
    a_lp[j] = row
  }
  let b_lp = Array::make(cols, -1.0)
  let problem = LpProblem::{ c: c_lp, a: a_lp, b: b_lp }
  let status = solve_lp(problem) catch { err => raise SimplexFailure(err) }
  match status {
    SimplexStatus::Optimal(x~, ..) => x
    SimplexStatus::Infeasible => raise InconsistentGame("row LP infeasible")
    SimplexStatus::Unbounded => raise InconsistentGame("row LP unbounded")
  }
}

///|
/// Solve the zero-sum game for the column player's mixed strategy by LP.
///
/// Input: positive-entry matrix A' (m × n).
/// Output: length-n vector x ≥ 0 with Σx = S = 1/shifted_value.
/// LP: `max Σxⱼ s.t. A'x ≤ 1, x ≥ 0`.
fn solve_col_lp(
  shifted : Array[Array[Double]],
  rows : Int,
  cols : Int,
) -> Array[Double] raise SolverError {
  let c_lp = Array::make(cols, 1.0)
  // a_lp: rows × cols, direct copy of shifted
  let a_lp = Array::make(rows, ([] : Array[Double]))
  for i in 0..<rows {
    a_lp[i] = shifted[i].copy()
  }
  let b_lp = Array::make(rows, 1.0)
  let problem = LpProblem::{ c: c_lp, a: a_lp, b: b_lp }
  let status = solve_lp(problem) catch { err => raise SimplexFailure(err) }
  match status {
    SimplexStatus::Optimal(x~, ..) => x
    SimplexStatus::Infeasible => raise InconsistentGame("col LP infeasible")
    SimplexStatus::Unbounded => raise InconsistentGame("col LP unbounded")
  }
}

///|
/// Compute the Nash equilibrium of a finite two-player zero-sum game.
///
/// Always returns `Optimal` for valid finite matrices — by von Neumann's
/// minimax theorem, every such game has an equilibrium in mixed strategies.
pub fn solve_zero_sum(matrix : FiniteMatrix) -> LpResult raise SolverError {
  let rows = matrix.rows()
  let cols = matrix.cols()
  // Fast path: if the matrix has a pure-strategy saddle, return it directly.
  // This both speeds up obvious games and sidesteps simplex instability on
  // highly degenerate LPs (see `SADDLE_TOL` doc comment for details).
  match detect_pure_saddle(matrix) {
    Some((i, j, v)) =>
      return Optimal(
        value=v,
        row_strategy=pure_strategy(rows, i),
        col_strategy=pure_strategy(cols, j),
      )
    None => ()
  }
  let min_e = min_entry(matrix)
  // Shift so that all entries of A' are ≥ 1 (strictly positive value guaranteed).
  let shift = if min_e < 1.0 { 1.0 - min_e } else { 0.0 }
  let shifted = Array::make(rows, ([] : Array[Double]))
  for r in 0..<rows {
    let row = Array::make(cols, 0.0)
    for c in 0..<cols {
      row[c] = matrix.at(r, c) + shift
    }
    shifted[r] = row
  }
  let y = solve_row_lp(shifted, rows, cols)
  let x = solve_col_lp(shifted, rows, cols)
  let mut sum_y = 0.0
  for i in 0..<rows {
    sum_y += y[i]
  }
  if sum_y <= 0.0 {
    raise InconsistentGame("zero row LP sum")
  }
  let mut sum_x = 0.0
  for j in 0..<cols {
    sum_x += x[j]
  }
  if sum_x <= 0.0 {
    raise InconsistentGame("zero col LP sum")
  }
  let v_shifted = 1.0 / sum_y
  let value = v_shifted - shift
  let p = Array::make(rows, 0.0)
  for i in 0..<rows {
    p[i] = y[i] / sum_y
  }
  let q = Array::make(cols, 0.0)
  for j in 0..<cols {
    q[j] = x[j] / sum_x
  }
  let row_strategy = sanitize_strategy(p, "row")
  let col_strategy = sanitize_strategy(q, "col")
  Optimal(value~, row_strategy~, col_strategy~)
}

///|
/// Clamp tiny floating-point noise (e.g. `-2.7e-17` from simplex in degenerate
/// games) to zero and renormalize, then construct a `MixedStrategy`.
///
/// Tolerance is 1e-9 — anything more negative than that is treated as a real
/// numerical failure and surfaced as `InconsistentGame`. The previous
/// implementation silently fell back to `MixedStrategy::uniform`, which could
/// replace a valid equilibrium with a completely different strategy.
fn sanitize_strategy(
  probs : Array[Double],
  which : String,
) -> MixedStrategy raise SolverError {
  let n = probs.length()
  let cleaned = Array::make(n, 0.0)
  let mut sum = 0.0
  let neg_tol = 1.0e-9
  for i in 0..<n {
    let v = probs[i]
    if v.is_nan() {
      raise InconsistentGame(which + " strategy contains NaN")
    }
    if v < -neg_tol {
      raise InconsistentGame(
        which + " strategy has negative component " + v.to_string(),
      )
    }
    let c = if v < 0.0 { 0.0 } else { v }
    cleaned[i] = c
    sum += c
  }
  if sum <= 0.0 {
    raise InconsistentGame(which + " strategy sums to zero after clamping")
  }
  for i in 0..<n {
    cleaned[i] = cleaned[i] / sum
  }
  match MixedStrategy::new(cleaned) {
    Ok(s) => s
    Err(e) =>
      raise InconsistentGame(
        which + " strategy construction failed: " + e.to_string(),
      )
  }
}

///|
/// Exploitability of a pair of mixed strategies against the payoff matrix.
///
/// Defined as `max_j (Aᵀp)[j] − min_i (Aq)[i]`, which is 0 iff (p, q) is a
/// Nash equilibrium (up to floating-point tolerance).
pub fn exploitability(
  matrix : FiniteMatrix,
  row : MixedStrategy,
  col : MixedStrategy,
) -> Double {
  let (_, best_row_value) = best_response(matrix, Row, fn(j) { col.at(j) })
  let (_, best_col_value) = best_response(matrix, Col, fn(i) { row.at(i) })
  best_row_value - best_col_value
}
