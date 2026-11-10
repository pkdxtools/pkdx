///|
/// てっていこうせん の最大 HP 1/2 反動 (DP 側)。
///
/// 反動量は Showdown `Math.round(maxhp / 2)` (= (maxhp + 1) / 2)。発動条件:
/// - 命中: 実ダメージ > 0 (`apply_damage_variants_fanout` の dmg_for_effects)
/// - 免疫 (`hits_count = 0`): 対象生存時 (`with_immune_effects` の後段)
/// - 外れ: 対象生存時 (`attempt_with_miss_recoil`)
/// マジックガードは反動を無効化する。
///
/// 感度ガード: 同じ技・同じ状況で名前だけ別 (`テスト技`) にすると反動が消える。
/// helper: `im_state` / `im_combatant` / `im_pokemon` (switching_game_intimidate_wbtest)、
/// `mk_move` (switching_game_status_wbtest)、`compute_damage_variants` と
/// `apply_damage_variants_fanout` (switching_game_immune_wbtest と同じ経路)。

///|
/// 最大 HP を `actual_stats` で固定した使用者。`type1` で タイプを変えられる。
fn sbr_user(
  hp : Int,
  ability? : String = "",
  type1? : String = "はがね",
  name? : String = "てっていこうせん",
  spe? : Int = 100,
  moves? : Array[@model.Move] = [],
) -> Combatant {
  let mv = mk_move(name, "はがね", @model.Special, 140, accuracy=100)
  let mvs = if moves.length() == 0 { [mv] } else { moves }
  let p = { ..im_pokemon("SbUser", spe=spe), type1 }
  let c = im_combatant(p, mvs, ability=ability)
  { ..c, actual_stats: Some([hp, 100, 100, 100, 100, 100]) }
}

///|
/// 防御側 (HP 固定, 通常タイプ)。
fn sbr_defender(hp : Int, type1? : String = "ノーマル") -> Combatant {
  let p = { ..im_pokemon("SbDef"), type1 }
  let c = im_combatant(p, [im_tackle()])
  { ..c, actual_stats: Some([hp, 100, 100, 100, 100, 100]) }
}

///|
/// 命中 leg を DP の本物の経路で解決する (`im_leaves` と同じ手順)。
fn sbr_hit_leaves(
  own : Combatant,
  opp : Combatant,
  mv : @model.Move,
  my_hp : Int,
  opp_hp : Int,
) -> Array[(Double, SwitchingGameState)] {
  let outcomes = compute_damage_variants(own, opp, mv, 0, 0)
  apply_damage_variants_fanout(
    im_state(my_hps=[my_hp, 100, 100], opp_hps=[opp_hp, 100, 100]),
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[own],
    defender_team=[opp],
    pre_dmg_defender_hp=opp_hp,
  )
}

///|
/// 全 leaf の自分 HP が `expected` で、確率の合計が 1 であることを確認する。
fn sbr_assert_my_hp(
  leaves : Array[(Double, SwitchingGameState)],
  expected : Int,
) -> Unit raise {
  let mut total = 0.0
  for leaf in leaves {
    total = total + leaf.0
    @debug.assert_eq(leaf.1.my_hps[0], expected)
  }
  assert_true((total - 1.0).abs() < 0.000000001)
}

///|
/// 免疫 leg (hits_count = 0 の sentinel) を fanout に通す。Steel 技は pkdx の型相性と
/// 特性 (ふしぎなまもり 未実装) では無効化されないため、結果だけを手で組み立てる。
fn sbr_immune_leaves(
  own : Combatant,
  opp : Combatant,
  mv : @model.Move,
  my_hp : Int,
  opp_hp~ : Int,
) -> Array[(Double, SwitchingGameState)] {
  let outcomes : Array[@model.DamageOutcome] = [
    { probability: 1.0, mean_damage: 0, hits_count: 0, hit_steps: [] },
  ]
  apply_damage_variants_fanout(
    im_state(my_hps=[my_hp, 100, 100], opp_hps=[opp_hp, 100, 100]),
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[own],
    defender_team=[opp],
    pre_dmg_defender_hp=opp_hp,
  )
}

///|
/// 命中: 最大 HP 200 → 反動 100 (偶数の基本ケース)。
test "DP max-hp recoil: hit costs half of max HP (200 -> 100)" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let leaves = sbr_hit_leaves(
    sbr_user(200),
    sbr_defender(100),
    mv,
    200,
    100,
  )
  assert_true(leaves.length() > 0)
  sbr_assert_my_hp(leaves, 100)
}

///|
/// 奇数の最大 HP: Math.round(151/2) = 76 (切り上げ)。floor の 75 とは 1 だけ違う。
test "DP max-hp recoil: odd max HP rounds half up (151 -> 75, not 76)" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let leaves = sbr_hit_leaves(
    sbr_user(151),
    sbr_defender(100),
    mv,
    151,
    100,
  )
  sbr_assert_my_hp(leaves, 75)
}

///|
/// 奇数の最大 HP: Math.round(153/2) = 77 → 153 - 77 = 76。
test "DP max-hp recoil: odd max HP 153 loses 77" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let leaves = sbr_hit_leaves(
    sbr_user(153),
    sbr_defender(100),
    mv,
    153,
    100,
  )
  sbr_assert_my_hp(leaves, 76)
}

///|
/// 感度ガード: 同じ技を別名にすると反動は無い (HP 200 のまま)。
test "DP max-hp recoil: sensitivity guard (same move under another name has no recoil)" {
  let mv = mk_move("テスト技", "はがね", @model.Special, 140)
  let leaves = sbr_hit_leaves(
    sbr_user(200, name="テスト技"),
    sbr_defender(100),
    mv,
    200,
    100,
  )
  sbr_assert_my_hp(leaves, 200)
}

///|
/// マジックガード: 命中しても反動を受けない。
test "DP max-hp recoil: Magic Guard blocks the hit recoil" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let leaves = sbr_hit_leaves(
    sbr_user(200, ability="マジックガード"),
    sbr_defender(100),
    mv,
    200,
    100,
  )
  sbr_assert_my_hp(leaves, 200)
}

///|
/// 自己 KO: 現在 HP 50 (最大 151) で命中すると反動 76 で ひんし (HP 0)。
/// 相手は同時に倒れていなくても、使用者は倒れる。
test "DP max-hp recoil: user faints when the recoil exceeds its HP" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let leaves = sbr_hit_leaves(
    sbr_user(151),
    sbr_defender(100),
    mv,
    50,
    100,
  )
  sbr_assert_my_hp(leaves, 0)
}

///|
/// 対象が既に ひんし (pre_dmg 0) なら、命中 leg は発動しない (Showdown の `!target`)。
test "DP max-hp recoil: no recoil when the target is already fainted" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let outcomes = compute_damage_variants(sbr_user(200), sbr_defender(100), mv, 0, 0)
  let leaves = apply_damage_variants_fanout(
    im_state(my_hps=[200, 100, 100], opp_hps=[0, 100, 100]),
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[sbr_user(200)],
    defender_team=[sbr_defender(100)],
    pre_dmg_defender_hp=0,
  )
  sbr_assert_my_hp(leaves, 200)
}

///|
/// 免疫 (hits_count = 0): 対象生存なら MoveFail で反動を受ける (`sbr_immune_leaves`)。
test "DP max-hp recoil: immune (fail) still costs half of max HP when the target is alive" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let own = sbr_user(200)
  let opp = sbr_defender(100)
  let leaves = sbr_immune_leaves(own, opp, mv, 200, opp_hp=100)
  // 免疫なので相手 HP は動かず、自分だけ 100 失う。
  for leaf in leaves {
    @debug.assert_eq(leaf.1.opp_hps[0], 100)
    @debug.assert_eq(leaf.1.my_hps[0], 100)
  }
}

///|
/// 免疫 + マジックガード: 反動なし。
test "DP max-hp recoil: Magic Guard also blocks the fail-path recoil" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let own = sbr_user(200, ability="マジックガード")
  let leaves = sbr_immune_leaves(own, sbr_defender(100), mv, 200, opp_hp=100)
  sbr_assert_my_hp(leaves, 200)
}

///|
/// 発動順の検証 (`attempt_with_miss_recoil` を直接呼ぶ): 自分の てっていこうせん が
/// 外れ、相手は だいばくはつ (自爆) を使う。相手の自爆で相手が倒れる前に外れ反動が
/// 解決すれば、対象生存で反動が入る (自分 200 → 100)。相手が先に倒れれば反動なし。
test "DP max-hp recoil: miss leg resolves in speed order (me faster -> recoil, opp faster -> no target)" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let boom = mk_move("だいばくはつ", "ノーマル", @model.Physical, 250, self_ko=true)
  // 自分はゴースト (ノーマル技が効かない) なので相手の自爆は免疫 = 自分へのダメージ無し。
  let own_fast = [sbr_user(200, type1="ゴースト", spe=150, moves=[mv])]
  let own_slow = [sbr_user(200, type1="ゴースト", spe=50, moves=[mv])]
  let opp = [
    { ..im_combatant(im_pokemon("Boom", spe=100), [boom]), actual_stats: Some([100, 100, 100, 100, 100, 100]) },
  ]
  let ma : SideAttempt = {
    prob: 1.0,
    acts: false,
    action: UseMove(0),
    post_status: @model.None,
    missed: true,
  }
  let oa : SideAttempt = {
    prob: 1.0,
    acts: true,
    action: UseMove(0),
    post_status: @model.None,
    missed: false,
  }
  let pre = im_state(my_hps=[200, 100, 100], opp_hps=[100, 100, 100])
  // 自分が速い: 外れ反動 (対象 HP 100 > 0) → 自分 100、その後 相手が自爆。
  let fast = attempt_with_miss_recoil(pre, ma, oa, own_fast, opp, new_damage_cache())
  assert_true(fast.length() > 0)
  for leaf in fast {
    @debug.assert_eq(leaf.1.my_hps[0], 100)
    @debug.assert_eq(leaf.1.opp_hps[0], 0)
  }
  // 相手が速い: 相手が先に自爆 (対象 HP 0) → 自分の外れ反動は発動しない (200 のまま)。
  let slow = attempt_with_miss_recoil(pre, ma, oa, own_slow, opp, new_damage_cache())
  assert_true(slow.length() > 0)
  for leaf in slow {
    @debug.assert_eq(leaf.1.my_hps[0], 200)
    @debug.assert_eq(leaf.1.opp_hps[0], 0)
  }
}

///|
/// 外れ leg の確率: accuracy 50 の てっていこうせん と はねる の組合せで、
/// 外れ (50%) の leaf では相手 HP が動かず、自分だけ 100 失う。
test "DP max-hp recoil: accuracy miss branch costs recoil, hit branch also costs recoil" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140, accuracy=50)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let own = [{ ..sbr_user(200), moves: [mv] }]
  let opp = [{ ..sbr_defender(100), moves: [splash] }]
  let outs = attempt_turn_with_cache(
    im_state(my_hps=[200, 100, 100], opp_hps=[100, 100, 100]),
    UseMove(0),
    UseMove(0),
    own,
    opp,
    new_damage_cache(),
  )
  let mut total = 0.0
  let mut miss_mass = 0.0
  for leaf in outs {
    total = total + leaf.0
    // 命中しても外れても自分は 100 失う (命中時は相手にもダメージが入る)。
    @debug.assert_eq(leaf.1.my_hps[0], 100)
    if leaf.1.opp_hps[0] == 100 {
      miss_mass = miss_mass + leaf.0
    }
  }
  assert_true((total - 1.0).abs() < 0.000000001)
  assert_true((miss_mass - 0.5).abs() < 0.000000001)
}

///|
/// 感度ガード (外れ): 同じ確率構造で名前を変えると、外れ leaf の自分 HP は 200 のまま。
test "DP max-hp recoil: accuracy miss branch has no recoil under another name" {
  let mv = mk_move("テスト技", "はがね", @model.Special, 140, accuracy=50)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let own = [{ ..sbr_user(200, name="テスト技"), moves: [mv] }]
  let opp = [{ ..sbr_defender(100), moves: [splash] }]
  let outs = attempt_turn_with_cache(
    im_state(my_hps=[200, 100, 100], opp_hps=[100, 100, 100]),
    UseMove(0),
    UseMove(0),
    own,
    opp,
    new_damage_cache(),
  )
  for leaf in outs {
    @debug.assert_eq(leaf.1.my_hps[0], 200)
  }
}

///|
/// `SideAttempt.missed` は命中判定の外れだけ true。麻痺の不発 (prob 0.125) は false。
test "per_side_attempt: missed is set only for the accuracy miss, not for a paralysis skip" {
  let outs = per_side_attempt(@model.Paralyze, false, UseMove(0), 50)
  let skips = outs.filter(a => !a.acts && !a.missed)
  @debug.assert_eq(skips.length(), 1)
  assert_true((skips[0].prob - 0.125).abs() < 0.000000001)
  // 命中判定の外れ: (1 - 0.125) * 0.5 = 0.4375。
  let misses = outs.filter(a => !a.acts && a.missed)
  @debug.assert_eq(misses.length(), 1)
  assert_true((misses[0].prob - 0.4375).abs() < 0.000000001)
}
