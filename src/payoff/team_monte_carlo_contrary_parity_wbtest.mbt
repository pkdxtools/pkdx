///|
/// あまのじゃく (Contrary) の MC/DP parity テスト。DP 側は
/// `with_post_hit_effects` → `apply_stat_effects`、MC 側は
/// `team_apply_post_hit` → `apply_stat_effects` と、同一チョークポイントで
/// delta を反転する。本ファイルは両 resolver が value-tol で一致することを
/// pin する (team_monte_carlo_intimidate_parity_wbtest.mbt の無飽和 fixture +
/// 感度ガードのパターンを踏襲)。
///
/// pin する観点:
///   1. value-tol parity: `|dp - mc| < 0.15` (sign-agreement のみでは不可)。
///      fixture 感度ガードとして「あまのじゃく 有無の DP 差 > 0.15」も assert
///      する — MC 側で反転が配線されていなければ mc は特性なし側の値
///      (≈ dp_plain) に張り付き、parity が tol を超えて fail する構成である
///      ことの自己検証。
///   2. 対称ケース (opp 側 あまのじゃく) でも同様に一致。
///
/// 方針メモ: fixture は 1v1・moveset 1 個 (交代/技選択の方策乖離が出ない構成)
/// で、双方 KO なしの horizon により terminal value が HP 比率差になる無飽和
/// 構成に固定する。ほのお→みず の半減 (0.5x) で与ダメを抑え、あまのじゃく
/// 側の C+2 連打でも KO に届かないようにしている。

///|
/// **Case 1 (value-tol parity, own 側 あまのじゃく)**: own = あまのじゃく
/// 持ちオーバーヒート連打、opp = 高耐久みず壁 (無威力技のみ)。初撃後に
/// own の C が +2 へ反転し、2 発目以降の与ダメが倍化する分が value に現れる。
test "MC/DP value parity under Contrary Overheat spam (own side)" {
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
  let own = [pl_cmb(atk_p, [overheat], ability="あまのじゃく")]
  let own_plain = [pl_cmb(atk_p, [overheat])]
  let opp = [pl_cmb(wall_p, [splash])]
  let turn_limit = 4
  let dp_value = switching_game_winrate(own, opp, turn_limit)
  let dp_plain = switching_game_winrate(own_plain, opp, turn_limit)
  // fixture 感度ガード: あまのじゃく の有無が tol を超えて value を動かす
  // 構成であること (= 飽和 fixture の「trivially |dp-mc|=0」を排除)。
  assert_true((dp_value - dp_plain).abs() > 0.15)
  let mc_value = team_monte_carlo_value(own, opp, 64, 4242UL, turn_limit~)
  let diff = (dp_value - mc_value).abs()
  assert_true(diff < 0.15)
}

///|
/// **Case 2 (value-tol parity, opp 側 あまのじゃく)**: Case 1 の対称。opp が
/// あまのじゃく 持ちオーバーヒート連打側でも DP / MC が value-tol で一致する
/// ことを pin する。感度ガードも対称に置く。
test "MC/DP value parity under Contrary Overheat spam (opp side)" {
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
  let own = [pl_cmb(wall_p, [splash])]
  let opp = [pl_cmb(atk_p, [overheat], ability="あまのじゃく")]
  let opp_plain = [pl_cmb(atk_p, [overheat])]
  let turn_limit = 4
  let dp_value = switching_game_winrate(own, opp, turn_limit)
  let dp_plain = switching_game_winrate(own, opp_plain, turn_limit)
  assert_true((dp_value - dp_plain).abs() > 0.15)
  let mc_value = team_monte_carlo_value(own, opp, 64, 5151UL, turn_limit~)
  let diff = (dp_value - mc_value).abs()
  assert_true(diff < 0.15)
}
