///|
/// フライングプレスの DP / MC parity。
///
/// `pkdx select` の SwitchingGame (`value`) と MC screening
/// (`team_monte_carlo_value`) はどちらも `calc_damage` の相性を使う。
/// ここは 1v1・技 1 本で、複合相性が勝率を動かす matchup を pin する。
///
/// - くさ: フライングプレスは 2 倍、同威力のかくとう技は等倍。DP 値は
///   フライングプレスの方が高い。
/// - はがね/いわ: フライングプレスは等倍、かくとう技は 4 倍。逆。
/// - ゴースト: フライングプレスは無効。くさ相手より値が低い。
///
/// 命中は 100 に固定する (本番の 95 は技 accuracy フィールドの話で、
/// 相性差の比較には乗せない)。ちいさくなるはシミュレーション未モデル。

///|
fn fp_press() -> @model.Move {
  mk_move("フライングプレス", "かくとう", @model.Physical, 100)
}

///|
fn fp_fight() -> @model.Move {
  mk_move("かくとうテスト技", "かくとう", @model.Physical, 100)
}

///|
fn fp_tackle() -> @model.Move {
  mk_move("たいあたり", "ノーマル", @model.Physical, 40)
}

///|
fn fp_dp(
  own : Array[Combatant],
  opp : Array[Combatant],
  turn_limit : Int,
) -> Double {
  let state = pl_parity_state(own, opp)
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  let stats = new_stats_with_progress(noop_progress, 0)
  let dmg = new_damage_cache()
  value(state, own, opp, turn_limit, cache, stats, dmg)
}

///|
fn fp_pair(
  own_type1 : String,
  opp_type1 : String,
  opp_type2 : String,
  own_move : @model.Move,
) -> (Array[Combatant], Array[Combatant]) {
  // 攻撃は通るが 3 ターンでは倒れきらない耐久。素早さは own が先制。
  let own_p = mk_pokemon("PressUser", own_type1, "", 180, 80, 140, 60, 120, 130)
  let opp_p = mk_pokemon(
    "PressTarget", opp_type1, opp_type2, 220, 40, 200, 40, 180, 40,
  )
  ([pl_cmb(own_p, [own_move])], [pl_cmb(opp_p, [fp_tackle()])])
}

///|
test "select DP/MC parity: Flying Press vs Grass beats plain Fighting" {
  let turn_limit = 3
  let (own_fp, opp) = fp_pair("かくとう", "くさ", "", fp_press())
  let (own_fight, _opp_fight) = fp_pair(
    "かくとう",
    "くさ",
    "",
    fp_fight(),
  )
  let dp_fp = fp_dp(own_fp, opp, turn_limit)
  let dp_fight = fp_dp(own_fight, opp, turn_limit)
  assert_true(dp_fp > dp_fight)
  let mc_fp = team_monte_carlo_value(own_fp, opp, 64, 56001UL, turn_limit~)
  let diff = (dp_fp - mc_fp).abs()
  assert_true(diff < 0.15)
}

///|
test "select DP/MC parity: plain Fighting beats Flying Press vs Steel/Rock" {
  let turn_limit = 3
  let (own_fp, opp) = fp_pair("かくとう", "はがね", "いわ", fp_press())
  let (own_fight, _opp_fight) = fp_pair(
    "かくとう",
    "はがね",
    "いわ",
    fp_fight(),
  )
  let dp_fp = fp_dp(own_fp, opp, turn_limit)
  let dp_fight = fp_dp(own_fight, opp, turn_limit)
  assert_true(dp_fight > dp_fp)
  let mc_fp = team_monte_carlo_value(own_fp, opp, 64, 56002UL, turn_limit~)
  let diff = (dp_fp - mc_fp).abs()
  assert_true(diff < 0.15)
}

///|
test "select DP/MC parity: Flying Press vs Ghost deals no damage" {
  let turn_limit = 3
  let (own_ghost, opp_ghost) = fp_pair(
    "かくとう",
    "ゴースト",
    "",
    fp_press(),
  )
  let (own_grass, opp_grass) = fp_pair("かくとう", "くさ", "", fp_press())
  let dp_ghost = fp_dp(own_ghost, opp_ghost, turn_limit)
  let dp_grass = fp_dp(own_grass, opp_grass, turn_limit)
  assert_true(dp_grass > dp_ghost)
  let mc_ghost = team_monte_carlo_value(
    own_ghost,
    opp_ghost,
    64,
    56003UL,
    turn_limit~,
  )
  let diff = (dp_ghost - mc_ghost).abs()
  assert_true(diff < 0.15)
}
