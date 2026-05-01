///|
/// Sanity checks pinning the static `contact_moves` table. これは公式仕様の
/// 接触判定であり、物理/特殊と独立 — 物理でも接触しない技 (じしん / じならし /
/// テラバースト) と、物理で接触ありの技 (ボディプレス) があるので雑に
/// 「物理 = 接触」で扱わないように注意。シェルアームズ物理モード等の
/// 動的判定は force_contact 経由で別レイヤー。
test "is_contact_move: 接触する代表的な物理技" {
  assert_true(is_contact_move("でんこうせっか"))
  assert_true(is_contact_move("ばかぢから"))
  assert_true(is_contact_move("インファイト"))
  assert_true(is_contact_move("じゃれつく"))
  assert_true(is_contact_move("もろはのずつき"))
  assert_true(is_contact_move("ぶちかまし"))
  // 物理かつ接触 — pkdx の手書き table から漏れていたケース
  assert_true(is_contact_move("ボディプレス"))
  assert_true(is_contact_move("イカサマ"))
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
  // Final Gambit は非接触 (Gen 6+ 仕様)。
  assert_false(is_contact_move("いのちがけ"))
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

///|
/// `is_spread_move` で 0.75x 補正対象を取り違えないこと。
test "is_spread_move: 自分以外全体 (target=4) と相手全体 (target=5)" {
  // target=5 (相手全体)
  assert_true(is_spread_move("ふぶき"))
  assert_true(is_spread_move("いわなだれ"))
  assert_true(is_spread_move("ねっぷう"))
  assert_true(is_spread_move("ハイパーボイス"))
  // target=4 (自分以外全体)
  assert_true(is_spread_move("じしん"))
  assert_true(is_spread_move("なみのり"))
  assert_true(is_spread_move("だいばくはつ"))
  // 単体技は補正対象外
  assert_false(is_spread_move("でんこうせっか"))
  assert_false(is_spread_move("シャドーボール"))
  assert_false(is_spread_move("インファイト"))
}
