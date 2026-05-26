///|
/// Black-box tests for the ability-based immunity layer used by the healing
/// move support. Mirrors the truth table documented in the plan's section C
/// (`ability_immunity`): three abilities block Sleep + Drowsy, Magic Guard
/// gates the LeechSeed end-of-turn tick, and Liquid Ooze flips Drain into
/// damage. Every other (ability, kind) combination must return false so the
/// downstream healing pipeline does not skip legitimate status / heal events.

///|
test "ability_blocks_status_insomnia_blocks_sleep_and_drowsy" {
  @debug.assert_eq(ability_blocks_status("ふみん", @model.SleepKind), true)
  @debug.assert_eq(ability_blocks_status("ふみん", @model.DrowsyKind), true)
}

///|
test "ability_blocks_status_vital_spirit_blocks_sleep_and_drowsy" {
  @debug.assert_eq(ability_blocks_status("やるき", @model.SleepKind), true)
  @debug.assert_eq(ability_blocks_status("やるき", @model.DrowsyKind), true)
}

///|
test "ability_blocks_status_sweet_veil_blocks_sleep_and_drowsy" {
  @debug.assert_eq(
    ability_blocks_status("スイートベール", @model.SleepKind),
    true,
  )
  @debug.assert_eq(
    ability_blocks_status("スイートベール", @model.DrowsyKind),
    true,
  )
}

///|
test "ability_blocks_status_insomnia_does_not_block_non_sleep_kinds" {
  @debug.assert_eq(ability_blocks_status("ふみん", @model.ParalyzeKind), false)
  @debug.assert_eq(ability_blocks_status("ふみん", @model.BurnKind), false)
  @debug.assert_eq(ability_blocks_status("ふみん", @model.PoisonKind), false)
  @debug.assert_eq(ability_blocks_status("ふみん", @model.BadPoisonKind), false)
}

///|
test "ability_blocks_status_vital_spirit_does_not_block_non_sleep_kinds" {
  @debug.assert_eq(ability_blocks_status("やるき", @model.ParalyzeKind), false)
  @debug.assert_eq(ability_blocks_status("やるき", @model.BurnKind), false)
  @debug.assert_eq(ability_blocks_status("やるき", @model.PoisonKind), false)
  @debug.assert_eq(ability_blocks_status("やるき", @model.BadPoisonKind), false)
}

///|
test "ability_blocks_status_sweet_veil_does_not_block_non_sleep_kinds" {
  @debug.assert_eq(
    ability_blocks_status("スイートベール", @model.ParalyzeKind),
    false,
  )
  @debug.assert_eq(
    ability_blocks_status("スイートベール", @model.BurnKind),
    false,
  )
  @debug.assert_eq(
    ability_blocks_status("スイートベール", @model.PoisonKind),
    false,
  )
  @debug.assert_eq(
    ability_blocks_status("スイートベール", @model.BadPoisonKind),
    false,
  )
}

///|
test "ability_blocks_status_magic_guard_does_not_block_status_application" {
  // Magic Guard suppresses residual damage, not the status itself.
  @debug.assert_eq(
    ability_blocks_status("マジックガード", @model.SleepKind),
    false,
  )
  @debug.assert_eq(
    ability_blocks_status("マジックガード", @model.DrowsyKind),
    false,
  )
  @debug.assert_eq(
    ability_blocks_status("マジックガード", @model.BurnKind),
    false,
  )
}

///|
test "ability_blocks_status_unrelated_ability_never_blocks" {
  @debug.assert_eq(ability_blocks_status("もうか", @model.SleepKind), false)
  @debug.assert_eq(ability_blocks_status("もうか", @model.DrowsyKind), false)
  @debug.assert_eq(ability_blocks_status("もうか", @model.BurnKind), false)
}

///|
test "ability_blocks_status_empty_ability_never_blocks" {
  @debug.assert_eq(ability_blocks_status("", @model.SleepKind), false)
  @debug.assert_eq(ability_blocks_status("", @model.DrowsyKind), false)
  @debug.assert_eq(ability_blocks_status("", @model.ParalyzeKind), false)
}

///|
test "ability_blocks_leech_seed_magic_guard_returns_true" {
  @debug.assert_eq(ability_blocks_leech_seed("マジックガード"), true)
}

///|
test "ability_blocks_leech_seed_other_abilities_return_false" {
  @debug.assert_eq(ability_blocks_leech_seed("ふみん"), false)
  @debug.assert_eq(ability_blocks_leech_seed("やるき"), false)
  @debug.assert_eq(ability_blocks_leech_seed("スイートベール"), false)
  @debug.assert_eq(ability_blocks_leech_seed("ヘドロえき"), false)
  @debug.assert_eq(ability_blocks_leech_seed(""), false)
}

///|
test "ability_reverses_drain_liquid_ooze_returns_true" {
  @debug.assert_eq(ability_reverses_drain("ヘドロえき"), true)
}

///|
test "ability_reverses_drain_other_abilities_return_false" {
  @debug.assert_eq(ability_reverses_drain("マジックガード"), false)
  @debug.assert_eq(ability_reverses_drain("ふみん"), false)
  @debug.assert_eq(ability_reverses_drain("やるき"), false)
  @debug.assert_eq(ability_reverses_drain("スイートベール"), false)
  @debug.assert_eq(ability_reverses_drain(""), false)
}

///|
/// Magic Guard / Sand Rush / Sand Veil / Sand Force / Overcoat all hold
/// implicit sandstorm immunity in mainline behaviour. Type-based immunity
/// (はがね / いわ / じめん) is enforced at the call site, not through this
/// helper, so the truth table here only enumerates ability-side blockers.
test "ability_blocks_sand_damage_truth_table" {
  @debug.assert_eq(ability_blocks_sand_damage("マジックガード"), true)
  @debug.assert_eq(ability_blocks_sand_damage("すなかき"), true)
  @debug.assert_eq(ability_blocks_sand_damage("すながくれ"), true)
  @debug.assert_eq(ability_blocks_sand_damage("すなのちから"), true)
  @debug.assert_eq(ability_blocks_sand_damage("ぼうじん"), true)
}

///|
/// すなおこし (Sand Stream) only *summons* sand — it does not itself grant
/// sandstorm chip immunity, so the helper must return false. Its canonical
/// users (バンギラス / カバルドン / ギガイアス 等) are Rock / Ground and are
/// covered by the type-immunity check at the call site, never by this helper.
test "ability_blocks_sand_damage_other_abilities_return_false" {
  @debug.assert_eq(ability_blocks_sand_damage("すなおこし"), false)
  @debug.assert_eq(ability_blocks_sand_damage("ふみん"), false)
  @debug.assert_eq(ability_blocks_sand_damage("やるき"), false)
  @debug.assert_eq(ability_blocks_sand_damage("スイートベール"), false)
  @debug.assert_eq(ability_blocks_sand_damage("ヘドロえき"), false)
  @debug.assert_eq(ability_blocks_sand_damage("もうか"), false)
  @debug.assert_eq(ability_blocks_sand_damage(""), false)
}
