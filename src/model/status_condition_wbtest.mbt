///|
test "StatusCondition equality: None" {
  let a : StatusCondition = None
  let b : StatusCondition = None
  assert_true(a == b)
}

///|
test "StatusCondition equality: BadPoison counter distinguishes variants" {
  let a : StatusCondition = BadPoison(1)
  let b : StatusCondition = BadPoison(2)
  assert_true(!(a == b))
  assert_true(a == BadPoison(1))
}

///|
test "StatusCondition equality: Sleep counter distinguishes variants" {
  assert_true(Sleep(2) == Sleep(2))
  assert_true(!(Sleep(2) == Sleep(1)))
}

///|
test "StatusKind round trip via from_jp" {
  @debug.debug_inspect(
    status_kind_from_jp("まひ"),
    content="Some(ParalyzeKind)",
  )
  @debug.debug_inspect(
    status_kind_from_jp("やけど"),
    content="Some(BurnKind)",
  )
  @debug.debug_inspect(
    status_kind_from_jp("どく"),
    content="Some(PoisonKind)",
  )
  @debug.debug_inspect(
    status_kind_from_jp("もうどく"),
    content="Some(BadPoisonKind)",
  )
  @debug.debug_inspect(
    status_kind_from_jp("ねむり"),
    content="Some(SleepKind)",
  )
  assert_true(status_kind_from_jp("unknown") == None)
}

///|
test "immune_to_status: electric is immune to paralyze" {
  assert_true(immune_to_status(ParalyzeKind, "でんき", ""))
  assert_true(immune_to_status(ParalyzeKind, "ノーマル", "でんき"))
  assert_true(!immune_to_status(ParalyzeKind, "ノーマル", ""))
}

///|
test "immune_to_status: fire is immune to burn" {
  assert_true(immune_to_status(BurnKind, "ほのお", ""))
  assert_true(immune_to_status(BurnKind, "ノーマル", "ほのお"))
  assert_true(!immune_to_status(BurnKind, "みず", ""))
}

///|
test "immune_to_status: steel and poison are immune to poison and badpoison" {
  assert_true(immune_to_status(PoisonKind, "はがね", ""))
  assert_true(immune_to_status(PoisonKind, "どく", ""))
  assert_true(immune_to_status(BadPoisonKind, "はがね", ""))
  assert_true(immune_to_status(BadPoisonKind, "どく", ""))
  assert_true(!immune_to_status(PoisonKind, "ノーマル", ""))
  assert_true(!immune_to_status(BadPoisonKind, "ノーマル", ""))
}

///|
test "immune_to_status: sleep has no type immunity in MVP (abilities handled separately)" {
  assert_true(!immune_to_status(SleepKind, "くさ", ""))
  assert_true(!immune_to_status(SleepKind, "ノーマル", ""))
}

///|
test "inflict_status: maps StatusKind to initial StatusCondition" {
  @debug.debug_inspect(inflict_status(ParalyzeKind), content="Paralyze")
  @debug.debug_inspect(inflict_status(BurnKind), content="Burn")
  @debug.debug_inspect(inflict_status(PoisonKind), content="Poison")
  @debug.debug_inspect(inflict_status(BadPoisonKind), content="BadPoison(0)")
  @debug.debug_inspect(inflict_status(SleepKind), content="Sleep(2)")
  @debug.debug_inspect(inflict_status(DrowsyKind), content="Drowsy(1)")
}

///|
test "status_kind_from_jp: あくび maps to DrowsyKind" {
  @debug.debug_inspect(
    status_kind_from_jp("あくび"),
    content="Some(DrowsyKind)",
  )
}

///|
test "immune_to_status: drowsy ignores type (MVP behaviour)" {
  assert_true(!immune_to_status(DrowsyKind, "くさ", ""))
  assert_true(!immune_to_status(DrowsyKind, "でんき", ""))
  assert_true(!immune_to_status(DrowsyKind, "ノーマル", ""))
}
