///|
/// ダブルの段階 3。段階 1 の同時行動を、深さ `turn_limit` の厳密 DP にする。
///
/// 各ノードは両陣営の同時行動行列で、値は零和 Nash。速度順、同速グループの
/// 全順列、命中の枝、対象ひんし時の振り替えは `action_orders` / `eval_turn` /
/// `strike_plan` をそのまま使う。自発交代は `BenchTo` で、そのターンは技を
/// 出さない（段階 2 と同じ）。
///
/// ひんし補充は技の解決後ではなく、次のターンの行動選択の前。出たポケモンは
/// そのターンから技を出せる。champout `50e7233` の `app_tutorial.json`
/// （交代したターンは技が使えない）と、Showdown のターン間 faint switch。
/// 補充の選び方は段階 2 の攻撃期待貪欲ではなく、その場の Nash。自陣の補充案が
/// 行、相手が列。両スロットがひんしで控えが 1 体のときは左から埋める
/// （段階 2 と同じ）。控えが 2 体なら左右の割り当てを両方解く。
/// 入ったポケモンのいかくは、そのターンの技の前に `fire_entry_intimidate` が掛ける。
///
/// 深さの終端は HP 比（`double_terminal`）。ロールアウトは終端に使わない。
/// `turn_limit <= 1` は段階 1 の `joint_matrix_value` と同じ経路。
///
/// メモはシングルの `value` と同じく、状態（位置・HP・まもるの stall・
/// サイドチェンジの stall・5 段階のパック・未処理の登場フラグ・残りターン）
/// から値への写像。ターン内の盾・ワイドガード・ファストガード・てだすけ・
/// こらえるの旗・引きつけはキーに入れない。
/// ダメージ平均は段階 1 の `DoubleEvalCache`。選出行列では
/// `V(A,B) = -V(B,A)` を使い、同じ 4 対 4 を二度解かない。
/// 葉（残り 1 ターン）では、同じ優先度・命中・範囲で、どの生存相手にも
/// ダメージが劣る技を落とす。まもる・てだすけ・ワイドガード・ファストガード・
/// こらえる・サイドチェンジと、このゆびとまれ・いかりのこなはダメージ 0 でも
/// 残す。零和の値は変わらない。それより前のターンでは同じ効果の重複だけを
/// 落とす。KO すると次に強い控えが出るため、弱い技を値の前に捨てると厳密で
/// なくなる。行列を埋めたあと、厳密に支配される純戦略と純鞍点はシングル DP
/// と同じく LP の前に処理する。
///
/// 入れないもの: 状態異常、メガシンカ、ひらいしんの引きつけ、
/// こうげき以外の能力ランク変化技、設置、反動、回復、追加効果。

///|
const DOUBLE_DP_SADDLE_TOL : Double = 1.0e-10

///|
priv struct DoubleDpKey {
  p0 : Int
  p1 : Int
  p2 : Int
  p3 : Int
  h0 : Int
  h1 : Int
  h2 : Int
  h3 : Int
  o0 : Int
  o1 : Int
  o2 : Int
  o3 : Int
  s0 : Int
  s1 : Int
  s2 : Int
  s3 : Int
  u0 : Int
  u1 : Int
  u2 : Int
  u3 : Int
  k0 : Int
  k1 : Int
  k2 : Int
  k3 : Int
  e0 : Int
  e1 : Int
  e2 : Int
  e3 : Int
  turns : Int
} derive(Eq, Hash)

///|
priv struct DoubleDpSearch {
  memo : @hashmap.HashMap[DoubleDpKey, Double]
  nodes : Ref[Int]
  hits : Ref[Int]
  failed : Ref[Bool]
}

///|
fn new_dp_search() -> DoubleDpSearch {
  {
    memo: @hashmap.HashMap([]),
    nodes: { val: 0 },
    hits: { val: 0 },
    failed: { val: false },
  }
}

///|
fn at_or0(xs : Array[Int], i : Int) -> Int {
  if i >= 0 && i < xs.length() {
    xs[i]
  } else {
    0
  }
}

///|
fn dp_key_of(s : DoubleFieldHp, turns : Int) -> DoubleDpKey {
  {
    p0: at_or0(s.pos, 0),
    p1: at_or0(s.pos, 1),
    p2: at_or0(s.pos, 2),
    p3: at_or0(s.pos, 3),
    h0: at_or0(s.my_hp, 0),
    h1: at_or0(s.my_hp, 1),
    h2: at_or0(s.my_hp, 2),
    h3: at_or0(s.my_hp, 3),
    o0: at_or0(s.opp_hp, 0),
    o1: at_or0(s.opp_hp, 1),
    o2: at_or0(s.opp_hp, 2),
    o3: at_or0(s.opp_hp, 3),
    s0: at_or0(s.stall, 0),
    s1: at_or0(s.stall, 1),
    s2: at_or0(s.stall, 2),
    s3: at_or0(s.stall, 3),
    u0: at_or0(s.sw_stall, 0),
    u1: at_or0(s.sw_stall, 1),
    u2: at_or0(s.sw_stall, 2),
    u3: at_or0(s.sw_stall, 3),
    k0: pack_slot_ranks(s, 0),
    k1: pack_slot_ranks(s, 1),
    k2: pack_slot_ranks(s, 2),
    k3: pack_slot_ranks(s, 3),
    e0: at_or0(s.entered, 0),
    e1: at_or0(s.entered, 1),
    e2: at_or0(s.entered, 2),
    e3: at_or0(s.entered, 3),
    turns,
  }
}

///|
fn state_at(s : DoubleFieldHp, pos : Array[Int]) -> DoubleFieldHp {
  let next = {
    pos: copy_hp_row(pos),
    my_hp: copy_hp_row(s.my_hp),
    opp_hp: copy_hp_row(s.opp_hp),
    stall: copy_hp_row(s.stall),
    shield: copy_hp_row(s.shield),
    wide: copy_hp_row(s.wide),
    fast: copy_hp_row(s.fast),
    hand: copy_hp_row(s.hand),
    broken: copy_hp_row(s.broken),
    endure: copy_hp_row(s.endure),
    sw_stall: copy_hp_row(s.sw_stall),
    sw_held: copy_hp_row(s.sw_held),
    ranks: copy_hp_row(s.ranks),
    entered: copy_hp_row(s.entered),
    follow: copy_hp_row(s.follow),
    rage: copy_hp_row(s.rage),
    follow_at: copy_hp_row(s.follow_at),
    rage_at: copy_hp_row(s.rage_at),
    draw_clock: copy_hp_row(s.draw_clock),
  }
  let n = if pos.length() < 4 { pos.length() } else { 4 }
  for i in 0..<n {
    if at_or0(s.pos, i) != at_or0(pos, i) {
      zero_slot_ranks(next, i)
      if i < next.entered.length() {
        next.entered[i] = 1
      }
      clear_draw_slot(next, slot_of_index(i))
      if i < next.stall.length() {
        next.stall[i] = 0
      }
      if i < next.shield.length() {
        next.shield[i] = 0
      }
      if i < next.hand.length() {
        next.hand[i] = 0
      }
      if i < next.broken.length() {
        next.broken[i] = 0
      }
      if i < next.endure.length() {
        next.endure[i] = 0
      }
      if i < next.sw_stall.length() {
        next.sw_stall[i] = 0
      }
      if i < next.sw_held.length() {
        next.sw_held[i] = 0
      }
    }
  }
  next
}

///|
fn pos_same(a : Array[Int], b : Array[Int]) -> Bool {
  a.length() == b.length() &&
  at_or0(a, 0) == at_or0(b, 0) &&
  at_or0(a, 1) == at_or0(b, 1) &&
  at_or0(a, 2) == at_or0(b, 2) &&
  at_or0(a, 3) == at_or0(b, 3)
}

///|
fn living_mons(
  hps : Array[Int],
  squad : Array[Combatant],
) -> Array[Combatant] {
  let out : Array[Combatant] = []
  let n = if hps.length() < squad.length() { hps.length() } else { squad.length() }
  for i in 0..<n {
    if hps[i] > 0 {
      out.push(squad[i])
    }
  }
  out
}

///|
fn copy_pos(s : DoubleFieldHp) -> Array[Int] {
  copy_hp_row(s.pos)
}

///|
/// 補充案。各要素は適用後の `pos`。候補が無いときは現状の 1 通り。
fn replacement_positions(s : DoubleFieldHp, is_me : Bool) -> Array[Array[Int]] {
  let left_i = if is_me { 0 } else { 2 }
  let right_i = if is_me { 1 } else { 3 }
  let left_slot = acting_slot(is_me, true)
  let right_slot = acting_slot(is_me, false)
  let left_f = hp_at(s, left_slot) <= 0
  let right_f = hp_at(s, right_slot) <= 0
  let bench = living_bench_ids(s, is_me)
  if (!left_f && !right_f) || bench.length() == 0 {
    return [copy_pos(s)]
  }
  if left_f && right_f {
    if bench.length() == 1 {
      let pos = copy_pos(s)
      pos[left_i] = bench[0]
      return [pos]
    }
    let out : Array[Array[Int]] = []
    for i in 0..<bench.length() {
      for j in 0..<bench.length() {
        if i != j {
          let pos = copy_pos(s)
          pos[left_i] = bench[i]
          pos[right_i] = bench[j]
          out.push(pos)
        }
      }
    }
    if out.length() == 0 {
      [copy_pos(s)]
    } else {
      out
    }
  } else {
    let idx = if left_f { left_i } else { right_i }
    let out : Array[Array[Int]] = []
    for b in bench {
      let pos = copy_pos(s)
      pos[idx] = b
      out.push(pos)
    }
    out
  }
}

///|
fn living_bench_ids(s : DoubleFieldHp, is_me : Bool) -> Array[Int] {
  let ids = bench_squads(s, is_me)
  let hps = side_hps(s, is_me)
  let out : Array[Int] = []
  for id in ids {
    if id >= 0 && id < hps.length() && hps[id] > 0 {
      out.push(id)
    }
  }
  out
}

///|
fn merge_replacement(
  s : DoubleFieldHp,
  mine : Array[Int],
  opp : Array[Int],
) -> DoubleFieldHp {
  let pos = copy_pos(s)
  pos[0] = at_or0(mine, 0)
  pos[1] = at_or0(mine, 1)
  pos[2] = at_or0(opp, 2)
  pos[3] = at_or0(opp, 3)
  state_at(s, pos)
}

///|
fn double_slot_move(
  mon : Combatant,
  action : @doubles.DoubleAction,
) -> @model.Move? {
  match action {
    @doubles.BenchTo(_) => None
    @doubles.Use(i) =>
      if i >= 0 && i < mon.moves.length() {
        Some(mon.moves[i])
      } else {
        None
      }
    @doubles.UseOn(i, _) =>
      if i >= 0 && i < mon.moves.length() {
        Some(mon.moves[i])
      } else {
        None
      }
  }
}

///|
fn action_code_of(targets : Array[Int], action : @doubles.DoubleAction) -> Int {
  match action {
    @doubles.Use(i) => code_at(targets, i)
    @doubles.UseOn(i, _) => code_at(targets, i)
    @doubles.BenchTo(_) => -1
  }
}

///|
fn chosen_index_of(action : @doubles.DoubleAction) -> Int {
  match action {
    @doubles.UseOn(_, slot) => slot_index(slot)
    _ => -1
  }
}

///|
fn foe_only_code(code : Int) -> Bool {
  code == 0 || code == 5 || code == 9
}

///|
fn max_vs(
  cache : DoubleEvalCache,
  atk : Combatant,
  mv : @model.Move,
  foes : Array[Combatant],
  ranks : Array[Int],
) -> Int {
  let stage = stage_for_move(mv, ranks)
  let mut best = 0
  for foe in foes {
    let d = cached_move_mean(cache, atk, foe, mv, stage=stage)
    if d > best {
      best = d
    }
  }
  best
}

///|
fn damages_cover(
  cache : DoubleEvalCache,
  atk : Combatant,
  a : @model.Move,
  b : @model.Move,
  foes : Array[Combatant],
  allies : Array[Combatant],
  foe_only : Bool,
  ranks : Array[Int],
) -> Int {
  let sa = stage_for_move(a, ranks)
  let sb = stage_for_move(b, ranks)
  let mut strict = false
  for foe in foes {
    let da = cached_move_mean(cache, atk, foe, a, stage=sa)
    let db = cached_move_mean(cache, atk, foe, b, stage=sb)
    if da < db {
      return -1
    }
    if da > db {
      strict = true
    }
  }
  if !foe_only {
    for ally in allies {
      let da = cached_move_mean(cache, atk, ally, a, stage=sa)
      let db = cached_move_mean(cache, atk, ally, b, stage=sb)
      if da > db {
        return -1
      }
      if da < db {
        strict = true
      }
    }
  }
  if strict {
    1
  } else {
    0
  }
}

///|
/// 葉では劣る技と、攻撃があるときの「何もしない」を落とす。
/// まもる・てだすけ・ワイドガード・ファストガード・こらえる・サイドチェンジと、
/// このゆびとまれ・いかりのこなは葉でも残す。ダメージ比較は今の攻撃側段階で行う。
/// それ以外のターンは同じ効果の重複だけを落とす。
fn prune_slot_actions(
  cache : DoubleEvalCache,
  mon : Combatant,
  targets : Array[Int],
  actions : Array[@doubles.DoubleAction],
  foes : Array[Combatant],
  allies : Array[Combatant],
  leaf : Bool,
  ranks? : Array[Int] = [],
) -> Array[@doubles.DoubleAction] {
  let n = actions.length()
  if n == 0 {
    return actions
  }
  let drop = Array::make(n, false)
  let mut any_safe = false
  for i in 0..<n {
    match double_slot_move(mon, actions[i]) {
      None => ()
      Some(mv) =>
        if foe_only_code(action_code_of(targets, actions[i])) &&
          max_vs(cache, mon, mv, foes, ranks) > 0 {
          any_safe = true
        }
    }
  }
  let mut kept_blank = false
  for i in 0..<n {
    match actions[i] {
      @doubles.BenchTo(_) => ()
      _ =>
        match double_slot_move(mon, actions[i]) {
          None => drop[i] = true
          Some(mv) => {
            let code = action_code_of(targets, actions[i])
            let is_keep = keeps_zero_damage_move(mv.name)
            let blank = !is_keep &&
              (mv.category == @model.Status ||
                (foe_only_code(code) && max_vs(cache, mon, mv, foes, ranks) == 0))
            if blank {
              if leaf && any_safe {
                drop[i] = true
              } else if kept_blank {
                drop[i] = true
              } else {
                kept_blank = true
              }
            }
          }
        }
    }
  }
  for i in 0..<n {
    if drop[i] {
      continue
    }
    let skip = match actions[i] {
      @doubles.BenchTo(_) => true
      _ => false
    }
    if skip {
      continue
    }
    match double_slot_move(mon, actions[i]) {
      None => ()
      Some(mi) => {
        let pri_i = double_actor_priority(mon, mi)
        let code_i = action_code_of(targets, actions[i])
        let chosen_i = chosen_index_of(actions[i])
        // 味方を巻く技は、仮のダメージ比較が当たる先とずれる。
        // 同じ威力・範囲の重複だけ落とす。相手だけに当たる技は、
        // 生存している相手全員へのダメージで比較する。
        if !foe_only_code(code_i) {
          for k in 0..<i {
            if drop[k] {
              continue
            }
            match double_slot_move(mon, actions[k]) {
              None => ()
              Some(mk) =>
                if double_actor_priority(mon, mk) == pri_i &&
                  mk.accuracy == mi.accuracy &&
                  mk.power == mi.power &&
                  mk.category == mi.category &&
                  mk.type_ == mi.type_ &&
                  mk.name == mi.name &&
                  action_code_of(targets, actions[k]) == code_i &&
                  chosen_index_of(actions[k]) == chosen_i {
                  drop[i] = true
                }
            }
          }
        } else {
          for k in 0..<n {
            if k == i || drop[i] {
              continue
            }
            match double_slot_move(mon, actions[k]) {
              None => ()
              Some(mk) =>
                if double_actor_priority(mon, mk) == pri_i &&
                  mk.accuracy == mi.accuracy &&
                  action_code_of(targets, actions[k]) == code_i &&
                  chosen_index_of(actions[k]) == chosen_i {
                  let rel = damages_cover(
                    cache, mon, mk, mi, foes, allies, true, ranks,
                  )
                  if (rel == 0 && k < i) || (leaf && rel == 1) {
                    drop[i] = true
                  }
                }
            }
          }
        }
      }
    }
  }
  let out : Array[@doubles.DoubleAction] = []
  for i in 0..<n {
    if !drop[i] {
      out.push(actions[i])
    }
  }
  if out.length() == 0 {
    actions
  } else {
    out
  }
}

///|
fn raw_slot_actions(
  state : DoubleFieldHp,
  is_me : Bool,
  is_left : Bool,
  my : Array[Combatant],
  opp : Array[Combatant],
  all_targets : Array[Array[Int]],
) -> Array[@doubles.DoubleAction] {
  let slot = acting_slot(is_me, is_left)
  if hp_at(state, slot) <= 0 {
    return []
  }
  let squad = state.pos[slot_index(slot)]
  let mon = squad_mon(is_me, squad, my, opp)
  let ids = bench_squads(state, is_me)
  legal_slot_actions(
    mon,
    targets_of(all_targets, squad),
    slot,
    field_of(state),
    bench_occupants(state, is_me, ids),
  )
}

///|
fn same_bench_action(
  left : @doubles.DoubleAction?,
  right : @doubles.DoubleAction?,
) -> Bool {
  match (left, right) {
    (Some(@doubles.BenchTo(i)), Some(@doubles.BenchTo(j))) => i == j
    _ => false
  }
}

///|
fn product_joints(
  left : Array[@doubles.DoubleAction],
  right : Array[@doubles.DoubleAction],
) -> Array[@doubles.DoubleJointAction] {
  let ls : Array[@doubles.DoubleAction?] = if left.length() == 0 {
    [None]
  } else {
    let acc : Array[@doubles.DoubleAction?] = []
    for a in left {
      acc.push(Some(a))
    }
    acc
  }
  let rs : Array[@doubles.DoubleAction?] = if right.length() == 0 {
    [None]
  } else {
    let acc : Array[@doubles.DoubleAction?] = []
    for a in right {
      acc.push(Some(a))
    }
    acc
  }
  let out : Array[@doubles.DoubleJointAction] = []
  for l in ls {
    for r in rs {
      if !same_bench_action(l, r) {
        out.push({ left: l, right: r })
      }
    }
  }
  out
}

///|
fn prune_one_slot(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  is_me : Bool,
  is_left : Bool,
  actions : Array[@doubles.DoubleAction],
  my : Array[Combatant],
  opp : Array[Combatant],
  all_targets : Array[Array[Int]],
  leaf : Bool,
) -> Array[@doubles.DoubleAction] {
  let slot = acting_slot(is_me, is_left)
  if hp_at(state, slot) <= 0 {
    return actions
  }
  let squad = state.pos[slot_index(slot)]
  let mon = squad_mon(is_me, squad, my, opp)
  let foes = if is_me {
    living_mons(state.opp_hp, opp)
  } else {
    living_mons(state.my_hp, my)
  }
  let allies = if is_me {
    living_mons(state.my_hp, my)
  } else {
    living_mons(state.opp_hp, opp)
  }
  prune_slot_actions(
    cache,
    mon,
    targets_of(all_targets, squad),
    actions,
    foes,
    allies,
    leaf,
    ranks=read_ranks(state, slot_index(slot)),
  )
}

///|
/// 今の場の同時行動。スロットはグローバル座標。ひんしのスロットは `None`。
fn joints_for(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  is_me : Bool,
  leaf : Bool,
  my : Array[Combatant],
  opp : Array[Combatant],
  all_targets : Array[Array[Int]],
) -> Array[@doubles.DoubleJointAction] {
  let left_raw = raw_slot_actions(state, is_me, true, my, opp, all_targets)
  let right_raw = raw_slot_actions(state, is_me, false, my, opp, all_targets)
  let left = prune_one_slot(
    cache, state, is_me, true, left_raw, my, opp, all_targets, leaf,
  )
  let right = prune_one_slot(
    cache, state, is_me, false, right_raw, my, opp, all_targets, leaf,
  )
  product_joints(left, right)
}

///|
fn turn_after_joint(
  search : DoubleDpSearch,
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  turns_left : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  config : NashSolverConfig,
  my_left : @doubles.DoubleAction?,
  my_right : @doubles.DoubleAction?,
  opp_left : @doubles.DoubleAction?,
  opp_right : @doubles.DoubleAction?,
) -> Double {
  let my_ids = bench_squads(state, true)
  let opp_ids = bench_squads(state, false)
  let branch = copy_field(state)
  apply_snapshot_switch(branch, true, true, my_left, my_ids)
  apply_snapshot_switch(branch, true, false, my_right, my_ids)
  apply_snapshot_switch(branch, false, true, opp_left, opp_ids)
  apply_snapshot_switch(branch, false, false, opp_right, opp_ids)
  fire_entry_intimidate(branch, my, opp)
  let actors : Array[DoubleActor] = []
  push_policy_actor(actors, branch, true, true, my_left, my_targets, my, opp)
  push_policy_actor(actors, branch, true, false, my_right, my_targets, my, opp)
  push_policy_actor(actors, branch, false, true, opp_left, opp_targets, my, opp)
  push_policy_actor(actors, branch, false, false, opp_right, opp_targets, my, opp)
  let orders = action_orders(actors)
  let finish = fn(s : DoubleFieldHp) -> Double {
    if search.failed.val {
      0.0
    } else if turns_left <= 1 {
      double_terminal(s, my, opp)
    } else {
      double_dp_value(
        search,
        cache,
        copy_field(s),
        turns_left - 1,
        my,
        opp,
        my_targets,
        opp_targets,
        config,
      )
    }
  }
  if orders.length() == 0 {
    settle_double_guard(branch)
    return finish(branch)
  }
  let mut sum = 0.0
  let n = orders.length()
  for i in 0..<n {
    if search.failed.val {
      return 0.0
    }
    let b2 = copy_field(branch)
    sum = sum + eval_turn(cache, b2, orders[i], 0, [], 0, false, my, opp, finish)
  }
  sum / n.to_double()
}

///|
fn drop_dup_rows(data : Array[Array[Double]]) -> Array[Array[Double]] {
  let out : Array[Array[Double]] = []
  for row in data {
    let mut seen = false
    let mut i = 0
    while i < out.length() && !seen {
      let prev = out[i]
      if prev.length() == row.length() {
        let mut eq = true
        let mut c = 0
        while c < row.length() && eq {
          if prev[c] != row[c] {
            eq = false
          }
          c = c + 1
        }
        if eq {
          seen = true
        }
      }
      i = i + 1
    }
    if !seen {
      out.push(row)
    }
  }
  out
}

///|
fn transpose_matrix(data : Array[Array[Double]]) -> Array[Array[Double]] {
  let rows = data.length()
  let cols = if rows == 0 { 0 } else { data[0].length() }
  let out : Array[Array[Double]] = []
  for j in 0..<cols {
    let col = Array::make(rows, 0.0)
    for i in 0..<rows {
      col[i] = data[i][j]
    }
    out.push(col)
  }
  out
}

///|
fn saddle_value(data : Array[Array[Double]]) -> Double? {
  let rows = data.length()
  if rows == 0 {
    return None
  }
  let cols = data[0].length()
  if cols == 0 {
    return None
  }
  let mut lower = -2.0
  for i in 0..<rows {
    let mut row_min = 2.0
    for j in 0..<cols {
      let v = data[i][j]
      if v < row_min {
        row_min = v
      }
    }
    if row_min > lower {
      lower = row_min
    }
  }
  let mut upper = 2.0
  for j in 0..<cols {
    let mut col_max = -2.0
    for i in 0..<rows {
      let v = data[i][j]
      if v > col_max {
        col_max = v
      }
    }
    if col_max < upper {
      upper = col_max
    }
  }
  if upper - lower <= DOUBLE_DP_SADDLE_TOL {
    Some((upper + lower) / 2.0)
  } else {
    None
  }
}

///|
fn dp_nash(
  search : DoubleDpSearch,
  data : Array[Array[Double]],
  config : NashSolverConfig,
) -> Double {
  if search.failed.val {
    return 0.0
  }
  if data.length() == 0 || data[0].length() == 0 {
    return 0.0
  }
  if data.length() == 1 && data[0].length() == 1 {
    return data[0][0]
  }
  match saddle_value(data) {
    Some(v) => v
    None => {
      let slim = transpose_matrix(drop_dup_rows(transpose_matrix(drop_dup_rows(data))))
      match saddle_value(slim) {
        Some(v) => v
        None =>
          try {
            nash_value_of(slim, config)
          } catch {
            _ => {
              search.failed.val = true
              0.0
            }
          }
      }
    }
  }
}

///|
fn double_dp_actions(
  search : DoubleDpSearch,
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  turns_left : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  config : NashSolverConfig,
) -> Double {
  let leaf = turns_left <= 1
  let my_js = joints_for(cache, state, true, leaf, my, opp, my_targets)
  let opp_js = joints_for(cache, state, false, leaf, my, opp, opp_targets)
  if my_js.length() == 0 || opp_js.length() == 0 {
    return double_terminal(state, my, opp)
  }
  let data : Array[Array[Double]] = []
  for mine in my_js {
    if search.failed.val {
      return 0.0
    }
    let row = Array::make(opp_js.length(), 0.0)
    for j in 0..<opp_js.length() {
      if search.failed.val {
        return 0.0
      }
      let opp_j = opp_js[j]
      row[j] = turn_after_joint(
        search,
        cache,
        state,
        turns_left,
        my,
        opp,
        my_targets,
        opp_targets,
        config,
        mine.left,
        mine.right,
        opp_j.left,
        opp_j.right,
      )
    }
    data.push(row)
  }
  dp_nash(search, data, config)
}

///|
fn double_dp_decide(
  search : DoubleDpSearch,
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  turns_left : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  config : NashSolverConfig,
) -> Double {
  let my_plans = replacement_positions(state, true)
  let opp_plans = replacement_positions(state, false)
  if my_plans.length() <= 1 && opp_plans.length() <= 1 {
    let mine = if my_plans.length() == 1 { my_plans[0] } else { copy_pos(state) }
    let theirs = if opp_plans.length() == 1 { opp_plans[0] } else { copy_pos(state) }
    let next = merge_replacement(state, mine, theirs)
    if pos_same(next.pos, state.pos) {
      double_dp_actions(
        search, cache, state, turns_left, my, opp, my_targets, opp_targets, config,
      )
    } else {
      double_dp_value(
        search, cache, next, turns_left, my, opp, my_targets, opp_targets, config,
      )
    }
  } else {
    let data : Array[Array[Double]] = []
    for mine in my_plans {
      if search.failed.val {
        return 0.0
      }
      let row = Array::make(opp_plans.length(), 0.0)
      for j in 0..<opp_plans.length() {
        if search.failed.val {
          return 0.0
        }
        let next = merge_replacement(state, mine, opp_plans[j])
        row[j] = double_dp_value(
          search, cache, next, turns_left, my, opp, my_targets, opp_targets, config,
        )
      }
      data.push(row)
    }
    dp_nash(search, data, config)
  }
}

///|
fn double_dp_value(
  search : DoubleDpSearch,
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  turns_left : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  config : NashSolverConfig,
) -> Double {
  if search.failed.val {
    return 0.0
  }
  if !any_hp(state.my_hp) {
    return -1.0
  }
  if !any_hp(state.opp_hp) {
    return 1.0
  }
  if turns_left <= 0 {
    return double_terminal(state, my, opp)
  }
  let key = dp_key_of(state, turns_left)
  match search.memo.get(key) {
    Some(v) => {
      search.hits.val = search.hits.val + 1
      v
    }
    None => {
      search.nodes.val = search.nodes.val + 1
      let v = double_dp_decide(
        search, cache, state, turns_left, my, opp, my_targets, opp_targets, config,
      )
      if !search.failed.val {
        search.memo[key] = v
      }
      v
    }
  }
}

///|
fn dp_line_key(
  turn_limit : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
) -> String {
  "D" + turn_limit.to_string() + "#" + cell_key(my, opp, my_targets, opp_targets)
}

///|
/// 先発 4 対 4 の厳密値。`turn_limit <= 1` は段階 1 と同一経路。
fn double_dp_cell_stats(
  cache : DoubleEvalCache,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  config : NashSolverConfig,
  turn_limit : Int,
) -> (Double, Int, Int) raise NashCliError {
  if turn_limit <= 1 {
    let v = cached_lead_value(
      cache, my, opp, my_targets, opp_targets, config,
    )
    return (v, 0, 0)
  }
  let key = dp_line_key(turn_limit, my, opp, my_targets, opp_targets)
  match cache.cell.get(key) {
    Some(v) => return (v, 0, 0)
    None => ()
  }
  let rev = dp_line_key(turn_limit, opp, my, opp_targets, my_targets)
  match cache.cell.get(rev) {
    Some(v) => {
      let n = 0.0 - v
      cache.cell[key] = n
      return (n, 0, 0)
    }
    None => ()
  }
  let search = new_dp_search()
  let v = double_dp_value(
    search,
    cache,
    fresh_field(my, opp),
    turn_limit,
    my,
    opp,
    my_targets,
    opp_targets,
    config,
  )
  if search.failed.val {
    raise InvalidJson("double joint matrix was rejected")
  }
  cache.cell[key] = v
  (v, search.nodes.val, search.hits.val)
}

///|
fn double_dp_cell(
  cache : DoubleEvalCache,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  config : NashSolverConfig,
  turn_limit : Int,
) -> Double raise NashCliError {
  let (v, _, _) = double_dp_cell_stats(
    cache, my, opp, my_targets, opp_targets, config, turn_limit,
  )
  v
}
