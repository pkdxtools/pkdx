///|
/// Stage C-1: Field model unit tests.
///
/// 二系統の入力を `field_from_jp` が受けることを pin する:
///   1. CLI 入力 (日本語短縮形: "エレキ" / "グラス" / "ミスト" / "サイコ")
///   2. DB 入力 (m015 投入の canonical: "electric" / "grassy" / "misty" / "psychic")
/// どちらも未知 / 空文字は `None` を返す。
///
/// derive 句が `(Eq, Hash, Show)` を含むことも pin する: damage cache key 化
/// (Hash) / debug_inspect (Show) / 比較 (Eq) を後段 Stage D-F で使うため。

///|
test "field_from_jp: canonical (DB) keys → Field variant" {
  assert_true(field_from_jp("electric") == Field::Electric)
  assert_true(field_from_jp("grassy") == Field::Grassy)
  assert_true(field_from_jp("misty") == Field::Misty)
  assert_true(field_from_jp("psychic") == Field::Psychic)
}

///|
test "field_from_jp: Japanese (CLI) keys → Field variant" {
  assert_true(field_from_jp("エレキ") == Field::Electric)
  assert_true(field_from_jp("グラス") == Field::Grassy)
  assert_true(field_from_jp("ミスト") == Field::Misty)
  assert_true(field_from_jp("サイコ") == Field::Psychic)
}

///|
test "field_from_jp: empty / unknown → None" {
  assert_true(field_from_jp("") == Field::None)
  assert_true(field_from_jp("unknown") == Field::None)
  assert_true(field_from_jp("でんき") == Field::None)
}

///|
test "Field::is_active: None false, others true" {
  assert_false(Field::is_active(Field::None))
  assert_true(Field::is_active(Field::Electric))
  assert_true(Field::is_active(Field::Grassy))
  assert_true(Field::is_active(Field::Misty))
  assert_true(Field::is_active(Field::Psychic))
}

///|
test "Field: Debug derive enables debug_inspect (variant-name distinct)" {
  // Stage D-F の cache_key_completeness 系テストで `debug_inspect` されるため
  // `Debug` derive が必須。Weather の `derive(Debug, Eq, Hash)` と揃える。
  // 具体的な出力文字列は @debug の実装に任せ、本テストは「derive(Debug)
  // が成立していること」を変更時の早期警告として pin する (compile が通れば
  // debug_inspect が動く)。
  @debug.debug_inspect(Field::None, content="None")
  @debug.debug_inspect(Field::Electric, content="Electric")
  @debug.debug_inspect(Field::Grassy, content="Grassy")
  @debug.debug_inspect(Field::Misty, content="Misty")
  @debug.debug_inspect(Field::Psychic, content="Psychic")
}

///|
test "Field: Hash derive enables Map key (Stage F damage cache prep)" {
  // Hash + Eq があれば `Map[Field, T]` のキーになれる。Stage F の damage
  // cache key で Field を埋め込むときの prerequisite。
  let m : Map[Field, Int] = Map([(Field::None, 0), (Field::Electric, 1)])
  assert_true(m.get(Field::None) == Some(0))
  assert_true(m.get(Field::Electric) == Some(1))
  assert_true(m.get(Field::Grassy) == None)
}
