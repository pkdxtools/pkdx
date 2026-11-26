///|
/// ダブルの段階 2。段階 1 の同時行動行列は残し、終端だけを数ターンの
/// モンテカルロ期待値に替える。
///
/// 先発の 1 ターンは段階 1 と同じく正確に平均する。優先度、素早さ、同速の
/// 全順列、命中、対象ひんし時の振り替えは `eval_turn` / `strike_plan` を
/// そのまま使う。その葉の状態から、残りターンを 1 本の軌跡で進める。
///
/// 続きのターンの同速は、全順列の平均と同じ分布になるよう同速グループを
/// 一様に並べ替える。命中は対象ごとに独立で、外れたときはダメージ 0。
/// target 9 は生きている候補を一様に 1 体選んでから命中を引く。
///
/// 方策はシングル MC の ε-greedy。確率 `epsilon` で合法行動を一様に選び、
/// それ以外は攻撃の期待ダメージが最大の技（対象を選ぶ技はそのスロット）を
/// 選ぶ。控えの攻撃期待が場の技より `DOUBLE_SWITCH_HYSTERESIS`（シングルの
/// 0.05 と同じ）だけ高いときだけ、自発的に交代する。ひんし補充はシングルの
/// 強制交代と同じく貪欲で、乱数は使わない。
///
/// ひんし補充は技の解決が終わったあと、次のターンの行動選択の前に行う。
/// ひんしが起きたターンには出さず、次のターンから技を出せる。自発交代
/// （`BenchTo`）はそのターンの行動なので、そのターンは技を出さない。
/// champout `50e7233` の
/// `app_tutorial.json`（jpn「ポケモンがひんしになると　トレーナーは
/// 他の手持ちのポケモンに　交代させます」「交代したターンは　技が使えません」）。
/// 補充のタイミング自体は champout に文が無いので、Showdown のターン間の
/// faint switch（次のターンから行動できる）に合わせる。両スロットが
/// ひんしで控えが 1 体のときは、左スロットから埋める。
///
/// 乱数は `seeded_rng`。同じ seed と同じ評価順なら同じ値になる。
/// `turn_limit <= 1` は段階 1 の HP 比と一致する（続きを引かない）。
///
/// まもるの連続成功率は場の stall。てだすけとワイドガードも `double_guard.mbt`。
/// 分母が 1 のときは `sample_hit` を呼ばない。ε = 0 の方策はこれらの技の
/// 期待ダメージを 0 と見る。選ばれたときの解決は `resolve_actor_sampled`。
///
/// 入れないもの: 状態異常、メガシンカ、ファストガード、このゆびとまれ、いかく、
/// 設置、反動、回復、追加効果。いかくは補充時にも掛けない。

///|
/// シングル `team_monte_carlo.mbt` の `SWITCH_HYSTERESIS` と同じ幅。
const DOUBLE_SWITCH_HYSTERESIS : Double = 0.05

///|
fn rollout_unit(rng : @random.Rand) -> Double {
  rng.int(limit=1000000).to_double() / 1000000.0
}

///|
fn sample_hit(rng : @random.Rand, p : Double) -> Bool {
  if p >= 1.0 {
    true
  } else if p <= 0.0 {
    false
  } else {
    rollout_unit(rng) < p
  }
}

///|
fn acting_slot(is_me : Bool, is_left : Bool) -> @doubles.DoubleSlot {
  if is_me {
    if is_left {
      @doubles.MyLeft
    } else {
      @doubles.MyRight
    }
  } else if is_left {
    @doubles.FoeLeft
  } else {
    @doubles.FoeRight
  }
}

///|
fn bench_squads(s : DoubleFieldHp, is_me : Bool) -> Array[Int] {
  let left = if is_me { s.pos[0] } else { s.pos[2] }
  let right = if is_me { s.pos[1] } else { s.pos[3] }
  let out : Array[Int] = []
  for i in 0..<4 {
    if i != left && i != right {
      out.push(i)
    }
  }
  out
}

///|
fn side_hps(s : DoubleFieldHp, is_me : Bool) -> Array[Int] {
  if is_me {
    s.my_hp
  } else {
    s.opp_hp
  }
}

///|
fn bench_occupants(
  s : DoubleFieldHp,
  is_me : Bool,
  ids : Array[Int],
) -> Array[@doubles.DoubleOccupant] {
  let hps = side_hps(s, is_me)
  let out : Array[@doubles.DoubleOccupant] = []
  for id in ids {
    if id >= 0 && id < hps.length() && hps[id] > 0 {
      out.push(@doubles.Alive)
    } else {
      out.push(@doubles.Fainted)
    }
  }
  out
}

///|
fn targets_of(all : Array[Array[Int]], squad : Int) -> Array[Int] {
  if squad >= 0 && squad < all.length() {
    all[squad]
  } else {
    []
  }
}

///|
fn code_at(targets : Array[Int], move_idx : Int) -> Int {
  if move_idx >= 0 && move_idx < targets.length() {
    targets[move_idx]
  } else {
    0
  }
}

///|
fn scan_slots() -> Array[@doubles.DoubleSlot] {
  [@doubles.MyLeft, @doubles.MyRight, @doubles.FoeLeft, @doubles.FoeRight]
}

///|
/// 1 スロットの合法行動。対象を選ぶ技は、今の場で `double_slots_hit` が
/// そのスロットだけに当たるときだけ入れる。控えの添字は `bench` の並び。
fn legal_slot_actions(
  mon : Combatant,
  targets : Array[Int],
  actor : @doubles.DoubleSlot,
  field : @doubles.DoubleField,
  bench : Array[@doubles.DoubleOccupant],
) -> Array[@doubles.DoubleAction] {
  let actions : Array[@doubles.DoubleAction] = []
  for i in 0..<mon.moves.length() {
    let mv = mon.moves[i]
    let code = code_at(targets, i)
    if @doubles.double_target_chooses(code) {
      for slot in scan_slots() {
        let hit = @doubles.double_slots_hit(
          0, code, actor, Some(slot), field, false, name=mv.name,
        )
        match hit {
          @doubles.Struck(xs) =>
            if xs.length() == 1 && xs[0] == slot {
              actions.push(@doubles.UseOn(i, slot))
            }
          _ => ()
        }
      }
    } else {
      actions.push(@doubles.Use(i))
    }
  }
  for i in 0..<bench.length() {
    if bench[i] == @doubles.Alive {
      actions.push(@doubles.BenchTo(i))
    }
  }
  actions
}

///|
fn plan_for(
  state : DoubleFieldHp,
  is_me : Bool,
  squad : Int,
  slot : @doubles.DoubleSlot,
  move_idx : Int,
  code : Int,
  chosen : @doubles.DoubleSlot?,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> DoubleStrike {
  let actor : DoubleActor = {
    is_me,
    squad,
    slot,
    move_idx,
    target_code: code,
    chosen,
    priority: 0,
    speed: 0,
  }
  strike_plan(state, actor, my, opp)
}

///|
fn foe_of(actor : @doubles.DoubleSlot, slot : @doubles.DoubleSlot) -> Bool {
  slot_is_mine(actor) != slot_is_mine(slot)
}

///|
fn slot_score(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  actor : @doubles.DoubleSlot,
  atk : Combatant,
  mv : @model.Move,
  slot : @doubles.DoubleSlot,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Double {
  if hp_at(state, slot) <= 0 {
    return 0.0
  }
  let def = defender_of(state, slot, my, opp)
  let max_hp = def.pokemon.hp
  if max_hp <= 0 {
    return 0.0
  }
  let dmg = cached_move_mean(cache, atk, def, mv)
  let ratio = dmg.to_double() / max_hp.to_double()
  if foe_of(actor, slot) {
    ratio
  } else {
    0.0 - ratio
  }
}

///|
fn score_plan(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  actor : @doubles.DoubleSlot,
  atk : Combatant,
  mv : @model.Move,
  plan : DoubleStrike,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Double {
  match plan {
    Miss => 0.0
    All(slots) => {
      let mut sum = 0.0
      for slot in slots {
        sum = sum + slot_score(cache, state, actor, atk, mv, slot, my, opp)
      }
      sum
    }
    OneOf(cands) => {
      let n = cands.length()
      if n == 0 {
        0.0
      } else {
        let mut sum = 0.0
        for slot in cands {
          sum = sum + slot_score(cache, state, actor, atk, mv, slot, my, opp)
        }
        sum / n.to_double()
      }
    }
  }
}

///|
fn score_move_at(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  is_me : Bool,
  squad : Int,
  mon : Combatant,
  slot : @doubles.DoubleSlot,
  move_idx : Int,
  chosen : @doubles.DoubleSlot?,
  targets : Array[Int],
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Double {
  if move_idx < 0 || move_idx >= mon.moves.length() {
    return 0.0
  }
  let mv = mon.moves[move_idx]
  let plan = plan_for(
    state, is_me, squad, slot, move_idx, code_at(targets, move_idx), chosen, my, opp,
  )
  score_plan(cache, state, slot, mon, mv, plan, my, opp)
}

///|
/// 交代先の攻撃期待。控えへの再交代は数えない。
fn best_attack_score(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  is_me : Bool,
  squad : Int,
  mon : Combatant,
  slot : @doubles.DoubleSlot,
  targets : Array[Int],
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Double {
  let actions = legal_slot_actions(mon, targets, slot, field_of(state), [])
  let mut best = 0.0
  let mut any = false
  for action in actions {
    let sc = match action {
      @doubles.Use(i) =>
        score_move_at(
          cache, state, is_me, squad, mon, slot, i, None, targets, my, opp,
        )
      @doubles.UseOn(i, chosen) =>
        score_move_at(
          cache, state, is_me, squad, mon, slot, i, Some(chosen), targets, my, opp,
        )
      @doubles.BenchTo(_) => 0.0
    }
    match action {
      @doubles.BenchTo(_) => ()
      _ =>
        if !any || sc > best {
          any = true
          best = sc
        }
    }
  }
  if any {
    best
  } else {
    0.0
  }
}

///|
fn pick_slot_action(
  cache : DoubleEvalCache,
  rng : @random.Rand,
  epsilon : Double,
  state : DoubleFieldHp,
  is_me : Bool,
  squad : Int,
  mon : Combatant,
  slot : @doubles.DoubleSlot,
  all_targets : Array[Array[Int]],
  bench_ids : Array[Int],
  bench : Array[@doubles.DoubleOccupant],
  my : Array[Combatant],
  opp : Array[Combatant],
) -> @doubles.DoubleAction? {
  let mine = targets_of(all_targets, squad)
  let actions = legal_slot_actions(mon, mine, slot, field_of(state), bench)
  let n = actions.length()
  if n == 0 {
    return None
  }
  let draw = rollout_unit(rng)
  if draw < epsilon {
    return Some(actions[rng.int(limit=n)])
  }
  let mut move_i = -1
  let mut move_sc = 0.0
  let mut switch_i = -1
  let mut switch_sc = 0.0
  for i in 0..<n {
    match actions[i] {
      @doubles.BenchTo(b) =>
        if b >= 0 && b < bench_ids.length() {
          let incoming_squad = bench_ids[b]
          let incoming = squad_mon(is_me, incoming_squad, my, opp)
          let sc = best_attack_score(
            cache,
            state,
            is_me,
            incoming_squad,
            incoming,
            slot,
            targets_of(all_targets, incoming_squad),
            my,
            opp,
          )
          if switch_i < 0 || sc > switch_sc {
            switch_i = i
            switch_sc = sc
          }
        }
      @doubles.Use(mv) => {
        let sc = score_move_at(
          cache, state, is_me, squad, mon, slot, mv, None, mine, my, opp,
        )
        if move_i < 0 || sc > move_sc {
          move_i = i
          move_sc = sc
        }
      }
      @doubles.UseOn(mv, chosen) => {
        let sc = score_move_at(
          cache, state, is_me, squad, mon, slot, mv, Some(chosen), mine, my, opp,
        )
        if move_i < 0 || sc > move_sc {
          move_i = i
          move_sc = sc
        }
      }
    }
  }
  if switch_i >= 0 && (move_i < 0 || switch_sc > move_sc + DOUBLE_SWITCH_HYSTERESIS) {
    return Some(actions[switch_i])
  }
  if move_i >= 0 {
    return Some(actions[move_i])
  }
  None
}

///|
fn choose_side(
  cache : DoubleEvalCache,
  rng : @random.Rand,
  epsilon : Double,
  state : DoubleFieldHp,
  is_me : Bool,
  all_targets : Array[Array[Int]],
  my : Array[Combatant],
  opp : Array[Combatant],
) -> (@doubles.DoubleAction?, @doubles.DoubleAction?, Array[Int]) {
  let left_slot = acting_slot(is_me, true)
  let right_slot = acting_slot(is_me, false)
  let ids = bench_squads(state, is_me)
  let occ = bench_occupants(state, is_me, ids)
  let left_squad = state.pos[slot_index(left_slot)]
  let left = if hp_at(state, left_slot) <= 0 {
    None
  } else {
    pick_slot_action(
      cache,
      rng,
      epsilon,
      state,
      is_me,
      left_squad,
      squad_mon(is_me, left_squad, my, opp),
      left_slot,
      all_targets,
      ids,
      occ,
      my,
      opp,
    )
  }
  match left {
    Some(@doubles.BenchTo(i)) =>
      if i >= 0 && i < occ.length() {
        occ[i] = @doubles.Fainted
      }
    _ => ()
  }
  let right_squad = state.pos[slot_index(right_slot)]
  let right = if hp_at(state, right_slot) <= 0 {
    None
  } else {
    pick_slot_action(
      cache,
      rng,
      epsilon,
      state,
      is_me,
      right_squad,
      squad_mon(is_me, right_squad, my, opp),
      right_slot,
      all_targets,
      ids,
      occ,
      my,
      opp,
    )
  }
  (left, right, ids)
}

///|
fn apply_snapshot_switch(
  state : DoubleFieldHp,
  is_me : Bool,
  is_left : Bool,
  action : @doubles.DoubleAction?,
  bench_ids : Array[Int],
) -> Unit {
  match action {
    Some(@doubles.BenchTo(i)) =>
      if i >= 0 && i < bench_ids.length() {
        set_slot_squad(
          state, slot_index(acting_slot(is_me, is_left)), bench_ids[i],
        )
      }
    _ => ()
  }
}

///|
fn push_policy_actor(
  out : Array[DoubleActor],
  state : DoubleFieldHp,
  is_me : Bool,
  is_left : Bool,
  action : @doubles.DoubleAction?,
  all_targets : Array[Array[Int]],
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Unit {
  let (move_idx, chosen) = match action {
    Some(@doubles.Use(i)) => (i, None)
    Some(@doubles.UseOn(i, slot)) => (i, Some(slot))
    _ => return
  }
  let slot = acting_slot(is_me, is_left)
  if hp_at(state, slot) <= 0 {
    return
  }
  let squad = state.pos[slot_index(slot)]
  let mon = squad_mon(is_me, squad, my, opp)
  if move_idx < 0 || move_idx >= mon.moves.length() {
    return
  }
  let mv = mon.moves[move_idx]
  out.push({
    is_me,
    squad,
    slot,
    move_idx,
    target_code: code_at(targets_of(all_targets, squad), move_idx),
    chosen,
    priority: double_actor_priority(mon, mv),
    speed: double_actor_speed(mon),
  })
}

///|
fn sample_action_order(
  actors : Array[DoubleActor],
  rng : @random.Rand,
) -> Array[DoubleActor] {
  let groups = tie_groups(sort_actors(actors))
  let out : Array[DoubleActor] = []
  for g in groups {
    let n = g.length()
    let xs : Array[DoubleActor] = []
    for a in g {
      xs.push(a)
    }
    if n > 1 {
      for i in 0..<(n - 1) {
        let j = i + rng.int(limit=n - i)
        let tmp = xs[i]
        xs[i] = xs[j]
        xs[j] = tmp
      }
    }
    for a in xs {
      out.push(a)
    }
  }
  out
}

///|
fn resolve_actor_sampled(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  actor : DoubleActor,
  rng : @random.Rand,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Unit {
  match move_of_actor(actor, my, opp) {
    Some(mv) =>
      if is_helping_hand(mv.name) {
        mark_helping_hand(state, actor)
        return
      } else if is_wide_guard(mv.name) {
        mark_wide_guard(state, actor.slot)
        return
      } else if is_protect_move(mv.name) {
        let den = stall_denominator(stall_at(state, actor.slot))
        let ok = if den <= 1 {
          true
        } else {
          sample_hit(rng, 1.0 / den.to_double())
        }
        mark_protect_result(state, actor.slot, ok, protect_kind(mv.name))
        return
      }
    None => ()
  }
  let mon = squad_mon(actor.is_me, actor.squad, my, opp)
  let acc = if actor.move_idx >= 0 && actor.move_idx < mon.moves.length() {
    mon.moves[actor.move_idx].accuracy
  } else {
    100
  }
  let p = hit_probability(acc)
  match strike_plan(state, actor, my, opp) {
    Miss => ()
    All(slots) =>
      for slot in slots {
        if sample_hit(rng, p) {
          apply_hit(cache, state, actor, slot, my, opp)
        }
      }
    OneOf(cands) => {
      let n = cands.length()
      if n > 0 {
        let slot = cands[rng.int(limit=n)]
        if sample_hit(rng, p) {
          apply_hit(cache, state, actor, slot, my, opp)
        }
      }
    }
  }
}

///|
fn send_best_bench(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  is_me : Bool,
  slot : @doubles.DoubleSlot,
  all_targets : Array[Array[Int]],
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Unit {
  if hp_at(state, slot) > 0 {
    return
  }
  let ids = bench_squads(state, is_me)
  let hps = side_hps(state, is_me)
  let mut best_i = -1
  let mut best_sc = 0.0
  for i in 0..<ids.length() {
    let squad = ids[i]
    if squad < 0 || squad >= hps.length() || hps[squad] <= 0 {
      continue
    }
    let mon = squad_mon(is_me, squad, my, opp)
    let sc = best_attack_score(
      cache,
      state,
      is_me,
      squad,
      mon,
      slot,
      targets_of(all_targets, squad),
      my,
      opp,
    )
    if best_i < 0 || sc > best_sc {
      best_i = i
      best_sc = sc
    }
  }
  if best_i >= 0 {
    set_slot_squad(state, slot_index(slot), ids[best_i])
  }
}

///|
/// 左を先に埋める。いかくは掛けない。
fn replace_fainted(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Unit {
  send_best_bench(cache, state, true, @doubles.MyLeft, my_targets, my, opp)
  send_best_bench(cache, state, true, @doubles.MyRight, my_targets, my, opp)
  send_best_bench(cache, state, false, @doubles.FoeLeft, opp_targets, my, opp)
  send_best_bench(cache, state, false, @doubles.FoeRight, opp_targets, my, opp)
}

///|
fn play_policy_turn(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  rng : @random.Rand,
  epsilon : Double,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
) -> Unit {
  let (my_left, my_right, my_ids) = choose_side(
    cache, rng, epsilon, state, true, my_targets, my, opp,
  )
  let (opp_left, opp_right, opp_ids) = choose_side(
    cache, rng, epsilon, state, false, opp_targets, my, opp,
  )
  apply_snapshot_switch(state, true, true, my_left, my_ids)
  apply_snapshot_switch(state, true, false, my_right, my_ids)
  apply_snapshot_switch(state, false, true, opp_left, opp_ids)
  apply_snapshot_switch(state, false, false, opp_right, opp_ids)
  let actors : Array[DoubleActor] = []
  push_policy_actor(actors, state, true, true, my_left, my_targets, my, opp)
  push_policy_actor(actors, state, true, false, my_right, my_targets, my, opp)
  push_policy_actor(actors, state, false, true, opp_left, opp_targets, my, opp)
  push_policy_actor(actors, state, false, false, opp_right, opp_targets, my, opp)
  let order = sample_action_order(actors, rng)
  for actor in order {
    if hp_at(state, actor.slot) > 0 {
      resolve_actor_sampled(cache, state, actor, rng, my, opp)
    }
  }
  settle_double_guard(state)
}

///|
fn wiped_value(state : DoubleFieldHp) -> Double? {
  if !any_hp(state.my_hp) {
    Some(-1.0)
  } else if !any_hp(state.opp_hp) {
    Some(1.0)
  } else {
    None
  }
}

///|
fn continue_rollout(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  rng : @random.Rand,
  epsilon : Double,
  turns_left : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
) -> Double {
  match wiped_value(state) {
    Some(v) => return v
    None => ()
  }
  if turns_left <= 0 {
    return double_terminal(state, my, opp)
  }
  replace_fainted(cache, state, my_targets, opp_targets, my, opp)
  play_policy_turn(
    cache, state, rng, epsilon, my, opp, my_targets, opp_targets,
  )
  continue_rollout(
    cache,
    state,
    rng,
    epsilon,
    turns_left - 1,
    my,
    opp,
    my_targets,
    opp_targets,
  )
}

///|
fn expected_scripted_turn(
  cache : DoubleEvalCache,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  my_left : @doubles.DoubleAction?,
  my_right : @doubles.DoubleAction?,
  opp_left : @doubles.DoubleAction?,
  opp_right : @doubles.DoubleAction?,
  finish : (DoubleFieldHp) -> Double,
) -> Double {
  let state = fresh_field(my, opp)
  apply_switch(state, true, true, my_left)
  apply_switch(state, true, false, my_right)
  apply_switch(state, false, true, opp_left)
  apply_switch(state, false, false, opp_right)
  let actors : Array[DoubleActor] = []
  push_mover(actors, true, true, my_left, my, my_targets)
  push_mover(actors, true, false, my_right, my, my_targets)
  push_mover(actors, false, true, opp_left, opp, opp_targets)
  push_mover(actors, false, false, opp_right, opp, opp_targets)
  let orders = action_orders(actors)
  if orders.length() == 0 {
    settle_double_guard(state)
    return finish(state)
  }
  let mut sum = 0.0
  let n = orders.length()
  for i in 0..<n {
    let branch = copy_field(state)
    sum = sum +
      eval_turn(
        cache, branch, orders[i], 0, [], 0, false, my, opp, finish,
      )
  }
  sum / n.to_double()
}

///|
/// 先発の同時行動を固定したときの期待値。`turn_limit <= 1` は HP 比。
fn double_scripted_rollout(
  cache : DoubleEvalCache,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  my_left : @doubles.DoubleAction?,
  my_right : @doubles.DoubleAction?,
  opp_left : @doubles.DoubleAction?,
  opp_right : @doubles.DoubleAction?,
  rng : @random.Rand,
  trials : Int,
  turn_limit : Int,
  epsilon : Double,
) -> Double {
  if trials <= 0 || turn_limit <= 1 {
    return expected_scripted_turn(
      cache,
      my,
      opp,
      my_targets,
      opp_targets,
      my_left,
      my_right,
      opp_left,
      opp_right,
      fn(s) { double_terminal(s, my, opp) },
    )
  }
  expected_scripted_turn(
    cache,
    my,
    opp,
    my_targets,
    opp_targets,
    my_left,
    my_right,
    opp_left,
    opp_right,
    fn(s) {
      let mut total = 0.0
      for _ in 0..<trials {
        let branch = copy_field(s)
        total = total +
          continue_rollout(
            cache,
            branch,
            rng,
            epsilon,
            turn_limit - 1,
            my,
            opp,
            my_targets,
            opp_targets,
          )
      }
      total / trials.to_double()
    },
  )
}

///|
/// 先発 2 体の同時行動行列を、ロールアウト終端で解いた値。
fn double_joint_rollout_value(
  cache : DoubleEvalCache,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  config : NashSolverConfig,
  rng : @random.Rand,
  trials : Int,
  turn_limit : Int,
  epsilon : Double,
) -> Double raise NashCliError {
  if my.length() < 4 || opp.length() < 4 {
    raise InvalidJson("double rollout expects 4 pokemon on each side")
  }
  let my_js = side_joints(my[0], my[1], my_targets[0], my_targets[1])
  let opp_raw = side_joints(opp[0], opp[1], opp_targets[0], opp_targets[1])
  let opp_js : Array[@doubles.DoubleJointAction] = []
  for j in opp_raw {
    opp_js.push(translate_joint(j))
  }
  if my_js.length() == 0 || opp_js.length() == 0 {
    return 0.0
  }
  let data : Array[Array[Double]] = []
  for mine in my_js {
    let row = Array::make(opp_js.length(), 0.0)
    for j in 0..<opp_js.length() {
      let opp_j = opp_js[j]
      row[j] = double_scripted_rollout(
        cache,
        my,
        opp,
        my_targets,
        opp_targets,
        mine.left,
        mine.right,
        opp_j.left,
        opp_j.right,
        rng,
        trials,
        turn_limit,
        epsilon,
      )
    }
    data.push(row)
  }
  nash_value_of(data, config)
}
