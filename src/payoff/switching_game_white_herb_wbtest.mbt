///|
/// しろいハーブ (負のランクを全て 0 に戻して消費) の DP 配線。判定点は Showdown の
/// `whiteherb` に合わせて、登場 (いかく の直後)、技の効果の後 (両 active)、メガ直後、EOT。
///
/// 仕様 (Showdown 準拠):
///   - 負のランクが 1 つでもあれば全て 0 に戻し、持ち物は 1 戦闘 1 回だけ消費される。
///   - 相手ダウンが不発 (クリアボディ 等) なら負のランクは生じず、消費されない。
///   - まけんき / かちき は下がった後に反応し (`AfterEachBoost`)、その後に しろいハーブ が
///     判定する。反応で負でなくなった能力は消費を起こさず、負の能力だけが 0 に戻る。
///   - 消費は交代を跨いで持続する (`my_item_consumed` = P5 の per-slot フラグを流用)。
///
/// helper: `im_pokemon` / `im_combatant` / `im_state` / `im_tackle` (intimidate_wbtest)、
/// `mk_move` (status_wbtest)、`wh_holder` (held_item_stat_reset_wbtest)。

///|
/// 持ち物と特性を指定した 1 体 (`im_combatant` は item が空なので差し替える)。
fn wh_mon(
  name : String,
  moves : Array[@model.Move],
  ability : String,
  item : String,
  spe? : Int = 100,
) -> Combatant {
  let c = im_combatant(im_pokemon(name, spe=spe), moves, ability=ability)
  { ..c, item, }
}

///|
/// 3 体チーム。先頭 (lead) を差し替えて使う。控えは素の 1 体ずつ。
fn wh_team(lead : Combatant) -> Array[Combatant] {
  [
    lead,
    im_combatant(im_pokemon("Bench1"), [im_tackle()]),
    im_combatant(im_pokemon("Bench2"), [im_tackle()]),
  ]
}

///|
/// 何もしない変化技 (はねる)。相手の行動を無害にして、判定点だけを観測する。
fn wh_nop() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
/// 相手の なきごえ (A-1 / 相手ダウン)。
fn wh_growl() -> @model.Move {
  mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
}

///|
/// 分布の期待値: `slot` の HP を確率で重み付けした平均。
fn wh_expected_hp(
  outs : Array[(Double, SwitchingGameState)],
  slot : Int,
) -> Double {
  let mut e = 0.0
  for o in outs {
    e = e + o.0 * o.1.my_hps[slot].to_double()
  }
  e
}

///|
/// **Case 1 (なきごえ で消費)**: 相手の なきごえ (A-1) を受けた しろいハーブ 所持者は
/// A が 0 に戻り、消費される。対照として持ち物なしは A -1 のまま。
test "しろいハーブ: 相手のなきごえ (A-1) で A が 0 に戻り消費される" {
  let growl = wh_growl()
  let opp_team = wh_team(wh_mon("Growler", [growl], "", ""))
  let herb_team = wh_team(wh_mon("Herb", [wh_nop()], "", "しろいハーブ"))
  let s = with_post_hit_effects(im_state(), false, 0, 0, opp_team, herb_team, growl, 0)
  @debug.assert_eq(s.my_ranks, [0, 0, 0, 0, 0])
  @debug.assert_eq(s.my_item_consumed[0], true)
  // 対照: 持ち物なし (= 解除されない)
  let plain_team = wh_team(wh_mon("Plain", [wh_nop()], "", ""))
  let p = with_post_hit_effects(im_state(), false, 0, 0, opp_team, plain_team, growl, 0)
  @debug.assert_eq(p.my_ranks[0], -1)
  @debug.assert_eq(p.my_item_consumed[0], false)
}

///|
/// **Case 2 (自己ダウン)**: 技の使用者自身の負のランク (インファイト 型の B-1 / D-1) も
/// 技の直後に解除される。自己ダウンは まけんき / かちき の反応を起こさない。
test "しろいハーブ: 自己ダウン (B-1 / D-1) を撃った使用者も直後に解除される" {
  let brawl = mk_move("インファイト", "かくとう", @model.Physical, 120, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 3, delta: -1, target: 0 },
  ])
  let my_team = wh_team(wh_mon("Brawler", [brawl], "", "しろいハーブ"))
  let opp_team = wh_team(wh_mon("Dummy", [wh_nop()], "", ""))
  let s = with_post_hit_effects(im_state(), true, 0, 0, my_team, opp_team, brawl, 50)
  @debug.assert_eq(s.my_ranks, [0, 0, 0, 0, 0])
  @debug.assert_eq(s.my_item_consumed[0], true)
}

///|
/// **Case 3 (まけんき: 反応後に判定)**: まけんき の所持者が なきごえ (A-1) を受けると、
/// 反応で A +2 となり A は +1。負の能力が無いので しろいハーブ は消費されない。
test "しろいハーブ × まけんき: なきごえ は反応 (A +2) で負にならず消費されない" {
  let growl = wh_growl()
  let opp_team = wh_team(wh_mon("Growler", [growl], "", ""))
  let my_team = wh_team(wh_mon("Defiant", [wh_nop()], "まけんき", "しろいハーブ"))
  let s = with_post_hit_effects(im_state(), false, 0, 0, opp_team, my_team, growl, 0)
  @debug.assert_eq(s.my_ranks, [1, 0, 0, 0, 0])
  @debug.assert_eq(s.my_item_consumed[0], false)
}

///|
/// **Case 4 (まけんき × くすぐる)**: くすぐる (A-1 / B-1) は両方とも下がるので、まけんき は
/// 下がった能力ごとに 1 回ずつ反応する (A +2 が 2 回)。A は 0 → -1 → +1 → +3 となり、
/// 負のままの B だけが解除される。消費される (負の B が残らない)。
test "しろいハーブ × まけんき: くすぐる は下がった能力ごとに反応 (A +3)、B だけ 0 に戻る" {
  let tickle = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let opp_team = wh_team(wh_mon("Tickler", [tickle], "", ""))
  let my_team = wh_team(wh_mon("Defiant", [wh_nop()], "まけんき", "しろいハーブ"))
  let s = with_post_hit_effects(im_state(), false, 0, 0, opp_team, my_team, tickle, 0)
  @debug.assert_eq(s.my_ranks, [3, 0, 0, 0, 0])
  @debug.assert_eq(s.my_item_consumed[0], true)
}

///|
/// **Case 5 (クリアボディ: 不発は判定を起こさない)**: クリアボディ の所持者は なきごえ を
/// 受けない。負の能力が生じないので しろいハーブ は消費されない。
test "しろいハーブ × クリアボディ: 不発のダウンでは消費されない" {
  let growl = wh_growl()
  let opp_team = wh_team(wh_mon("Growler", [growl], "", ""))
  let my_team = wh_team(wh_mon("Clear", [wh_nop()], "クリアボディ", "しろいハーブ"))
  let s = with_post_hit_effects(im_state(), false, 0, 0, opp_team, my_team, growl, 0)
  @debug.assert_eq(s.my_ranks, [0, 0, 0, 0, 0])
  @debug.assert_eq(s.my_item_consumed[0], false)
}

///|
/// **Case 6 (かちき: 特攻の反応)**: かちき の所持者は 特攻 -1 の相手ダウンで反応 (C +2)、
/// C は +1 になり負にならない。消費されない。
test "しろいハーブ × かちき: 特攻ダウンは反応 (C +2) で負にならず消費されない" {
  let snarl = mk_move("テスト特攻ダウン", "あく", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 2, delta: -1, target: 1 },
  ])
  let opp_team = wh_team(wh_mon("Snarler", [snarl], "", ""))
  let my_team = wh_team(wh_mon("Compet", [wh_nop()], "かちき", "しろいハーブ"))
  let s = with_post_hit_effects(im_state(), false, 0, 0, opp_team, my_team, snarl, 0)
  @debug.assert_eq(s.my_ranks, [0, 0, 1, 0, 0])
  @debug.assert_eq(s.my_item_consumed[0], false)
}

///|
/// **Case 7 (登場時いかく: Switch arm)**: 相手のいかく で登場したとき、しろいハーブ 所持者の
/// A は -1 → 登場直後に 0 へ戻り消費される。相手 (opp) の技は解除後の A で撃つ。
/// 対照として持ち物なしは A -1 のまま。
test "しろいハーブ: 登場時いかく (A-1) は登場直後に解除され消費される" {
  let my_team = [
    wh_mon("Bench0", [im_tackle()], "", ""),
    wh_mon("Intim", [im_tackle()], "いかく", ""),
    wh_mon("Bench2", [im_tackle()], "", ""),
  ]
  let herb_opp = wh_team(wh_mon("Herb", [wh_nop()], "", "しろいハーブ"))
  let outs = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    herb_opp,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length() > 0, true)
  for o in outs {
    @debug.assert_eq(o.1.opp_ranks[0], 0)
    @debug.assert_eq(o.1.opp_item_consumed[0], true)
  }
  let plain_opp = wh_team(wh_mon("Plain", [wh_nop()], "", ""))
  let plain_outs = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    plain_opp,
    new_damage_cache(),
  )
  for o in plain_outs {
    @debug.assert_eq(o.1.opp_ranks[0], -1)
    @debug.assert_eq(o.1.opp_item_consumed[0], false)
  }
}

///|
/// **Case 8 (ミラーアーマー反射)**: 相手が ミラーアーマー なら、いかく の -1 は使用者へ
/// 反射される。使用者が しろいハーブ を持つと、その A は登場直後に解除され消費される。
test "しろいハーブ: ミラーアーマーで反射された いかく の -1 は使用者の herb で解除" {
  let my_team = [
    wh_mon("Bench0", [im_tackle()], "", ""),
    wh_mon("HerbIntim", [im_tackle()], "いかく", "しろいハーブ"),
    wh_mon("Bench2", [im_tackle()], "", ""),
  ]
  let mirror_opp = wh_team(wh_mon("Mirror", [wh_nop()], "ミラーアーマー", ""))
  let outs = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    mirror_opp,
    new_damage_cache(),
  )
  for o in outs {
    @debug.assert_eq(o.1.my_ranks[0], 0)
    @debug.assert_eq(o.1.my_item_consumed[1], true)
  }
}

///|
/// **Case 9 (いかく × まけんき)**: いかく の -1 が まけんき の所持者に入ると反応 (A +2) で
/// A は +1 になり、負にならないので しろいハーブ は消費されない。
test "しろいハーブ × まけんき: 登場時いかく は反応後の A +1 のまま消費されない" {
  let my_team = [
    wh_mon("Bench0", [im_tackle()], "", ""),
    wh_mon("Intim", [im_tackle()], "いかく", ""),
    wh_mon("Bench2", [im_tackle()], "", ""),
  ]
  let defiant_opp = wh_team(wh_mon("Defiant", [wh_nop()], "まけんき", "しろいハーブ"))
  let outs = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    defiant_opp,
    new_damage_cache(),
  )
  for o in outs {
    @debug.assert_eq(o.1.opp_ranks[0], 1)
    @debug.assert_eq(o.1.opp_item_consumed[0], false)
  }
}

///|
/// **Case 10 (消費は交代を跨いで持続)**: 既に消費済みの所持者は、後の なきごえ で A が -1
/// に下がっても 0 に戻らない (1 戦闘 1 回)。
test "しろいハーブ: 消費済みの所持者は 2 回目の なきごえ で解除されない" {
  let growl = wh_growl()
  let opp_team = wh_team(wh_mon("Growler", [growl], "", ""))
  let my_team = wh_team(wh_mon("Used", [wh_nop()], "", "しろいハーブ"))
  let used = { ..im_state(), my_item_consumed: [true, false, false] }
  let s = with_post_hit_effects(used, false, 0, 0, opp_team, my_team, growl, 0)
  @debug.assert_eq(s.my_ranks[0], -1)
  @debug.assert_eq(s.my_item_consumed[0], true)
}

///|
/// **Case 11 (技の後に判定: 同ターンの後攻に効く)**: 先攻の自己ダウン技 (B-1) を撃った
/// しろいハーブ 所持者は、技の直後に B が 0 に戻る。後攻の物理技はその B で受けるので、
/// 持ち物なしより被ダメージが小さい (期待 HP が大きい)。
test "しろいハーブ: 自己ダウン技の直後に判定され、後攻の被弾は解除後の B で計算される" {
  let brawl = mk_move("インファイト", "かくとう", @model.Physical, 60, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
  ])
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let opp_team = wh_team(wh_mon("Hitter", [hit], "", "", spe=100))
  let state = im_state()
  let herb_team = wh_team(wh_mon("Herb", [brawl], "", "しろいハーブ", spe=200))
  let plain_team = wh_team(wh_mon("Plain", [brawl], "", "", spe=200))
  let herb_outs = transition_with_cache(
    state,
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    herb_team,
    opp_team,
    new_damage_cache(),
  )
  let plain_outs = transition_with_cache(
    state,
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    plain_team,
    opp_team,
    new_damage_cache(),
  )
  let herb_hp = wh_expected_hp(herb_outs, 0)
  let plain_hp = wh_expected_hp(plain_outs, 0)
  assert_true(herb_hp > plain_hp + 1.0)
  for o in herb_outs {
    @debug.assert_eq(o.1.my_ranks[1], 0)
    @debug.assert_eq(o.1.my_item_consumed[0], true)
  }
}

///|
/// **Case 12 (EOT の判定点)**: 残存する負のランクは residual (apply_eot) で解除され消費される。
/// 実到達では技の後の判定で既に 0 なので no-op だが、判定点の対応を pin する。
test "しろいハーブ: EOT (residual) で残存する負のランクを解除し消費する" {
  let s = { ..im_state(), my_ranks: [-1, 0, 0, 0, 0] }
  let my_team = wh_team(wh_mon("Herb", [wh_nop()], "", "しろいハーブ"))
  let opp_team = wh_team(wh_mon("Opp", [wh_nop()], "", ""))
  let out = apply_eot(s, my_team, opp_team)
  @debug.assert_eq(out.my_ranks, [0, 0, 0, 0, 0])
  @debug.assert_eq(out.my_item_consumed[0], true)
}

///|
/// **Case 13 (メガ直後の判定点)**: 相手の しろいハーブ 所持者に残った負のランクは、自分の
/// メガ進化 (transition の mega 判定点) の直後に両 active を判定して解除される。
test "しろいハーブ: メガ進化の直後に相手 active の負のランクを解除する" {
  let mega = @model.MegaForm::{
    atk: 130,
    def_: 130,
    spa: 130,
    spd: 130,
    spe: 130,
    type1: "ノーマル",
    type2: "",
    ability: "",
    name_ja: "メガテスト",
  }
  let my_base = im_combatant(im_pokemon("Megaer"), [wh_nop()], ability="", mega_form=Some(mega))
  let my_team = wh_team(my_base)
  let opp_team = wh_team(wh_mon("Herb", [wh_nop()], "", "しろいハーブ"))
  let s = { ..im_state(), opp_ranks: [-1, 0, 0, 0, 0] }
  let outs = transition_with_cache(
    s,
    ActionKind::Mega(0),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  for o in outs {
    @debug.assert_eq(o.1.opp_ranks[0], 0)
    @debug.assert_eq(o.1.opp_item_consumed[0], true)
  }
}

///|
/// **Case 14 (partial-act の登場)**: 相手が行動不能 (skip) でも、こちらの交代登場の いかく で
/// 相手の しろいハーブ 所持者の A は解除される。partial_act_outcomes の判定点を pin する。
test "しろいハーブ: 相手が skip しても交代登場のいかく で解除される (partial-act)" {
  let my_team = [
    wh_mon("Bench0", [im_tackle()], "", ""),
    wh_mon("Intim", [im_tackle()], "いかく", ""),
    wh_mon("Bench2", [im_tackle()], "", ""),
  ]
  let herb_opp = wh_team(wh_mon("Herb", [wh_nop()], "", "しろいハーブ"))
  let outs = partial_act_outcomes(
    im_state(),
    ActionKind::Switch(1),
    true,
    my_team,
    herb_opp,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length() > 0, true)
  for o in outs {
    @debug.assert_eq(o.1.opp_ranks[0], 0)
    @debug.assert_eq(o.1.opp_item_consumed[0], true)
  }
}

///|
/// **Case 15 (初期 lead)**: 先発の いかく で相手の しろいハーブ lead の A が解除されるので、
/// 相手の物理技は A 0 で撃たれる。持ち物なし (A -1) より自分の値が低くなる。
test "しろいハーブ: 先発の登場時いかくで相手 lead の A が解除され値が動く" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let intim = wh_mon("Intim", [im_tackle()], "いかく", "")
  let herb_lead = wh_mon("Herb", [hit], "", "しろいハーブ")
  let plain_lead = wh_mon("Plain", [hit], "", "")
  let v_herb = switching_game_winrate([intim], [herb_lead], 2)
  let v_plain = switching_game_winrate([intim], [plain_lead], 2)
  // 解除されると相手の A は 0 のまま撃つので、こちらの値は持ち物なしより低い
  assert_true(v_plain - v_herb > 0.01)
}
