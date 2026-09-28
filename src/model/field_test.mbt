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
  assert_true(@model.field_from_jp("electric") == @model.Field::Electric)
  assert_true(@model.field_from_jp("grassy") == @model.Field::Grassy)
  assert_true(@model.field_from_jp("misty") == @model.Field::Misty)
  assert_true(@model.field_from_jp("psychic") == @model.Field::Psychic)
}

///|
test "field_from_jp: Japanese (CLI) keys → Field variant" {
  assert_true(@model.field_from_jp("エレキ") == @model.Field::Electric)
  assert_true(@model.field_from_jp("グラス") == @model.Field::Grassy)
  assert_true(@model.field_from_jp("ミスト") == @model.Field::Misty)
  assert_true(@model.field_from_jp("サイコ") == @model.Field::Psychic)
}

///|
test "field_from_jp: empty / unknown → None" {
  assert_true(@model.field_from_jp("") == @model.Field::None)
  assert_true(@model.field_from_jp("unknown") == @model.Field::None)
  assert_true(@model.field_from_jp("でんき") == @model.Field::None)
}

///|
test "Field::is_active: None false, others true" {
  assert_false(@model.Field::is_active(@model.Field::None))
  assert_true(@model.Field::is_active(@model.Field::Electric))
  assert_true(@model.Field::is_active(@model.Field::Grassy))
  assert_true(@model.Field::is_active(@model.Field::Misty))
  assert_true(@model.Field::is_active(@model.Field::Psychic))
}

///|
test "Field: Debug derive enables debug_inspect (variant-name distinct)" {
  // Stage D-F の cache_key_completeness 系テストで `debug_inspect` されるため
  // `Debug` derive が必須。Weather の `derive(Debug, Eq, Hash)` と揃える。
  // 具体的な出力文字列は @debug の実装に任せ、本テストは「derive(Debug)
  // が成立していること」を変更時の早期警告として pin する (compile が通れば
  // debug_inspect が動く)。
  @debug.debug_inspect(@model.Field::None, content="None")
  @debug.debug_inspect(@model.Field::Electric, content="Electric")
  @debug.debug_inspect(@model.Field::Grassy, content="Grassy")
  @debug.debug_inspect(@model.Field::Misty, content="Misty")
  @debug.debug_inspect(@model.Field::Psychic, content="Psychic")
}

///|
test "Field: Hash derive enables Map key (Stage F damage cache prep)" {
  // Hash + Eq があれば `Map[Field, T]` のキーになれる。Stage F の damage
  // cache key で Field を埋め込むときの prerequisite。
  let m : Map[@model.Field, Int] = Map([(@model.Field::None, 0), (@model.Field::Electric, 1)])
  assert_true(m.get(@model.Field::None) == Some(0))
  assert_true(m.get(@model.Field::Electric) == Some(1))
  assert_true(m.get(@model.Field::Grassy) == None)
}
