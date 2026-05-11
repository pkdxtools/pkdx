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

///|
test "combinations_with_lead_enumerates_n_times_choose_n_minus_1_k_minus_1" {
  // n=6, k=3 → 6 × C(5,2) = 60 selections (singles の標準ケース)
  let s = combinations_with_lead(6, 3)
  inspect(s.length(), content="60")
  // n=4, k=3 → 4 × C(3,2) = 12 selections (テスト fixture でよく出る規模)
  let t = combinations_with_lead(4, 3)
  inspect(t.length(), content="12")
  // 各エントリは [lead, b1, b2]、lead ∉ {b1, b2}、backups は昇順
  for tup in t {
    assert_true(tup.length() == 3)
    let lead = tup[0]
    let b1 = tup[1]
    let b2 = tup[2]
    assert_true(lead != b1 && lead != b2 && b1 != b2)
    assert_true(b1 < b2)
  }
  // lead ごとのブロック数 (= C(3,2) = 3) を確認。
  // 出力は lead 昇順の固まり、各固まりの中で backups 昇順。
  inspect(t[0], content="[0, 1, 2]")
  inspect(t[1], content="[0, 1, 3]")
  inspect(t[2], content="[0, 2, 3]")
  inspect(t[3], content="[1, 0, 2]")
  inspect(t[4], content="[1, 0, 3]")
  inspect(t[5], content="[1, 2, 3]")
  inspect(t[6], content="[2, 0, 1]")
  inspect(t[7], content="[2, 0, 3]")
  inspect(t[8], content="[2, 1, 3]")
  inspect(t[9], content="[3, 0, 1]")
  inspect(t[10], content="[3, 0, 2]")
  inspect(t[11], content="[3, 1, 2]")
}

///|
test "combinations_with_lead_handles_edge_cases" {
  // k = 1: 自分が lead でバックアップなし → n エントリ
  let s = combinations_with_lead(3, 1)
  inspect(s.length(), content="3")
  inspect(s[0], content="[0]")
  inspect(s[1], content="[1]")
  inspect(s[2], content="[2]")
  // k > n / k <= 0 / n = 0 はすべて空配列
  inspect(combinations_with_lead(2, 3).length(), content="0")
  inspect(combinations_with_lead(3, 0).length(), content="0")
  inspect(combinations_with_lead(0, 3).length(), content="0")
  inspect(combinations_with_lead(3, -1).length(), content="0")
}
