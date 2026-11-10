///|
/// そうしょく (Sap Sipper) の MC 経路テストと DP / MC parity。
///
/// MC は `team_apply_post_hit` (吸収時は防御側 A +1 のみ)、`mc_try_apply_status`
/// (状態異常を付与しない)、`mc_attempt_accuracy` (命中 100) で、DP の
/// `with_absorb_effects` / `attempt_accuracy` と同じ判定をする。
///
/// parity fixture は乱数が入らない matchup にする: own の くさ技 は必ず吸収され、
/// 相手 (そうしょく) は はねる しか使わない。damage roll が 1 本も入らないので、DP の
/// 期待値と MC の単一 rollout が一致する (horizon 2 / 3 とも)。
/// 感度ガード: 相手が そうしょく でない (plain) と own の技が当たるので、DP の値が変わる。

///|
fn sapmc_leaf_blade() -> @model.Move {
  mk_move("リーフブレード", "くさ", @model.Physical, 90)
}

///|
fn sapmc_splash() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
/// own の攻撃役。素早さ 100 で相手 (60) より先に動く。
fn sapmc_attacker() -> Combatant {
  let p = mk_pokemon("SapAtk", "くさ", "", 260, 130, 100, 60, 100, 100)
  pl_cmb(p, [sapmc_leaf_blade()])
}

///|
/// 相手。はねる しか使わないので、ダメージを与えず攻撃役の技の影響だけを受ける。
fn sapmc_holder(ability : String) -> Combatant {
  let p = mk_pokemon("SapHolder", "ノーマル", "", 260, 60, 100, 60, 100, 60)
  pl_cmb(p, [sapmc_splash()], ability=ability)
}

///|
fn sapmc_dp(
  own : Array[Combatant],
  opp : Array[Combatant],
  turn_limit : Int,
) -> Double {
  switching_game_winrate(own, opp, turn_limit)
}

///|
fn sapmc_mc(
  own : Array[Combatant],
  opp : Array[Combatant],
  turn_limit : Int,
  seed : UInt64,
) -> Double {
  let rng = seeded_rng(seed)
  team_rollout(own, opp, rng, turn_limit~, epsilon=0.0)
}

///|
/// **Case 1 (MC の post-hit 吸収)**: 吸収された くさ技 (反動つき) は、反動も HP
/// 変化も起こさず、防御側の A のみ +1 する。
test "MC: 吸収された くさ技は反動も HP 変化もなく、防御側の A が +1" {
  let wood = mk_move(
    "ウッドハンマー",
    "くさ",
    @model.Physical,
    120,
    recoil_num=1,
    recoil_den=3,
  )
  let attacker_hps = [100]
  let defender_hps = [100]
  let defender_ranks = [0, 0, 0, 0, 0]
  team_apply_post_hit(
    attacker_hps,
    0,
    [0, 0, 0, 0, 0],
    [false],
    [@model.None],
    [-1],
    [sapmc_attacker()],
    defender_hps,
    0,
    defender_ranks,
    [false],
    [sapmc_holder("そうしょく")],
    [false],
    [@model.Weather::None],
    [0],
    [@model.Field::None],
    [0],
    wood,
    60,
  )
  @debug.assert_eq(attacker_hps[0], 100)
  @debug.assert_eq(defender_hps[0], 100)
  @debug.assert_eq(defender_ranks[0], 1)
}

///|
/// **Case 2 (対照: 非吸収の反動)**: 相手が そうしょく でなければ、同じ技は反動を受け、
/// 防御側の A は変わらない。経路が壊れていないことの対照。
test "MC: 対照 (非吸収) は反動を受け防御側の A は変わらない" {
  let wood = mk_move(
    "ウッドハンマー",
    "くさ",
    @model.Physical,
    120,
    recoil_num=1,
    recoil_den=3,
  )
  let attacker_hps = [100]
  let defender_ranks = [0, 0, 0, 0, 0]
  team_apply_post_hit(
    attacker_hps,
    0,
    [0, 0, 0, 0, 0],
    [false],
    [@model.None],
    [-1],
    [sapmc_attacker()],
    [100],
    0,
    defender_ranks,
    [false],
    [sapmc_holder("")],
    [false],
    [@model.Weather::None],
    [0],
    [@model.Field::None],
    [0],
    wood,
    60,
  )
  @debug.assert_eq(attacker_hps[0], 80)
  @debug.assert_eq(defender_ranks[0], 0)
}

///|
/// **Case 3 (MC の状態付与)**: 吸収された ねむりごな は眠らせない (チャンス 100%
/// でも)。対照の非吸収相手は眠る。
test "MC: 吸収された状態技は状態異常を付与せず、対照の相手には付与する" {
  let spore = mk_move(
    "ねむりごな",
    "くさ",
    @model.Status,
    0,
    accuracy=75,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let rng = seeded_rng(7UL)
  let absorbed_status : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(
    rng,
    spore,
    [sapmc_holder("そうしょく")],
    [100],
    absorbed_status,
    0,
  )
  @debug.assert_eq(absorbed_status[0], @model.None)
  let plain_status : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(rng, spore, [sapmc_holder("")], [100], plain_status, 0)
  assert_true(plain_status[0] != @model.None)
}

///|
/// **Case 4 (MC の命中)**: 吸収対象は命中 100 として扱う。通常の相手では技の命中率。
test "MC: mc_attempt_accuracy は吸収時 100、それ以外は技の命中率" {
  let spore = mk_move(
    "ねむりごな",
    "くさ",
    @model.Status,
    0,
    accuracy=75,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let atk = sapmc_attacker()
  @debug.assert_eq(
    mc_attempt_accuracy(atk, spore, sapmc_holder("そうしょく"), @model.Weather::None),
    100,
  )
  @debug.assert_eq(
    mc_attempt_accuracy(atk, spore, sapmc_holder(""), @model.Weather::None),
    75,
  )
}

///|
/// **Case 5 (DP / MC parity)**: 吸収が起きる matchup で、DP の期待値と MC の単一
/// rollout が一致する (horizon 2 と 3)。乱数が入らないので許容誤差は小さい。
/// 感度ガード: 相手が そうしょく でなければ DP の値は変わる (own の技が当たる)。
test "select DP/MC parity: Sap Sipper absorbs own Leaf Blade (no damage roll)" {
  let own = [sapmc_attacker()]
  let opp_sap = [sapmc_holder("そうしょく")]
  let opp_plain = [sapmc_holder("")]
  let dp_sap_2 = sapmc_dp(own, opp_sap, 2)
  let mc_sap_2 = sapmc_mc(own, opp_sap, 2, 74007UL)
  assert_true((dp_sap_2 - mc_sap_2).abs() < 0.001)
  let dp_sap_3 = sapmc_dp(own, opp_sap, 3)
  let mc_sap_3 = sapmc_mc(own, opp_sap, 3, 74007UL)
  assert_true((dp_sap_3 - mc_sap_3).abs() < 0.001)
  let dp_plain = sapmc_dp(own, opp_plain, 2)
  assert_true(dp_plain - dp_sap_2 > 0.03)
}
