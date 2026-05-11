///|
fn mv(x : Double, y : Double) -> MatchupVector {
  MatchupVector::{ x, y }
}

///|
fn ch(label : String, p : Double, x : Double, y : Double) -> Character {
  Character::{ label, power: p, v: mv(x, y) }
}

///|
test "from_characters_empty_list_errors" {
  let empty : Array[Character] = []
  let res : Result[@nash.FiniteMatrix, CharacterError] = Ok(
    from_characters(empty),
  ) catch {
    err => Err(err)
  }
  inspect(res, content="Err(EmptyCharacters)")
}

///|
test "from_characters_reconstructs_rps_from_monocycle_nash_baseline" {
  // baseline/janken characters from monocycle_nash README.
  let chars = [
    ch("A", 0.0, 2.0, 0.0),
    ch("B", 0.0, -1.0, 1.7),
    ch("C", 0.0, -1.0, -1.7),
  ]
  let m = from_characters(chars)
  // A × B = 2·1.7 − 0·(−1) = 3.4
  assert_true((m.at(0, 1) - 3.4).abs() < 1.0e-12)
  // A × C = 2·(−1.7) − 0·(−1) = −3.4
  assert_true((m.at(0, 2) - -3.4).abs() < 1.0e-12)
  // B × C = (−1)·(−1.7) − 1.7·(−1) = 1.7 + 1.7 = 3.4
  assert_true((m.at(1, 2) - 3.4).abs() < 1.0e-12)
  // Cyclically symmetric — Nash equilibrium is uniform with value 0.
  match @nash.solve_zero_sum(m) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true(value.abs() < 1.0e-7)
      for i in 0..<3 {
        assert_true((row_strategy.at(i) - 1.0 / 3.0).abs() < 1.0e-6)
        assert_true((col_strategy.at(i) - 1.0 / 3.0).abs() < 1.0e-6)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "from_characters_is_antisymmetric_with_zero_diagonal" {
  let chars = [
    ch("x", 1.5, 0.7, -0.3),
    ch("y", -0.5, 2.0, 1.1),
    ch("z", 3.2, -1.5, 0.4),
  ]
  let m = from_characters(chars)
  // Zero diagonal: A[i,i] = (pᵢ − pᵢ) + vᵢ × vᵢ = 0.
  for i in 0..<3 {
    assert_true(m.at(i, i).abs() < 1.0e-12)
  }
  // Antisymmetric: A[i,j] + A[j,i] = 0 (zero-sum game).
  for i in 0..<3 {
    for j in 0..<3 {
      assert_true((m.at(i, j) + m.at(j, i)).abs() < 1.0e-12)
    }
  }
}

///|
test "power_shift_invariance_and_compat_rotation_invariance" {
  let chars = [
    ch("A", 1.0, 2.0, 0.5),
    ch("B", -1.0, -1.0, 1.7),
    ch("C", 0.5, 0.3, -1.2),
  ]
  let m = from_characters(chars)
  // 1. Adding a constant to all powers leaves the matrix unchanged (since
  //    (pᵢ + c) − (pⱼ + c) = pᵢ − pⱼ).
  let shift = 7.5
  let shifted = chars.map(fn(c) {
    Character::{ label: c.label, power: c.power + shift, v: c.v }
  })
  let m_shifted = from_characters(shifted)
  for i in 0..<3 {
    for j in 0..<3 {
      assert_true((m.at(i, j) - m_shifted.at(i, j)).abs() < 1.0e-12)
    }
  }
  // 2. Rotating all v by the same angle preserves the cross product, so the
  //    matrix is invariant.
  let theta = 0.7
  let cs = @math.cos(theta)
  let sn = @math.sin(theta)
  let rotated = chars.map(fn(c) {
    Character::{
      label: c.label,
      power: c.power,
      v: mv(c.v.x * cs - c.v.y * sn, c.v.x * sn + c.v.y * cs),
    }
  })
  let m_rot = from_characters(rotated)
  for i in 0..<3 {
    for j in 0..<3 {
      assert_true((m.at(i, j) - m_rot.at(i, j)).abs() < 1.0e-10)
    }
  }
}

///|
test "compat_2d_cross_product_formula_matches_derivation" {
  let chars = [ch("a", 0.3, 1.2, -0.4), ch("b", -0.1, 0.5, 2.0)]
  let m = from_characters(chars)
  // A[0,1] = (p₀ − p₁) + v₀ × v₁
  //        = (0.3 − (−0.1)) + (1.2 · 2.0 − (−0.4) · 0.5)
  //        = 0.4 + (2.4 + 0.2) = 3.0
  assert_true((m.at(0, 1) - 3.0).abs() < 1.0e-12)
  assert_true((m.at(1, 0) - -3.0).abs() < 1.0e-12)
}

///|
test "equal_power_coordinate_transform_found_when_exists" {
  // Two characters with distinct powers; the 1-equation-2-unknowns system is
  // always solvable, so a valid transform exists.
  let chars = [ch("A", 0.0, 1.0, 0.0), ch("B", 1.0, -1.0, 0.0)]
  let m_before = from_characters(chars)
  match equal_power_transform(chars) {
    Some(a) => {
      let c0_new = chars[0].convert(a)
      let c1_new = chars[1].convert(a)
      // Powers are now equal.
      assert_true((c0_new.power - c1_new.power).abs() < 1.0e-6)
      // Payoff matrix is invariant under the transform.
      let m_after = from_characters([c0_new, c1_new])
      for i in 0..<2 {
        for j in 0..<2 {
          assert_true((m_before.at(i, j) - m_after.at(i, j)).abs() < 1.0e-10)
        }
      }
    }
    None => assert_true(false)
  }
  // Already-equal-power chars should return the identity transform.
  let equal = [ch("A", 0.0, 2.0, 0.0), ch("B", 0.0, -1.0, 1.7)]
  match equal_power_transform(equal) {
    Some(a) => {
      assert_true(a.x.abs() < 1.0e-12)
      assert_true(a.y.abs() < 1.0e-12)
    }
    None => assert_true(false)
  }
  // Over-constrained case with no exact solution returns None.
  //
  // 4 characters yield 3 equations in 2 unknowns; the first two resolve to
  // (a.x, a.y) = (1, −1), but the third contradicts.
  let over = [
    ch("A", 0.0, 0.0, 0.0),
    ch("B", 1.0, 1.0, 0.0),
    ch("C", 1.0, 0.0, 1.0),
    ch("D", 5.0, 1.0, 1.0),
  ]
  // Row D: (1 − 0)·a.y − (1 − 0)·a.x = 0 − 5 → a.y − a.x = −5
  // But earlier: a.y = −1, a.x = 1 → a.y − a.x = −2 ≠ −5. Inconsistent.
  assert_true(equal_power_transform(over) is None)
}
