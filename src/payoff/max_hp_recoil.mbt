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
