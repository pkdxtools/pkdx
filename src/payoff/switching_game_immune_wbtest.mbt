///|
/// タイプ / 特性で無効な技 (DP の immune leg) の自己効果テスト。
///
/// Showdown では `hitStepTypeImmunity` / `TryHit` が対象を外すため `spreadMoveHit` に届かず、
/// 自己ダウン・反動・回復・自己 recharge・相手ダウン・状態異常・接触 proc は起きない
/// (battle-actions.ts:705-727, 1080-1192)。残るのは selfdestruct: 'always' (じばく系は
/// useMove が対象判定より前に使用者を ひんし にする: battle-actions.ts:564-566) と Protean
/// の記録 (PrepareHit は TryHit より前: battle-actions.ts:652-654)。
///
/// 各ケースに非免疫の対照 (同じ技が当たる) を置き、経路が壊れていないことを確認する。
/// helper: `mk_move` (switching_game_status_wbtest)、`im_pokemon` / `im_combatant` /
/// `im_state` / `im_tackle` (switching_game_intimidate_wbtest)、`sap_leaf_blade` /
/// `sap_spore` (switching_game_sap_sipper_wbtest)。

///|
fn imm_close_combat() -> @model.Move {
  mk_move("インファイト", "かくとう", @model.Physical, 120, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 3, delta: -1, target: 0 },
  ])
}

///|
fn imm_defender(
  type1 : String,
  ability? : String = "",
  item? : String = "",
) -> Combatant {
  let p = { ..im_pokemon("Defender"), type1, }
  let c = im_combatant(p, [im_tackle()], ability=ability)
  { ..c, item, }
}

///|
fn imm_attacker(mv : @model.Move, ability? : String = "") -> Combatant {
  im_combatant(im_pokemon("Attacker"), [mv], ability=ability)
}

///|
/// 1 本の leg を DP の本物の経路で解決する。`compute_damage_variants` で outcome
/// (免疫なら hits_count=0 の sentinel) を作り、攻撃 leg の fanout に通す。
fn imm_leaves(
  own : Combatant,
  opp : Combatant,
  mv : @model.Move,
) -> Array[(Double, SwitchingGameState)] {
  let outcomes = compute_damage_variants(own, opp, mv, 0, 0)
  apply_damage_variants_fanout(
    im_state(),
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[own],
    defender_team=[opp],
    pre_dmg_defender_hp=100,
  )
}

///|
fn imm_one(
  own : Combatant,
  opp : Combatant,
  mv : @model.Move,
) -> SwitchingGameState {
  let outs = imm_leaves(own, opp, mv)
  if outs.length() != 1 {
    abort("imm_one: expected a single leaf")
  }
  outs[0].1
}

///|
/// **Case 1 (インファイトのゴースト無効)**: 自己の B -1 / D -1 は起きない。HP も動かない。
test "immune: インファイトがゴーストに無効なら自己ダウンは起きない" {
  let mv = imm_close_combat()
  let s = imm_one(imm_attacker(mv), imm_defender("ゴースト"), mv)
  @debug.assert_eq(s.my_ranks[1], 0)
  @debug.assert_eq(s.my_ranks[3], 0)
  @debug.assert_eq(s.opp_hps[0], 100)
  @debug.assert_eq(s.my_hps[0], 100)
}

///|
/// **Case 2 (対照: 非免疫)**: 同じインファイトがノーマルに当たれば自己ダウンは従来どおり入る。
test "immune 対照: インファイトが非免疫なら自己 B-1 / D-1 が入る" {
  let mv = imm_close_combat()
  let s = imm_one(imm_attacker(mv), imm_defender("ノーマル"), mv)
  @debug.assert_eq(s.my_ranks[1], -1)
  @debug.assert_eq(s.my_ranks[3], -1)
  assert_true(s.opp_hps[0] < 100)
}

///|
/// **Case 3 (りゅうせいぐんのフェアリー無効)**: 自己の C -2 は起きない (ドラゴン技は
/// フェアリーに無効、Showdown は TypeImmunity で対象を外す)。
test "immune: りゅうせいぐんがフェアリーに無効なら自己 C-2 は起きない" {
  let mv = mk_move("りゅうせいぐん", "ドラゴン", @model.Special, 130, stat_effects=[
    @model.StatEffect::{ stat: 2, delta: -2, target: 0 },
  ])
  let s = imm_one(imm_attacker(mv), imm_defender("フェアリー"), mv)
  @debug.assert_eq(s.my_ranks[2], 0)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
/// **Case 3b (対照)**: 同じ りゅうせいぐん がノーマルに当たれば自己 C -2 が入る。
test "immune 対照: りゅうせいぐんが非免疫なら自己 C-2 が入る" {
  let mv = mk_move("りゅうせいぐん", "ドラゴン", @model.Special, 130, stat_effects=[
    @model.StatEffect::{ stat: 2, delta: -2, target: 0 },
  ])
  let s = imm_one(imm_attacker(mv), imm_defender("ノーマル"), mv)
  @debug.assert_eq(s.my_ranks[2], -2)
}

///|
/// **Case 4 (じばく系の免疫)**: だいばくはつ は免疫でも使用者が ひんし になる
/// (selfdestruct: 'always', battle-actions.ts:564-566)。相手 HP は動かない。
test "immune: だいばくはつはゴーストに無効でも使用者が ひんし になる" {
  let mv = mk_move("だいばくはつ", "ノーマル", @model.Physical, 250, self_ko=true)
  let s = imm_one(imm_attacker(mv), imm_defender("ゴースト"), mv)
  @debug.assert_eq(s.my_hps[0], 0)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
/// **Case 4b (対照)**: 非免疫なら だいばくはつ は相手にも当たり、使用者も ひんし になる。
test "immune 対照: だいばくはつは非免疫でも使用者が ひんし になり相手も減る" {
  let mv = mk_move("だいばくはつ", "ノーマル", @model.Physical, 250, self_ko=true)
  let s = imm_one(imm_attacker(mv), imm_defender("ノーマル"), mv)
  @debug.assert_eq(s.my_hps[0], 0)
  assert_true(s.opp_hps[0] < 100)
}

///|
/// **Case 5 (はかいこうせんの免疫)**: 自己 mustrecharge (selfDrops 内) は立たない。
test "immune: はかいこうせんがゴーストに無効なら反動の recharge は立たない" {
  let mv = mk_move("はかいこうせん", "ノーマル", @model.Special, 150, recharge=true)
  let s = imm_one(imm_attacker(mv), imm_defender("ゴースト"), mv)
  @debug.assert_eq(s.my_must_recharge[0], false)
  @debug.assert_eq(s.my_hps[0], 100)
}

///|
/// **Case 5b (対照)**: 非免疫なら はかいこうせん は recharge を立てる。
test "immune 対照: はかいこうせんが非免疫なら recharge が立つ" {
  let mv = mk_move("はかいこうせん", "ノーマル", @model.Special, 150, recharge=true)
  let s = imm_one(imm_attacker(mv), imm_defender("ノーマル"), mv)
  @debug.assert_eq(s.my_must_recharge[0], true)
}

///|
/// **Case 6 (反動の免疫)**: 反動技 (反動 1/3) は免疫なら使用者 HP が減らない
/// (hitStepMoveHitLoop の applyRecoilDamage は対象が残る時だけ)。
test "immune: 反動技はゴーストに無効なら反動を受けない" {
  let mv = mk_move("すてみタックル", "ノーマル", @model.Physical, 120, recoil_num=1, recoil_den=3)
  let s = imm_one(imm_attacker(mv), imm_defender("ゴースト"), mv)
  @debug.assert_eq(s.my_hps[0], 100)
}

///|
/// **Case 6b (対照)**: 非免疫なら反動を受ける。
test "immune 対照: 反動技は非免疫なら反動を受ける" {
  let mv = mk_move("すてみタックル", "ノーマル", @model.Physical, 120, recoil_num=1, recoil_den=3)
  let s = imm_one(imm_attacker(mv), imm_defender("ノーマル"), mv)
  assert_true(s.my_hps[0] < 100)
}

///|
/// **Case 7 (Protean の記録)**: へんげんじざい は無効な技でも使用時にタイプを記録する
/// (PrepareHit は TryHit より前)。自己ダウンは起きない。
test "immune: へんげんじざいは無効な技でもタイプを記録し自己ダウンは起きない" {
  let mv = imm_close_combat()
  let s = imm_one(imm_attacker(mv, ability="へんげんじざい"), imm_defender("ゴースト"), mv)
  @debug.assert_eq(s.my_protean_locked[0], "かくとう")
  @debug.assert_eq(s.my_ranks[1], 0)
}

///|
/// **Case 8 (もらいびの免疫)**: オーバーヒート は もらいび (ほのお無効) の holder に無効なので
/// 自己 SpA -2 は起きない。engine の check_def_immunity (ability) 経由の免疫。
test "immune: オーバーヒートはもらいびの holder に無効なら自己 SpA-2 は起きない" {
  let mv = mk_move("オーバーヒート", "ほのお", @model.Special, 130, stat_effects=[
    @model.StatEffect::{ stat: 2, delta: -2, target: 0 },
  ])
  let s = imm_one(imm_attacker(mv), imm_defender("ノーマル", ability="もらいび"), mv)
  @debug.assert_eq(s.my_ranks[2], 0)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
/// **Case 9 (状態異常 fanout の免疫)**: 免疫 leg は付与される状態異常も止める。
/// 対照 (非免疫) では同じ技が状態異常を付与する。
test "immune: 免疫 leg は状態異常を付与しない (対照: 非免疫は付与する)" {
  let mv = mk_move("テスト技", "ノーマル", @model.Physical, 80, status_effect=Some((@model.BurnKind, 100)))
  let immune_s = imm_one(imm_attacker(mv), imm_defender("ゴースト"), mv)
  @debug.assert_eq(immune_s.opp_status[0], @model.None)
  let plain_s = imm_one(imm_attacker(mv), imm_defender("ノーマル"), mv)
  assert_true(plain_s.opp_status[0] != @model.None)
}

///|
/// **Case 10 (そうしょく + しろいハーブ, 吸収)**: ゴーゴート (そうしょく, しろいハーブ) の
/// くさ技は吸収され A +1 のみ。負の段階がないのでハーブは消費されない。
test "そうしょく+しろいハーブ: 吸収された くさ技は A+1 だけで、ハーブは消費されない" {
  let leaf = sap_leaf_blade()
  let s1 = apply_damage_variants_fanout(
    im_state(),
    [{ probability: 1.0, mean_damage: 60, hits_count: 1, hit_steps: [] }],
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=leaf,
    attacker_team=[imm_attacker(leaf)],
    defender_team=[imm_defender("くさ", ability="そうしょく", item="しろいハーブ")],
    pre_dmg_defender_hp=100,
  )
  if s1.length() != 1 {
    abort("sap+herb step1: expected a single leaf")
  }
  let st = s1[0].1
  @debug.assert_eq(st.opp_ranks[0], 1)
  @debug.assert_eq(st.opp_item_consumed[0], false)
  @debug.assert_eq(st.opp_hps[0], 100)
}

///|
/// **Case 11 (吸収の後の A-2 で ハーブ消費)**: 吸収で A は +1。続く あまえる (A -2, 相手へ)
/// で A は -1 になり、しろいハーブ が消費されて A は 0 に戻る。
test "そうしょく+しろいハーブ: 吸収後の A-2 で A が負になり、ハーブが消費されて 0 に戻る" {
  let leaf = sap_leaf_blade()
  let charm = mk_move("あまえる", "フェアリー", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -2, target: 1 },
  ])
  let holder = imm_defender("くさ", ability="そうしょく", item="しろいハーブ")
  let s1 = apply_damage_variants_fanout(
    im_state(),
    [{ probability: 1.0, mean_damage: 60, hits_count: 1, hit_steps: [] }],
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=leaf,
    attacker_team=[imm_attacker(leaf)],
    defender_team=[holder],
    pre_dmg_defender_hp=100,
  )
  let s2 = apply_damage_variants_fanout(
    s1[0].1,
    [{ probability: 1.0, mean_damage: 0, hits_count: 1, hit_steps: [] }],
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=charm,
    attacker_team=[imm_attacker(charm)],
    defender_team=[holder],
    pre_dmg_defender_hp=100,
  )
  if s2.length() != 1 {
    abort("sap+herb step2: expected a single leaf")
  }
  let st = s2[0].1
  @debug.assert_eq(st.opp_ranks[0], 0)
  @debug.assert_eq(st.opp_item_consumed[0], true)
}
