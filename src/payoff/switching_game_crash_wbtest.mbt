///|
/// 崩れ技 (Showdown `hasCrashDamage` + `onMoveFail`) の使用者 HP 消費 (DP)。
///
/// 外れ leg は attempt 段 (`attempt_turn_with_cache` → `crash_miss_outcomes`)、免疫 leg は
/// `apply_damage_variants_fanout` の hits_count=0 で処理される。最大 HP は `actual_stats`
/// で 200 に固定し、消費量 100 (= 200/2) を直接確認する。各ケースに対照 (非崩れ技 / 命中 /
/// マジックガード) を置く。
/// helper: `mk_move` (test_helpers_test)、`im_pokemon` / `im_combatant` / `im_state`
/// (switching_game_intimidate_wbtest)。

///|
fn crash_hjk() -> @model.Move {
  mk_move("とびひざげり", "かくとう", @model.Physical, 130, accuracy=90)
}

///|
fn crash_hjk_never_hits() -> @model.Move {
  mk_move("とびひざげり", "かくとう", @model.Physical, 130, accuracy=0)
}

///|
fn crash_tackle() -> @model.Move {
  mk_move("たいあたり", "ノーマル", @model.Physical, 60)
}

///|
fn crash_tackle_never_hits() -> @model.Move {
  mk_move("たいあたり", "ノーマル", @model.Physical, 60, accuracy=0)
}

///|
/// 反動 1/3 の たいあたり (相手の行動順の検証用: 使用者の崩れ後の HP で反動が変わる)。
fn crash_tackle_recoil() -> @model.Move {
  mk_move("たいあたり", "ノーマル", @model.Physical, 60, recoil_num=1, recoil_den=3)
}

///|
fn crash_splash() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
/// 100% 眠り技 (ねむりごな 命中 100 の固定版)。
fn crash_spore() -> @model.Move {
  mk_move(
    "ねむりごな",
    "くさ",
    @model.Status,
    0,
    status_effect=Some((@model.SleepKind, 100)),
  )
}

///|
/// 最大 HP を `max_hp` に固定した Combatant (`actual_stats` の HP 成分)。
fn crash_mon(
  name : String,
  moves : Array[@model.Move],
  max_hp : Int,
  type1? : String = "ノーマル",
  spe? : Int = 100,
  ability? : String = "",
) -> Combatant {
  let base = im_pokemon(name, spe=spe)
  let p = { ..base, type1 }
  let c = im_combatant(p, moves, ability=ability)
  { ..c, actual_stats: Some([max_hp, 100, 100, 100, 100, spe]) }
}

///|
/// 1 本の命中 leg を DP の本物の経路で解決する (`compute_damage_variants` → fanout)。
/// 自分の HP は `my_hp`、相手の HP は 200。
fn crash_leg(
  own : Combatant,
  opp : Combatant,
  mv : @model.Move,
  my_hp : Int,
) -> Array[(Double, SwitchingGameState)] {
  let outcomes = compute_damage_variants(own, opp, mv, 0, 0)
  apply_damage_variants_fanout(
    im_state(my_hps=[my_hp], opp_hps=[200]),
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[own],
    defender_team=[opp],
    pre_dmg_defender_hp=200,
  )
}

///|
/// 1 ターン (attempt 段 → 解決) を DP の本物の経路で解決する。両者とも先頭の技を使う。
fn crash_turn(
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  my_hp : Int,
) -> Array[(Double, SwitchingGameState)] {
  let state = im_state(my_hps=[my_hp], opp_hps=[200])
  attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
}

///|
/// 述語を満たす leaf の確率和。
fn crash_mass(
  outs : Array[(Double, SwitchingGameState)],
  pred : (SwitchingGameState) -> Bool,
) -> Double {
  let mut total = 0.0
  for o in outs {
    if pred(o.1) {
      total = total + o.0
    }
  }
  total
}

///|
/// 相手 HP の期待値 (leaf の確率加重平均)。
fn crash_expected_opp_hp(outs : Array[(Double, SwitchingGameState)]) -> Double {
  let mut total = 0.0
  for o in outs {
    total = total + o.0 * o.1.opp_hps[0].to_double()
  }
  total
}

///|
/// **Case 1 (免疫 leg)**: とびひざげり がゴーストに無効なら使用者は最大 HP の 1/2 (200 → 100)
/// を失う。相手 HP は動かない (Showdown `onMoveFail`: 技は当たらず、崩れだけが起きる)。
test "crash DP: とびひざげりがゴーストに無効なら使用者は最大HPの1/2を失う" {
  let own = crash_mon("CrashOwn", [crash_hjk()], 200)
  let opp = crash_mon("CrashGhost", [crash_tackle()], 200, type1="ゴースト")
  let outs = crash_leg(own, opp, crash_hjk(), 200)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.my_hps[0], 100)
  @debug.assert_eq(outs[0].1.opp_hps[0], 200)
}

///|
/// **Case 1b (免疫 leg の崩れ KO)**: 残り HP が崩れ量 (100) 以下なら使用者は ひんし になる。
test "crash DP: 免疫の崩れで使用者の HP が崩れ量以下なら ひんし になる" {
  let own = crash_mon("CrashOwn", [crash_hjk()], 200)
  let opp = crash_mon("CrashGhost", [crash_tackle()], 200, type1="ゴースト")
  let outs = crash_leg(own, opp, crash_hjk(), 80)
  @debug.assert_eq(outs[0].1.my_hps[0], 0)
}

///|
/// **Case 2 (マジックガード)**: 使用者がマジックガードなら、免疫の崩れでも HP は減らない。
test "crash DP: マジックガードの使用者は免疫のとびひざげりで HP を失わない" {
  let own = crash_mon("CrashOwn", [crash_hjk()], 200, ability="マジックガード")
  let opp = crash_mon("CrashGhost", [crash_tackle()], 200, type1="ゴースト")
  let outs = crash_leg(own, opp, crash_hjk(), 200)
  @debug.assert_eq(outs[0].1.my_hps[0], 200)
}

///|
/// **Case 3 (対照: 非崩れ技の免疫)**: たいあたり がゴーストに無効でも使用者 HP は減らない。
test "crash DP 対照: 非崩れ技の免疫では使用者 HP は減らない" {
  let own = crash_mon("CrashOwn", [crash_tackle()], 200)
  let opp = crash_mon("CrashGhost", [crash_tackle()], 200, type1="ゴースト")
  let outs = crash_leg(own, opp, crash_tackle(), 200)
  @debug.assert_eq(outs[0].1.my_hps[0], 200)
}

///|
/// **Case 4 (命中: 崩れは起きない)**: とびひざげり がノーマルに当たれば使用者 HP は減らず、
/// 相手 HP が減る (全 leaf で使用者 HP = 200)。
test "crash DP: とびひざげりが命中すれば使用者 HP は減らない" {
  let own = crash_mon("CrashOwn", [crash_hjk()], 200)
  let opp = crash_mon("CrashNormal", [crash_tackle()], 200)
  let outs = crash_leg(own, opp, crash_hjk(), 200)
  @debug.assert_eq(crash_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0)
  assert_true(crash_mass(outs, fn(s) { s.opp_hps[0] < 200 }) > 0.99)
}

///|
/// **Case 5 (外れ: attempt 段)**: とびひざげり (命中 90) の外れ確率 0.1 の枝だけ使用者 HP が
/// 100 になる。命中の枝 (0.9) は使用者 HP 200 のまま。相手 はねる は HP に影響しない。
test "crash DP: とびひざげり (命中90) の外れ枝 (0.1) で使用者は 100 になる" {
  let own = crash_mon("CrashOwn", [crash_hjk()], 200)
  let opp = crash_mon("CrashOpp", [crash_splash()], 200)
  let outs = crash_turn([own], [opp], 200)
  let p_loss = crash_mass(outs, fn(s) { s.my_hps[0] == 100 })
  let p_full = crash_mass(outs, fn(s) { s.my_hps[0] == 200 })
  assert_true((p_loss - 0.1).abs() < 0.000000001)
  assert_true((p_full - 0.9).abs() < 0.000000001)
}

///|
/// **Case 6 (対照: 非崩れ技の外れ)**: たいあたり (命中 90) の外れでは使用者 HP は減らない。
test "crash DP 対照: 非崩れ技の外れでは使用者 HP は減らない" {
  let own = crash_mon("CrashOwn", [crash_tackle()], 200)
  let opp = crash_mon("CrashOpp", [crash_splash()], 200)
  let outs = crash_turn([own], [opp], 200)
  @debug.assert_eq(crash_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0)
}

///|
/// **Case 7 (マジックガードの外れ)**: マジックガードの使用者は外れても HP は減らない。
test "crash DP: マジックガードの使用者は外れたとびひざげりで HP を失わない" {
  let own = crash_mon("CrashOwn", [crash_hjk_never_hits()], 200, ability="マジックガード")
  let opp = crash_mon("CrashOpp", [crash_splash()], 200)
  let outs = crash_turn([own], [opp], 200)
  @debug.assert_eq(crash_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0)
}

///|
/// **Case 8 (外れの崩れ KO)**: 残り HP が崩れ量以下の使用者が外すと ひんし になる (確率 1)。
test "crash DP: 外れたとびひざげりで使用者の HP が崩れ量以下なら ひんし になる" {
  let own = crash_mon("CrashOwn", [crash_hjk_never_hits()], 200)
  let opp = crash_mon("CrashOpp", [crash_splash()], 200)
  let outs = crash_turn([own], [opp], 80)
  @debug.assert_eq(crash_mass(outs, fn(s) { s.my_hps[0] == 0 }), 1.0)
}

///|
/// **Case 9 (両者が外れる)**: 両方が崩れ技を外すと、両方とも最大 HP の 1/2 を失う (1 leaf)。
test "crash DP: 両者がとびひざげりを外すと両者とも 1/2 を失う" {
  let own = crash_mon("CrashOwn", [crash_hjk_never_hits()], 200)
  let opp = crash_mon("CrashOpp", [crash_hjk_never_hits()], 200)
  let outs = crash_turn([own], [opp], 200)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.my_hps[0], 100)
  @debug.assert_eq(outs[0].1.opp_hps[0], 100)
}

///|
/// **Case 10 (行動順: 崩れの位置)**: 使用者 HP 120、崩れ量 100。
///   - 使用者が速い: 崩れが先 (HP 120 → 20)。相手 たいあたり の与ダメは 20 で頭打ちになり、
///     反動 (1/3) は 20 の分だけ (約 6) 相手に入る。
///   - 使用者が遅い: 相手が先。与ダメは 120 で頭打ちにならず (約 39)、反動は約 13。
/// よって相手の期待 HP は速い側の方が高い (約 194 > 約 187)。反動の式で行動順を検出する。
test "crash DP: 外れた崩れは使用者が速ければ相手の行動より先に起きる (反動で検出)" {
  let fast = crash_mon("CrashFast", [crash_hjk_never_hits()], 200, spe=150)
  let slow_opp = crash_mon("CrashSlowOpp", [crash_tackle_recoil()], 200, spe=50)
  let outs_fast = crash_turn([fast], [slow_opp], 120)
  let slow = crash_mon("CrashSlow", [crash_hjk_never_hits()], 200, spe=50)
  let fast_opp = crash_mon("CrashFastOpp", [crash_tackle_recoil()], 200, spe=150)
  let outs_slow = crash_turn([slow], [fast_opp], 120)
  // 感度: 行動順が変わると反動が変わり、期待相手 HP に差が出る (> 1)。
  assert_true((crash_expected_opp_hp(outs_fast) - crash_expected_opp_hp(outs_slow)).abs() > 1.0)
  assert_true(crash_expected_opp_hp(outs_fast) > crash_expected_opp_hp(outs_slow))
}

///|
/// **Case 11 (睡眠で崩れが起きない)**: 遅い使用者は、先に行動した相手の ねむりごな で眠ると
/// 行動できず崩れも起きない (`action_blocked_by_fresh_status`)。使用者 HP は 200 のまま。
test "crash DP: 遅い使用者は先の相手の眠り技で眠らされると崩れない" {
  let slow = crash_mon("CrashSlow", [crash_hjk_never_hits()], 200, spe=50)
  let fast_opp = crash_mon("CrashFastSpore", [crash_spore()], 200, spe=150)
  let outs = crash_turn([slow], [fast_opp], 200)
  @debug.assert_eq(crash_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0)
}

///|
/// **Case 11b (対照: 速い使用者は眠りより先に崩れる)**: 速い使用者は眠り技より先に行動するので、
/// 崩れ (200 → 100) が起きる。
test "crash DP 対照: 速い使用者は相手の眠り技より先に崩れる" {
  let fast = crash_mon("CrashFast", [crash_hjk_never_hits()], 200, spe=150)
  let slow_opp = crash_mon("CrashSlowSpore", [crash_spore()], 200, spe=50)
  let outs = crash_turn([fast], [slow_opp], 200)
  @debug.assert_eq(crash_mass(outs, fn(s) { s.my_hps[0] == 100 }), 1.0)
}

///|
/// **Case 12 (同速の tie)**: 同速は両順序の平均 (0.5 / 0.5)。確率質量は失われない。
test "crash DP: 同速の崩れ外しは両順序を平均し確率質量を保つ" {
  let own = crash_mon("CrashOwn", [crash_hjk_never_hits()], 200, spe=100)
  let opp = crash_mon("CrashOpp", [crash_tackle_recoil()], 200, spe=100)
  let outs = crash_turn([own], [opp], 200)
  assert_true((crash_mass(outs, fn(_s) { true }) - 1.0).abs() < 0.000000001)
}
