///|
/// ソクノのみ (でんき) was missing from the resist-berry table while the
/// other 17 berries were present, so a super-effective でんき hit into
/// ソクノのみ passed through unhalved. Pin the full 18-berry mapping and
/// the engine-level halving so a partial table can't regress silently.
/// Shares rb_* fixtures with multi_hit_resist_berry_wbtest.mbt.

///|
test "get_resist_berry_type: full 18-berry mapping" {
  let pairs = [
    ("オッカのみ", "ほのお"),
    ("イトケのみ", "みず"),
    ("ソクノのみ", "でんき"),
    ("リンドのみ", "くさ"),
    ("ヤチェのみ", "こおり"),
    ("ヨプのみ", "かくとう"),
    ("ビアーのみ", "どく"),
    ("シュカのみ", "じめん"),
    ("バコウのみ", "ひこう"),
    ("ウタンのみ", "エスパー"),
    ("タンガのみ", "むし"),
    ("ヨロギのみ", "いわ"),
    ("カシブのみ", "ゴースト"),
    ("ハバンのみ", "ドラゴン"),
    ("ナモのみ", "あく"),
    ("リリバのみ", "はがね"),
    ("ロゼルのみ", "フェアリー"),
    ("ホズのみ", "ノーマル"),
  ]
  for i = 0; i < pairs.length(); i = i + 1 {
    let (item, expected) = pairs[i]
    assert_eq(get_resist_berry_type(item), expected)
  }
  // Non-berries fall through to "".
  assert_eq(get_resist_berry_type("こだわりハチマキ"), "")
  assert_eq(get_resist_berry_type(""), "")
}

///|
test "ソクノのみ: super-effective でんき hit is halved" {
  let atk = rb_pokemon("attacker", "でんき")
  let dfn = rb_pokemon("defender", "みず")
  let mv = rb_move("10まんボルト", "でんき")
  let with_berry = calc_damage(
    rb_input(atk, dfn, mv, def_item="ソクノのみ"),
  )
  let without_berry = calc_damage(rb_input(atk, dfn, mv))
  let w = with_berry.damages[8]
  let n = without_berry.damages[8]
  // Berry halves with 4096-base round5(2048), so w ≈ n / 2 within ±2.
  assert_true(w * 2 >= n - 2 && w * 2 <= n + 2)
}

///|
test "ソクノのみ: neutral でんき hit is NOT halved" {
  let atk = rb_pokemon("attacker", "でんき")
  let dfn = rb_pokemon("defender", "ノーマル")
  let mv = rb_move("10まんボルト", "でんき")
  let with_berry = calc_damage(
    rb_input(atk, dfn, mv, def_item="ソクノのみ"),
  )
  let without_berry = calc_damage(rb_input(atk, dfn, mv))
  assert_eq(with_berry.damages[8], without_berry.damages[8])
}
