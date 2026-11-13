///|
/// Black-box tests for the ability-based immunity layer used by the healing
/// move support. Mirrors the truth table documented in the plan's section C
/// (`ability_immunity`): three abilities block Sleep + Drowsy, Magic Guard
/// gates the LeechSeed end-of-turn tick, and Liquid Ooze flips Drain into
/// damage. Every other (ability, kind) combination must return false so the
/// downstream healing pipeline does not skip legitimate status / heal events.

///|
test "ability_blocks_status_insomnia_blocks_sleep_and_drowsy" {
  @debug.assert_eq(@payoff.ability_blocks_status("ふみん", @model.SleepKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("ふみん", @model.DrowsyKind), true)
}

///|
test "ability_blocks_status_vital_spirit_blocks_sleep_and_drowsy" {
  @debug.assert_eq(@payoff.ability_blocks_status("やるき", @model.SleepKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("やるき", @model.DrowsyKind), true)
}

///|
test "ability_blocks_status_sweet_veil_blocks_sleep_and_drowsy" {
  @debug.assert_eq(
    @payoff.ability_blocks_status("スイートベール", @model.SleepKind),
    true,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status("スイートベール", @model.DrowsyKind),
    true,
  )
}

///|
test "ability_blocks_status_insomnia_does_not_block_non_sleep_kinds" {
  @debug.assert_eq(
    @payoff.ability_blocks_status("ふみん", @model.ParalyzeKind),
    false,
  )
  @debug.assert_eq(@payoff.ability_blocks_status("ふみん", @model.BurnKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("ふみん", @model.PoisonKind), false)
  @debug.assert_eq(
    @payoff.ability_blocks_status("ふみん", @model.BadPoisonKind),
    false,
  )
}

///|
test "ability_blocks_status_vital_spirit_does_not_block_non_sleep_kinds" {
  @debug.assert_eq(
    @payoff.ability_blocks_status("やるき", @model.ParalyzeKind),
    false,
  )
  @debug.assert_eq(@payoff.ability_blocks_status("やるき", @model.BurnKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("やるき", @model.PoisonKind), false)
  @debug.assert_eq(
    @payoff.ability_blocks_status("やるき", @model.BadPoisonKind),
    false,
  )
}

///|
test "ability_blocks_status_sweet_veil_does_not_block_non_sleep_kinds" {
  @debug.assert_eq(
    @payoff.ability_blocks_status("スイートベール", @model.ParalyzeKind),
    false,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status("スイートベール", @model.BurnKind),
    false,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status("スイートベール", @model.PoisonKind),
    false,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status("スイートベール", @model.BadPoisonKind),
    false,
  )
}

///|
test "ability_blocks_status_magic_guard_does_not_block_status_application" {
  // Magic Guard suppresses residual damage, not the status itself.
  @debug.assert_eq(
    @payoff.ability_blocks_status("マジックガード", @model.SleepKind),
    false,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status("マジックガード", @model.DrowsyKind),
    false,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status("マジックガード", @model.BurnKind),
    false,
  )
}

///|
test "ability_blocks_status_unrelated_ability_never_blocks" {
  @debug.assert_eq(@payoff.ability_blocks_status("もうか", @model.SleepKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("もうか", @model.DrowsyKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("もうか", @model.BurnKind), false)
}

///|
test "ability_blocks_status_empty_ability_never_blocks" {
  @debug.assert_eq(@payoff.ability_blocks_status("", @model.SleepKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("", @model.DrowsyKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("", @model.ParalyzeKind), false)
}

///|
/// じゅうなん (TOKUSEIINFO_SYN_007:256) はまひだけ。
test "ability_blocks_status_limber_blocks_only_paralyze" {
  @debug.assert_eq(@payoff.ability_blocks_status("じゅうなん", @model.ParalyzeKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("じゅうなん", @model.BurnKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("じゅうなん", @model.PoisonKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("じゅうなん", @model.BadPoisonKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("じゅうなん", @model.SleepKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("じゅうなん", @model.FreezeKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("じゅうなん", @model.DrowsyKind), false)
}

///|
/// めんえき (TOKUSEIINFO_SYN_017:544) はどく・もうどくだけ。
test "ability_blocks_status_immunity_blocks_poison_and_bad_poison" {
  @debug.assert_eq(@payoff.ability_blocks_status("めんえき", @model.PoisonKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("めんえき", @model.BadPoisonKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("めんえき", @model.ParalyzeKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("めんえき", @model.BurnKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("めんえき", @model.SleepKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("めんえき", @model.DrowsyKind), false)
}

///|
/// すいほう / ねつこうかん はやけどだけ。
test "ability_blocks_status_water_bubble_and_thermal_exchange_block_burn" {
  @debug.assert_eq(@payoff.ability_blocks_status("すいほう", @model.BurnKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("ねつこうかん", @model.BurnKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("すいほう", @model.ParalyzeKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("ねつこうかん", @model.PoisonKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("すいほう", @model.FreezeKind), false)
}

///|
/// きよめのしお (TOKUSEIINFO_SYN_272:7712) は全 StatusKind。あくびは Showdown fallback。
test "ability_blocks_status_purifying_salt_blocks_every_kind" {
  @debug.assert_eq(@payoff.ability_blocks_status("きよめのしお", @model.ParalyzeKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("きよめのしお", @model.BurnKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("きよめのしお", @model.PoisonKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("きよめのしお", @model.BadPoisonKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("きよめのしお", @model.SleepKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("きよめのしお", @model.FreezeKind), true)
  @debug.assert_eq(@payoff.ability_blocks_status("きよめのしお", @model.DrowsyKind), true)
}

///|
/// リーフガード (TOKUSEIINFO_SYN_102:3566) ははれのときだけ全状態。
test "ability_blocks_status_leaf_guard_only_in_sun" {
  @debug.assert_eq(
    @payoff.ability_blocks_status(
      "リーフガード",
      @model.BurnKind,
      weather=@model.Weather::Sun,
    ),
    true,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status(
      "リーフガード",
      @model.DrowsyKind,
      weather=@model.Weather::Sun,
    ),
    true,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status(
      "リーフガード",
      @model.FreezeKind,
      weather=@model.Weather::Sun,
    ),
    true,
  )
  @debug.assert_eq(@payoff.ability_blocks_status("リーフガード", @model.BurnKind), false)
  @debug.assert_eq(
    @payoff.ability_blocks_status(
      "リーフガード",
      @model.SleepKind,
      weather=@model.Weather::Rain,
    ),
    false,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status(
      "リーフガード",
      @model.ParalyzeKind,
      weather=@model.Weather::Sand,
    ),
    false,
  )
}

///|
/// フラワーベール (TOKUSEIINFO_SYN_166:5468)。シングルは自分がくさのとき。
/// ねむる (self_inflicted) は Showdown fallback で通す。
test "ability_blocks_status_flower_veil_grass_self_only" {
  @debug.assert_eq(
    @payoff.ability_blocks_status("フラワーベール", @model.BurnKind, type1="くさ"),
    true,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status(
      "フラワーベール",
      @model.SleepKind,
      type2="くさ",
    ),
    true,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status("フラワーベール", @model.ParalyzeKind, type1="ノーマル"),
    false,
  )
  @debug.assert_eq(
    @payoff.ability_blocks_status(
      "フラワーベール",
      @model.SleepKind,
      type1="くさ",
      self_inflicted=true,
    ),
    false,
  )
}

///|
/// マイペースはこんらん (未モデル) といかくだけ。状態異常は止めない。
test "ability_blocks_status_own_tempo_does_not_block_modelled_status" {
  @debug.assert_eq(@payoff.ability_blocks_status("マイペース", @model.ParalyzeKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("マイペース", @model.BurnKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("マイペース", @model.PoisonKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("マイペース", @model.SleepKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("マイペース", @model.DrowsyKind), false)
  @debug.assert_eq(@payoff.ability_blocks_status("マイペース", @model.FreezeKind), false)
}

///|
test "ability_blocks_leech_seed_magic_guard_returns_true" {
  @debug.assert_eq(@payoff.ability_blocks_leech_seed("マジックガード"), true)
}

///|
test "ability_blocks_leech_seed_other_abilities_return_false" {
  @debug.assert_eq(@payoff.ability_blocks_leech_seed("ふみん"), false)
  @debug.assert_eq(@payoff.ability_blocks_leech_seed("やるき"), false)
  @debug.assert_eq(@payoff.ability_blocks_leech_seed("スイートベール"), false)
  @debug.assert_eq(@payoff.ability_blocks_leech_seed("ヘドロえき"), false)
  @debug.assert_eq(@payoff.ability_blocks_leech_seed(""), false)
}

///|
test "ability_reverses_drain_liquid_ooze_returns_true" {
  @debug.assert_eq(@payoff.ability_reverses_drain("ヘドロえき"), true)
}

///|
test "ability_reverses_drain_other_abilities_return_false" {
  @debug.assert_eq(@payoff.ability_reverses_drain("マジックガード"), false)
  @debug.assert_eq(@payoff.ability_reverses_drain("ふみん"), false)
  @debug.assert_eq(@payoff.ability_reverses_drain("やるき"), false)
  @debug.assert_eq(@payoff.ability_reverses_drain("スイートベール"), false)
  @debug.assert_eq(@payoff.ability_reverses_drain(""), false)
}

///|
/// Magic Guard / Sand Rush / Sand Veil / Sand Force / Overcoat all hold
/// implicit sandstorm immunity in mainline behaviour. Type-based immunity
/// (はがね / いわ / じめん) is enforced at the call site, not through this
/// helper, so the truth table here only enumerates ability-side blockers.
test "ability_blocks_sand_damage_truth_table" {
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("マジックガード"), true)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("すなかき"), true)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("すながくれ"), true)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("すなのちから"), true)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("ぼうじん"), true)
}

///|
/// すなおこし (Sand Stream) only *summons* sand — it does not itself grant
/// sandstorm chip immunity, so the helper must return false. Its canonical
/// users (バンギラス / カバルドン / ギガイアス 等) are Rock / Ground and are
/// covered by the type-immunity check at the call site, never by this helper.
test "ability_blocks_sand_damage_other_abilities_return_false" {
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("すなおこし"), false)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("ふみん"), false)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("やるき"), false)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("スイートベール"), false)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("ヘドロえき"), false)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage("もうか"), false)
  @debug.assert_eq(@payoff.ability_blocks_sand_damage(""), false)
}

///|
/// Four abilities gained Intimidate-specific immunity in Gen8 (どんかん /
/// マイペース / せいしんりょく / きもったま) and four block Attack drops in
/// general (クリアボディ / かいりきバサミ / しろいけむり / メタルプロテクト).
/// All eight must return true; nothing else does.
test "ability_blocks_intimidate_truth_table" {
  @debug.assert_eq(@payoff.ability_blocks_intimidate("どんかん"), true)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("マイペース"), true)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("せいしんりょく"), true)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("きもったま"), true)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("クリアボディ"), true)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("かいりきバサミ"), true)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("しろいけむり"), true)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("メタルプロテクト"), true)
}

///|
/// いかく itself never blocks an incoming Intimidate — two Intimidate users
/// facing each other both drop Attack. ばんけん / ミラーアーマー / びびり /
/// あまのじゃく redirect the drop instead of blocking it, so they must stay
/// false here and are dispatched separately in `apply_intimidate_on_entry`.
test "ability_blocks_intimidate_other_abilities_return_false" {
  @debug.assert_eq(@payoff.ability_blocks_intimidate("いかく"), false)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("テクニシャン"), false)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("ばんけん"), false)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("ミラーアーマー"), false)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("びびり"), false)
  @debug.assert_eq(@payoff.ability_blocks_intimidate("あまのじゃく"), false)
  @debug.assert_eq(@payoff.ability_blocks_intimidate(""), false)
}

///|
/// Clear Body / White Smoke / Full Metal Body block a move's opponent-inflicted
/// drop on every stat (Showdown `onTryBoost`, one shared body).
test "ability_blocks_opp_stat_drop_all_stat_blockers_return_true" {
  for stat in 0..<5 {
    @debug.assert_eq(
      @payoff.ability_blocks_opp_stat_drop("クリアボディ", stat),
      true,
    )
    @debug.assert_eq(
      @payoff.ability_blocks_opp_stat_drop("しろいけむり", stat),
      true,
    )
    @debug.assert_eq(
      @payoff.ability_blocks_opp_stat_drop("メタルプロテクト", stat),
      true,
    )
  }
}

///|
/// Hyper Cutter blocks only the Attack drop (stat 0); Defense / SpA / SpD /
/// Speed drops from a move still land.
test "ability_blocks_opp_stat_drop_hyper_cutter_attack_only" {
  @debug.assert_eq(
    @payoff.ability_blocks_opp_stat_drop("かいりきバサミ", 0),
    true,
  )
  for stat in 1..<5 {
    @debug.assert_eq(
      @payoff.ability_blocks_opp_stat_drop("かいりきバサミ", stat),
      false,
    )
  }
}

///|
/// Intimidate-only blockers (Showdown gates them on `effect.name ===
/// 'Intimidate'`), Guard Dog, and the redirect / reverse / reaction abilities
/// do not block a move's drop on any stat.
test "ability_blocks_opp_stat_drop_other_abilities_return_false" {
  let abilities = [
    "どんかん",
    "マイペース",
    "せいしんりょく",
    "きもったま",
    "ばんけん",
    "ミラーアーマー",
    "びびり",
    "あまのじゃく",
    "まけんき",
    "かちき",
    "いかく",
    "",
  ]
  for ability in abilities {
    for stat in 0..<5 {
      @debug.assert_eq(
        @payoff.ability_blocks_opp_stat_drop(ability, stat),
        false,
      )
    }
  }
}

///|
test "ability_reverses_stat_changes_contrary_returns_true" {
  @debug.assert_eq(@payoff.ability_reverses_stat_changes("あまのじゃく"), true)
}

///|
test "ability_reverses_stat_changes_other_abilities_return_false" {
  @debug.assert_eq(@payoff.ability_reverses_stat_changes("いかく"), false)
  @debug.assert_eq(@payoff.ability_reverses_stat_changes("クリアボディ"), false)
  @debug.assert_eq(@payoff.ability_reverses_stat_changes("テクニシャン"), false)
  @debug.assert_eq(
    @payoff.ability_reverses_stat_changes("ミラーアーマー"),
    false,
  )
  @debug.assert_eq(@payoff.ability_reverses_stat_changes(""), false)
}

///|
test "ability_absorb_boost: そうしょく は Attack +1、他の特性は None" {
  @debug.assert_eq(@payoff.ability_absorb_boost("そうしょく"), Some((0, 1)))
  @debug.assert_eq(@payoff.ability_absorb_boost("ちょすい"), None)
  @debug.assert_eq(@payoff.ability_absorb_boost("でんきエンジン"), None)
  @debug.assert_eq(@payoff.ability_absorb_boost("クリアボディ"), None)
  @debug.assert_eq(@payoff.ability_absorb_boost(""), None)
}

///|
test "ability_absorbs_move: くさ技を相手に向けた時だけ吸収する" {
  @debug.assert_eq(
    @payoff.ability_absorbs_move("そうしょく", "リーフブレード", "くさ"),
    true,
  )
  @debug.assert_eq(
    @payoff.ability_absorbs_move("そうしょく", "ねむりごな", "くさ"),
    true,
  )
  @debug.assert_eq(
    @payoff.ability_absorbs_move("そうしょく", "たいあたり", "ノーマル"),
    false,
  )
  @debug.assert_eq(
    @payoff.ability_absorbs_move("ちょすい", "なみのり", "みず"),
    false,
  )
  @debug.assert_eq(@payoff.ability_absorbs_move("", "リーフブレード", "くさ"), false)
}

///|
test "ability_absorbs_move: 自分・自分側・フィールドを狙うくさ技は吸収されない" {
  for name in [
    "ねをはる",
    "こうごうせい",
    "せいちょう",
    "コットンガード",
    "ニードルガード",
    "グラスフィールド",
    "アロマセラピー",
    "ジャングルヒール",
  ] {
    @debug.assert_eq(@payoff.ability_absorbs_move("そうしょく", name, "くさ"), false)
  }
}

///|
test "ability_tracks_full_stages: まけんき / かちき / そうしょく は ±6 で追跡" {
  @debug.assert_eq(@payoff.ability_tracks_full_stages("まけんき"), true)
  @debug.assert_eq(@payoff.ability_tracks_full_stages("かちき"), true)
  @debug.assert_eq(@payoff.ability_tracks_full_stages("そうしょく"), true)
  @debug.assert_eq(@payoff.ability_tracks_full_stages("ちょすい"), false)
  @debug.assert_eq(@payoff.ability_tracks_full_stages(""), false)
}

///|
test "clamp_rank_for: そうしょく は +6 まで、通常特性は +2 まで" {
  @debug.assert_eq(@payoff.clamp_rank_for("そうしょく", 9), 6)
  @debug.assert_eq(@payoff.clamp_rank_for("そうしょく", -9), -6)
  @debug.assert_eq(@payoff.clamp_rank_for("", 9), 2)
  @debug.assert_eq(@payoff.clamp_rank_for("", -9), -2)
}
