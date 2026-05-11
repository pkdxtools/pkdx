///|
test "get_atk_ability_final: そうだいしょう multiplier table" {
  // fainted=0 → no modifier
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", 0), content="0")
  // fainted=1 → x1.1 (4506/4096)
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", 1), content="4506")
  // fainted=2 → x1.2 (4915/4096)
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", 2), content="4915")
  // fainted=3 → x1.3 (5325/4096)
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", 3), content="5325")
  // fainted=4 → x1.4 (5734/4096)
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", 4), content="5734")
  // fainted=5 → x1.5 (6144/4096)
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", 5), content="6144")
}

///|
test "get_atk_ability_final: そうだいしょう clamps out-of-range" {
  // negative → 0 (clamped to 0)
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", -1), content="0")
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", -10), content="0")
  // > 5 → clamped to 5 (6144)
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", 6), content="6144")
  inspect(get_atk_ability_final("そうだいしょう", "ノーマル", 100), content="6144")
}

///|
test "get_atk_ability_final: そうだいしょう is type-independent" {
  // move type does not affect そうだいしょう
  let fainted = 3
  let base = get_atk_ability_final("そうだいしょう", "ノーマル", fainted)
  inspect(
    base == get_atk_ability_final("そうだいしょう", "ほのお", fainted),
    content="true",
  )
  inspect(
    base == get_atk_ability_final("そうだいしょう", "みず", fainted),
    content="true",
  )
  inspect(
    base == get_atk_ability_final("そうだいしょう", "ゴースト", fainted),
    content="true",
  )
}

///|
test "get_atk_ability_final: other abilities ignore fainted_count" {
  // fainted_count は そうだいしょう 以外に影響しない
  inspect(get_atk_ability_final("ちからずく", "ノーマル", 0), content="5325")
  inspect(get_atk_ability_final("ちからずく", "ノーマル", 5), content="5325")
  inspect(get_atk_ability_final("トランジスタ", "でんき", 3), content="5325")
  inspect(get_atk_ability_final("", "ノーマル", 2), content="0")
}
