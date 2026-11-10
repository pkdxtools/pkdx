///|
/// 最大 HP の 1/2 反動 (てっていこうせん = Showdown `mindBlownRecoil`)。
///
/// 使用者の HP 消費量は Showdown `sim/battle-actions.ts` `applyRecoilDamage` の
/// `Math.round(pokemon.maxhp / 2)` (非負整数では ceil(maxhp / 2) と一致、丸め
/// 方向は切り上げ)。`clampIntRange` の下限 1 は maxhp >= 1 で常に満たされる。
///
/// 発動条件 (`triggered`) は呼び出し側が決める:
/// - 命中: 実ダメージ > 0 (`totalDamage` が真のときのみ反動。Disguise が初撃を
///   吸収して 0 ダメージの leg は発動しない)。
/// - 外れ / 免疫 (`MoveFail`): 対象が生存していること (対象不在なら
///   `battle-actions.ts` の `!target` / `!targets.length` で早期 return し
///   `MoveFail` に届かない)。
/// Protect 系はモデルしていない (payoff 層に Protect 無し)。
///
/// マジックガード: 技以外のダメージを受けない (Champions `tokuseiinfo_syn.json:3442`)。
/// Showdown でも `magicguard.onDamage` が `effect.effectType !== 'Move'` を弾く
/// (`steelbeam` の condition は `effectType: 'Condition'`) ので反動も無効。
///
/// ひんし: 反動で HP が 0 になれば使用者は倒れる (呼び出し側で clamp)。
pub fn max_hp_recoil_loss(
  mv : @model.Move,
  user_ability : String,
  user_max_hp : Int,
  triggered : Bool,
) -> Int {
  if !triggered || user_max_hp <= 0 || !@damage.is_max_hp_recoil_move(mv.name) {
    return 0
  }
  if user_ability == "マジックガード" {
    return 0
  }
  (user_max_hp + 1) / 2
}

///|
/// DP: 使用者 (`attacker_is_me` の `attacker_slot`) に最大 HP の 1/2 反動を適用する。
/// 反動量が 0 のときは入力 state をそのまま返す (no-Steel-Beam 経路は bit-exact)。
fn with_max_hp_recoil(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  attacker_team : Array[Combatant],
  mv : @model.Move,
  triggered : Bool,
) -> SwitchingGameState {
  if !triggered ||
    !@damage.is_max_hp_recoil_move(mv.name) ||
    attacker_slot < 0 ||
    attacker_slot >= attacker_team.length() {
    return state
  }
  // mega 後の実効特性 / 実効最大 HP で判定する (Showdown は mega 後の maxhp を使う)。
  let atk_megaed = if attacker_is_me {
    state.my_megaed
  } else {
    state.opp_megaed
  }
  let atk_is_mega = attacker_slot < atk_megaed.length() &&
    atk_megaed[attacker_slot]
  let eff = effective_combatant(attacker_team[attacker_slot], atk_is_mega)
  let loss = max_hp_recoil_loss(mv, eff.ability, effective_hp(eff), triggered)
  if loss <= 0 {
    return state
  }
  let hps = if attacker_is_me {
    state.my_hps.copy()
  } else {
    state.opp_hps.copy()
  }
  if attacker_slot >= hps.length() {
    return state
  }
  hps[attacker_slot] = clamp_zero(hps[attacker_slot] - loss)
  if attacker_is_me {
    { ..state, my_hps: hps }
  } else {
    { ..state, opp_hps: hps }
  }
}

///|
/// MC: 使用者 HP 配列 `attacker_hps[attacker_active]` に最大 HP の 1/2 反動を
/// in-place で適用する (MC は mega を未モデルなので raw combatant を読む)。
fn team_apply_max_hp_recoil(
  attacker_hps : Array[Int],
  attacker_active : Int,
  attacker_team : Array[Combatant],
  mv : @model.Move,
  triggered : Bool,
) -> Unit {
  if !triggered ||
    !@damage.is_max_hp_recoil_move(mv.name) ||
    attacker_active < 0 ||
    attacker_active >= attacker_team.length() ||
    attacker_active >= attacker_hps.length() {
    return
  }
  let attacker_c = attacker_team[attacker_active]
  let loss = max_hp_recoil_loss(
    mv,
    attacker_c.ability,
    effective_hp(attacker_c),
    triggered,
  )
  if loss > 0 {
    attacker_hps[attacker_active] = clamp_zero(
      attacker_hps[attacker_active] - loss,
    )
  }
}

///|
/// `SideAttempt.missed` が立ち、かつその技が最大 HP 反動技なら、その技の `Move` を返す。
/// 外れた leg (accuracy miss) だけが対象で、麻痺 / 睡眠による不発は含まない。
fn miss_recoil_move_of(
  attempt : SideAttempt,
  team : Array[Combatant],
  active : Int,
) -> @model.Move? {
  if !attempt.missed || active < 0 || active >= team.length() {
    return None
  }
  match attempt.action {
    UseMove(mi) | Mega(mi) =>
      if mi >= 0 && mi < team[active].moves.length() {
        let mv = team[active].moves[mi]
        if @damage.is_max_hp_recoil_move(mv.name) {
          Some(mv)
        } else {
          None
        }
      } else {
        None
      }
    Switch(_) => None
  }
}

///|
/// 外れた最大 HP 反動技が (どちらかの側に) あるか。true のときだけ
/// `attempt_with_miss_recoil` を通し、それ以外の経路は既存のコードをそのまま使う。
fn has_miss_recoil(
  pre_state : SwitchingGameState,
  ma : SideAttempt,
  oa : SideAttempt,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> Bool {
  match miss_recoil_move_of(ma, my_team, pre_state.my_active) {
    Some(_) => return true
    None => ()
  }
  match miss_recoil_move_of(oa, opp_team, pre_state.opp_active) {
    Some(_) => true
    None => false
  }
}

///|
/// UseMove / Mega の技を返す。Switch や範囲外の添字は None。
fn attempt_move_of(
  team : Array[Combatant],
  active : Int,
  action : ActionKind,
) -> @model.Move? {
  match action {
    UseMove(mi) | Mega(mi) =>
      if active >= 0 &&
        active < team.length() &&
        mi >= 0 &&
        mi < team[active].moves.length() {
        Some(team[active].moves[mi])
      } else {
        None
      }
    Switch(_) => None
  }
}

///|
/// 両 leg の行動順 (`move_turn_sign` と同じ符号)。正: 自分が先、負: 相手が先、0: 同速。
/// 交代は技より常に先 (Showdown の行動順)。
fn miss_leg_order(
  pre_state : SwitchingGameState,
  ma : SideAttempt,
  oa : SideAttempt,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> Int {
  match oa.action {
    Switch(_) => return -1
    _ => ()
  }
  match ma.action {
    Switch(_) => return 1
    _ => ()
  }
  let my_mv = match attempt_move_of(my_team, pre_state.my_active, ma.action) {
    Some(mv) => mv
    None => return 0
  }
  let opp_mv = match attempt_move_of(opp_team, pre_state.opp_active, oa.action) {
    Some(mv) => mv
    None => return 0
  }
  let my_mega = match ma.action {
    Mega(_) => true
    _ => false
  }
  let opp_mega = match oa.action {
    Mega(_) => true
    _ => false
  }
  move_turn_sign(
    my_team[pre_state.my_active],
    pre_state.my_ranks,
    my_mv,
    my_mega,
    is_paralyzed(pre_state.my_status[pre_state.my_active]),
    opp_team[pre_state.opp_active],
    pre_state.opp_ranks,
    opp_mv,
    opp_mega,
    is_paralyzed(pre_state.opp_status[pre_state.opp_active]),
  )
}

///|
/// `attempt_turn_with_cache` の (acts, acts) 分岐を、外れた最大 HP 反動技の leg を
/// 行動順の位置に挿入して解決する。片側が行動した場合は `partial_act_outcomes`、
/// 両側とも行動しなかった場合は `pass_turn_state` で閉じる (ターン加算は各経路が
/// 1 回だけ行うため、反動 leg 自体はターンを進めない)。
///
/// 同速 (order = 0) は `transition_with_cache` と同じく両順序を 0.5 ずつ平均する。
fn attempt_with_miss_recoil(
  pre_state : SwitchingGameState,
  ma : SideAttempt,
  oa : SideAttempt,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
) -> Array[(Double, SwitchingGameState)] {
  // 自分側の leg: 行動 / 外れ反動 / 不発 (麻痺・睡眠) のいずれか。
  let leg_me = fn(s : SwitchingGameState) -> Array[(Double, SwitchingGameState)] {
    if ma.acts {
      partial_act_outcomes(s, ma.action, true, my_team, opp_team, dmg_cache)
    } else {
      match miss_recoil_move_of(ma, my_team, s.my_active) {
        Some(mv) => {
          let defender_alive = s.opp_hps[s.opp_active] > 0
          [
            (
              1.0,
              with_max_hp_recoil(
                s, true, s.my_active, my_team, mv, defender_alive,
              ),
            ),
          ]
        }
        None => [(1.0, s)]
      }
    }
  }
  let leg_opp = fn(s : SwitchingGameState) -> Array[(Double, SwitchingGameState)] {
    if oa.acts {
      partial_act_outcomes(s, oa.action, false, my_team, opp_team, dmg_cache)
    } else {
      match miss_recoil_move_of(oa, opp_team, s.opp_active) {
        Some(mv) => {
          let defender_alive = s.my_hps[s.my_active] > 0
          [
            (
              1.0,
              with_max_hp_recoil(
                s, false, s.opp_active, opp_team, mv, defender_alive,
              ),
            ),
          ]
        }
        None => [(1.0, s)]
      }
    }
  }
  let run = fn(me_first : Bool) -> Array[(Double, SwitchingGameState)] {
    let outs : Array[(Double, SwitchingGameState)] = []
    if me_first {
      for first in leg_me(pre_state) {
        for second in leg_opp(first.1) {
          outs.push((first.0 * second.0, second.1))
        }
      }
    } else {
      for first in leg_opp(pre_state) {
        for second in leg_me(first.1) {
          outs.push((first.0 * second.0, second.1))
        }
      }
    }
    outs
  }
  let order = miss_leg_order(pre_state, ma, oa, my_team, opp_team)
  let raw : Array[(Double, SwitchingGameState)] = []
  if order > 0 {
    for x in run(true) {
      raw.push(x)
    }
  } else if order < 0 {
    for x in run(false) {
      raw.push(x)
    }
  } else {
    for x in run(true) {
      raw.push((0.5 * x.0, x.1))
    }
    for x in run(false) {
      raw.push((0.5 * x.0, x.1))
    }
  }
  if ma.acts || oa.acts {
    return raw
  }
  // 両側とも行動しなかった: `pass_turn_state` と同じく状態遷移 (ターン +1 と
  // 後状態の上書き) で閉じる。
  let closed : Array[(Double, SwitchingGameState)] = []
  for x in raw {
    closed.push((x.0, pass_turn_state(x.1, ma.post_status, oa.post_status)))
  }
  closed
}
