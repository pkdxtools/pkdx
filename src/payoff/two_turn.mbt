///|
/// 2ターン技 (champout `50e7233`)。
///
/// ため (BTR_STATE_SYN_114 Charging): 1 ターンためて、次のターンに攻撃する。
/// 姿を消すのは次の状態だけ。
/// - Sky-High (115): そらをとぶ / とびはねる。かみなり・ぼうふう・うちおとすだけ当たる。
/// - Underground (117): あなをほる。じしんが当たり、威力 2 倍。
/// - Submerged (116): ダイビング。なみのり・うずしおが当たり、威力 2 倍。
/// - Concealed (118): ゴーストダイブ。姿隠し中は技が当たらない。
///   解放は守るを解除して当たる (`protect.mbt`)。
///
/// 天候でためない (wazainfo):
/// - ソーラービーム / ソーラーブレード + はれ: そのターンに撃つ。
/// - エレクトロビーム + あめ: そのターンに撃つ。
/// ソーラービーム / ソーラーブレードは、はれ以外の天候 (あめ・すなあらし・ゆき) で威力半減。
/// 天候なしは半減しない (Showdown `onBasePower`。champout は「other weather」とだけ書く)。
///
/// ためたターンの特攻 +1 (そのターンに撃ったとき。解放ターンでは上げない):
/// メテオビーム、エレクトロビーム。あまのじゃくは符号を反転する。
///
/// ロック中に選べるのはその技だけ (交代はひんしのときだけ)。行動不能・交代・
/// 外れた解放ではロックを外す。パワフルハーブは itemname に無いので扱わない。
/// 反動 (Recharging) は既存の `must_recharge`。ここには入れない。

priv enum TwoTurnPhase {
  TtNormal
  TtCharge
  TtRelease
  TtImmediate
}

priv enum TwoTurnGate {
  TwoTurnStop(SwitchingGameState)
  TwoTurnGo(SwitchingGameState)
}

///|
fn is_two_turn_name(name : String) -> Bool {
  name == "ソーラービーム" ||
  name == "ソーラーブレード" ||
  name == "ゴッドバード" ||
  name == "メテオビーム" ||
  name == "エレクトロビーム" ||
  name == "そらをとぶ" ||
  name == "とびはねる" ||
  name == "あなをほる" ||
  name == "ダイビング" ||
  name == "ゴーストダイブ"
}

///|
fn two_turn_boosts_spa(name : String) -> Bool {
  name == "メテオビーム" || name == "エレクトロビーム"
}

///|
fn two_turn_weather_skips(name : String, weather : @model.Weather) -> Bool {
  match weather {
    @model.Sun => name == "ソーラービーム" || name == "ソーラーブレード"
    @model.Rain => name == "エレクトロビーム"
    _ => false
  }
}

///|
fn two_turn_phase(
  name : String,
  weather : @model.Weather,
  lock : Int,
  mv_idx : Int,
) -> TwoTurnPhase {
  if !is_two_turn_name(name) {
    TtNormal
  } else if lock >= 0 && lock == mv_idx {
    TtRelease
  } else if two_turn_weather_skips(name, weather) {
    TtImmediate
  } else {
    TtCharge
  }
}

///|
fn two_turn_is_charging(
  name : String,
  weather : @model.Weather,
  lock : Int,
  mv_idx : Int,
) -> Bool {
  match two_turn_phase(name, weather, lock, mv_idx) {
    TtCharge => true
    _ => false
  }
}

/// 姿を消している技名。溜めていない、または姿を消さないため技なら ""。
fn charged_vanish_name(
  team : Array[Combatant],
  slot : Int,
  lock : Int,
) -> String {
  if lock < 0 || slot < 0 || slot >= team.length() {
    return ""
  }
  let moves = team[slot].moves
  if lock >= moves.length() {
    return ""
  }
  let name = moves[lock].name
  if name == "そらをとぶ" ||
    name == "とびはねる" ||
    name == "あなをほる" ||
    name == "ダイビング" ||
    name == "ゴーストダイブ" {
    name
  } else {
    ""
  }
}

///|
fn two_turn_hits(move_name : String, vanished : String) -> Bool {
  if vanished == "" {
    true
  } else if vanished == "そらをとぶ" || vanished == "とびはねる" {
    move_name == "かみなり" || move_name == "ぼうふう" || move_name == "うちおとす"
  } else if vanished == "あなをほる" {
    move_name == "じしん"
  } else if vanished == "ダイビング" {
    move_name == "なみのり" || move_name == "うずしお"
  } else {
    false
  }
}

/// 4096 は無補正。2048 は半減、8192 は 2 倍。4096 のときは呼び出し側が丸めない。
fn two_turn_power_mod(
  move_name : String,
  weather : @model.Weather,
  vanished : String,
) -> Int {
  if (move_name == "ソーラービーム" || move_name == "ソーラーブレード") &&
    (weather == @model.Rain || weather == @model.Sand || weather == @model.Snow) {
    2048
  } else if move_name == "じしん" && vanished == "あなをほる" {
    8192
  } else if (move_name == "なみのり" || move_name == "うずしお") &&
    vanished == "ダイビング" {
    8192
  } else {
    4096
  }
}

///|
fn scale_two_turn_outcomes(
  outcomes : Array[@model.DamageOutcome],
  move_name : String,
  weather : @model.Weather,
  vanished : String,
) -> Array[@model.DamageOutcome] {
  let m = two_turn_power_mod(move_name, weather, vanished)
  if m == 4096 {
    return outcomes
  }
  let out : Array[@model.DamageOutcome] = []
  for o in outcomes {
    out.push({ ..o, mean_damage: @damage.round5(o.mean_damage, m) })
  }
  out
}

///|
fn with_two_turn_lock(
  state : SwitchingGameState,
  is_me : Bool,
  v : Int,
) -> SwitchingGameState {
  if is_me {
    if state.my_two_turn == v {
      state
    } else {
      { ..state, my_two_turn: v }
    }
  } else if state.opp_two_turn == v {
    state
  } else {
    { ..state, opp_two_turn: v }
  }
}

///|
fn with_spa_boost_state(
  state : SwitchingGameState,
  is_me : Bool,
  attacker : Combatant,
  attacker_mega : Bool,
  move_name : String,
) -> SwitchingGameState {
  if !two_turn_boosts_spa(move_name) {
    return state
  }
  let ability = effective_combatant(attacker, attacker_mega).ability
  let ranks = if is_me { state.my_ranks } else { state.opp_ranks }
  if ranks.length() <= 2 {
    return state
  }
  let delta = if ability_reverses_stat_changes(ability) { -1 } else { 1 }
  let next_rank = clamp_rank_for(ability, ranks[2] + delta)
  if next_rank == ranks[2] {
    return state
  }
  let next = ranks.copy()
  next[2] = next_rank
  if is_me {
    { ..state, my_ranks: next }
  } else {
    { ..state, opp_ranks: next }
  }
}

/// 交代+技 / 片側行動の攻撃。`TwoTurnGo` の中身は、通常技なら引数と同じ参照。
fn gate_two_turn_attack(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  defender_slot : Int,
  mv : @model.Move,
  mv_idx : Int,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  attacker_mega : Bool,
  attacker_lock : Int,
  defender_lock : Int,
) -> TwoTurnGate {
  let phase = two_turn_phase(mv.name, state.weather, attacker_lock, mv_idx)
  let vanished = charged_vanish_name(defender_team, defender_slot, defender_lock)
  let miss = vanished != "" && !two_turn_hits(mv.name, vanished)
  let attacker = attacker_team[attacker_slot]
  match phase {
    TtNormal =>
      if miss {
        TwoTurnStop(state)
      } else {
        TwoTurnGo(state)
      }
    TtCharge =>
      TwoTurnStop(
        with_two_turn_lock(
          with_spa_boost_state(
            state, attacker_is_me, attacker, attacker_mega, mv.name,
          ),
          attacker_is_me,
          mv_idx,
        ),
      )
    TtRelease => {
      let cleared = with_two_turn_lock(state, attacker_is_me, -1)
      if miss {
        TwoTurnStop(cleared)
      } else {
        TwoTurnGo(cleared)
      }
    }
    TtImmediate => {
      let boosted = with_spa_boost_state(
        state, attacker_is_me, attacker, attacker_mega, mv.name,
      )
      if miss {
        TwoTurnStop(boosted)
      } else {
        TwoTurnGo(boosted)
      }
    }
  }
}

///|
fn with_ws_lock(ws : TurnWorkspace, is_me : Bool, v : Int) -> TurnWorkspace {
  if is_me {
    if ws.my_two_turn == v {
      ws
    } else {
      { ..ws, my_two_turn: v }
    }
  } else if ws.opp_two_turn == v {
    ws
  } else {
    { ..ws, opp_two_turn: v }
  }
}

///|
fn boost_ws_spa(
  ws : TurnWorkspace,
  is_me : Bool,
  attacker : Combatant,
  attacker_mega : Bool,
  move_name : String,
) -> Unit {
  if !two_turn_boosts_spa(move_name) {
    return
  }
  let ability = effective_combatant(attacker, attacker_mega).ability
  let ranks = if is_me { ws.my_ranks } else { ws.opp_ranks }
  if ranks.length() <= 2 {
    return
  }
  let delta = if ability_reverses_stat_changes(ability) { -1 } else { 1 }
  ranks[2] = clamp_rank_for(ability, ranks[2] + delta)
}

/// 通常技は引数の workspace をそのまま返す。phase は更新前のもの。
fn apply_two_turn_to_ws(
  ws : TurnWorkspace,
  attacker_is_me : Bool,
  mv : @model.Move,
  mv_idx : Int,
  attacker : Combatant,
  attacker_mega : Bool,
) -> (TurnWorkspace, TwoTurnPhase) {
  let lock = if attacker_is_me { ws.my_two_turn } else { ws.opp_two_turn }
  let phase = two_turn_phase(mv.name, ws.weather, lock, mv_idx)
  match phase {
    TtNormal => (ws, phase)
    TtCharge => {
      boost_ws_spa(ws, attacker_is_me, attacker, attacker_mega, mv.name)
      (with_ws_lock(ws, attacker_is_me, mv_idx), phase)
    }
    TtRelease => (with_ws_lock(ws, attacker_is_me, -1), phase)
    TtImmediate => {
      boost_ws_spa(ws, attacker_is_me, attacker, attacker_mega, mv.name)
      (ws, phase)
    }
  }
}

/// ターン開始時に溜めていて、解決後も同じ値なら外す。
/// 両方 -1 で始まったターンは引数をそのまま返す (新規の溜めは残す)。
fn settle_interrupted_two_turn(
  state : SwitchingGameState,
  start_my : Int,
  start_opp : Int,
) -> SwitchingGameState {
  if start_my < 0 && start_opp < 0 {
    return state
  }
  let my = if start_my >= 0 && state.my_two_turn == start_my {
    -1
  } else {
    state.my_two_turn
  }
  let opp = if start_opp >= 0 && state.opp_two_turn == start_opp {
    -1
  } else {
    state.opp_two_turn
  }
  if my == state.my_two_turn && opp == state.opp_two_turn {
    state
  } else {
    { ..state, my_two_turn: my, opp_two_turn: opp }
  }
}

///|
fn mc_note_two_turn(
  buf : Array[Int],
  move_name : String,
  weather : @model.Weather,
  lock : Int,
  mv_idx : Int,
  atk_ranks : Array[Int],
  ability : String,
) -> Bool {
  let phase = two_turn_phase(move_name, weather, lock, mv_idx)
  match phase {
    TtCharge => {
      if two_turn_boosts_spa(move_name) && atk_ranks.length() > 2 {
        let delta = if ability_reverses_stat_changes(ability) { -1 } else { 1 }
        atk_ranks[2] = clamp_rank_for(ability, atk_ranks[2] + delta)
      }
      if buf.length() > 0 {
        buf[0] = mv_idx
      }
      true
    }
    TtRelease => {
      if buf.length() > 0 {
        buf[0] = -1
      }
      false
    }
    TtImmediate => {
      if two_turn_boosts_spa(move_name) && atk_ranks.length() > 2 {
        let delta = if ability_reverses_stat_changes(ability) { -1 } else { 1 }
        atk_ranks[2] = clamp_rank_for(ability, atk_ranks[2] + delta)
      }
      if buf.length() > 0 {
        buf[0] = -1
      }
      false
    }
    TtNormal => false
  }
}
