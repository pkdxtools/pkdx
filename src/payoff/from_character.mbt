///|
/// Monocycle character model: each character has a scalar `power` and a 2-D
/// `MatchupVector`. The zero-sum payoff between two characters is
///
///   `A[i, j] = (pᵢ − pⱼ) + vᵢ × vⱼ`
///
/// where `×` is the 2-D cross product `(x₁·y₂ − y₁·x₂)`.
///
/// Gauge symmetry (equal-power coordinate transform): shifting the origin of
/// matchup space by `a` yields an equivalent representation with
///
///   `p' = p + v × a`,  `v' = v − a`
///
/// which preserves the payoff matrix. The `equal_power_transform` function
/// solves for `a` that equalises all powers (when such `a` exists).
///
/// Reference: monocycle_nash project, `src/monocycle_nash/character/domain.py`.

///|
pub(all) struct MatchupVector {
  x : Double
  y : Double
} derive(Show, Eq)

///|
/// 2-D cross product: `self × other = self.x · other.y − self.y · other.x`.
pub fn MatchupVector::cross(
  self : MatchupVector,
  other : MatchupVector,
) -> Double {
  self.x * other.y - self.y * other.x
}

///|
pub(all) struct Character {
  label : String
  power : Double
  v : MatchupVector
} derive(Show, Eq)

///|
/// Apply the equal-power coordinate transform with origin shift `a`.
///
/// The resulting character has `p' = p + v × a`, `v' = v − a`.
pub fn Character::convert(self : Character, a : MatchupVector) -> Character {
  Character::{
    label: self.label,
    power: self.power + self.v.cross(a),
    v: MatchupVector::{ x: self.v.x - a.x, y: self.v.y - a.y },
  }
}

///|
pub suberror CharacterError {
  EmptyCharacters
} derive(Show)

///|
/// Build the zero-sum payoff matrix `A[i, j] = (pᵢ − pⱼ) + vᵢ × vⱼ` from a
/// list of characters.
pub fn from_characters(
  chars : Array[Character],
) -> @nash.FiniteMatrix raise CharacterError {
  let n = chars.length()
  if n == 0 {
    raise EmptyCharacters
  }
  let data = Array::make(n, ([] : Array[Double]))
  for i in 0..<n {
    let row = Array::make(n, 0.0)
    for j in 0..<n {
      row[j] = chars[i].power - chars[j].power + chars[i].v.cross(chars[j].v)
    }
    data[i] = row
  }
  match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise EmptyCharacters
  }
}

///|
/// Compute an origin shift `a` that makes all characters equal-power, if one
/// exists (within numeric tolerance).
///
/// - If all powers are already equal, returns `Some({x: 0, y: 0})`.
/// - For `n ≥ 2` and non-constant powers, solves the linear system
///   `(vᵢ − v₀) · ⟨a.y, −a.x⟩ = p₀ − pᵢ` via least squares; returns `None`
///   if the system is inconsistent or rank-deficient.
pub fn equal_power_transform(chars : Array[Character]) -> MatchupVector? {
  let n = chars.length()
  if n == 0 {
    return None
  }
  let zero = MatchupVector::{ x: 0.0, y: 0.0 }
  if n == 1 {
    return Some(zero)
  }
  let p0 = chars[0].power
  let mut all_equal = true
  for i in 1..<n {
    if (chars[i].power - p0).abs() > 1.0e-12 {
      all_equal = false
      break
    }
  }
  if all_equal {
    return Some(zero)
  }

  // For each i ≥ 1, equation:
  //   −(vᵢ.y − v₀.y) · a.x + (vᵢ.x − v₀.x) · a.y = p₀ − pᵢ
  let v0 = chars[0].v

  // Special case: a single equation (n = 2). Use the minimum-norm solution to
  // avoid the rank-deficient normal equations.
  if n == 2 {
    let c_ax = -(chars[1].v.y - v0.y)
    let c_ay = chars[1].v.x - v0.x
    let d = p0 - chars[1].power
    let norm2 = c_ax * c_ax + c_ay * c_ay
    if norm2 < 1.0e-12 {
      // Zero coefficients: solvable only if the RHS is also zero.
      return if d.abs() < 1.0e-6 { Some(zero) } else { None }
    }
    return Some(MatchupVector::{ x: c_ax * d / norm2, y: c_ay * d / norm2 })
  }

  // General case (n ≥ 3): normal equations MᵀM · w = Mᵀd.
  let mut m00 = 0.0
  let mut m01 = 0.0
  let mut m11 = 0.0
  let mut rx = 0.0
  let mut ry = 0.0
  for i in 1..<n {
    let c_ax = -(chars[i].v.y - v0.y)
    let c_ay = chars[i].v.x - v0.x
    let d = p0 - chars[i].power
    m00 += c_ax * c_ax
    m01 += c_ax * c_ay
    m11 += c_ay * c_ay
    rx += c_ax * d
    ry += c_ay * d
  }
  let det = m00 * m11 - m01 * m01
  if det.abs() < 1.0e-12 {
    return None
  }
  let ax = (m11 * rx - m01 * ry) / det
  let ay = (m00 * ry - m01 * rx) / det
  // Verify the solution is exact (not a least-squares approximation).
  for i in 1..<n {
    let c_ax = -(chars[i].v.y - v0.y)
    let c_ay = chars[i].v.x - v0.x
    let d = p0 - chars[i].power
    if (c_ax * ax + c_ay * ay - d).abs() > 1.0e-6 {
      return None
    }
  }
  Some(MatchupVector::{ x: ax, y: ay })
}
