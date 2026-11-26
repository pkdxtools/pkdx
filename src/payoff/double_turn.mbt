///|
/// ダブルの 1 ターン評価。シングルの `SwitchingGameState` / `transition_with_cache`
/// / `build_input_with_ranks` は使わない。
///
/// 解決順: 交代を先に行い、その後に技を優先度の高い順、同優先度は素早さの速い順。
/// 優先度はターン開始時の `effective_priority`（いたずらごころ / はやてのつばさ）。
/// 素早さはランク 0 の `effective_speed` に、未消費のこだわりスカーフを掛けた値。
/// まひ・ランク・メガは入れない。同優先度かつ同素早さは、シングルが 2 者の両順序を
/// 0.5 ずつ平均するのと同じく、その同速グループの全順列を等確率で平均する。
/// 値は状態ではなく終端値の平均。
///
/// ダメージは `build_input_with_ranks` の結果に `is_double: true` だけを足して
/// `calc_damage` し、16 ロールと連続技 variant はシングルと同じ
/// `weighted_mean_floor` で 1 つの整数にする。命中は `accuracy/100` でその整数を
/// 入れる枝と 0 の枝に分け、終端値を確率で平均する（ダメージに命中率を掛けて
/// から 1 回引くのではない）。
///
/// target 0 で選んだ相手がすでにひんしのときは、生きている相手が 1 体ならそこへ
/// 振り替える。champout `50e7233` の `wazatarget.json` / `btl_target_select.json`
/// は範囲の名前だけで、ひんし時の振り替え文は無い。Showdown `Battle#getTarget` /
/// `getRandomTarget`（doubles は `randomFoe`）に合わせる。相手が残っていなければ
/// 当たらない。target 1 で味方がひんしのときは自分へ（Showdown、Gen5 以外）。
/// target 2 / 14 のひんしの味方へは振り替えない。
///
/// 終端はシングルの turn_limit 終端と同じ式。片方の 4 体が全員ひんしなら ±1。
/// そうでなければ `(my_ratio - opp_ratio) / 2` を [-1, 1] に収める。分母は
/// `pokemon.hp`。この経路は 1 ターンでその終端を返す。`eval_turn` の終端関数は
/// ここへ HP 比を渡す。`double_rollout` は同じ解決のあと、その状態から
/// ロールアウトした値を渡す。終端関数は HP を書き換えない。
///
/// 入れないもの: 状態異常、設置、メガ、ばけのかわ、反動、自滅、回復、追加効果、
/// てだすけ、ワイドガード、このゆびとまれ、いかく。L2 ディスクには書かない。

///|
priv struct DoubleActor {
  is_me : Bool
  squad : Int
  slot : @doubles.DoubleSlot
  move_idx : Int
  target_code : Int
  chosen : @doubles.DoubleSlot?
  priority : Int
  speed : Int
}

///|
priv struct DoubleFieldHp {
  pos : Array[Int]
  my_hp : Array[Int]
  opp_hp : Array[Int]
}

///|
///|
/// ダメージ平均のキャッシュキー。文字列を連結せず、既存の文字列参照と
/// 数値だけを持つ。`double_move_mean` が読む項目に揃える。
priv struct DoubleMeanKey {
  atk_name : String
  atk_t1 : String
  atk_t2 : String
  atk_hp : Int
  atk_atk : Int
  atk_def : Int
  atk_spa : Int
  atk_spd : Int
  atk_spe : Int
  atk_weight : Double
  atk_ability : String
  atk_item : String
  atk_tera : String
  atk_sys : Int
  atk_nature : String
  atk_s0 : Int
  atk_s1 : Int
  atk_s2 : Int
  atk_s3 : Int
  atk_s4 : Int
  atk_s5 : Int
  def_name : String
  def_t1 : String
  def_t2 : String
  def_hp : Int
  def_atk : Int
  def_def : Int
  def_spa : Int
  def_spd : Int
  def_spe : Int
  def_weight : Double
  def_ability : String
  def_item : String
  def_tera : String
  def_sys : Int
  def_nature : String
  def_s0 : Int
  def_s1 : Int
  def_s2 : Int
  def_s3 : Int
  def_s4 : Int
  def_s5 : Int
  mv_name : String
  mv_type : String
  mv_cat : Int
  mv_power : Int
  mv_acc : Int
  mv_pri : Int
} derive(Eq, Hash)

///|
priv struct DoubleEvalCache {
  dmg : @hashmap.HashMap[DoubleMeanKey, Int]
  cell : @hashmap.HashMap[String, Double]
}

///|
priv enum DoubleStrike {
  All(Array[@doubles.DoubleSlot])
  OneOf(Array[@doubles.DoubleSlot])
  Miss
}

///|
fn new_double_eval() -> DoubleEvalCache {
  { dmg: @hashmap.HashMap([]), cell: @hashmap.HashMap([]) }
}

///|
fn copy_hp_row(xs : Array[Int]) -> Array[Int] {
  let out = Array::make(xs.length(), 0)
  for i in 0..<xs.length() {
    out[i] = xs[i]
  }
  out
}

///|
fn copy_field(s : DoubleFieldHp) -> DoubleFieldHp {
  { pos: copy_hp_row(s.pos), my_hp: copy_hp_row(s.my_hp), opp_hp: copy_hp_row(s.opp_hp) }
}

///|
fn slot_index(slot : @doubles.DoubleSlot) -> Int {
  match slot {
    @doubles.MyLeft => 0
    @doubles.MyRight => 1
    @doubles.FoeLeft => 2
    @doubles.FoeRight => 3
  }
}

///|
fn slot_is_mine(slot : @doubles.DoubleSlot) -> Bool {
  match slot {
    @doubles.MyLeft => true
    @doubles.MyRight => true
    @doubles.FoeLeft => false
    @doubles.FoeRight => false
  }
}

///|
fn flip_slot(slot : @doubles.DoubleSlot) -> @doubles.DoubleSlot {
  match slot {
    @doubles.MyLeft => @doubles.FoeLeft
    @doubles.MyRight => @doubles.FoeRight
    @doubles.FoeLeft => @doubles.MyLeft
    @doubles.FoeRight => @doubles.MyRight
  }
}

///|
fn foe_slots(actor : @doubles.DoubleSlot) -> Array[@doubles.DoubleSlot] {
  if slot_is_mine(actor) {
    [@doubles.FoeLeft, @doubles.FoeRight]
  } else {
    [@doubles.MyLeft, @doubles.MyRight]
  }
}

///|
fn hp_at(s : DoubleFieldHp, slot : @doubles.DoubleSlot) -> Int {
  let squad = s.pos[slot_index(slot)]
  if slot_is_mine(slot) {
    s.my_hp[squad]
  } else {
    s.opp_hp[squad]
  }
}

///|
fn set_hp(s : DoubleFieldHp, slot : @doubles.DoubleSlot, hp : Int) -> Unit {
  let squad = s.pos[slot_index(slot)]
  let next = if hp > 0 { hp } else { 0 }
  if slot_is_mine(slot) {
    s.my_hp[squad] = next
  } else {
    s.opp_hp[squad] = next
  }
}

///|
fn occupant_at(s : DoubleFieldHp, slot : @doubles.DoubleSlot) -> @doubles.DoubleOccupant {
  if hp_at(s, slot) > 0 {
    @doubles.Alive
  } else {
    @doubles.Fainted
  }
}

///|
fn field_of(s : DoubleFieldHp) -> @doubles.DoubleField {
  {
    my_left: occupant_at(s, @doubles.MyLeft),
    my_right: occupant_at(s, @doubles.MyRight),
    foe_left: occupant_at(s, @doubles.FoeLeft),
    foe_right: occupant_at(s, @doubles.FoeRight),
  }
}

///|
fn any_hp(hps : Array[Int]) -> Bool {
  for hp in hps {
    if hp > 0 {
      return true
    }
  }
  false
}

///|
fn side_ratio(hps : Array[Int], squad : Array[Combatant]) -> Double {
  let n = hps.length()
  if n == 0 {
    return 0.0
  }
  let mut total = 0.0
  for i in 0..<n {
    let max_hp = squad[i].pokemon.hp
    if max_hp > 0 {
      let cur = if hps[i] > 0 { hps[i] } else { 0 }
      total = total + cur.to_double() / max_hp.to_double()
    }
  }
  total / n.to_double()
}

///|
/// シングル `terminal_value` の turn_limit 終端と同じ式。
fn double_terminal(
  s : DoubleFieldHp,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Double {
  if !any_hp(s.my_hp) {
    return -1.0
  }
  if !any_hp(s.opp_hp) {
    return 1.0
  }
  let delta = (side_ratio(s.my_hp, my) - side_ratio(s.opp_hp, opp)) / 2.0
  if delta > 1.0 {
    1.0
  } else if delta < -1.0 {
    -1.0
  } else {
    delta
  }
}

///|
fn mon_cache_key(c : Combatant, targets : Array[Int]) -> String {
  let sys = match c.stat_system {
    @model.Champions => "C"
    @model.Standard => "S"
  }
  let nature = match c.nature {
    Some(n) => n.name_ja
    None => ""
  }
  let mut stats = ""
  match c.actual_stats {
    Some(arr) =>
      for i in 0..<arr.length() {
        stats = stats + arr[i].to_string() + "."
      }
    None => ()
  }
  let mut s = c.pokemon.name_ja +
    "," +
    c.pokemon.type1 +
    "," +
    c.pokemon.type2 +
    "," +
    c.pokemon.hp.to_string() +
    "," +
    c.pokemon.atk.to_string() +
    "," +
    c.pokemon.def_.to_string() +
    "," +
    c.pokemon.spa.to_string() +
    "," +
    c.pokemon.spd.to_string() +
    "," +
    c.pokemon.spe.to_string() +
    "," +
    c.ability +
    "," +
    c.item +
    "," +
    c.tera_type +
    "," +
    sys +
    "," +
    nature +
    "," +
    stats
  let n = c.moves.length()
  for i in 0..<n {
    let m = c.moves[i]
    let t = if i < targets.length() { targets[i] } else { -1 }
    let cat = match m.category {
      @model.Physical => "p"
      @model.Special => "s"
      @model.Status => "z"
    }
    s = s +
      "|" +
      m.name +
      ":" +
      cat +
      ":" +
      m.type_ +
      ":" +
      m.power.to_string() +
      ":" +
      m.accuracy.to_string() +
      ":" +
      m.priority.to_string() +
      ":" +
      t.to_string()
  }
  s
}

///|
fn stat_at(c : Combatant, i : Int) -> Int {
  match c.actual_stats {
    Some(arr) => if i < arr.length() { arr[i] } else { -1 }
    None => -1
  }
}

///|
fn sys_id(c : Combatant) -> Int {
  match c.stat_system {
    @model.Champions => 1
    @model.Standard => 0
  }
}

///|
fn nature_id(c : Combatant) -> String {
  match c.nature {
    Some(n) => n.name_ja
    None => ""
  }
}

///|
fn cat_id(mv : @model.Move) -> Int {
  match mv.category {
    @model.Physical => 0
    @model.Special => 1
    @model.Status => 2
  }
}

///|
fn mean_cache_key(atk : Combatant, def : Combatant, mv : @model.Move) -> DoubleMeanKey {
  let ap = atk.pokemon
  let dp = def.pokemon
  {
    atk_name: ap.name_ja,
    atk_t1: ap.type1,
    atk_t2: ap.type2,
    atk_hp: ap.hp,
    atk_atk: ap.atk,
    atk_def: ap.def_,
    atk_spa: ap.spa,
    atk_spd: ap.spd,
    atk_spe: ap.spe,
    atk_weight: ap.weight,
    atk_ability: atk.ability,
    atk_item: atk.item,
    atk_tera: atk.tera_type,
    atk_sys: sys_id(atk),
    atk_nature: nature_id(atk),
    atk_s0: stat_at(atk, 0),
    atk_s1: stat_at(atk, 1),
    atk_s2: stat_at(atk, 2),
    atk_s3: stat_at(atk, 3),
    atk_s4: stat_at(atk, 4),
    atk_s5: stat_at(atk, 5),
    def_name: dp.name_ja,
    def_t1: dp.type1,
    def_t2: dp.type2,
    def_hp: dp.hp,
    def_atk: dp.atk,
    def_def: dp.def_,
    def_spa: dp.spa,
    def_spd: dp.spd,
    def_spe: dp.spe,
    def_weight: dp.weight,
    def_ability: def.ability,
    def_item: def.item,
    def_tera: def.tera_type,
    def_sys: sys_id(def),
    def_nature: nature_id(def),
    def_s0: stat_at(def, 0),
    def_s1: stat_at(def, 1),
    def_s2: stat_at(def, 2),
    def_s3: stat_at(def, 3),
    def_s4: stat_at(def, 4),
    def_s5: stat_at(def, 5),
    mv_name: mv.name,
    mv_type: mv.type_,
    mv_cat: cat_id(mv),
    mv_power: mv.power,
    mv_acc: mv.accuracy,
    mv_pri: mv.priority,
  }
}

///|
/// ダブルの整数期待ダメージ。`is_double: true` 以外はシングルの
/// `build_input_with_ranks` と同じ入力。変化技は 0。
fn double_move_mean(atk : Combatant, def : Combatant, mv : @model.Move) -> Int {
  if mv.category == @model.Status {
    return 0
  }
  let input = { ..build_input_with_ranks(atk, def, mv, 0, 0), is_double: true }
  let r = @damage.calc_damage(input)
  if r.is_immune {
    return 0
  }
  weighted_mean_floor(outcomes_from_calc_result(r, mv.category, false))
}

///|
fn cached_move_mean(
  cache : DoubleEvalCache,
  atk : Combatant,
  def : Combatant,
  mv : @model.Move,
) -> Int {
  let key = mean_cache_key(atk, def, mv)
  match cache.dmg.get(key) {
    Some(v) => v
    None => {
      let v = double_move_mean(atk, def, mv)
      cache.dmg[key] = v
      v
    }
  }
}

///|
fn squad_mon(
  is_me : Bool,
  squad : Int,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Combatant {
  if is_me {
    my[squad]
  } else {
    opp[squad]
  }
}

///|
fn double_actor_speed(c : Combatant) -> Int {
  let staged = effective_speed(c.pokemon.spe, 0)
  speed_after_choice_scarf(staged, c.item, false)
}

///|
fn double_actor_priority(c : Combatant, mv : @model.Move) -> Int {
  effective_priority(c.ability, mv, c.pokemon.hp, c.pokemon.hp)
}

///|
fn living_slots(
  s : DoubleFieldHp,
  slots : Array[@doubles.DoubleSlot],
) -> Array[@doubles.DoubleSlot] {
  let out : Array[@doubles.DoubleSlot] = []
  for slot in slots {
    if hp_at(s, slot) > 0 {
      out.push(slot)
    }
  }
  out
}

///|
/// target 0 / 1 のひんし振り替え。根拠はファイル先頭。
fn redirect_fainted(
  s : DoubleFieldHp,
  actor : @doubles.DoubleSlot,
  target_code : Int,
) -> Array[@doubles.DoubleSlot] {
  if target_code == 0 {
    let living = living_slots(s, foe_slots(actor))
    if living.length() == 1 {
      [living[0]]
    } else {
      []
    }
  } else if target_code == 1 {
    if hp_at(s, actor) > 0 {
      [actor]
    } else {
      []
    }
  } else {
    []
  }
}

///|
fn strike_plan(
  s : DoubleFieldHp,
  actor : DoubleActor,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> DoubleStrike {
  let mon = squad_mon(actor.is_me, actor.squad, my, opp)
  if actor.move_idx < 0 || actor.move_idx >= mon.moves.length() {
    return Miss
  }
  let mv = mon.moves[actor.move_idx]
  let resolved = @doubles.double_slots_hit(
    0,
    actor.target_code,
    actor.slot,
    actor.chosen,
    field_of(s),
    false,
    name=mv.name,
  )
  match resolved {
    @doubles.Struck(slots) => All(slots)
    @doubles.RandomOne(cands) => OneOf(cands)
    @doubles.Battlefield(_) => Miss
    @doubles.NoStrike => {
      let slots = redirect_fainted(s, actor.slot, actor.target_code)
      if slots.length() == 0 {
        Miss
      } else {
        All(slots)
      }
    }
  }
}

///|
fn defender_of(
  s : DoubleFieldHp,
  slot : @doubles.DoubleSlot,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Combatant {
  let squad = s.pos[slot_index(slot)]
  if slot_is_mine(slot) {
    my[squad]
  } else {
    opp[squad]
  }
}

///|
fn apply_hit(
  cache : DoubleEvalCache,
  s : DoubleFieldHp,
  actor : DoubleActor,
  target : @doubles.DoubleSlot,
  my : Array[Combatant],
  opp : Array[Combatant],
) -> Unit {
  if hp_at(s, target) <= 0 {
    return
  }
  let atk = squad_mon(actor.is_me, actor.squad, my, opp)
  if actor.move_idx < 0 || actor.move_idx >= atk.moves.length() {
    return
  }
  let mv = atk.moves[actor.move_idx]
  let def = defender_of(s, target, my, opp)
  let dmg = cached_move_mean(cache, atk, def, mv)
  set_hp(s, target, hp_at(s, target) - dmg)
}

///|
fn hit_probability(accuracy : Int) -> Double {
  if accuracy <= 0 {
    0.0
  } else if accuracy >= 100 {
    1.0
  } else {
    accuracy.to_double() / 100.0
  }
}

///|
/// 1 ターンの技を優先度と素早さの順に解決し、動き終わった状態を `finish` に渡す。
/// 命中と対象ランダムと同速は、状態ではなく `finish` の値を確率で平均する。
fn eval_turn(
  cache : DoubleEvalCache,
  state : DoubleFieldHp,
  actors : Array[DoubleActor],
  actor_idx : Int,
  pending : Array[@doubles.DoubleSlot],
  hit_idx : Int,
  in_hits : Bool,
  my : Array[Combatant],
  opp : Array[Combatant],
  finish : (DoubleFieldHp) -> Double,
) -> Double {
  if in_hits {
    if hit_idx >= pending.length() {
      return eval_turn(
        cache, state, actors, actor_idx + 1, [], 0, false, my, opp, finish,
      )
    }
    let actor = actors[actor_idx]
    let mon = squad_mon(actor.is_me, actor.squad, my, opp)
    let acc = if actor.move_idx >= 0 && actor.move_idx < mon.moves.length() {
      mon.moves[actor.move_idx].accuracy
    } else {
      100
    }
    let p = hit_probability(acc)
    let target = pending[hit_idx]
    if p >= 1.0 {
      apply_hit(cache, state, actor, target, my, opp)
      return eval_turn(
        cache, state, actors, actor_idx, pending, hit_idx + 1, true, my, opp, finish,
      )
    }
    if p <= 0.0 {
      return eval_turn(
        cache, state, actors, actor_idx, pending, hit_idx + 1, true, my, opp, finish,
      )
    }
    let hit_state = copy_field(state)
    apply_hit(cache, hit_state, actor, target, my, opp)
    let v_hit = eval_turn(
      cache, hit_state, actors, actor_idx, pending, hit_idx + 1, true, my, opp, finish,
    )
    let v_miss = eval_turn(
      cache, state, actors, actor_idx, pending, hit_idx + 1, true, my, opp, finish,
    )
    return p * v_hit + (1.0 - p) * v_miss
  }
  if actor_idx >= actors.length() {
    return finish(state)
  }
  let actor = actors[actor_idx]
  if hp_at(state, actor.slot) <= 0 {
    return eval_turn(
      cache, state, actors, actor_idx + 1, [], 0, false, my, opp, finish,
    )
  }
  match strike_plan(state, actor, my, opp) {
    Miss =>
      eval_turn(
        cache, state, actors, actor_idx + 1, [], 0, false, my, opp, finish,
      )
    All(slots) =>
      eval_turn(
        cache, state, actors, actor_idx, slots, 0, true, my, opp, finish,
      )
    OneOf(cands) => {
      let n = cands.length()
      if n == 0 {
        eval_turn(
          cache, state, actors, actor_idx + 1, [], 0, false, my, opp, finish,
        )
      } else {
        let p = 1.0 / n.to_double()
        let mut acc = 0.0
        for c in cands {
          let branch = copy_field(state)
          let one : Array[@doubles.DoubleSlot] = [c]
          acc = acc +
            p *
            eval_turn(
              cache, branch, actors, actor_idx, one, 0, true, my, opp, finish,
            )
        }
        acc
      }
    }
  }
}

///|
fn acts_before(a : DoubleActor, b : DoubleActor) -> Bool {
  if a.priority != b.priority {
    a.priority > b.priority
  } else {
    a.speed > b.speed
  }
}

///|
fn same_turn_key(a : DoubleActor, b : DoubleActor) -> Bool {
  a.priority == b.priority && a.speed == b.speed
}

///|
fn sort_actors(xs : Array[DoubleActor]) -> Array[DoubleActor] {
  let mut out : Array[DoubleActor] = []
  for a in xs {
    let mut i = 0
    while i < out.length() && acts_before(out[i], a) {
      i = i + 1
    }
    let next : Array[DoubleActor] = []
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
fn perm_actors(xs : Array[DoubleActor]) -> Array[Array[DoubleActor]] {
  if xs.length() == 0 {
    return [[]]
  }
  let out : Array[Array[DoubleActor]] = []
  for i in 0..<xs.length() {
    let rest : Array[DoubleActor] = []
    for j in 0..<xs.length() {
      if j != i {
        rest.push(xs[j])
      }
    }
    let tails = perm_actors(rest)
    for tail in tails {
      let one : Array[DoubleActor] = [xs[i]]
      for t in tail {
        one.push(t)
      }
      out.push(one)
    }
  }
  out
}

///|
fn tie_groups(sorted : Array[DoubleActor]) -> Array[Array[DoubleActor]] {
  let groups : Array[Array[DoubleActor]] = []
  let mut i = 0
  while i < sorted.length() {
    let mut j = i + 1
    while j < sorted.length() && same_turn_key(sorted[i], sorted[j]) {
      j = j + 1
    }
    let g : Array[DoubleActor] = []
    for k in i..<j {
      g.push(sorted[k])
    }
    groups.push(g)
    i = j
  }
  groups
}

///|
fn expand_orders(groups : Array[Array[DoubleActor]]) -> Array[Array[DoubleActor]] {
  let mut acc : Array[Array[DoubleActor]] = [[]]
  for g in groups {
    let ps = perm_actors(g)
    let next : Array[Array[DoubleActor]] = []
    for prefix in acc {
      for p in ps {
        let row : Array[DoubleActor] = []
        for a in prefix {
          row.push(a)
        }
        for a in p {
          row.push(a)
        }
        next.push(row)
      }
    }
    acc = next
  }
  acc
}

///|
fn action_orders(actors : Array[DoubleActor]) -> Array[Array[DoubleActor]] {
  expand_orders(tie_groups(sort_actors(actors)))
}

///|
fn push_mover(
  out : Array[DoubleActor],
  is_me : Bool,
  is_left : Bool,
  action : @doubles.DoubleAction?,
  squad : Array[Combatant],
  targets : Array[Array[Int]],
) -> Unit {
  let squad_idx = if is_left { 0 } else { 1 }
  let slot = if is_me {
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
  let (move_idx, chosen) = match action {
    Some(@doubles.Use(i)) => (i, None)
    Some(@doubles.UseOn(i, chosen_slot)) => (i, Some(chosen_slot))
    _ => (-1, None)
  }
  if move_idx < 0 {
    return
  }
  let mon = squad[squad_idx]
  if move_idx >= mon.moves.length() {
    return
  }
  let code = if move_idx < targets[squad_idx].length() {
    targets[squad_idx][move_idx]
  } else {
    0
  }
  let mv = mon.moves[move_idx]
  out.push({
    is_me,
    squad: squad_idx,
    slot,
    move_idx,
    target_code: code,
    chosen,
    priority: double_actor_priority(mon, mv),
    speed: double_actor_speed(mon),
  })
}

///|
fn apply_switch(
  s : DoubleFieldHp,
  is_me : Bool,
  is_left : Bool,
  action : @doubles.DoubleAction?,
) -> Unit {
  match action {
    Some(@doubles.BenchTo(i)) => {
      let squad = 2 + i
      let idx = if is_me {
        if is_left { 0 } else { 1 }
      } else if is_left {
        2
      } else {
        3
      }
      s.pos[idx] = squad
    }
    _ => ()
  }
}

///|
fn fresh_field(my : Array[Combatant], opp : Array[Combatant]) -> DoubleFieldHp {
  let my_hp = Array::make(my.length(), 0)
  let opp_hp = Array::make(opp.length(), 0)
  for i in 0..<my.length() {
    my_hp[i] = my[i].pokemon.hp
  }
  for i in 0..<opp.length() {
    opp_hp[i] = opp[i].pokemon.hp
  }
  { pos: [0, 1, 0, 1], my_hp, opp_hp }
}

///|
fn scripted_value_and_hp(
  cache : DoubleEvalCache,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  my_left : @doubles.DoubleAction?,
  my_right : @doubles.DoubleAction?,
  opp_left : @doubles.DoubleAction?,
  opp_right : @doubles.DoubleAction?,
) -> (Double, Array[Int], Array[Int]) {
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
    let v = double_terminal(state, my, opp)
    return (v, copy_hp_row(state.my_hp), copy_hp_row(state.opp_hp))
  }
  let mut sum = 0.0
  let mut first_my = copy_hp_row(state.my_hp)
  let mut first_opp = copy_hp_row(state.opp_hp)
  for i in 0..<orders.length() {
    let branch = copy_field(state)
    let v = eval_turn(
      cache, branch, orders[i], 0, [], 0, false, my, opp,
      fn(s) { double_terminal(s, my, opp) },
    )
    if i == 0 {
      first_my = copy_hp_row(branch.my_hp)
      first_opp = copy_hp_row(branch.opp_hp)
    }
    sum = sum + v
  }
  (sum / orders.length().to_double(), first_my, first_opp)
}

///|
fn active_from(
  mon : Combatant,
  targets : Array[Int],
  alive : Bool,
) -> @doubles.DoubleActive {
  let moves : Array[@doubles.DoubleMoveSpec] = []
  for i in 0..<mon.moves.length() {
    let code = if i < targets.length() { targets[i] } else { 0 }
    moves.push({ id: 0, name: mon.moves[i].name, target: code })
  }
  let occ = if alive { @doubles.Alive } else { @doubles.Fainted }
  { occupant: occ, moves }
}

///|
fn side_joints(
  left : Combatant,
  right : Combatant,
  left_targets : Array[Int],
  right_targets : Array[Int],
) -> Array[@doubles.DoubleJointAction] {
  @doubles.double_joint_actions(
    active_from(left, left_targets, true),
    active_from(right, right_targets, true),
    [@doubles.Alive, @doubles.Alive],
    @doubles.Alive,
    @doubles.Alive,
    false,
  )
}

///|
fn translate_action(action : @doubles.DoubleAction?) -> @doubles.DoubleAction? {
  match action {
    None => None
    Some(@doubles.Use(i)) => Some(@doubles.Use(i))
    Some(@doubles.BenchTo(i)) => Some(@doubles.BenchTo(i))
    Some(@doubles.UseOn(i, slot)) => Some(@doubles.UseOn(i, flip_slot(slot)))
  }
}

///|
fn translate_joint(j : @doubles.DoubleJointAction) -> @doubles.DoubleJointAction {
  { left: translate_action(j.left), right: translate_action(j.right) }
}

///|
fn matrix_is_constant(data : Array[Array[Double]]) -> Double? {
  if data.length() == 0 || data[0].length() == 0 {
    return None
  }
  let v = data[0][0]
  for row in data {
    for x in row {
      if x != v {
        return None
      }
    }
  }
  Some(v)
}

///|
fn row_dominated(data : Array[Array[Double]], i : Int) -> Bool {
  let cols = data[i].length()
  for k in 0..<data.length() {
    if k == i {
      continue
    }
    let mut ge_all = true
    let mut gt_one = false
    let mut c = 0
    while c < cols && ge_all {
      if data[k][c] < data[i][c] {
        ge_all = false
      } else if data[k][c] > data[i][c] {
        gt_one = true
      }
      c = c + 1
    }
    if ge_all && gt_one {
      return true
    }
  }
  false
}

///|
fn col_dominated(data : Array[Array[Double]], j : Int) -> Bool {
  let rows = data.length()
  let cols = data[0].length()
  for k in 0..<cols {
    if k == j {
      continue
    }
    let mut le_all = true
    let mut lt_one = false
    let mut r = 0
    while r < rows && le_all {
      if data[r][k] > data[r][j] {
        le_all = false
      } else if data[r][k] < data[r][j] {
        lt_one = true
      }
      r = r + 1
    }
    if le_all && lt_one {
      return true
    }
  }
  false
}

///|
fn project_matrix(
  data : Array[Array[Double]],
  rows : Array[Int],
  cols : Array[Int],
) -> Array[Array[Double]] {
  let out : Array[Array[Double]] = []
  for r in rows {
    let row = Array::make(cols.length(), 0.0)
    for c in 0..<cols.length() {
      row[c] = data[r][cols[c]]
    }
    out.push(row)
  }
  out
}

///|
/// 厳密に支配される純戦略を落とす。零和の値は変わらない。
fn eliminate_dominated(data : Array[Array[Double]]) -> Array[Array[Double]] {
  let mut cur = data
  let mut changed = true
  while changed {
    changed = false
    if cur.length() == 0 || cur[0].length() == 0 {
      return data
    }
    let keep_r : Array[Int] = []
    for i in 0..<cur.length() {
      if !row_dominated(cur, i) {
        keep_r.push(i)
      }
    }
    let keep_c : Array[Int] = []
    for j in 0..<cur[0].length() {
      if !col_dominated(cur, j) {
        keep_c.push(j)
      }
    }
    if keep_r.length() == 0 || keep_c.length() == 0 {
      return data
    }
    if keep_r.length() != cur.length() || keep_c.length() != cur[0].length() {
      cur = project_matrix(cur, keep_r, keep_c)
      changed = true
    }
  }
  cur
}

///|
fn nash_value_of(
  data : Array[Array[Double]],
  config : NashSolverConfig,
) -> Double raise NashCliError {
  match matrix_is_constant(data) {
    Some(v) => v
    None => {
      let reduced = eliminate_dominated(data)
      match matrix_is_constant(reduced) {
        Some(v) => v
        None =>
          match @nash.FiniteMatrix::new(reduced) {
            Err(_) => raise InvalidJson("double joint matrix was rejected")
            Ok(m) => solve_with_fallback(m, config~).value
          }
      }
    }
  }
}

///|
fn joint_matrix_value(
  cache : DoubleEvalCache,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  config : NashSolverConfig,
) -> Double raise NashCliError {
  if my.length() < 4 || opp.length() < 4 {
    raise InvalidJson("double turn expects 4 pokemon on each side")
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
      let (v, _, _) = scripted_value_and_hp(
        cache,
        my,
        opp,
        my_targets,
        opp_targets,
        mine.left,
        mine.right,
        opp_j.left,
        opp_j.right,
      )
      row[j] = v
    }
    data.push(row)
  }
  nash_value_of(data, config)
}

///|
fn cell_key(
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
) -> String {
  let mut s = "M"
  for i in 0..<my.length() {
    s = s + "#" + mon_cache_key(my[i], my_targets[i])
  }
  s = s + "#O"
  for i in 0..<opp.length() {
    s = s + "#" + mon_cache_key(opp[i], opp_targets[i])
  }
  s
}

///|
fn cached_lead_value(
  cache : DoubleEvalCache,
  my : Array[Combatant],
  opp : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  config : NashSolverConfig,
) -> Double raise NashCliError {
  let key = cell_key(my, opp, my_targets, opp_targets)
  match cache.cell.get(key) {
    Some(v) => v
    None => {
      let v = joint_matrix_value(
        cache, my, opp, my_targets, opp_targets, config,
      )
      cache.cell[key] = v
      v
    }
  }
}

///|
fn take4(
  team : Array[Combatant],
  targets : Array[Array[Int]],
  bring : @doubles.DoubleBring,
) -> (Array[Combatant], Array[Array[Int]]) raise NashCliError {
  let idx = [bring.leads.0, bring.leads.1, bring.bench.0, bring.bench.1]
  let mons : Array[Combatant] = []
  let ts : Array[Array[Int]] = []
  for i in idx {
    if i < 0 || i >= team.length() || i >= targets.length() {
      raise InvalidJson("double bring index out of range")
    }
    mons.push(team[i])
    ts.push(targets[i])
  }
  (mons, ts)
}

///|
/// `format=double` の選出利得。行も列も `double_brings`（6 体なら 90）。
fn double_selection_matrix(
  team : Array[Combatant],
  opponent : Array[Combatant],
  my_targets : Array[Array[Int]],
  opp_targets : Array[Array[Int]],
  mode : DoubleTurnMode,
  config : NashSolverConfig,
) -> @nash.FiniteMatrix raise NashCliError {
  if my_targets.length() != team.length() ||
    opp_targets.length() != opponent.length() {
    raise InvalidJson("double move targets must align with team members")
  }
  let brings = @doubles.double_brings(team.length())
  let n = brings.length()
  if n == 0 {
    raise InvalidJson("double_brings is empty")
  }
  let cache = new_double_eval()
  let data : Array[Array[Double]] = []
  match mode {
    AllTargets =>
      for i in 0..<n {
        let (my_sq, my_tg) = take4(team, my_targets, brings[i])
        let row = Array::make(n, 0.0)
        for j in 0..<n {
          let (op_sq, op_tg) = take4(opponent, opp_targets, brings[j])
          row[j] = cached_lead_value(cache, my_sq, op_sq, my_tg, op_tg, config)
        }
        data.push(row)
      }
    Rollout(trials, seed, turn_limit) => {
      let rng = seeded_rng(seed)
      for i in 0..<n {
        let (my_sq, my_tg) = take4(team, my_targets, brings[i])
        let row = Array::make(n, 0.0)
        for j in 0..<n {
          let (op_sq, op_tg) = take4(opponent, opp_targets, brings[j])
          row[j] = double_joint_rollout_value(
            cache,
            my_sq,
            op_sq,
            my_tg,
            op_tg,
            config,
            rng,
            trials,
            turn_limit,
            default_rollout_epsilon,
          )
        }
        data.push(row)
      }
    }
    Exact(turn_limit) =>
      for i in 0..<n {
        let (my_sq, my_tg) = take4(team, my_targets, brings[i])
        let row = Array::make(n, 0.0)
        for j in 0..<n {
          let (op_sq, op_tg) = take4(opponent, opp_targets, brings[j])
          row[j] = double_dp_cell(
            cache, my_sq, op_sq, my_tg, op_tg, config, turn_limit,
          )
        }
        data.push(row)
      }
  }
  match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise InvalidJson("double selection matrix was rejected")
  }
}
