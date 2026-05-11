///|
test "StatusCondition equality: None" {
  let a : StatusCondition = None
  let b : StatusCondition = None
  inspect(a == b, content="true")
}

///|
test "StatusCondition equality: BadPoison counter distinguishes variants" {
  let a : StatusCondition = BadPoison(1)
  let b : StatusCondition = BadPoison(2)
  inspect(a == b, content="false")
  inspect(a == BadPoison(1), content="true")
}

///|
test "StatusCondition equality: Sleep counter distinguishes variants" {
  inspect(Sleep(2) == Sleep(2), content="true")
  inspect(Sleep(2) == Sleep(1), content="false")
}

///|
test "StatusKind round trip via from_jp" {
  inspect(status_kind_from_jp("まひ"), content="Some(ParalyzeKind)")
  inspect(status_kind_from_jp("やけど"), content="Some(BurnKind)")
  inspect(status_kind_from_jp("どく"), content="Some(PoisonKind)")
  inspect(status_kind_from_jp("もうどく"), content="Some(BadPoisonKind)")
  inspect(status_kind_from_jp("ねむり"), content="Some(SleepKind)")
  inspect(status_kind_from_jp("unknown"), content="None")
}

///|
test "immune_to_status: electric is immune to paralyze" {
  inspect(immune_to_status(ParalyzeKind, "でんき", ""), content="true")
  inspect(immune_to_status(ParalyzeKind, "ノーマル", "でんき"), content="true")
  inspect(immune_to_status(ParalyzeKind, "ノーマル", ""), content="false")
}

///|
test "immune_to_status: fire is immune to burn" {
  inspect(immune_to_status(BurnKind, "ほのお", ""), content="true")
  inspect(immune_to_status(BurnKind, "ノーマル", "ほのお"), content="true")
  inspect(immune_to_status(BurnKind, "みず", ""), content="false")
}

///|
test "immune_to_status: steel and poison are immune to poison and badpoison" {
  inspect(immune_to_status(PoisonKind, "はがね", ""), content="true")
  inspect(immune_to_status(PoisonKind, "どく", ""), content="true")
  inspect(immune_to_status(BadPoisonKind, "はがね", ""), content="true")
  inspect(immune_to_status(BadPoisonKind, "どく", ""), content="true")
  inspect(immune_to_status(PoisonKind, "ノーマル", ""), content="false")
  inspect(immune_to_status(BadPoisonKind, "ノーマル", ""), content="false")
}

///|
test "immune_to_status: sleep has no type immunity in MVP (abilities handled separately)" {
  inspect(immune_to_status(SleepKind, "くさ", ""), content="false")
  inspect(immune_to_status(SleepKind, "ノーマル", ""), content="false")
}

///|
test "inflict_status: maps StatusKind to initial StatusCondition" {
  inspect(inflict_status(ParalyzeKind), content="Paralyze")
  inspect(inflict_status(BurnKind), content="Burn")
  inspect(inflict_status(PoisonKind), content="Poison")
  inspect(inflict_status(BadPoisonKind), content="BadPoison(0)")
  inspect(inflict_status(SleepKind), content="Sleep(2)")
  inspect(inflict_status(DrowsyKind), content="Drowsy(1)")
}

///|
test "status_kind_from_jp: あくび maps to DrowsyKind" {
  inspect(status_kind_from_jp("あくび"), content="Some(DrowsyKind)")
}

///|
test "immune_to_status: drowsy ignores type (MVP behaviour)" {
  inspect(immune_to_status(DrowsyKind, "くさ", ""), content="false")
  inspect(immune_to_status(DrowsyKind, "でんき", ""), content="false")
  inspect(immune_to_status(DrowsyKind, "ノーマル", ""), content="false")
}
