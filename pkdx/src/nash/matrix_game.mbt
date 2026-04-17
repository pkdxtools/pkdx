///|
/// Matrix game primitives for zero-sum two-player games.
///
/// - `FiniteMatrix`: payoff matrix validated to be rectangular and finite.
/// - `MixedStrategy`: probability simplex vector.
/// - `LpResult`: outcome of a Nash equilibrium computation.
///
/// Reference: von Neumann (1928) minimax theorem; Dantzig (1951) LP equivalence
/// (Cowles Monograph 13, Ch. XX).

///|
pub enum MatrixError {
  NonRectangular
  NonFinite
  Empty
} derive(Show, Eq)

///|
pub enum StrategyError {
  NegativeProbability
  NotNormalized
  EmptyStrategy
} derive(Show, Eq)

///|
pub struct FiniteMatrix {
  data : Array[Array[Double]]
  rows : Int
  cols : Int
} derive(Show, Eq)

///|
/// Construct a FiniteMatrix from a row-major 2D array.
///
/// Fails if the input is empty, jagged, or contains NaN/Inf.
pub fn FiniteMatrix::new(
  data : Array[Array[Double]],
) -> Result[FiniteMatrix, MatrixError] {
  let rows = data.length()
  if rows == 0 {
    return Err(Empty)
  }
  let cols = data[0].length()
  if cols == 0 {
    return Err(Empty)
  }
  for r in 0..<rows {
    if data[r].length() != cols {
      return Err(NonRectangular)
    }
    for c in 0..<cols {
      let v = data[r][c]
      if v.is_nan() || v.is_inf() {
        return Err(NonFinite)
      }
    }
  }
  // Deep copy to enforce immutability of the validated value.
  let copied : Array[Array[Double]] = Array::make(rows, [])
  for r in 0..<rows {
    copied[r] = data[r].copy()
  }
  Ok(FiniteMatrix::{ data: copied, rows, cols })
}

///|
pub fn FiniteMatrix::rows(self : FiniteMatrix) -> Int {
  self.rows
}

///|
pub fn FiniteMatrix::cols(self : FiniteMatrix) -> Int {
  self.cols
}

///|
pub fn FiniteMatrix::at(self : FiniteMatrix, row : Int, col : Int) -> Double {
  self.data[row][col]
}

///|
/// Column player's payoff matrix in a zero-sum game: -Aᵀ.
pub fn FiniteMatrix::zero_sum_opponent(self : FiniteMatrix) -> FiniteMatrix {
  let out : Array[Array[Double]] = Array::make(self.cols, [])
  for c in 0..<self.cols {
    let row : Array[Double] = Array::make(self.rows, 0.0)
    for r in 0..<self.rows {
      row[r] = -self.data[r][c]
    }
    out[c] = row
  }
  // Bypass validation — we know it's finite and rectangular by construction.
  FiniteMatrix::{ data: out, rows: self.cols, cols: self.rows }
}

///|
pub struct MixedStrategy {
  probs : Array[Double]
} derive(Show, Eq)

///|
const STRATEGY_SUM_TOLERANCE : Double = 1.0e-9

///|
/// Construct a MixedStrategy from a probability vector.
///
/// Requires all components non-negative and sum within 1e-9 of 1.
pub fn MixedStrategy::new(
  probs : Array[Double],
) -> Result[MixedStrategy, StrategyError] {
  let n = probs.length()
  if n == 0 {
    return Err(EmptyStrategy)
  }
  let mut sum = 0.0
  for i in 0..<n {
    let p = probs[i]
    if p.is_nan() || p < 0.0 {
      return Err(NegativeProbability)
    }
    sum += p
  }
  if (sum - 1.0).abs() > STRATEGY_SUM_TOLERANCE {
    return Err(NotNormalized)
  }
  Ok(MixedStrategy::{ probs: probs.copy() })
}

///|
/// Uniform distribution over n strategies.
pub fn MixedStrategy::uniform(n : Int) -> MixedStrategy {
  let p = 1.0 / n.to_double()
  MixedStrategy::{ probs: Array::make(n, p) }
}

///|
pub fn MixedStrategy::len(self : MixedStrategy) -> Int {
  self.probs.length()
}

///|
pub fn MixedStrategy::at(self : MixedStrategy, i : Int) -> Double {
  self.probs[i]
}

///|
pub fn MixedStrategy::to_array(self : MixedStrategy) -> Array[Double] {
  self.probs.copy()
}

///|
/// Expected payoff for the row player: pᵀ A q.
pub fn expected_payoff(
  row : MixedStrategy,
  matrix : FiniteMatrix,
  col : MixedStrategy,
) -> Double {
  let mut total = 0.0
  for r in 0..<matrix.rows {
    let pr = row.probs[r]
    for c in 0..<matrix.cols {
      total += pr * matrix.data[r][c] * col.probs[c]
    }
  }
  total
}

///|
/// Player selector for best-response computations.
pub(all) enum PlayerAxis {
  Row
  Col
} derive(Show, Eq)

///|
/// Best response of one player to the other's strategy.
///
/// For `Row`: returns `(argmax_i Σ_j A[i,j]·opponent(j), max value)`.
/// For `Col`: returns `(argmin_j Σ_i A[i,j]·opponent(i), min value)`.
///
/// `opponent(k)` is the probability the opponent plays its k-th action;
/// passing a closure lets callers supply either `MixedStrategy::at` or a raw
/// `Array[Double]` lookup without converting between them.
pub fn best_response(
  matrix : FiniteMatrix,
  axis : PlayerAxis,
  opponent : (Int) -> Double,
) -> (Int, Double) {
  match axis {
    Row => {
      let mut best = 0
      let mut best_val = 0.0
      for i in 0..<matrix.rows() {
        let mut s = 0.0
        for j in 0..<matrix.cols() {
          s += matrix.at(i, j) * opponent(j)
        }
        if i == 0 || s > best_val {
          best = i
          best_val = s
        }
      }
      (best, best_val)
    }
    Col => {
      let mut best = 0
      let mut best_val = 0.0
      for j in 0..<matrix.cols() {
        let mut s = 0.0
        for i in 0..<matrix.rows() {
          s += matrix.at(i, j) * opponent(i)
        }
        if j == 0 || s < best_val {
          best = j
          best_val = s
        }
      }
      (best, best_val)
    }
  }
}

///|
/// Linear program outcome for a two-player zero-sum game.
pub(all) enum LpResult {
  Optimal(
    value~ : Double,
    row_strategy~ : MixedStrategy,
    col_strategy~ : MixedStrategy
  )
  Infeasible
  Unbounded
}
