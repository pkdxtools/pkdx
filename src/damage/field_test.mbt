///|
/// Stage F-1 tests: `get_field_damage_mod` (Gen 9 spec) + `is_grounded`.
///
/// Gen 9 field semantics:
///   - Electric field + でんき技 (attacker grounded)      → 1.3x (5325/4096)
///   - Grassy field   + くさ技   (attacker grounded)      → 1.3x
///   - Psychic field  + エスパー技 (attacker grounded)    → 1.3x
///   - Grassy field   + じしん/マグニチュード/じならし  → 0.5x  (defender grounded)
///   - Misty field    + ドラゴン技 (defender grounded)    → 0.5x
///   - Otherwise                                            → 0    (no mod)
///
/// Grounded check (Gen 9 minimal — primitive args so `@damage` does not need
/// to import `@payoff.Combatant`):
///   - ability == "ふゆう"       → NOT grounded
///   - type1/type2 == "ひこう"   → NOT grounded
///   - item == "ふうせん"         → NOT grounded
///   - else                       → grounded

// ───────── Boost arm (attacker grounded → 1.3x = 5325/4096) ─────────

///|
test "field F-1: Electric + でんき + attacker grounded → 5325 (1.3x)" {
  let mod_ = get_field_damage_mod(
    @model.Field::Electric,
    "10まんボルト",
    "でんき",
    true, // attacker grounded
    true, // defender grounded
  )
  assert_eq(mod_, 5325)
}

///|
test "field F-1: Grassy + くさ + attacker grounded → 5325 (1.3x)" {
  let mod_ = get_field_damage_mod(
    @model.Field::Grassy,
    "リーフブレード",
    "くさ",
    true,
    true,
  )
  assert_eq(mod_, 5325)
}

///|
test "field F-1: Psychic + エスパー + attacker grounded → 5325 (1.3x)" {
  let mod_ = get_field_damage_mod(
    @model.Field::Psychic,
    "サイコキネシス",
    "エスパー",
    true,
    true,
  )
  assert_eq(mod_, 5325)
}

///|
test "field F-1: Electric + でんき + attacker NOT grounded → 0 (no boost)" {
  let mod_ = get_field_damage_mod(
    @model.Field::Electric,
    "10まんボルト",
    "でんき",
    false, // attacker airborne
    true,
  )
  assert_eq(mod_, 0)
}

// ───────── Debuff arm (defender grounded) ─────────

///|
test "field F-1: Grassy + じしん + defender grounded → 2048 (0.5x)" {
  let mod_ = get_field_damage_mod(
    @model.Field::Grassy,
    "じしん",
    "じめん",
    true,
    true, // defender grounded
  )
  assert_eq(mod_, 2048)
}

///|
test "field F-1: Grassy + マグニチュード + defender grounded → 2048" {
  let mod_ = get_field_damage_mod(
    @model.Field::Grassy,
    "マグニチュード",
    "じめん",
    true,
    true,
  )
  assert_eq(mod_, 2048)
}

///|
test "field F-1: Grassy + じならし + defender grounded → 2048" {
  let mod_ = get_field_damage_mod(
    @model.Field::Grassy,
    "じならし",
    "じめん",
    true,
    true,
  )
  assert_eq(mod_, 2048)
}

///|
test "field F-1: Grassy + じしん + defender NOT grounded → 0 (no debuff)" {
  let mod_ = get_field_damage_mod(
    @model.Field::Grassy,
    "じしん",
    "じめん",
    true,
    false, // defender airborne
  )
  assert_eq(mod_, 0)
}

///|
test "field F-1: Misty + ドラゴン + defender grounded → 2048 (0.5x)" {
  let mod_ = get_field_damage_mod(
    @model.Field::Misty,
    "りゅうのはどう",
    "ドラゴン",
    true,
    true,
  )
  assert_eq(mod_, 2048)
}

///|
test "field F-1: Misty + ドラゴン + defender NOT grounded → 0" {
  let mod_ = get_field_damage_mod(
    @model.Field::Misty,
    "りゅうのはどう",
    "ドラゴン",
    true,
    false,
  )
  assert_eq(mod_, 0)
}

// ───────── Non-applicable cases ─────────

///|
test "field F-1: Grassy + ground move other than EQ/Mag/Bull → 0" {
  // Gen 9: Grassy debuff is restricted to じしん/マグニチュード/じならし.
  // Other ground moves (e.g. あなをほる) are not weakened.
  let mod_ = get_field_damage_mod(
    @model.Field::Grassy,
    "あなをほる",
    "じめん",
    true,
    true,
  )
  assert_eq(mod_, 0)
}

///|
test "field F-1: Field::None always 0" {
  let mod_ = get_field_damage_mod(
    @model.Field::None,
    "10まんボルト",
    "でんき",
    true,
    true,
  )
  assert_eq(mod_, 0)
}

///|
test "field F-1: Electric + non-electric move → 0" {
  let mod_ = get_field_damage_mod(
    @model.Field::Electric,
    "なみのり",
    "みず",
    true,
    true,
  )
  assert_eq(mod_, 0)
}

// ───────── is_grounded (primitive-arg shape) ─────────

///|
test "field F-1: is_grounded — plain normal type → true" {
  assert_true(is_grounded(type1="ノーマル", type2="", ability="", item=""))
}

///|
test "field F-1: is_grounded — Flying type1 → false" {
  assert_false(is_grounded(type1="ひこう", type2="", ability="", item=""))
}

///|
test "field F-1: is_grounded — Flying type2 → false" {
  assert_false(
    is_grounded(type1="ノーマル", type2="ひこう", ability="", item=""),
  )
}

///|
test "field F-1: is_grounded — Levitate (ふゆう) ability → false" {
  assert_false(
    is_grounded(type1="ノーマル", type2="", ability="ふゆう", item=""),
  )
}

///|
test "field F-1: is_grounded — Air Balloon (ふうせん) item → false" {
  assert_false(
    is_grounded(type1="ノーマル", type2="", ability="", item="ふうせん"),
  )
}

///|
test "field F-1: is_grounded — combined (Flying + Pressure + Leftovers) → false" {
  assert_false(
    is_grounded(
      type1="ひこう",
      type2="",
      ability="プレッシャー",
      item="たべのこし",
    ),
  )
}
