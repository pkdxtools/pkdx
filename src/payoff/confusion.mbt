///|
/// こんらん (confusion)。major status (`StatusCondition`) とは別の揮発カウンタ。
///
/// Champions 本文 `btl_state_syn.json` `BTR_STATE_SYN_12_02`:
/// 「１ー４ターンの間 / １／３の確率で自分を攻撃する。」
/// カウンタの内部表現は本文に数値が無い。Showdown `data/conditions.ts` の
/// `confusion` (`random(2, 6)`、行動前に減算、0 なら解除して技を出す、
/// 残っていれば 1/3 で自傷して技は失敗) を採る。観測できる自傷ターンは
/// 1, 2, 3, 4 が等確率になる。
///
/// 自傷威力 40 も本文に無い。Showdown `getConfusionDamage` の base power 40、
/// タイプ無し物理、急所なし、やけどは他の payoff ダメージと同じく
/// 16 ロール平均のあと半減。
///
/// 行動前の順は Showdown の onBeforeMove 優先度: 眠り / こおり、ひるみ、
/// まひ (優先度 1)、こんらん (優先度なし = 0)。まひで動けない枝はカウンタを進めない。

///|
/// 自傷判定の確率。本文の「１／３」に合わせ、33/100 にはしない。
const CONFUSION_SELF_HIT_RATE : Double = 1.0 / 3.0

///|
/// 付与時のカウンタ。Showdown `random(2, 6)` の 2, 3, 4, 5 が等確率。
fn confusion_duration_starts() -> Array[Int] {
  [2, 3, 4, 5]
}

///|
/// 眠り / ねむる でこのターン行動できない確定の枝。こんらんカウンタは進めない
/// (Showdown は slp / frz が confusion より先。完全に眠っている間は自傷しない)。
fn confusion_held_through_sleep(status : @model.StatusCondition) -> Bool {
  match status {
    @model.Sleep(n) => n >= 2
    @model.RestSleep(n) => n > 0
    _ => false
  }
}

///|
/// マイペース / りんぷん / ミストフィールド (地上) でこんらんを受けない。
/// マイペースは `ability_ignored_by_mold_breaker` に入れない (いかく以外の
/// 既存経路を変えない)。ここだけ、攻撃側がかたやぶりのとき無効を外す。
/// りんぷんはダメージ技の追加効果だけ。ミストは `field_blocks_status` を
/// 変えず、こんらん専用に見る (本文は「状態異常」と「こんらん」を分けて書く)。
fn confusion_blocked(
  atk_ability : String,
  defender : Combatant,
  field : @model.Field,
  mv : @model.Move,
) -> Bool {
  if defender.ability == "マイペース" && !is_mold_breaker_ability(atk_ability) {
    return true
  }
  let seen = defender_ability_for_move(atk_ability, defender.ability)
  if mv.power > 0 && ability_blocks_secondary(seen) {
    return true
  }
  if field == @model.Field::Misty &&
    @damage.is_grounded(
      type1=defender.pokemon.type1,
      type2=defender.pokemon.type2,
      ability=seen,
      item=defender.item,
    ) {
    return true
  }
  false
}

///|
/// 変化技のこんらん (能力変化も状態異常も無い) が、命中抽選の前に不発になるか。
/// いばる / おだてるは能力上昇が残るので、ここでは落とさない。
fn pure_confusion_move_blocked(
  atk_ability : String,
  defender : Combatant,
  field : @model.Field,
  mv : @model.Move,
) -> Bool {
  if mv.category != @model.Status || mv.confusion_chance <= 0 {
    return false
  }
  if mv.stat_effects.length() > 0 {
    return false
  }
  match mv.status_effect {
    None => confusion_blocked(atk_ability, defender, field, mv)
    Some(_) => false
  }
}

///|
/// 付与対象の見え方。変化技はメガと Protean ロック後。ダメージ技の追加効果は
/// メガ後 (Protean の地上判定は major status と同じく未対応)。
fn confusion_holder(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  target_team : Array[Combatant],
  mv : @model.Move,
) -> Combatant {
  let combatant = target_team[target_slot]
  let target_megaed = if target_is_me {
    state.my_megaed
  } else {
    state.opp_megaed
  }
  let is_mega = target_slot < target_megaed.length() && target_megaed[target_slot]
  if mv.power <= 0 {
    let protean = if is_mega {
      ""
    } else {
      protean_locked_of(state, target_is_me, target_slot)
    }
    effective_combatant(combatant, is_mega, protean_locked=protean)
  } else {
    effective_combatant(combatant, is_mega)
  }
}

///|
fn with_confusion(
  state : SwitchingGameState,
  target_is_me : Bool,
  time : Int,
) -> SwitchingGameState {
  if target_is_me {
    if state.my_confusion == time {
      state
    } else {
      { ..state, my_confusion: time }
    }
  } else if state.opp_confusion == time {
    state
  } else {
    { ..state, opp_confusion: time }
  }
}

///|
/// こんらん付与の fanout。chance が 0、すでにこんらん、ひんし、特性 / フィールドで
/// 不発のときは同じ state を確率 1 で返す (加算順を増やさない)。
/// 成功時のカウンタは 2, 3, 4, 5 をこの順で等分する。100% 未満は
/// 「付かない」枝を先に置く。
pub fn maybe_apply_confusion_fanout(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  target_team : Array[Combatant],
  mv : @model.Move,
  hits_count? : Int = 1,
  attacker_ability? : String = "",
) -> Array[(Double, SwitchingGameState)] {
  if mv.confusion_chance <= 0 {
    return [(1.0, state)]
  }
  let target_hps = if target_is_me { state.my_hps } else { state.opp_hps }
  if target_slot < 0 || target_slot >= target_hps.length() {
    return [(1.0, state)]
  }
  if target_hps[target_slot] <= 0 {
    return [(1.0, state)]
  }
  let cur = if target_is_me { state.my_confusion } else { state.opp_confusion }
  if cur > 0 {
    return [(1.0, state)]
  }
  if target_slot >= target_team.length() {
    return [(1.0, state)]
  }
  let holder = confusion_holder(
    state, target_is_me, target_slot, target_team, mv,
  )
  if confusion_blocked(attacker_ability, holder, state.field, mv) {
    return [(1.0, state)]
  }
  let p = flinch_probability(mv.confusion_chance, hits_count)
  if p <= 0.0 {
    return [(1.0, state)]
  }
  let out : Array[(Double, SwitchingGameState)] = []
  if p < 1.0 {
    out.push((1.0 - p, state))
  }
  let share = if p >= 1.0 { 0.25 } else { p * 0.25 }
  let starts = confusion_duration_starts()
  for i = 0; i < starts.length(); i = i + 1 {
    out.push((share, with_confusion(state, target_is_me, starts[i])))
  }
  out
}

///|
/// タイプ無し物理・威力 40。STAB も相性も乗らない (`???` はタイプ表に無く、
/// Protean の STAB 押し込みは `protean_consumed=true` で止める)。
fn confusion_self_move() -> @model.Move {
  {
    name: "",
    type_: "???",
    category: @model.Physical,
    power: 40,
    accuracy: 100,
    pp: 1,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
    flinch_chance: 0,
    confusion_chance: 0,
  }
}

///|
fn rank_at(ranks : Array[Int], i : Int) -> Int {
  if i >= 0 && i < ranks.length() { ranks[i] } else { 0 }
}

///|
/// 自傷ダメージ。16 ロールの整数平均のあと、やけどなら物理半減 (`apply_burn_to_mean`)。
/// 1 ロールでも正なら最低 1。道具補正は `calc_damage` に載せたまま (いのちのたまの
/// 威力上昇は乗る。反動 10% は payoff が通常技でも別途持っていない)。
fn confusion_self_damage(
  user : Combatant,
  ranks : Array[Int],
  status : @model.StatusCondition,
  weather : @model.Weather,
  field : @model.Field,
) -> Int {
  let input = build_input_with_ranks(
    user,
    user,
    confusion_self_move(),
    rank_at(ranks, 0),
    rank_at(ranks, 1),
    weather~,
    field~,
    protean_consumed=true,
  )
  let r = @damage.calc_damage(input)
  let n = r.damages.length()
  if n == 0 || r.is_immune {
    return 0
  }
  let mut sum = 0
  let mut any = false
  for i = 0; i < n; i = i + 1 {
    let d = r.damages[i]
    sum = sum + d
    if d > 0 {
      any = true
    }
  }
  let mean = sum / n
  let burned = apply_burn_to_mean(mean, @model.Physical, is_burned(status))
  if any && burned < 1 { 1 } else if any { burned } else { 0 }
}

///|
fn ws_set_confusion(
  ws : TurnWorkspace,
  is_me : Bool,
  time : Int,
) -> TurnWorkspace {
  if is_me {
    if ws.my_confusion == time { ws } else { { ..ws, my_confusion: time } }
  } else if ws.opp_confusion == time {
    ws
  } else {
    { ..ws, opp_confusion: time }
  }
}

///|
/// 自傷で HP を減らし、オボン / フィラ / きあいのタスキは通常被弾と同じ fanout。
/// この関数は自傷枝からだけ呼ぶ。
fn confusion_self_hit_states(
  ws : TurnWorkspace,
  is_me : Bool,
  slot : Int,
  status : @model.StatusCondition,
  new_time : Int,
  team : Array[Combatant],
) -> Array[(Double, SwitchingGameState)] {
  let ws2 = ws_set_confusion(ws_with_status(ws, is_me, slot, status), is_me, new_time)
  let s0 = ws_to_state(ws2, bump_turn=false)
  let megaed = if is_me { ws.my_megaed } else { ws.opp_megaed }
  let is_mega = slot < megaed.length() && megaed[slot]
  let user = effective_combatant(team[slot], is_mega)
  let ranks = if is_me { ws.my_ranks } else { ws.opp_ranks }
  let dmg = confusion_self_damage(user, ranks, status, ws.weather, ws.field)
  let pre = if is_me { s0.my_hps[slot] } else { s0.opp_hps[slot] }
  let mut post = pre - dmg
  if post < 0 {
    post = 0
  }
  if is_me {
    s0.my_hps[slot] = post
  } else {
    s0.opp_hps[slot] = post
  }
  if post == pre {
    return [(1.0, s0)]
  }
  apply_item_post_damage_proc_fanout(
    s0, is_me, slot, team, team, pre, confusion_self_move(),
  )
}

///|
/// (確率, 行動前ステータスを解決したあとの状態, 起きていてこんらん判定に進むか)。
/// 眠ったまま / 凍ったままはこんらんを進めない。
fn confusion_awake_prefixes(
  status : @model.StatusCondition,
  thaws : Bool,
) -> Array[(Double, @model.StatusCondition, Bool)] {
  let out : Array[(Double, @model.StatusCondition, Bool)] = []
  match status {
    @model.Sleep(n) =>
      if n == 1 {
        out.push((1.0 - SLEEP_SECOND_TURN_WAKE_RATE, @model.Sleep(0), false))
        out.push((SLEEP_SECOND_TURN_WAKE_RATE, @model.None, true))
      } else {
        // Sleep(0) 以下は確定で起きる。n >= 2 は呼び出し側が除外する。
        out.push((1.0, @model.None, true))
      }
    @model.RestSleep(_) => out.push((1.0, @model.None, true))
    @model.Freeze(n) =>
      if thaws || n <= 0 {
        out.push((1.0, @model.None, true))
      } else {
        out.push((1.0 - FREEZE_THAW_RATE, @model.Freeze(n - 1), false))
        out.push((FREEZE_THAW_RATE, @model.None, true))
      }
    other => out.push((1.0, other, true))
  }
  out
}

///|
/// 行動前のこんらん。まひで動けない枝はカウンタを進めない。動けるとき
/// カウンタを 1 減らし、0 なら解除して技へ。残るなら 1/3 で自傷して技は
/// 出さない。2/3 と解除後は `per_side_attempt`。
fn resolve_while_confused(
  ws : TurnWorkspace,
  is_me : Bool,
  mv : @model.Move,
  mv_idx : Int,
  mega_now : Bool,
  def_mega_now : Bool,
  pre_state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
  foe_move : @model.Move?,
) -> Array[(Double, SwitchingGameState)] {
  let slot = if is_me { ws.my_active } else { ws.opp_active }
  let user_team = if is_me { my_team } else { opp_team }
  let status_now = if is_me { ws.my_status[slot] } else { ws.opp_status[slot] }
  let time = if is_me { ws.my_confusion } else { ws.opp_confusion }
  let thaws = freeze_move_thaws_user(pre_state, is_me, user_team, UseMove(mv_idx))
  let acc = if is_me {
    attempt_accuracy(
      pre_state, UseMove(mv_idx), true, my_team, opp_team,
      attacker_mega_trigger=mega_now, defender_mega_trigger=def_mega_now,
    )
  } else {
    attempt_accuracy(
      pre_state, UseMove(mv_idx), false, opp_team, my_team,
      attacker_mega_trigger=mega_now, defender_mega_trigger=def_mega_now,
    )
  }
  let result : Array[(Double, SwitchingGameState)] = []
  let action = UseMove(mv_idx)
  let prefixes = confusion_awake_prefixes(status_now, thaws)
  for i = 0; i < prefixes.length(); i = i + 1 {
    let (p_pre, st, awake) = prefixes[i]
    if !awake {
      let s = ws_to_state(
        ws_with_status(ws, is_me, slot, st),
        bump_turn=false,
      )
      result.push((p_pre, s))
      continue
    }
    // まひはこんらんより先。動けない枝はカウンタを進めない。
    let (p_awake, paralyzed) = match st {
      @model.Paralyze => {
        let s = ws_to_state(
          ws_with_status(ws, is_me, slot, @model.Paralyze),
          bump_turn=false,
        )
        result.push((p_pre * PARALYZE_SKIP_RATE, s))
        (p_pre * (1.0 - PARALYZE_SKIP_RATE), true)
      }
      _ => (p_pre, false)
    }
    // まひの残りは命中だけ。per_side_attempt(Paralyze) はもう一度まひを振る。
    let roll_status = if paralyzed {
      @model.StatusCondition::None
    } else {
      st
    }
    let left = time - 1
    if left <= 0 {
      push_confused_move(
        result, p_awake, ws_set_confusion(ws, is_me, 0), is_me, slot, roll_status, st,
        mv, mv_idx, mega_now, def_mega_now, my_team, opp_team, dmg_cache, foe_move,
        action, acc, user_team,
      )
    } else {
      push_confused_self_or_move(
        result, p_awake * CONFUSION_SELF_HIT_RATE, ws, is_me, slot, st, left, user_team,
      )
      push_confused_move(
        result, p_awake * (1.0 - CONFUSION_SELF_HIT_RATE),
        ws_set_confusion(ws, is_me, left), is_me, slot, roll_status, st, mv, mv_idx,
        mega_now, def_mega_now, my_team, opp_team, dmg_cache, foe_move, action, acc,
        user_team,
      )
    }
  }
  result
}

///|
fn push_confused_self_or_move(
  result : Array[(Double, SwitchingGameState)],
  prob : Double,
  ws : TurnWorkspace,
  is_me : Bool,
  slot : Int,
  status : @model.StatusCondition,
  new_time : Int,
  user_team : Array[Combatant],
) -> Unit {
  if prob <= 0.0 {
    return
  }
  let leaves = confusion_self_hit_states(ws, is_me, slot, status, new_time, user_team)
  for i = 0; i < leaves.length(); i = i + 1 {
    let (p, s) = leaves[i]
    result.push((prob * p, s))
  }
}

///|
/// こんらんを抜けた (または自傷しなかった) あとの技。まひ・命中は通常の
/// `per_side_attempt`。ステータスはすでに目覚め / 解凍済み。
fn push_confused_move(
  result : Array[(Double, SwitchingGameState)],
  prob : Double,
  ws : TurnWorkspace,
  is_me : Bool,
  slot : Int,
  roll_status : @model.StatusCondition,
  keep_status : @model.StatusCondition,
  mv : @model.Move,
  mv_idx : Int,
  mega_now : Bool,
  def_mega_now : Bool,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
  foe_move : @model.Move?,
  action : ActionKind,
  acc : Int,
  user_team : Array[Combatant],
) -> Unit {
  if prob <= 0.0 {
    return
  }
  let attempts = per_side_attempt(
    roll_status, false, action, acc, thaws_user=false,
  )
  for o in attempts {
    // まひは先に振った。命中用に None で振ったときはまひのまま書き戻す。
    let post = if roll_status == keep_status { o.post_status } else { keep_status }
    let s_o = ws_to_state(
      ws_with_status(ws, is_me, slot, post),
      bump_turn=false,
    )
    if o.acts {
      for leg in resolve_attacker_leg(
        ws_from_state(s_o), is_me, mv, mv_idx, mega_now, def_mega_now, false,
        my_team, opp_team, dmg_cache, foe_move,
      ) {
        let (p, s) = leg
        result.push((prob * o.prob * p, s))
      }
    } else {
      let s_m = if o.miss {
        with_miss_self_loss(s_o, is_me, slot, user_team, mv)
      } else {
        s_o
      }
      result.push((prob * o.prob, s_m))
    }
  }
}

///|
/// 自分がすでにこんらん、または相手の技が今ターンこんらんを付与しうるとき、
/// 試行を行動時点へ遅らせる。付与が特性 / ちからずく / フィールドで起きない
/// 相手には遅らせない (試行の位置を動かさない)。
fn confusion_roll_deferred(
  state : SwitchingGameState,
  is_me : Bool,
  action : ActionKind,
  team : Array[Combatant],
  opp_action : ActionKind,
  opp_team : Array[Combatant],
) -> Bool {
  let active = if is_me { state.my_active } else { state.opp_active }
  let recharge = if is_me {
    state.my_must_recharge[active]
  } else {
    state.opp_must_recharge[active]
  }
  let is_move = match action {
    UseMove(_) | Mega(_) => true
    Switch(_) => false
  }
  if !is_move || recharge {
    return false
  }
  let ctime = if is_me { state.my_confusion } else { state.opp_confusion }
  if ctime > 0 {
    return true
  }
  let opp_is_move = match opp_action {
    UseMove(_) | Mega(_) => true
    Switch(_) => false
  }
  if !opp_is_move {
    return false
  }
  let opp_active = if is_me { state.opp_active } else { state.my_active }
  match action_move_of(opp_team, opp_active, opp_action) {
    None => false
    Some(mv) => {
      if mv.confusion_chance <= 0 {
        return false
      }
      let atk_megaed = if is_me { state.opp_megaed } else { state.my_megaed }
      let atk_mega = opp_active < atk_megaed.length() && atk_megaed[opp_active]
      let atk = effective_combatant(opp_team[opp_active], atk_mega)
      if mv.power > 0 && ability_strips_secondaries(atk.ability) {
        return false
      }
      let def_megaed = if is_me { state.my_megaed } else { state.opp_megaed }
      let def_mega = active < def_megaed.length() && def_megaed[active]
      let protean = if def_mega {
        ""
      } else {
        protean_locked_of(state, is_me, active)
      }
      let def = if mv.power <= 0 {
        effective_combatant(team[active], def_mega, protean_locked=protean)
      } else {
        effective_combatant(team[active], def_mega)
      }
      !confusion_blocked(atk.ability, def, state.field, mv)
    }
  }
}

///|
/// 交代した側のカウンタを 0 にする。攻撃より前の状態に使う。
/// 交代していない側はそのまま。どちらも 0 のままなら呼び出し側は元の値を使う。
fn confusion_after_switch(state : SwitchingGameState, action : ActionKind, mine : Bool) -> Int {
  let cur = if mine { state.my_confusion } else { state.opp_confusion }
  match action {
    Switch(_) => 0
    _ => cur
  }
}

///|
fn confusion_berry_item(item : String) -> Bool {
  item == "キーのみ" || item == "ラムのみ"
}

///|
/// ターン終了に キーのみ / ラムのみ でこんらんだけ解く。ラムは major status を
/// 治さない (それを入れるとこんらんしていない入力の EOT が変わる)。
/// どちらもこんらんでなければ同じ state を返す。
fn cure_confusion_berries(
  state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> SwitchingGameState {
  if state.my_confusion <= 0 && state.opp_confusion <= 0 {
    return state
  }
  cure_confusion_berry_side(
    cure_confusion_berry_side(state, true, my_team),
    false,
    opp_team,
  )
}

///|
fn cure_confusion_berry_side(
  state : SwitchingGameState,
  is_me : Bool,
  team : Array[Combatant],
) -> SwitchingGameState {
  let time = if is_me { state.my_confusion } else { state.opp_confusion }
  if time <= 0 {
    return state
  }
  let slot = if is_me { state.my_active } else { state.opp_active }
  let consumed = if is_me { state.my_item_consumed } else { state.opp_item_consumed }
  if slot < 0 || slot >= team.length() || slot >= consumed.length() || consumed[slot] {
    return state
  }
  let megaed = if is_me { state.my_megaed } else { state.opp_megaed }
  let is_mega = slot < megaed.length() && megaed[slot]
  let item = effective_combatant(team[slot], is_mega).item
  if !confusion_berry_item(item) {
    return state
  }
  let next = consumed.copy()
  next[slot] = true
  if is_me {
    { ..state, my_confusion: 0, my_item_consumed: next }
  } else {
    { ..state, opp_confusion: 0, opp_item_consumed: next }
  }
}

///|
/// MC: こんらん付与。chance が 0 のときは乱数を引かず `cur` を返す。
fn mc_apply_confusion(
  rng : @random.Rand,
  mv : @model.Move,
  defender : Combatant,
  defender_hp : Int,
  cur : Int,
  field : @model.Field,
  immune : Bool,
  hp_lost : Int,
  attacker_ability : String,
  defender_protean : String,
) -> Int {
  if mv.confusion_chance <= 0 || immune || cur > 0 || defender_hp <= 0 {
    return cur
  }
  if mv.power > 0 && (hp_lost <= 0 || ability_strips_secondaries(attacker_ability)) {
    return cur
  }
  let holder = if mv.power <= 0 {
    effective_combatant(defender, false, protean_locked=defender_protean)
  } else {
    defender
  }
  if confusion_blocked(attacker_ability, holder, field, mv) {
    return cur
  }
  if !rand_bool(rng, flinch_probability(mv.confusion_chance, 1)) {
    return cur
  }
  // 2, 3, 4, 5 の一様。
  rng.int(limit=4) + 2
}

///|
/// MC の行動前こんらん。戻り値は (状態, 行動するか, 外れたか, 新しいカウンタ, 自傷したか)。
/// 眠り / こおりで止まったときはカウンタを進めない。
fn mc_resolve_confused(
  rng : @random.Rand,
  status : @model.StatusCondition,
  mv_acc : Int,
  thaws_user : Bool,
  time : Int,
) -> (@model.StatusCondition, Bool, Bool, Int, Bool) {
  match status {
    @model.Freeze(n) =>
      if !thaws_user && n >= 1 && !rand_bool(rng, FREEZE_THAW_RATE) {
        return (@model.Freeze(n - 1), false, false, time, false)
      }
    @model.Sleep(n) =>
      if n >= 2 {
        return (@model.Sleep(n - 1), false, false, time, false)
      } else if n == 1 && !rand_bool(rng, SLEEP_SECOND_TURN_WAKE_RATE) {
        return (@model.Sleep(0), false, false, time, false)
      }
    @model.RestSleep(n) =>
      if n > 0 {
        return (@model.RestSleep(n - 1), false, false, time, false)
      }
    _ => ()
  }
  // まひはこんらんより先。動けなければカウンタは進まない。
  let paralyzed = match status {
    @model.Paralyze => true
    _ => false
  }
  if paralyzed && rand_bool(rng, PARALYZE_SKIP_RATE) {
    return (@model.Paralyze, false, false, time, false)
  }
  let awake = if paralyzed {
    @model.StatusCondition::None
  } else {
    match status {
      @model.Burn => @model.Burn
      @model.Poison => @model.Poison
      @model.BadPoison(n) => @model.BadPoison(n)
      @model.Drowsy(n) => @model.Drowsy(n)
      _ => @model.StatusCondition::None
    }
  }
  let left = time - 1
  if left <= 0 {
    let (st, acts, missed) = mc_resolve_attempt(
      awake, mv_acc, rng, thaws_user=false,
    )
    let kept = if paralyzed { @model.Paralyze } else { st }
    return (kept, acts, missed, 0, false)
  }
  let self_status = if paralyzed { @model.Paralyze } else { awake }
  if rand_bool(rng, CONFUSION_SELF_HIT_RATE) {
    return (self_status, false, false, left, true)
  }
  let (st, acts, missed) = mc_resolve_attempt(awake, mv_acc, rng, thaws_user=false)
  let kept = if paralyzed { @model.Paralyze } else { st }
  (kept, acts, missed, left, false)
}

///|
/// MC の自傷。HP とピンチきのみ / きあいのタスキだけ更新する。
fn mc_apply_confusion_self_hit(
  hps : Array[Int],
  slot : Int,
  user : Combatant,
  ranks : Array[Int],
  status : @model.StatusCondition,
  weather : @model.Weather,
  field : @model.Field,
  item_consumed : Array[Bool],
) -> Unit {
  if slot < 0 || slot >= hps.length() {
    return
  }
  let dmg = confusion_self_damage(user, ranks, status, weather, field)
  let pre = hps[slot]
  let mut post = pre - dmg
  if post < 0 {
    post = 0
  }
  let consumed = slot < item_consumed.length() && item_consumed[slot]
  let item = if consumed { "" } else { user.item }
  let max_hp = user.pokemon.hp
  if item == "きあいのタスキ" && pre == max_hp && post <= 0 {
    hps[slot] = 1
    if slot < item_consumed.length() {
      item_consumed[slot] = true
    }
    return
  }
  let denom = match item {
    "フィラのみ" => 3
    "オボンのみ" => 4
    _ => 0
  }
  if denom > 0 && post > 0 && pre * 2 > max_hp && post * 2 <= max_hp {
    let healed = post + max_hp / denom
    hps[slot] = if healed > max_hp { max_hp } else { healed }
    if slot < item_consumed.length() {
      item_consumed[slot] = true
    }
    return
  }
  hps[slot] = post
}

///|
/// MC のターン終了。こんらんのときだけ キーのみ / ラムのみ を消費して 0 を返す。
fn mc_cure_confusion_berry(
  team : Array[Combatant],
  active : Int,
  item_consumed : Array[Bool],
  confusion : Int,
) -> Int {
  if confusion <= 0 {
    return confusion
  }
  if active < 0 || active >= team.length() || active >= item_consumed.length() {
    return confusion
  }
  if item_consumed[active] || !confusion_berry_item(team[active].item) {
    return confusion
  }
  item_consumed[active] = true
  0
}

///|
/// 相手の技が今ターンこんらんを付与しうるか。付与できない相手には試行を遅らせない。
fn mc_confusion_can_land(
  mv : @model.Move,
  attacker : Combatant,
  defender : Combatant,
  field : @model.Field,
  defender_protean : String,
) -> Bool {
  if mv.confusion_chance <= 0 {
    return false
  }
  if mv.power > 0 && ability_strips_secondaries(attacker.ability) {
    return false
  }
  let holder = if mv.power <= 0 {
    effective_combatant(defender, false, protean_locked=defender_protean)
  } else {
    defender
  }
  !confusion_blocked(attacker.ability, holder, field, mv)
}
