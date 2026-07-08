///|
/// あまのじゃく (Contrary) による技 `stat_effects` 反転のテスト。
///
/// ランク適用の唯一のチョークポイントは `apply_stat_effects` であり、
/// `ability_reverses_stat_changes` が true の holder (target=0 → attacker /
/// target=1 → defender) に対して delta を符号反転してから clamp する。
/// いかく (entry ability) × あまのじゃく の反転は entry_abilities 側で
/// 処理済みのため本ファイルでは扱わない (entry_abilities_test.mbt が担当)。
///
/// helper は wbtest 共有のものを使う: `mk_move` (switching_game_status_wbtest),
/// `mk_pokemon` (team_monte_carlo_healing_wbtest), `pl_cmb`
/// (team_monte_carlo_protean_parity_wbtest)。

///|
/// **Case 1 (自己積み反転)**: からをやぶる 相当 [A+2, C+2, S+2, B-1, D-1] を
/// あまのじゃく attacker が使うと全エントリが反転して A-2/C-2/S-2/B+1/D+1。
/// 2 回目の使用で reduced range [-2,+2] の clamp を踏む: A/C/S は -2 で飽和、
/// B/D は +2 に到達する。
test "contrary: からをやぶる 相当の自己 stat_effects が全反転する" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("shell_smash", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: 2, target: 0 },
    @model.StatEffect::{ stat: 2, delta: 2, target: 0 },
    @model.StatEffect::{ stat: 4, delta: 2, target: 0 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 3, delta: -1, target: 0 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="あまのじゃく",
    defender_ability="",
  )
  @debug.assert_eq(self_ranks[0], -2)
  @debug.assert_eq(self_ranks[2], -2)
  @debug.assert_eq(self_ranks[4], -2)
  @debug.assert_eq(self_ranks[1], 1)
  @debug.assert_eq(self_ranks[3], 1)
  for i in 0..<5 {
    @debug.assert_eq(opp_ranks[i], 0)
  }
  // 2 回目: clamp [-2,+2] 込みの飽和挙動。
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="あまのじゃく",
    defender_ability="",
  )
  @debug.assert_eq(self_ranks[0], -2)
  @debug.assert_eq(self_ranks[2], -2)
  @debug.assert_eq(self_ranks[4], -2)
  @debug.assert_eq(self_ranks[1], 2)
  @debug.assert_eq(self_ranks[3], 2)
}

///|
/// **Case 2 (自己ダウン反転 = あまのじゃく の主用途)**: インファイト 相当
/// [B-1, D-1] を あまのじゃく attacker が使うと B+1/D+1 に化ける。
test "contrary: インファイト 相当の自己ダウンが B+1/D+1 に反転する" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("close_combat", "かくとう", @model.Physical, 120, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 3, delta: -1, target: 0 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="あまのじゃく",
    defender_ability="",
  )
  @debug.assert_eq(self_ranks[1], 1)
  @debug.assert_eq(self_ranks[3], 1)
  @debug.assert_eq(self_ranks[0], 0)
  for i in 0..<5 {
    @debug.assert_eq(opp_ranks[i], 0)
  }
}

///|
/// **Case 3 (受け側反転)**: あまえる 相当 [A-2, target=1] を あまのじゃく
/// defender が受けると defender の A は +2 に上がる。
test "contrary: あまえる を あまのじゃく defender が受けると A+2" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("amaeru", "フェアリー", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -2, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="あまのじゃく",
  )
  @debug.assert_eq(opp_ranks[0], 2)
  for i in 0..<5 {
    @debug.assert_eq(self_ranks[i], 0)
  }
}

///|
/// **Case 3b (反転の holder 対応)**: attacker 側の あまのじゃく は opp-target
/// エントリに影響しない (反転は各エントリの holder の ability のみを見る)。
test "contrary: attacker の あまのじゃく は opp-target の delta を反転しない" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("mixed", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: 2, target: 0 },
    @model.StatEffect::{ stat: 0, delta: -2, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="あまのじゃく",
    defender_ability="",
  )
  // self 側だけ反転 (+2 → -2)、opp 側は素通し (-2 のまま)。
  @debug.assert_eq(self_ranks[0], -2)
  @debug.assert_eq(opp_ranks[0], -2)
}

///|
/// **Case 4 (非あまのじゃく regression)**: あまのじゃく 以外の ability
/// ("" / いかく) では従来と同一の結果になる (反転は predicate true のときのみ)。
test "contrary regression: 非あまのじゃく ability では従来結果と同一" {
  let mv = mk_move("mixed", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: 2, target: 0 },
    @model.StatEffect::{ stat: 0, delta: -2, target: 1 },
  ])
  // ability="" (従来 default 相当)。
  let self_a = [0, 0, 0, 0, 0]
  let opp_a = [0, 0, 0, 0, 0]
  apply_stat_effects(
    self_a,
    opp_a,
    true,
    mv,
    attacker_ability="",
    defender_ability="",
  )
  @debug.assert_eq(self_a[0], 2)
  @debug.assert_eq(opp_a[0], -2)
  // あまのじゃく 以外の非空 ability でも同一。
  let self_b = [0, 0, 0, 0, 0]
  let opp_b = [0, 0, 0, 0, 0]
  apply_stat_effects(
    self_b,
    opp_b,
    true,
    mv,
    attacker_ability="いかく",
    defender_ability="クリアボディ",
  )
  @debug.assert_eq(self_b[0], 2)
  @debug.assert_eq(opp_b[0], -2)
}

///|
/// **Case 5 (opp_alive gate)**: defender が KO 済み (opp_alive=false) のとき、
/// target=1 エントリは あまのじゃく による反転を含めて一切適用されない。
test "contrary: opp_alive=false では target=1 が反転込みで未適用" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("amaeru", "フェアリー", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -2, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    false,
    mv,
    attacker_ability="",
    defender_ability="あまのじゃく",
  )
  @debug.assert_eq(opp_ranks[0], 0)
}

///|
/// **Case 6 (value-level 方向性)**: オーバーヒート 相当 (C-2 self) 連打の
/// 1v1 fixture。双方 KO なしの horizon で terminal value = HP 比率差になる
/// 構成 (ほのお→みず の半減で与ダメを抑え飽和を防ぐ)。あまのじゃく 持ちは
/// 2 発目以降 C+2 で撃てるため、特性なしより value が有利方向に動く。
test "contrary value: オーバーヒート連打で あまのじゃく 側の value が有利化" {
  let atk_p = mk_pokemon(
    "Overheater", "ほのお", "", 240, 60, 100, 120, 100, 110,
  )
  let wall_p = mk_pokemon("AquaWall", "みず", "", 320, 60, 110, 60, 110, 60)
  let overheat = mk_move(
    "オーバーヒート",
    "ほのお",
    @model.Special,
    90,
    stat_effects=[@model.StatEffect::{ stat: 2, delta: -2, target: 0 }],
  )
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let own_contrary = [pl_cmb(atk_p, [overheat], ability="あまのじゃく")]
  let own_plain = [pl_cmb(atk_p, [overheat])]
  let opp = [pl_cmb(wall_p, [splash])]
  let turn_limit = 4
  let v_contrary = switching_game_winrate(own_contrary, opp, turn_limit)
  let v_plain = switching_game_winrate(own_plain, opp, turn_limit)
  assert_true(v_contrary > v_plain)
}
