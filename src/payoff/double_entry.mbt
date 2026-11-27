///|
/// ダブルの引きつけと登場時いかく。
///
/// 引きつけの本文は champout `50e7233` の `wazainfo_syn.json`（jpn）。
/// このゆびとまれ (`WAZAINFO_SYN_266`): 「相手の技を全て自分が受ける。
/// 相手を選ぶ技にしか効果はない。」
/// いかりのこな (`WAZAINFO_SYN_476`): 同じ文に「くさタイプのポケモンには効かない。」
/// `waza.json` ではどちらも available = 1、target 7、priority +2、accuracy 101。
/// 優先度は技の `priority` を `effective_priority` に通す。名前では上書きしない。
/// `move_meta` にこの 2 技の行は無い。
///
/// 相手を選ぶ技は target 0 だけ。範囲（4 / 5 / 8）と、選ばない target 9 は
/// 引きつけない。味方が自分に撃つ技も引きつけない（本文は「相手の技」）。
/// 後から成功した方が先のものを上書きする。両方残っているとき、いかりのこなを
/// 粉で受けない相手はフォロー側へ戻る。使った側がひんしになったら、その引きつけは
/// そこで終わる。ターン末に消す。DP のメモキーには入れない。
/// サイドチェンジで場所が入れ替わると、引きつけ先のスロット添字は使った体の
/// 新しい位置へ追従する（`swap_allies`）。本文は「自分が受ける」なので、
/// スロットではなく体を追う。
///
/// いかりのこなの粉無効は `powder_move_blocked`。根拠は `help_syn.json` の
/// Powder Moves（ぼうじんとくさタイプ）。ぼうじんゴーグルは champions の
/// `items` に無いので見ない。
///
/// いかくは `TOKUSEIINFO_SYN_022`「登場した時、相手の攻撃を 1 段階下げる。」
/// 先発 4 体はターン行動の前（`fresh_field`）。ひんし補充と自発交代で入った
/// ポケモンは、そのターンの技の前。補充のあとすぐに自発交代で入れ替わった
/// 途中の 1 体は、技の時点で場にいないので撃たない。相手の場に残っている
/// 2 体のこうげきを 1 段階下げる。反応と無効化は `apply_intimidate_on_entry`。
/// フラワーベールは本文が「味方のくさタイプ」なので、ダブルでは場の味方の
/// フラワーベールも見る。シングルの関数は変えない。
///
/// ランクはスロットの `[A, B, C, D, S]`。交代で 0 に戻してからいかくを掛ける。
/// メモキーは 5 段階を 1 整数にパックし、未処理の登場フラグも入れる。
///
/// 入れないもの: スポットライト（available = 0）、よびみず（tokusei に無い）、
/// ひらいしんの引きつけ（本文は電気技を寄せて無効にし特攻 +1。吸収と特攻上昇は
/// ダブルのダメージ経路に無い）、しろいハーブ、状態異常、メガシンカ、
/// こうげき以外の能力ランク変化技。

///|
fn is_follow_me(name : String) -> Bool {
  name == "このゆびとまれ"
}

///|
fn is_rage_powder(name : String) -> Bool {
  name == "いかりのこな"
}

///|
fn is_redirect_move(name : String) -> Bool {
  is_follow_me(name) || is_rage_powder(name)
}

///|
fn slot_of_index(i : Int) -> @doubles.DoubleSlot {
  if i == 0 {
    @doubles.MyLeft
  } else if i == 1 {
    @doubles.MyRight
  } else if i == 2 {
    @doubles.FoeLeft
  } else {
    @doubles.FoeRight
  }
}

///|
fn field_rank(state : DoubleFieldHp, slot_i : Int, stat : Int) -> Int {
  let i = slot_i * 5 + stat
  if slot_i < 0 || stat < 0 || i >= state.ranks.length() {
    0
  } else {
    state.ranks[i]
  }
}

///|
fn set_rank(state : DoubleFieldHp, slot_i : Int, stat : Int, v : Int) -> Unit {
  let i = slot_i * 5 + stat
  if slot_i >= 0 && stat >= 0 && i < state.ranks.length() {
    state.ranks[i] = v
  }
}

///|
fn read_ranks(state : DoubleFieldHp, slot_i : Int) -> Array[Int] {
  let out = Array::make(5, 0)
  for k in 0..<5 {
    out[k] = field_rank(state, slot_i, k)
  }
  out
}

///|
fn write_ranks(state : DoubleFieldHp, slot_i : Int, ranks : Array[Int]) -> Unit {
  let n = if ranks.length() < 5 { ranks.length() } else { 5 }
  for k in 0..<n {
    set_rank(state, slot_i, k, ranks[k])
  }
}

///|
fn zero_slot_ranks(state : DoubleFieldHp, slot_i : Int) -> Unit {
  for k in 0..<5 {
    set_rank(state, slot_i, k, 0)
  }
}

///|
/// `-6..+6` を 4 bit ずつ。0 段は 6。5 段階で 20 bit に収まる。
fn pack_slot_ranks(state : DoubleFieldHp, slot_i : Int) -> Int {
  let mut p = 0
  for k in 0..<5 {
    let r = field_rank(state, slot_i, k)
    let u = if r < -6 {
      0
    } else if r > 6 {
      12
    } else {
      r + 6
    }
    p = p * 16 + u
  }
  p
}

///|
fn spe_rank_at(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Int {
  field_rank(state, slot_index(slot), 4)
}

///|
/// `attack_defense_stat_indices` は HABCDS（1=A .. 4=D）。ランク配列は
/// `[A, B, C, D, S]`。ボディプレスは B、特殊技は C を使う。
fn stage_for_move(mv : @model.Move, ranks : Array[Int]) -> Int {
  if ranks.length() < 5 {
    return 0
  }
  let (idx, _) = attack_defense_stat_indices(mv)
  let ri = if idx == 1 {
    0
  } else if idx == 2 {
    1
  } else if idx == 3 {
    2
  } else if idx == 4 {
    3
  } else {
    -1
  }
  if ri < 0 {
    0
  } else {
    ranks[ri]
  }
}

///|
fn mon_at(
  state : DoubleFieldHp,
  idx : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Combatant {
  let squad = if idx >= 0 && idx < state.pos.length() { state.pos[idx] } else { 0 }
  squad_mon(idx < 2, squad, my, opp)
}

///|
fn type_is_grass(mon : Combatant) -> Bool {
  mon.pokemon.type1 == "くさ" || mon.pokemon.type2 == "くさ"
}

///|
/// 持っている本人がくさのときと、場の味方がフラワーベールのとき。
/// シングルは味方がいないので本人だけを見る。
fn flower_veil_blocks(
  state : DoubleFieldHp,
  target_idx : Int,
  target : Combatant,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Bool {
  if !type_is_grass(target) {
    return false
  }
  if target.ability == "フラワーベール" {
    return true
  }
  let ally = ally_slot(slot_of_index(target_idx))
  if hp_at(state, ally) <= 0 {
    return false
  }
  mon_at(state, slot_index(ally), my, opp).ability == "フラワーベール"
}

///|
fn intimidate_onto(
  state : DoubleFieldHp,
  entrant_idx : Int,
  target_idx : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Unit {
  if hp_at(state, slot_of_index(target_idx)) <= 0 {
    return
  }
  let entrant = mon_at(state, entrant_idx, my, opp)
  if entrant.ability != "いかく" {
    return
  }
  let target = mon_at(state, target_idx, my, opp)
  if flower_veil_blocks(state, target_idx, target, my, opp) {
    return
  }
  let e_ranks = read_ranks(state, entrant_idx)
  let t_ranks = read_ranks(state, target_idx)
  apply_intimidate_on_entry(
    entrant.ability,
    target.ability,
    t_ranks,
    e_ranks,
    target_type1=target.pokemon.type1,
    target_type2=target.pokemon.type2,
  )
  write_ranks(state, entrant_idx, e_ranks)
  write_ranks(state, target_idx, t_ranks)
}

///|
fn faster_entrant(
  state : DoubleFieldHp,
  a : Int,
  b : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Bool {
  let sa = double_actor_speed_at(mon_at(state, a, my, opp), 0)
  let sb = double_actor_speed_at(mon_at(state, b, my, opp), 0)
  if sa != sb {
    sa > sb
  } else {
    a < b
  }
}

///|
fn order_entrants(
  state : DoubleFieldHp,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Array[Int] {
  let raw : Array[Int] = []
  let n = if state.entered.length() < 4 { state.entered.length() } else { 4 }
  for i in 0..<n {
    if state.entered[i] != 0 && hp_at(state, slot_of_index(i)) > 0 {
      raw.push(i)
    }
    state.entered[i] = 0
  }
  let mut out : Array[Int] = []
  for a in raw {
    let mut i = 0
    while i < out.length() && faster_entrant(state, out[i], a, my, opp) {
      i = i + 1
    }
    let next : Array[Int] = []
    for j in 0..<i {
      next.push(out[j])
    }
    next.push(a)
    for j in i..<out.length() {
      next.push(out[j])
    }
    out = next
  }
  out
}

///|
/// `entered` が立っているスロットだけ。速い方から。呼び出した側はフラグを戻す。
fn fire_entry_intimidate(
  state : DoubleFieldHp,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Unit {
  let order = order_entrants(state, my, opp)
  for idx in order {
    if mon_at(state, idx, my, opp).ability != "いかく" {
      continue
    }
    let foes = if idx < 2 { [2, 3] } else { [0, 1] }
    for foe in foes {
      intimidate_onto(state, idx, foe, my, opp)
    }
  }
}

///|
fn bump_clock(state : DoubleFieldHp) -> Int {
  if state.draw_clock.length() == 0 {
    return 1
  }
  let n = state.draw_clock[0] + 1
  state.draw_clock[0] = n
  n
}

///|
fn mark_follow(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Unit {
  let side = side_of_slot(slot)
  if side < 0 || side >= state.follow.length() || side >= state.follow_at.length() {
    return
  }
  state.follow[side] = slot_index(slot)
  state.follow_at[side] = bump_clock(state)
}

///|
fn mark_rage(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Unit {
  let side = side_of_slot(slot)
  if side < 0 || side >= state.rage.length() || side >= state.rage_at.length() {
    return
  }
  state.rage[side] = slot_index(slot)
  state.rage_at[side] = bump_clock(state)
}

///|
fn clear_draw_slot(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Unit {
  let i = slot_index(slot)
  let side = side_of_slot(slot)
  if side >= 0 && side < state.follow.length() && state.follow[side] == i {
    state.follow[side] = -1
  }
  if side >= 0 && side < state.rage.length() && state.rage[side] == i {
    state.rage[side] = -1
  }
}

///|
fn clear_redirect(state : DoubleFieldHp) -> Unit {
  for i in 0..<state.follow.length() {
    state.follow[i] = -1
  }
  for i in 0..<state.rage.length() {
    state.rage[i] = -1
  }
}

///|
fn draw_alive(state : DoubleFieldHp, idx : Int) -> Bool {
  if idx < 0 || idx > 3 {
    false
  } else {
    hp_at(state, slot_of_index(idx)) > 0
  }
}

///|
fn powder_draw_blocked(mon : Combatant) -> Bool {
  powder_move_blocked(
    "いかりのこな",
    mon.pokemon.type1,
    mon.pokemon.type2,
    mon.ability,
  )
}

///|
/// 攻撃側から見た相手サイドの引きつけ先。無ければ -1。
fn drawn_index(
  state : DoubleFieldHp,
  actor : DoubleActor,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Int {
  if actor.target_code != 0 {
    return -1
  }
  let side = if actor.is_me { 1 } else { 0 }
  if side < 0 || side >= state.follow.length() || side >= state.rage.length() {
    return -1
  }
  let follow_i = state.follow[side]
  let rage_i = state.rage[side]
  let follow_ok = draw_alive(state, follow_i)
  let attacker = squad_mon(actor.is_me, actor.squad, my, opp)
  let rage_ok = draw_alive(state, rage_i) && !powder_draw_blocked(attacker)
  if follow_ok && rage_ok {
    if state.rage_at[side] >= state.follow_at[side] {
      rage_i
    } else {
      follow_i
    }
  } else if rage_ok {
    rage_i
  } else if follow_ok {
    follow_i
  } else {
    -1
  }
}

///|
fn strike_with_draw(
  state : DoubleFieldHp,
  actor : DoubleActor,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> DoubleStrike {
  let draw = drawn_index(state, actor, my, opp)
  if draw < 0 {
    strike_plan(state, actor, my, opp)
  } else {
    All([slot_of_index(draw)])
  }
}
