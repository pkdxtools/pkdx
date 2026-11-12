///|
test "get_atk_ability_final: そうだいしょう multiplier table" {
  // fainted=0 → no modifier
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", 0),
    content="0",
  )
  // fainted=1 → x1.1 (4506/4096)
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", 1),
    content="4506",
  )
  // fainted=2 → x1.2 (4915/4096)
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", 2),
    content="4915",
  )
  // fainted=3 → x1.3 (5325/4096)
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", 3),
    content="5325",
  )
  // fainted=4 → x1.4 (5734/4096)
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", 4),
    content="5734",
  )
  // fainted=5 → x1.5 (6144/4096)
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", 5),
    content="6144",
  )
}

///|
test "get_atk_ability_final: そうだいしょう clamps out-of-range" {
  // negative → 0 (clamped to 0)
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", -1),
    content="0",
  )
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", -10),
    content="0",
  )
  // > 5 → clamped to 5 (6144)
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", 6),
    content="6144",
  )
  @debug.debug_inspect(
    @damage.get_atk_ability_final("そうだいしょう", "ノーマル", 100),
    content="6144",
  )
}

///|
test "get_atk_ability_final: そうだいしょう is type-independent" {
  // move type does not affect そうだいしょう
  let fainted = 3
  let base = @damage.get_atk_ability_final(
    "そうだいしょう", "ノーマル", fainted,
  )
  @debug.debug_inspect(
    base == @damage.get_atk_ability_final("そうだいしょう", "ほのお", fainted),
    content="true",
  )
  @debug.debug_inspect(
    base == @damage.get_atk_ability_final("そうだいしょう", "みず", fainted),
    content="true",
  )
  @debug.debug_inspect(
    base ==
    @damage.get_atk_ability_final("そうだいしょう", "ゴースト", fainted),
    content="true",
  )
}

///|
test "get_atk_ability_final: other abilities ignore fainted_count" {
  // fainted_count は そうだいしょう 以外に影響しない。
  // ちからずく は追加効果フラグが無い既定 (false) では 1.0 倍。
  @debug.debug_inspect(
    @damage.get_atk_ability_final("ちからずく", "ノーマル", 0),
    content="0",
  )
  @debug.debug_inspect(
    @damage.get_atk_ability_final("ちからずく", "ノーマル", 5),
    content="0",
  )
  @debug.debug_inspect(
    @damage.get_atk_ability_final("トランジスタ", "でんき", 3),
    content="5325",
  )
  @debug.debug_inspect(
    @damage.get_atk_ability_final("", "ノーマル", 2),
    content="0",
  )
}

///|
/// アナライズ は追加効果フラグを見ない。ちからずく と分けたあとも常に 5325。
test "get_atk_ability_final: アナライズ stays 5325 whether or not the move has a secondary" {
  @debug.debug_inspect(
    @damage.get_atk_ability_final("アナライズ", "ノーマル", 0),
    content="5325",
  )
  @debug.debug_inspect(
    @damage.get_atk_ability_final(
      "アナライズ",
      "ノーマル",
      0,
      sheer_force_effect=false,
    ),
    content="5325",
  )
  @debug.debug_inspect(
    @damage.get_atk_ability_final(
      "アナライズ",
      "ノーマル",
      4,
      sheer_force_effect=true,
    ),
    content="5325",
  )
}

///|
/// ちからずく は追加効果があるときだけ 5325/4096。フラグが偽なら 0 (1.0 倍)。
test "get_atk_ability_final: ちからずく is 5325 only when the move has a stripped secondary" {
  @debug.debug_inspect(
    @damage.get_atk_ability_final(
      "ちからずく",
      "ほのお",
      0,
      sheer_force_effect=true,
    ),
    content="5325",
  )
  @debug.debug_inspect(
    @damage.get_atk_ability_final(
      "ちからずく",
      "ほのお",
      5,
      sheer_force_effect=false,
    ),
    content="0",
  )
}

///|
fn sf_move(
  name : String,
  power : Int,
  status_effect : (@model.StatusKind, Int)?,
  flinch_chance : Int,
) -> @model.Move {
  {
    ..mk_move(name, "ノーマル", @model.Physical, power),
    status_effect,
    flinch_chance,
  }
}

///|
/// 追加効果の定義。ダメージ技の status (chance > 0) と flinch だけ。
/// 変化技・chance 0・能力変化だけ、は偽。
test "move_has_sheer_force_effect: damaging status or flinch only" {
  let bite = sf_move("かみつく", 60, None, 30)
  let punch = sf_move("ほのおのパンチ", 75, Some((@model.BurnKind, 10)), 0)
  let both = sf_move("キバ", 65, Some((@model.FreezeKind, 10)), 10)
  let tackle = sf_move("たいあたり", 40, None, 0)
  let zero_chance = sf_move("からぶり", 40, Some((@model.BurnKind, 0)), 0)
  let status = sf_move("おにび", 0, Some((@model.BurnKind, 85)), 0)
  let stat_only = {
    ..tackle,
    stat_effects: [{ stat: 1, delta: -1, target: 0 }],
  }
  assert_true(@damage.move_has_sheer_force_effect(bite))
  assert_true(@damage.move_has_sheer_force_effect(punch))
  assert_true(@damage.move_has_sheer_force_effect(both))
  assert_true(!@damage.move_has_sheer_force_effect(tackle))
  assert_true(!@damage.move_has_sheer_force_effect(zero_chance))
  assert_true(!@damage.move_has_sheer_force_effect(status))
  assert_true(!@damage.move_has_sheer_force_effect(stat_only))
  assert_true(@damage.sheer_force_boost_applies("ちからずく", bite))
  assert_true(!@damage.sheer_force_boost_applies("ちからずく", tackle))
  assert_true(!@damage.sheer_force_boost_applies("アナライズ", bite))
  assert_true(!@damage.sheer_force_boost_applies("", punch))
  // 落としたあとは追加効果が残らない。能力変化は残る。
  let cleared = @damage.clear_damaging_secondaries(both)
  assert_true(!@damage.move_has_sheer_force_effect(cleared))
  assert_true(cleared.status_effect is None)
  assert_true(cleared.flinch_chance == 0)
  let cleared_stat = @damage.clear_damaging_secondaries(stat_only)
  assert_true(cleared_stat.stat_effects.length() == 1)
}

///|
fn sf_low_roll(ability : String, mv : @model.Move) -> Int {
  let atk = mk_pokemon_typed("a", "ノーマル", "", 200, 120, 100, 100, 100, 100)
  let def = mk_pokemon_typed("d", "ノーマル", "", 200, 80, 100, 80, 100, 80)
  let input = mk_damage_input(atk, def, mv, atk_ability=ability)
  @damage.calc_damage(input).damages[0]
}

///|
/// エンジンは追加効果のある技だけ ちからずく を掛け、アナライズ は技を問わず掛ける。
test "calc_damage: ちからずく boosts only moves with a stripped secondary; アナライズ does not change" {
  let tackle = sf_move("たいあたり", 40, None, 0)
  let bite = sf_move("かみつく", 60, None, 30)
  let punch = sf_move("ほのおのパンチ", 75, Some((@model.BurnKind, 10)), 0)
  let stat_only = {
    ..sf_move("インファイト", 120, None, 0),
    stat_effects: [{ stat: 1, delta: -1, target: 0 }],
  }
  let plain_tackle = sf_low_roll("", tackle)
  let sheer_tackle = sf_low_roll("ちからずく", tackle)
  let analytic_tackle = sf_low_roll("アナライズ", tackle)
  // 追加効果なし: ちからずく は無特性と同じ。アナライズ は従来どおり上がる。
  @debug.assert_eq(sheer_tackle, plain_tackle)
  assert_true(analytic_tackle > plain_tackle)
  // ひるみ / やけど: ちからずく は上がる。アナライズ も同じ 5325 なので同値。
  let plain_bite = sf_low_roll("", bite)
  let sheer_bite = sf_low_roll("ちからずく", bite)
  let analytic_bite = sf_low_roll("アナライズ", bite)
  assert_true(sheer_bite > plain_bite)
  @debug.assert_eq(sheer_bite, analytic_bite)
  let plain_punch = sf_low_roll("", punch)
  let sheer_punch = sf_low_roll("ちからずく", punch)
  assert_true(sheer_punch > plain_punch)
  @debug.assert_eq(sheer_punch, sf_low_roll("アナライズ", punch))
  // 能力変化だけは追加効果に数えない。威力は変わらない。
  @debug.assert_eq(sf_low_roll("ちからずく", stat_only), sf_low_roll("", stat_only))
}
