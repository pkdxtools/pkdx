///|
/// Stage H (MC non-damage terrain parity): MC rollout が DP の non-damage
/// terrain semantics (Misty status block / Grassy EOT heal / Psychic priority
/// block) を備えることを直接観測する parity test 群。
///
/// **背景**: Stage F/G で DP 側 (SwitchingGame) は terrain の damage 倍率に加え
/// 「ミストフィールドの状態異常無効」「グラスフィールドの EOT 回復」「サイコ
/// フィールドの優先度技ブロック」を完全に意味論化した。一方 MC 側
/// (`team_monte_carlo`) は terrain の damage 倍率しか反映しておらず、これら
/// 3 つの non-damage 効果が抜けていた。ScreenedSwitchingGame は MC screening →
/// DP refine のパイプラインのため、この乖離は terrain 絡みの選出で MC phase と
/// DP phase の payoff を割る。本 stage で MC 側に同じ意味論を移植し parity を
/// 保証する。
///
/// 直接ヘルパー呼び出し (`mc_try_apply_status` / `mc_psychic_priority_blocked`)
/// で exact semantics を deterministic に pin し、`team_rollout` /
/// `team_monte_carlo_value` 経由のケースで「MC が実際にそれらを呼んでいる」配線
/// を観測する。mk_pokemon / mk_combatant / mk_move / seeded_rng は同 package の
/// 既存 wbtest helper を共有する (file をまたいで可視)。

///|
/// **Case M-1 (Misty status block — direct, deterministic)**: grounded な
/// defender へ 100% paralyze 技を `mc_try_apply_status` で撃つ。field=Misty の
/// とき status は付与されず、field=None では Paralyze が付与される。chance=100
/// なので `rand_bool` は rng を消費せず確定 true を返し、roll の確率性に依存
/// しない deterministic な観測になる。
test "mc_try_apply_status: Misty Terrain blocks status on grounded defender" {
  let grounded = mk_pokemon("Grounded", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let thunderwave = mk_move(
    "でんじは", "でんき", @model.Status, 0,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
  let def_team = [mk_combatant(grounded, [thunderwave])]
  let hps = [200]
  let rng = seeded_rng(1UL)
  // Misty + grounded → 阻止 (status は None のまま)。
  let st_misty : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(
    rng, thunderwave, def_team, hps, st_misty, 0, field=@model.Field::Misty,
  )
  @debug.assert_eq(st_misty[0], @model.None)
  // None field → 付与される (Paralyze)。
  let st_none : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(
    rng, thunderwave, def_team, hps, st_none, 0, field=@model.Field::None,
  )
  @debug.assert_eq(st_none[0], @model.Paralyze)
}

///|
/// **Case M-2 (Misty does not block airborne — direct)**: ミストフィールドの
/// status block は grounded 限定。ひこう タイプ (= 非 grounded) には Misty 下
/// でも status が付与される。DP `maybe_apply_status_fanout` の grounded gate と
/// 一致。
test "mc_try_apply_status: Misty Terrain does not block airborne defender" {
  let flyer = mk_pokemon("Flyer", "ひこう", "", 200, 100, 100, 100, 100, 100)
  let thunderwave = mk_move(
    "でんじは", "でんき", @model.Status, 0,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
  let def_team = [mk_combatant(flyer, [thunderwave])]
  let hps = [200]
  let rng = seeded_rng(1UL)
  let st : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(
    rng, thunderwave, def_team, hps, st, 0, field=@model.Field::Misty,
  )
  @debug.assert_eq(st[0], @model.Paralyze)
}

///|
/// **Case M-3 (Electric Terrain blocks sleep on grounded — direct)**: #143
/// review parity. エレキフィールドは grounded を眠らせないため、grounded
/// defender への 100% sleep 技は status を付与しない。field=None では Sleep(2)
/// が付与される。DP `maybe_apply_status_fanout` の Electric sleep block (Case
/// G-2-H-A) と一致する MC 側 pin。
test "mc_try_apply_status: Electric Terrain blocks sleep on grounded defender" {
  let grounded = mk_pokemon("Grounded", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let spore = mk_move(
    "ねむらせる", "エスパー", @model.Status, 0,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let def_team = [mk_combatant(grounded, [spore])]
  let hps = [200]
  let rng = seeded_rng(1UL)
  // Electric + grounded + sleep → 阻止 (None のまま)。
  let st_electric : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(
    rng, spore, def_team, hps, st_electric, 0, field=@model.Field::Electric,
  )
  @debug.assert_eq(st_electric[0], @model.None)
  // None field → Sleep(2) が付与される。
  let st_none : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(
    rng, spore, def_team, hps, st_none, 0, field=@model.Field::None,
  )
  @debug.assert_eq(st_none[0], @model.Sleep(2))
}

///|
/// **Case M-4 (Electric Terrain does not block paralyze — direct)**: Electric は
/// sleep 限定の阻止なので、grounded defender への 100% paralyze は通常通り入る。
/// Misty (全状態阻止) との決定的差分を MC でも pin。DP Case G-2-H-C と一致。
test "mc_try_apply_status: Electric Terrain does not block paralyze on grounded defender" {
  let grounded = mk_pokemon("Grounded", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let thunderwave = mk_move(
    "でんじは", "でんき", @model.Status, 0,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
  let def_team = [mk_combatant(grounded, [thunderwave])]
  let hps = [200]
  let rng = seeded_rng(1UL)
  let st : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(
    rng, thunderwave, def_team, hps, st, 0, field=@model.Field::Electric,
  )
  @debug.assert_eq(st[0], @model.Paralyze)
}

///|
/// **Case M-5 (Electric Terrain does not block airborne sleep — direct)**:
/// Electric の sleep block は grounded 限定。ひこう (= 非 grounded) には Electric
/// 下でも sleep が付与される。DP Case G-2-H-D と一致。
test "mc_try_apply_status: Electric Terrain does not block sleep on airborne defender" {
  let flyer = mk_pokemon("Flyer", "ひこう", "", 200, 100, 100, 100, 100, 100)
  let spore = mk_move(
    "ねむらせる", "エスパー", @model.Status, 0,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let def_team = [mk_combatant(flyer, [spore])]
  let hps = [200]
  let rng = seeded_rng(1UL)
  let st : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(
    rng, spore, def_team, hps, st, 0, field=@model.Field::Electric,
  )
  @debug.assert_eq(st[0], @model.Sleep(2))
}

///|
/// **Case P-1 (Psychic priority block — direct, deterministic)**: priority>0 の
/// 技は grounded defender に対し Psychic Terrain で無効化される。priority<=0 /
/// Field != Psychic / 非 grounded defender の各境界では false を返す。DP
/// resolve 側 Stage G-3 (switching_game_turn.mbt) の判定と完全一致。
test "mc_psychic_priority_blocked: priority>0 negated vs grounded under Psychic" {
  let grounded = mk_pokemon("Grounded", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let flyer = mk_pokemon("Flyer", "ひこう", "", 200, 100, 100, 100, 100, 100)
  let quick_attack = mk_move("でんこうせっか", "ノーマル", @model.Physical, 40, priority=1)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let grounded_c = mk_combatant(grounded, [tackle])
  let flyer_c = mk_combatant(flyer, [tackle])
  // priority>0 + Psychic + grounded → blocked。
  assert_true(
    mc_psychic_priority_blocked(quick_attack, @model.Field::Psychic, grounded_c),
  )
  // priority>0 + Psychic + airborne → not blocked。
  assert_true(
    !mc_psychic_priority_blocked(quick_attack, @model.Field::Psychic, flyer_c),
  )
  // priority>0 + None field → not blocked。
  assert_true(
    !mc_psychic_priority_blocked(quick_attack, @model.Field::None, grounded_c),
  )
  // priority==0 + Psychic + grounded → not blocked。
  assert_true(
    !mc_psychic_priority_blocked(tackle, @model.Field::Psychic, grounded_c),
  )
}

///|
/// **Case G-1 (Grassy EOT heal wired into MC rollout)**: own = grounded
/// (Grassy 回復対象)、opp = ひこう (非 grounded、回復なし)。両者とも grass /
/// じめん 技を撃たないので Grassy の唯一の効果は grounded active への EOT
/// 回復 (max/16)。これにより field=Grassy では own_ratio が field=None より
/// 高くなり、`team_monte_carlo_value` が strict に上がる。配線が抜けていれば
/// 両 value は一致して fail する (= MC が `apply_grassy_heal_active` を EOT で
/// 呼んでいることの観測証拠)。
test "team_rollout: Grassy Terrain EOT heal raises grounded own value vs Field::None" {
  let own_p = mk_pokemon("Grounded", "ノーマル", "", 300, 90, 100, 90, 100, 100)
  let opp_p = mk_pokemon("Flyer", "ひこう", "", 300, 90, 100, 90, 100, 90)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  // かぜおこし は ひこう 技 — Grassy の grass-move boost 対象外。じめん 技も
  // 使わないので Grassy の defender 0.5x mod も発動しない。
  let gust = mk_move("かぜおこし", "ひこう", @model.Special, 50)
  let own = [mk_combatant(own_p, [tackle])]
  let opp = [mk_combatant(opp_p, [gust])]
  let v_none = team_monte_carlo_value(
    own, opp, 4, 55UL, turn_limit=6, field=@model.Field::None,
  )
  let v_grassy = team_monte_carlo_value(
    own, opp, 4, 55UL, turn_limit=6, field=@model.Field::Grassy,
  )
  assert_true(v_grassy > v_none)
}

///|
/// **Case P-2 (Psychic priority block wired into MC rollout)**: own は
/// でんこうせっか (priority +1, ノーマル) のみの moveset。opp は grounded で
/// たいあたり (priority 0)。field=Psychic では own の priority 技が毎ターン
/// 無効化され own は damage を通せず、opp のみ削り続けて own が不利になる。
/// field=None では own の technically 同 damage が通り、value は明確に高い。
/// よって v_psychic < v_none。priority 技ブロックが MC resolution に配線されて
/// いなければ両 value は一致して fail する。
test "team_rollout: Psychic Terrain priority block lowers priority-only own value" {
  // own の moveset を priority 技だけにすることで、greedy が必ず priority 技を
  // 選び、Psychic 下では毎ターン no-effect になる。opp は grounded ノーマルで
  // 非 priority 技 (block の影響なし)。
  let own_p = mk_pokemon("Prior1", "ノーマル", "", 250, 110, 90, 90, 90, 120)
  let opp_p = mk_pokemon("Grounded", "ノーマル", "", 250, 100, 100, 100, 100, 80)
  let quick_attack = mk_move("でんこうせっか", "ノーマル", @model.Physical, 60, priority=1)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 60)
  let own = [mk_combatant(own_p, [quick_attack])]
  let opp = [mk_combatant(opp_p, [tackle])]
  let v_none = team_monte_carlo_value(
    own, opp, 4, 88UL, turn_limit=8, field=@model.Field::None,
  )
  let v_psychic = team_monte_carlo_value(
    own, opp, 4, 88UL, turn_limit=8, field=@model.Field::Psychic,
  )
  assert_true(v_psychic < v_none)
}
