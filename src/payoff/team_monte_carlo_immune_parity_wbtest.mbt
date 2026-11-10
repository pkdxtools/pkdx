///|
/// タイプ / 特性で無効な技 (MC の immune leg) のテストと DP / MC parity。
///
/// `team_perform_attack` は `calc_damage` の `is_immune` を 4 番目の戻り値で返し、
/// `team_apply_post_hit` (immune=true) は自己効果を止める。DP の `with_immune_effects`
/// と同じ判定 (例外: じばく系の使用者ひんし、Protean の記録は caller 側)。
///
/// parity fixture は乱数が入らない matchup にする: own の技は命中 100 で、免疫 leg は
/// ダメージ roll を使わず、相手は はねる しか使わない。DP の期待値と MC の平均が一致する。
/// 感度ガード: 相手が非免疫 (ノーマル) だと own の技が当たるので、DP の値が変わる。
/// helper: `mk_pokemon` / `pl_cmb` (team_monte_carlo_healing_wbtest / protean_parity)、
/// `seeded_rng` (monte_carlo)、`mk_move` (switching_game_status_wbtest)、
/// `sap_leaf_blade` (switching_game_sap_sipper_wbtest)。

///|
fn mci_close_combat() -> @model.Move {
  mk_move("インファイト", "かくとう", @model.Physical, 120, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 3, delta: -1, target: 0 },
  ])
}

///|
fn mci_splash() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
fn mci_own(mv : @model.Move, spe : Int) -> Combatant {
  pl_cmb(mk_pokemon("MciOwn", "かくとう", "", 260, 130, 100, 60, 100, spe), [mv])
}

///|
fn mci_opp(type1 : String) -> Combatant {
  pl_cmb(mk_pokemon("MciOpp", type1, "", 260, 60, 100, 60, 100, 60), [mci_splash()])
}

///|
/// 1 回の攻撃解決 (team_perform_attack → team_apply_post_hit) を行い、
/// 相手 HP / 自分の ranks / 自分の HP / immune を返す。
fn mci_attack(
  own : Combatant,
  opp : Combatant,
  mv : @model.Move,
) -> (Int, Array[Int], Int, Bool) {
  let own_hps = [100]
  let own_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let (res_hp, res_eff, _res_bust, res_immune) = team_perform_attack(
    own,
    opp,
    100,
    mv,
    seeded_rng(9UL),
    [0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0],
  )
  let opp_hps = [res_hp]
  team_apply_post_hit(
    own_hps,
    0,
    own_ranks,
    [false],
    [@model.None],
    [-1],
    [own],
    opp_hps,
    0,
    opp_ranks,
    [false],
    [opp],
    [false],
    [@model.Weather::None],
    [0],
    [@model.Field::None],
    [0],
    mv,
    res_eff,
    immune=res_immune,
  )
  (opp_hps[0], own_ranks, own_hps[0], res_immune)
}

///|
/// **Case 1 (インファイトのゴースト無効)**: team_perform_attack は immune を返し、
/// 自分の B / D は動かない。相手 HP も動かない。
test "MC immune: インファイトがゴーストに無効なら自己ダウンは起きない" {
  let (opp_hp, own_ranks, own_hp, immune) = mci_attack(
    mci_own(mci_close_combat(), 100),
    mci_opp("ゴースト"),
    mci_close_combat(),
  )
  assert_true(immune)
  @debug.assert_eq(opp_hp, 100)
  @debug.assert_eq(own_ranks[1], 0)
  @debug.assert_eq(own_ranks[3], 0)
  @debug.assert_eq(own_hp, 100)
}

///|
/// **Case 2 (対照: 非免疫)**: ノーマルに当たれば immune=false で、自己 B-1 / D-1 が入る。
test "MC immune 対照: インファイトが非免疫なら自己 B-1 / D-1 が入る" {
  let (opp_hp, own_ranks, _own_hp, immune) = mci_attack(
    mci_own(mci_close_combat(), 100),
    mci_opp("ノーマル"),
    mci_close_combat(),
  )
  assert_true(!immune)
  assert_true(opp_hp < 100)
  @debug.assert_eq(own_ranks[1], -1)
  @debug.assert_eq(own_ranks[3], -1)
}

///|
/// **Case 3 (じばく系の免疫)**: だいばくはつ は免疫でも使用者が ひんし になる (self_ko)。
test "MC immune: だいばくはつはゴーストに無効でも使用者が ひんし になる" {
  let boom = mk_move("だいばくはつ", "ノーマル", @model.Physical, 250, self_ko=true)
  let (opp_hp, _own_ranks, own_hp, immune) = mci_attack(
    mci_own(boom, 100),
    mci_opp("ゴースト"),
    boom,
  )
  assert_true(immune)
  @debug.assert_eq(own_hp, 0)
  @debug.assert_eq(opp_hp, 100)
}

///|
/// **Case 4 (反動の免疫)**: 反動技は免疫なら使用者 HP が減らない。対照 (非免疫) は減る。
test "MC immune: 反動技はゴーストに無効なら反動を受けず、非免疫なら受ける" {
  let edge = mk_move("すてみタックル", "ノーマル", @model.Physical, 120, recoil_num=1, recoil_den=3)
  let (_h1, _r1, own_hp_immune, immune) = mci_attack(
    mci_own(edge, 100),
    mci_opp("ゴースト"),
    edge,
  )
  assert_true(immune)
  @debug.assert_eq(own_hp_immune, 100)
  let (_h2, _r2, own_hp_plain, plain) = mci_attack(
    mci_own(edge, 100),
    mci_opp("ノーマル"),
    edge,
  )
  assert_true(!plain)
  assert_true(own_hp_plain < 100)
}

///|
/// **Case 5 (はかいこうせんの免疫)**: 免疫 leg は recharge を立てない。対照は立つ。
test "MC immune: はかいこうせんはゴーストに無効なら recharge は立たず、非免疫なら立つ" {
  let beam = mk_move("はかいこうせん", "ノーマル", @model.Special, 150, recharge=true)
  let own = mci_own(beam, 100)
  let opp = mci_opp("ゴースト")
  let (_res_hp, res_eff, _bust, immune) = team_perform_attack(
    own, opp, 100, beam, seeded_rng(9UL), [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
  )
  assert_true(immune)
  let must = [false]
  team_apply_post_hit(
    [100], 0, [0, 0, 0, 0, 0], must, [@model.None], [-1], [own],
    [100], 0, [0, 0, 0, 0, 0], [false], [opp], [false],
    [@model.Weather::None], [0], [@model.Field::None], [0], beam, res_eff,
    immune=immune,
  )
  @debug.assert_eq(must[0], false)
  let plain_opp = mci_opp("ノーマル")
  let (_r2, res_eff2, _b2, immune2) = team_perform_attack(
    own, plain_opp, 100, beam, seeded_rng(9UL), [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
  )
  assert_true(!immune2)
  let must2 = [false]
  team_apply_post_hit(
    [100], 0, [0, 0, 0, 0, 0], must2, [@model.None], [-1], [own],
    [100], 0, [0, 0, 0, 0, 0], [false], [plain_opp], [false],
    [@model.Weather::None], [0], [@model.Field::None], [0], beam, res_eff2,
  )
  @debug.assert_eq(must2[0], true)
}

///|
/// **Case 6 (そうしょく + しろいハーブ, MC)**: 吸収された くさ技は A +1 だけで、続けて
/// herb 判定を通してもハーブは消費されない (負の段階がない)。その後の あまえる (A -2) で
/// A が負になり、判定でハーブが消費されて A は 0 に戻る。
test "MC そうしょく+しろいハーブ: 吸収で A+1、ハーブは消費されず、A-2 でハーブが消費される" {
  let leaf = sap_leaf_blade()
  let charm = mk_move("あまえる", "フェアリー", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -2, target: 1 },
  ])
  let own = pl_cmb(mk_pokemon("MciLeaf", "くさ", "", 260, 130, 100, 60, 100, 100), [leaf, charm])
  let holder_base = pl_cmb(
    mk_pokemon("MciGoGoat", "くさ", "", 260, 60, 100, 60, 100, 60),
    [mci_splash()],
    ability="そうしょく",
  )
  let holder = { ..holder_base, item: "しろいハーブ" }
  let own_hps = [100]
  let own_ranks = [0, 0, 0, 0, 0]
  let own_consumed = [false]
  let holder_hps = [100]
  let holder_ranks = [0, 0, 0, 0, 0]
  let holder_consumed = [false]
  // 1 ターン目: くさ技は吸収される (team_perform_attack が immune=true)
  let (hp1, eff1, _b1, immune1) = team_perform_attack(
    own, holder, 100, leaf, seeded_rng(9UL), own_ranks, holder_ranks,
  )
  assert_true(immune1)
  holder_hps[0] = hp1
  team_apply_post_hit(
    own_hps, 0, own_ranks, [false], [@model.None], [-1], [own],
    holder_hps, 0, holder_ranks, [false], [holder], [false],
    [@model.Weather::None], [0], [@model.Field::None], [0],
    leaf, eff1, immune=immune1,
  )
  apply_held_item_stat_reset_pair(
    [own], 0, own_hps, own_ranks, own_consumed,
    [holder], 0, holder_hps, holder_ranks, holder_consumed,
  )
  @debug.assert_eq(holder_ranks[0], 1)
  @debug.assert_eq(holder_consumed[0], false)
  // 2 ターン目: あまえる (A -2) → A = -1 → 判定で ハーブ 消費、A は 0
  let (hp2, eff2, _b2, immune2) = team_perform_attack(
    own, holder, holder_hps[0], charm, seeded_rng(9UL), own_ranks, holder_ranks,
  )
  assert_true(!immune2)
  holder_hps[0] = hp2
  team_apply_post_hit(
    own_hps, 0, own_ranks, [false], [@model.None], [-1], [own],
    holder_hps, 0, holder_ranks, [false], [holder], [false],
    [@model.Weather::None], [0], [@model.Field::None], [0],
    charm, eff2, immune=immune2,
  )
  apply_held_item_stat_reset_pair(
    [own], 0, own_hps, own_ranks, own_consumed,
    [holder], 0, holder_hps, holder_ranks, holder_consumed,
  )
  @debug.assert_eq(holder_ranks[0], 0)
  @debug.assert_eq(holder_consumed[0], true)
}

///|
/// **Case 7 (DP / MC parity: 免疫)**: own の インファイト が ゴーストに無効。
/// 免疫 leg はダメージ roll を使わないので、DP の期待値と MC の平均が一致する。
test "select DP/MC parity: インファイトがゴーストに無効 (免疫 leg, 乱数なし)" {
  let own = [mci_own(mci_close_combat(), 200)]
  let opp = [mci_opp("ゴースト")]
  let dp = switching_game_winrate(own, opp, 2)
  let mc = team_monte_carlo_value(own, opp, 256, 74007UL, turn_limit=2)
  assert_true((dp - mc).abs() < 0.001)
  // 感度ガード: 非免疫 (ノーマル) だと own の技が当たり、DP の値が変わる。
  let opp_plain = [mci_opp("ノーマル")]
  let dp_plain = switching_game_winrate(own, opp_plain, 2)
  assert_true((dp_plain - dp).abs() > 0.03)
}
