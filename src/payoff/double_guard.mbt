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
/// ファストガード (`_501`): 「自分と味方を先制技から守る。」usa は "protects
/// itself and its allies from priority moves"。waza.json は target 12、
/// priority +3、accuracy 101、available = 1。先制は `effective_priority >= 1`。
/// 行動順に使っている値（`DoubleActor.priority`）と同じなので、いたずらごころの
/// 変化技と満タン扱いのはやてのつばさも先制になる。Showdown の quickguard 注釈
/// （Prankster / Gale Wings で上がった技は防ぐ。Quick Claw は優先度ではない）
/// と同じ切り方。本文に連続成功率は無いので、ワイドガードと同じく stall は
/// 進まず、使ったターンはまもる不使用としてターン末に 0 へ戻す。
/// フェイントとゴーストダイブは守りの解除としてファストガードも落とす。
/// ふかしのこぶし（`TOKUSEIINFO_SYN_260`「守りの効果を無視して本来の１／４」）
/// の接触は 1/4。なみだめは通し、旗は残す。
///
/// こらえる (`_203`): 「ひんしになる技のダメージを受けるとＨＰを１残して耐える。
/// 連続で使うと成功率が前に使った時の１／３になる。」満タンは条件に無い。
/// 攻撃は無効にしない。連続成功率はまもる系の `stall` を共有する
/// （Showdown は `stallingMove` + `StallMove`）。成功したターンは旗を残し、
/// ターン末に stall を残して旗だけ消す。失敗・不使用・交代で 0。
///
/// サイドチェンジ (`_502`): 「自分と味方の場所を入れ替える。連続で使うと成功率が
/// 前に使った時の１／３になる。」waza.json は target 7、priority +2、
/// accuracy 101。優先度は DB の値を `effective_priority` に通す。
/// 連続成功率の段はまもると同じ `stall_denominator` だが、カウンタは別
/// （Showdown の volatile は `allyswitch` で、まもるの `stall` ではない）。
/// 使わなかったターンの末に 0 へ戻す。味方がひんしのときは入れ替えない。
/// 成功抽選自体は進み、失敗ならカウンタは 0（Showdown は onPrepareHit で
/// 抽選し、onHit で味方ひんしなら入れ替えない）。
/// 入れ替え後、相手が選んだ target 0 のスロットはそのままなので、そこにいる体に
/// 当たる。このゆびとまれの本文は「自分が受ける」なので、引きつけ先はスロット
/// ではなく使った体を追う（Showdown の `effectState.target`）。
///
/// フェイント (`_364`) とゴーストダイブの解放 (`_566`) は「まもる　みきり等」を
/// 解除する。そのターンの残りは当たる。成功した stall は残す（旗はターン末まで
/// 持ち、`settle_protect` と同じく旗が立ったスロットだけ stall を残す）。
/// ワイドガードとファストガードも等に含めて落とす（Showdown の breaksProtect）。
/// ゴーストダイブの溜めターンはダブルに無い。
/// なみだめは `protect_interaction` の通し。ランクは掛けないので HP は変わらない。
///
/// available = 0 のブロッキング / スレッドトラップ / かえんのまもり /
/// シャドーダイブ / トリックガードは扱わない。

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
fn is_fast_guard(name : String) -> Bool {
  name == "ファストガード"
}

///|
fn is_endure(name : String) -> Bool {
  name == "こらえる"
}

///|
fn is_ally_switch(name : String) -> Bool {
  name == "サイドチェンジ"
}

///|
/// ダメージ比較で「何もしない」と扱うと、守る・補強・範囲ガードが落ちる。
fn is_double_guard_move(name : String) -> Bool {
  is_protect_move(name) || is_helping_hand(name) || is_wide_guard(name)
}

///|
/// 葉の刈り込みで残す。ダメージ 0 でも、落すと値が変わる。
fn keeps_zero_damage_move(name : String) -> Bool {
  is_double_guard_move(name) ||
  is_redirect_move(name) ||
  is_fast_guard(name) ||
  is_endure(name) ||
  is_ally_switch(name)
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
  if idx < s.endure.length() {
    s.endure[idx] = 0
  }
  if idx < s.sw_stall.length() {
    s.sw_stall[idx] = 0
  }
  if idx < s.sw_held.length() {
    s.sw_held[idx] = 0
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
  let origin = live_slot(state, actor)
  match actor.chosen {
    None => ()
    Some(slot) =>
      if slot == ally_slot(origin) && hp_at(state, slot) > 0 {
        let i = slot_index(slot)
        if i >= 0 && i < state.hand.length() {
          state.hand[i] = 1
        }
      }
  }
}

///|
fn mark_fast_guard(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Unit {
  let side = side_of_slot(slot)
  if side >= 0 && side < state.fast.length() {
    state.fast[side] = 1
  }
}

///|
fn mark_endure_result(
  state : DoubleFieldHp,
  slot : @doubles.DoubleSlot,
  success : Bool,
) -> Unit {
  let i = slot_index(slot)
  if i < 0 || i >= state.stall.length() {
    return
  }
  if !success {
    state.stall[i] = 0
    if i < state.endure.length() {
      state.endure[i] = 0
    }
    return
  }
  state.stall[i] = stall_next(state.stall[i])
  if i < state.endure.length() {
    state.endure[i] = 1
  }
}

///|
/// 旗が立ったスロットだけ stall を残し、ターン内の旗は消す。
/// こらえるはまもるの stall を共有する。サイドチェンジは別カウンタ。
fn settle_double_guard(state : DoubleFieldHp) -> Unit {
  let n = state.stall.length()
  for i in 0..<n {
    let shielded = i < state.shield.length() && state.shield[i] != 0
    let endured = i < state.endure.length() && state.endure[i] != 0
    if !shielded && !endured {
      state.stall[i] = 0
    }
    let held = i < state.sw_held.length() && state.sw_held[i] != 0
    if i < state.sw_stall.length() && !held {
      state.sw_stall[i] = 0
    }
  }
  for i in 0..<state.shield.length() {
    state.shield[i] = 0
  }
  for i in 0..<state.endure.length() {
    state.endure[i] = 0
  }
  for i in 0..<state.sw_held.length() {
    state.sw_held[i] = 0
  }
  for i in 0..<state.hand.length() {
    state.hand[i] = 0
  }
  for i in 0..<state.wide.length() {
    state.wide[i] = 0
  }
  for i in 0..<state.fast.length() {
    state.fast[i] = 0
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
fn clear_fast_side(state : DoubleFieldHp, side : Int) -> Unit {
  if side >= 0 && side < state.fast.length() {
    state.fast[side] = 0
  }
}

///|
fn endure_up(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Bool {
  let i = slot_index(slot)
  i >= 0 && i < state.endure.length() && state.endure[i] != 0
}

///|
/// 当たった 1 体。`GuardBlock` の整数は接触反動に使う盾。
/// 0 はワイドガードかファストガードで、接触反動は無い。
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
  let fast_up = side >= 0 && side < state.fast.length() && state.fast[side] != 0
  let spread = wide_guard_spread(actor.target_code)
  let wide_cover = wide_up && spread
  let fast_on = fast_up && actor.priority >= 1 && !breaks_guard(mv.name)
  if shield != 0 {
    match protect_interaction(shield, mv, ability) {
      PvBreak => {
        if ti >= 0 && ti < state.broken.length() {
          state.broken[ti] = 1
        }
        clear_wide_side(state, side)
        clear_fast_side(state, side)
        return GuardThrough
      }
      PvQuarter =>
        if wide_cover {
          return GuardBlock(0)
        } else {
          return GuardQuarter
        }
      PvThrough =>
        if wide_cover {
          return GuardBlock(0)
        } else if fast_on && mv.name != "なみだめ" {
          return GuardBlock(0)
        } else {
          return GuardThrough
        }
      PvBlock =>
        if wide_cover {
          return GuardBlock(0)
        } else {
          return GuardBlock(shield)
        }
    }
  }
  if (wide_up || fast_up) && breaks_guard(mv.name) {
    if wide_up {
      clear_wide_side(state, side)
    }
    if fast_up {
      clear_fast_side(state, side)
    }
    return GuardThrough
  }
  if wide_cover {
    return GuardBlock(0)
  }
  if fast_on {
    match protect_interaction(PROTECT_FULL, mv, ability) {
      PvQuarter => GuardQuarter
      PvThrough => GuardThrough
      PvBreak => {
        clear_fast_side(state, side)
        GuardThrough
      }
      PvBlock => GuardBlock(0)
    }
  } else {
    GuardThrough
  }
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
    let slot = live_slot(state, actor)
    set_hp(state, slot, hp_at(state, slot) - chip)
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
  let slot = live_slot(state, actor)
  let den = stall_denominator(stall_at(state, slot))
  let kind = protect_kind(mv.name)
  let go = fn(s : DoubleFieldHp) -> Double {
    eval_turn(cache, s, actors, actor_idx + 1, [], 0, false, my, opp, finish)
  }
  if den <= 1 {
    mark_protect_result(state, slot, true, kind)
    return go(state)
  }
  let p = 1.0 / den.to_double()
  let ok = copy_field(state)
  mark_protect_result(ok, slot, true, kind)
  mark_protect_result(state, slot, false, kind)
  p * go(ok) + (1.0 - p) * go(state)
}

///|
fn sw_at(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Int {
  let i = slot_index(slot)
  if i >= 0 && i < state.sw_stall.length() {
    state.sw_stall[i]
  } else {
    0
  }
}

///|
fn exchange_ints(xs : Array[Int], i : Int, j : Int) -> Unit {
  if i == j || i < 0 || j < 0 || i >= xs.length() || j >= xs.length() {
    return
  }
  let tmp = xs[i]
  xs[i] = xs[j]
  xs[j] = tmp
}

///|
fn exchange_ranks(state : DoubleFieldHp, i : Int, j : Int) -> Unit {
  for k in 0..<5 {
    exchange_ints(state.ranks, i * 5 + k, j * 5 + k)
  }
}

///|
fn retarget_draw_index(xs : Array[Int], i : Int, j : Int) -> Unit {
  for s in 0..<xs.length() {
    if xs[s] == i {
      xs[s] = j
    } else if xs[s] == j {
      xs[s] = i
    }
  }
}

///|
/// 生きている味方と場所を入れ替える。体に付く stall・ランク・引きつけ先も動かす。
/// 味方がひんしなら false。HP は squad 側なので `pos` の交換で付いてくる。
fn swap_allies(state : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Bool {
  let ally = ally_slot(slot)
  if hp_at(state, ally) <= 0 {
    return false
  }
  let i = slot_index(slot)
  let j = slot_index(ally)
  exchange_ints(state.pos, i, j)
  exchange_ints(state.stall, i, j)
  exchange_ints(state.shield, i, j)
  exchange_ints(state.hand, i, j)
  exchange_ints(state.broken, i, j)
  exchange_ints(state.entered, i, j)
  exchange_ints(state.endure, i, j)
  exchange_ints(state.sw_stall, i, j)
  exchange_ints(state.sw_held, i, j)
  exchange_ranks(state, i, j)
  retarget_draw_index(state.follow, i, j)
  retarget_draw_index(state.rage, i, j)
  true
}

///|
fn commit_ally_switch(
  state : DoubleFieldHp,
  actor : DoubleActor,
  success : Bool,
) -> Unit {
  let slot = live_slot(state, actor)
  let i = slot_index(slot)
  if i < 0 || i >= state.sw_stall.length() {
    return
  }
  if !success {
    state.sw_stall[i] = 0
    if i < state.sw_held.length() {
      state.sw_held[i] = 0
    }
    return
  }
  state.sw_stall[i] = stall_next(state.sw_stall[i])
  if i < state.sw_held.length() {
    state.sw_held[i] = 1
  }
  let _swapped = swap_allies(state, slot)
}

///|
fn apply_opening_switch(s : DoubleFieldHp, stall : Array[Int]) -> Unit {
  let n = if stall.length() < s.sw_stall.length() {
    stall.length()
  } else {
    s.sw_stall.length()
  }
  for i in 0..<n {
    s.sw_stall[i] = stall[i]
  }
}

///|
fn eval_endure_turn(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  actors : Array[DoubleActor],
  actor_idx : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
  finish : (DoubleFieldHp) -> Double,
) -> Double {
  let actor = actors[actor_idx]
  let slot = live_slot(state, actor)
  let den = stall_denominator(stall_at(state, slot))
  let go = fn(s : DoubleFieldHp) -> Double {
    eval_turn(cache, s, actors, actor_idx + 1, [], 0, false, my, opp, finish)
  }
  if den <= 1 {
    mark_endure_result(state, slot, true)
    return go(state)
  }
  let p = 1.0 / den.to_double()
  let ok = copy_field(state)
  mark_endure_result(ok, slot, true)
  mark_endure_result(state, slot, false)
  p * go(ok) + (1.0 - p) * go(state)
}

///|
fn eval_ally_switch_turn(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  actors : Array[DoubleActor],
  actor_idx : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
  finish : (DoubleFieldHp) -> Double,
) -> Double {
  let actor = actors[actor_idx]
  let den = stall_denominator(sw_at(state, live_slot(state, actor)))
  let go = fn(s : DoubleFieldHp) -> Double {
    eval_turn(cache, s, actors, actor_idx + 1, [], 0, false, my, opp, finish)
  }
  if den <= 1 {
    commit_ally_switch(state, actor, true)
    return go(state)
  }
  let p = 1.0 / den.to_double()
  let ok = copy_field(state)
  commit_ally_switch(ok, actor, true)
  commit_ally_switch(state, actor, false)
  p * go(ok) + (1.0 - p) * go(state)
}
