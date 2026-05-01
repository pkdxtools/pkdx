///|
/// Sanity checks pinning the static `contact_moves` table. これは公式仕様の
/// 接触判定であり、物理/特殊と独立 — 物理でも接触しない技 (じしん / じならし /
/// テラバースト) と、特殊だが接触する技 (シェルアームズ物理モード等、ただし
/// その判定は move_flags ではなく force_contact 経由) があるので両方とも
/// 雑に「物理 = 接触」で扱わないように注意。
test "is_contact_move: 接触する代表的な物理技" {
  assert_true(is_contact_move("でんこうせっか"))
  assert_true(is_contact_move("ばかぢから"))
  assert_true(is_contact_move("インファイト"))
  assert_true(is_contact_move("じゃれつく"))
  assert_true(is_contact_move("もろはのずつき"))
  assert_true(is_contact_move("ぶちかまし"))
}

///|
test "is_contact_move: 非接触の物理技 (誤検出が起きやすい)" {
  // 地面波振動。Earthquake / Bulldoze は非接触。
  assert_false(is_contact_move("じしん"))
  assert_false(is_contact_move("じならし"))
  // Tera Blast はテラスタイプを問わず非接触 (公式仕様)。
  assert_false(is_contact_move("テラバースト"))
  // 物理だが投擲 / 飛び道具系の代表例。
  assert_false(is_contact_move("ストーンエッジ"))
  assert_false(is_contact_move("いわなだれ"))
}

///|
test "is_contact_move: 非接触の特殊技" {
  assert_false(is_contact_move("シャドーボール"))
  assert_false(is_contact_move("あくのはどう"))
  assert_false(is_contact_move("なみのり"))
  assert_false(is_contact_move("ハイドロポンプ"))
}

///|
test "is_contact_move: 未登録の技は非接触として扱う" {
  assert_false(is_contact_move("そんざいしないわざ"))
  assert_false(is_contact_move(""))
}
