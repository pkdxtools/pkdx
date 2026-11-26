///|
/// ダブルのまもる・てだすけ・ワイドガード。
///
/// 本文は champout `50e7233` の `wazainfo_syn.json`（jpn を優先、usa は照合）。
/// 連続成功率の段と接触の通し方はシングルの `protect.mbt` をそのまま使う。
///
/// まもる / みきり (`WAZAINFO_SYN_182` / `_197`): そのターンの技を防ぐ。
/// キングシールド (`_588`): 攻撃を防ぐ。接触の攻撃低下とシールドフォルムは
/// ダブルの状態にランクもフォルムも無いので掛けない。
/// ニードルガード (`_596`): 技を防ぐ。接触で最大 HP の 1/8。分母はこの経路の
/// `pokemon.hp`（場の HP と同じ値）。マジックガードは `spiky_chip`。
/// トーチカ (`_661`): 技を防ぐ。どくは状態異常なので掛けない。
/// 連続成功率は「前に使った時の１／３」。失敗・不使用・交代で 0。
/// 下限 1/729 は本文に無いのでシングルと同じ `stall_denominator`。
/// 1 ターン評価は `opening_stall`（自陣左、自陣右、相手左、相手右）を受け取る。
/// 厳密 DP とロールアウトはスロットの stall を状態に持つ。
///
/// てだすけ (`_270`): 「味方の技の威力を１．５倍」。優先度は waza.json の +5 で、
/// 行動順は `effective_priority`。威力は宣言威力へ `round5(_, 6144)` を掛けて
/// からダメージエンジンに渡す。可変威力やテクニシャンはその後のエンジン順。
/// 味方の技より後なら、その技には掛からない。
///
/// ワイドガード (`_469`): 「味方全員に当たる技」。usa は "moves that target all
/// allies"。waza.json の target 4（自分以外）と 5（相手全体）が、ガード側の
/// スロットに当たるとき防ぐ。Showdown の allAdjacent / allAdjacentFoes と同じ
/// 範囲。単体と target 8（ほろびのうた等）は通す。優先度は waza.json の +3。
/// 本文に連続成功率は無いので、stall は進まない。使ったターンはまもる不使用
/// としてターン末に stall を 0 に戻す。
///
/// フェイント (`_364`) とゴーストダイブの解放 (`_566`) は「まもる　みきり等」を
/// 解除する。そのターンの残りは当たる。成功した stall は残す（旗はターン末まで
/// 持ち、`settle_protect` と同じく旗が立ったスロットだけ stall を残す）。
/// ワイドガードも等に含めて落とす（Showdown の breaksProtect）。
/// ゴーストダイブの溜めターンはダブルに無い。
/// なみだめは `protect_interaction` の通し。ランクは掛けないので HP は変わらない。
///
/// ファストガードは available = 1 だが効果は入れない。こらえるはひんし回避で
/// 守るではない。available = 0 のブロッキング / スレッドトラップ /
/// かえんのまもり / シャドーダイブ / トリックガードは扱わない。

///|
priv enum DoubleGuardHit {
  GuardThrough
  GuardQuarter
  GuardBlock(Int)
}

///|
fn is_helping_hand(name : String) -> Bool {
  name == "てだすけ"
}

///|
fn is_wide_guard(name : String) -> Bool {
  name == "ワイドガード"
}

///|
/// ダメージ比較で「何もしない」と扱うと、守る・補強・範囲ガードが落ちる。
fn is_double_guard_move(name : String) -> Bool {
  is_protect_move(name) || is_helping_hand(name) || is_wide_guard(name)
}

///|
fn wide_guard_spread(code : Int) -> Bool {
  code == 4 || code == 5
}

///|
fn breaks_guard(name : String) -> Bool {
  name == "フェイント" || name == "ゴーストダイブ"
}

///|
fn helping_hand_move(mv : @model.Move) -> @model.Move {
  if mv.power <= 0 {
    mv
  } else {
    { ..mv, power: @damage.round5(mv.power, 6144) }
  }
}

///|
fn guard_zeros(n : Int) -> Array[Int] {
  Array::make(n, 0)
}

///|
fn apply_opening_stall(s : DoubleFieldHp, stall : Array[Int]) -> Unit {
  let n = if stall.length() < s.stall.length() {
    stall.length()
  } else {
    s.stall.length()
  }
  for i in 0..<n {
    s.stall[i] = stall[i]
  }
}

///|
/// 入ってきたポケモンの stall は 0。交代もひんし補充もここを通す。
fn set_slot_squad(s : DoubleFieldHp, idx : Int, squad : Int) -> Unit {
  if idx < 0 || idx >= s.pos.length() {
    return
  }
  if s.pos[idx] == squad {
    return
  }
  s.pos[idx] = squad
  zero_slot_ranks(s, idx)
  if idx < s.entered.length() {
    s.entered[idx] = 1
  }
  clear_draw_slot(s, slot_of_index(idx))
  if idx < s.stall.length() {
    s.stall[idx] = 0
  }
  if idx < s.shield.length() {
    s.shield[idx] = 0
  }
  if idx < s.hand.length() {
    s.hand[idx] = 0
  }
  if idx < s.broken.length() {
    s.broken[idx] = 0
  }
}

///|
fn ally_slot(slot : @doubles.DoubleSlot) -> @doubles.DoubleSlot {
  match slot {
    @doubles.MyLeft => @doubles.MyRight
    @doubles.MyRight => @doubles.MyLeft
    @doubles.FoeLeft => @doubles.FoeRight
    @doubles.FoeRight => @doubles.FoeLeft
  }
}

///|
fn side_of_slot(slot : @doubles.DoubleSlot) -> Int {
  if slot_is_mine(slot) {
    0
  } else {
    1
  }
}

///|
fn mark_protect_result(
  state : DoubleFieldHp,
  slot : @doubles.DoubleSlot,
  success : Bool,
  kind : Int,
) -> Unit {
  let i = slot_index(slot)
  if i < 0 || i >= state.stall.length() {
    return
  }
  if !success {
    state.stall[i] = 0
    if i < state.shield.length() {
      state.shield[i] = 0
    }
    return
  }
  state.stall[i] = stall_next(state.stall[i])
  if i < state.shield.length() {
    state.shield[i] = kind
  }
}

///|
fn mark_wide_guard(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Unit {
  let side = side_of_slot(slot)
  if side >= 0 && side < state.wide.length() {
    state.wide[side] = 1
  }
}

///|
fn mark_helping_hand(state : DoubleFieldHp, actor : DoubleActor) -> Unit {
  match actor.chosen {
    None => ()
    Some(slot) =>
      if slot == ally_slot(actor.slot) && hp_at(state, slot) > 0 {
        let i = slot_index(slot)
        if i >= 0 && i < state.hand.length() {
          state.hand[i] = 1
        }
      }
  }
}

///|
/// 旗が立ったスロットだけ stall を残し、ターン内の旗は消す。
fn settle_double_guard(state : DoubleFieldHp) -> Unit {
  let n = state.stall.length()
  for i in 0..<n {
    let shielded = i < state.shield.length() && state.shield[i] != 0
    if !shielded {
      state.stall[i] = 0
    }
  }
  for i in 0..<state.shield.length() {
    state.shield[i] = 0
  }
  for i in 0..<state.hand.length() {
    state.hand[i] = 0
  }
  for i in 0..<state.wide.length() {
    state.wide[i] = 0
  }
  for i in 0..<state.broken.length() {
    state.broken[i] = 0
  }
  clear_redirect(state)
}

///|
fn clear_wide_side(state : DoubleFieldHp, side : Int) -> Unit {
  if side >= 0 && side < state.wide.length() {
    state.wide[side] = 0
  }
}

///|
/// 当たった 1 体。`GuardBlock` の整数は接触反動に使う盾。0 はワイドガードだけ。
fn double_guard_hit(
  state : DoubleFieldHp,
  actor : DoubleActor,
  target : @doubles.DoubleSlot,
  mv : @model.Move,
  ability : String,
) -> DoubleGuardHit {
  let ti = slot_index(target)
  let broken = ti >= 0 && ti < state.broken.length() && state.broken[ti] != 0
  let shield = if broken || ti < 0 || ti >= state.shield.length() {
    0
  } else {
    state.shield[ti]
  }
  let side = side_of_slot(target)
  let wide_up = side >= 0 && side < state.wide.length() && state.wide[side] != 0
  let spread = wide_guard_spread(actor.target_code)
  if shield != 0 {
    match protect_interaction(shield, mv, ability) {
      PvBreak => {
        if ti >= 0 && ti < state.broken.length() {
          state.broken[ti] = 1
        }
        clear_wide_side(state, side)
        return GuardThrough
      }
      PvQuarter =>
        if wide_up && spread {
          return GuardBlock(0)
        } else {
          return GuardQuarter
        }
      PvThrough =>
        if wide_up && spread {
          return GuardBlock(0)
        } else {
          return GuardThrough
        }
      PvBlock =>
        if wide_up && spread {
          return GuardBlock(0)
        } else {
          return GuardBlock(shield)
        }
    }
  }
  if wide_up && breaks_guard(mv.name) {
    clear_wide_side(state, side)
    return GuardThrough
  }
  if wide_up && spread {
    return GuardBlock(0)
  }
  GuardThrough
}

///|
fn apply_spiky_chip(
  state : DoubleFieldHp,
  actor : DoubleActor,
  atk : Combatant,
  mv : @model.Move,
  shield : Int,
) -> Unit {
  if shield != PROTECT_SPIKY || !protect_move_contacts(mv, atk.ability) {
    return
  }
  let chip = spiky_chip(atk.ability, atk.pokemon.hp)
  if chip > 0 {
    set_hp(state, actor.slot, hp_at(state, actor.slot) - chip)
  }
}

///|
fn move_of_actor(
  actor : DoubleActor,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> @model.Move? {
  let mon = squad_mon(actor.is_me, actor.squad, my, opp)
  if actor.move_idx < 0 || actor.move_idx >= mon.moves.length() {
    None
  } else {
    Some(mon.moves[actor.move_idx])
  }
}

///|
fn stall_at(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Int {
  let i = slot_index(slot)
  if i >= 0 && i < state.stall.length() {
    state.stall[i]
  } else {
    0
  }
}

///|
fn hand_boosted(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Bool {
  let i = slot_index(slot)
  i >= 0 && i < state.hand.length() && state.hand[i] != 0
}

///|
/// 成功はコピー側、失敗は元の状態。分母 1 は乱数もコピーも作らない。
fn eval_protect_turn(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  actors : Array[DoubleActor],
  actor_idx : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
  finish : (DoubleFieldHp) -> Double,
  mv : @model.Move,
) -> Double {
  let actor = actors[actor_idx]
  let den = stall_denominator(stall_at(state, actor.slot))
  let kind = protect_kind(mv.name)
  let go = fn(s : DoubleFieldHp) -> Double {
    eval_turn(cache, s, actors, actor_idx + 1, [], 0, false, my, opp, finish)
  }
  if den <= 1 {
    mark_protect_result(state, actor.slot, true, kind)
    return go(state)
  }
  let p = 1.0 / den.to_double()
  let ok = copy_field(state)
  mark_protect_result(ok, actor.slot, true, kind)
  mark_protect_result(state, actor.slot, false, kind)
  p * go(ok) + (1.0 - p) * go(state)
}
