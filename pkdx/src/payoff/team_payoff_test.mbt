///|
/// Structural tests for `team_payoff.mbt`. Behavioural coverage of the
/// surviving matrix builders lives in `switching_game_test.mbt` and
/// `screened_switching_game_test.mbt`.

///|
test "combinations_returns_stable_lex_order" {
  let a = combinations(4, 3)
  let b = combinations(4, 3)
  inspect(a.length(), content="4")
  inspect(b.length(), content="4")
  for i in 0..<a.length() {
    for j in 0..<3 {
      assert_true(a[i][j] == b[i][j])
    }
  }
  inspect(a[0], content="[0, 1, 2]")
  inspect(a[1], content="[0, 1, 3]")
  inspect(a[2], content="[0, 2, 3]")
  inspect(a[3], content="[1, 2, 3]")
}
