///|
test "clamp_rank_collapses_to_two_and_minus_two" {
  assert_eq(clamp_rank(0), 0)
  assert_eq(clamp_rank(1), 1)
  assert_eq(clamp_rank(2), 2)
  assert_eq(clamp_rank(3), 2)
  assert_eq(clamp_rank(99), 2)
  assert_eq(clamp_rank(-1), -1)
  assert_eq(clamp_rank(-2), -2)
  assert_eq(clamp_rank(-3), -2)
  assert_eq(clamp_rank(-99), -2)
}

///|
test "effective_speed_positive_ranks_scale_correctly" {
  // +1 = ×1.5, +2 = ×2.0
  assert_eq(effective_speed(100, 0), 100)
  assert_eq(effective_speed(100, 1), 150)
  assert_eq(effective_speed(100, 2), 200)
}

///|
test "effective_speed_negative_ranks_scale_correctly" {
  // -1 = ÷1.5 ≈ ×0.667, -2 = ÷2 = ×0.5
  assert_eq(effective_speed(100, -1), 66)
  assert_eq(effective_speed(100, -2), 50)
}

///|
test "turn_order_sign_priority_beats_higher_speed" {
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 50),
    [mk_move("バレットパンチ", "はがね", @model.Physical, 40, priority=1)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 200),
    [mk_move("じしん", "じめん", @model.Physical, 100)],
  )
  // a is slower (50 < 200) but uses +1 priority; it should act first.
  assert_eq(turn_order_sign(a, 1, 50, b, 0, 200), 1)
  // Symmetric: b first when no priority edge.
  assert_eq(turn_order_sign(a, 0, 50, b, 0, 200), -1)
  // Equal priority + same speed → tie.
  assert_eq(turn_order_sign(a, 0, 100, b, 0, 100), 0)
}

///|
test "turn_order_sign_higher_priority_dominates_lower_priority" {
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("ねこだまし", "ノーマル", @model.Physical, 40, priority=3)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("バレットパンチ", "はがね", @model.Physical, 40, priority=1)],
  )
  // +3 (ねこだまし) beats +1 (バレットパンチ).
  assert_eq(turn_order_sign(a, 3, 100, b, 1, 100), 1)
}
