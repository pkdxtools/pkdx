///|
/// 設置技 (champout `50e7233`、`waza.json` `available = 1` だけ)。
///
/// 張る (`target = 11`、命中 101):
/// - ステルスロック (`WAZAINFO_SYN_446` / `help` ステルスロック状態):
///   交代時に最大 HP の 1/8。いわ相性で倍率が変わる。
/// - まきびし (`_191`): 1 層は 1/8。2 層・3 層は本文が「増える」とだけ書く。
///   層数の上限は 3 (`help` 「２ー３回」)。倍率は Showdown `spikes` の
///   3/24, 4/24, 6/24 (= 1/8, 1/6, 1/4)。
/// - どくびし (`_390`): 1 層でどく、2 層でもうどく。どくタイプの登場で消える。
///   はがねはどく状態にならない (`help` Steel Types)。
/// - ねばねばネット (`_564` / `BTR_STATE_SYN_40_02`): 素早さ 1 段階ダウン。
///
/// 地面にいないポケモンはまきびし・どくびし・ねばねばネットを受けない
/// (`help` ひこう、`TOKUSEIINFO_SYN_026` ふゆう、`ITEMINFO_SYN_541` ふうせん)。
/// くろいてっきゅう (`ITEMINFO_SYN_278`) は地面にいる扱いにする。
/// ステルスロックは地面判定をしない。
/// マジックガード (`TOKUSEIINFO_SYN_098` 「攻撃以外ではダメージが効かない」)
/// はステルスロックとまきびしのダメージだけを消す。どくと素早さ低下は残る。
/// あつぞこブーツとキョダイコウジンは itemname / waza に無いので入れない。
///
/// 外す:
/// - こうそくスピン (`_229`): 自分側の 4 つ。バインドとやどりぎのタネも外す。
///   素早さ +1 は `stat_effects` が無いときだけ足す (二重にしない)。
/// - キラースピン (`_866`): 自分側の 4 つとバインド・やどりぎ。どくは
///   `status_effect` が無いときだけ。本文のでんこうそうげきは電気タイプを
///   消す技で、設置は外さない。
/// - きりばらい (`_432`): 相手側の 4 つ。壁の解除は #243 のまま。設置が
///   0 のときは壁だけの結果になる。回避低下は足さない。
/// - おかたづけ (`_882`): 両側の 4 つ。攻撃・素早さ +1 は stat_effects が
///   無いときだけ。みがわりは未モデル。
/// - がんせきアックス (`_830`) / ひけん・ちえなみ (`_845`): 命中で相手側に
///   ステルスロック / まきびし。ちからずくは追加効果を消す。
/// - コートチェンジ (`_756`): 設置が 1 つでもあるときだけ 4 種を入れ替える。
///   壁・天候・フィールドは動かさない。
///
/// マジックミラー (`TOKUSEIINFO_SYN_156`) は上の 4 つの設置技だけ跳ね返す。
/// かたやぶりは跳ね返さない。双方がミラーなら失敗。他の変化技は跳ね返さない。
///
/// ダメージの分母は `pokemon.hp` (ソルバの HP プール。どくスリップと同じ)。
/// 0 より大きい計算結果が床で 0 になるときは 1 (Showdown `damage` の下限)。
/// 交代直後の順はステルスロック、まきびし、ねばねばネット、どくびし。
/// ひんしになったら残りは撃たない。先発には掛けない。

const HAZARD_STEALTH : Int = 1

const HAZARD_SPIKES : Int = 2

const HAZARD_TOXIC : Int = 3

const HAZARD_WEB : Int = 4

///|
fn hazard_setter_kind(name : String) -> Int {
  if name == "ステルスロック" {
    HAZARD_STEALTH
  } else if name == "まきびし" {
    HAZARD_SPIKES
  } else if name == "どくびし" {
    HAZARD_TOXIC
  } else if name == "ねばねばネット" {
    HAZARD_WEB
  } else {
    0
  }
}

///|
fn is_hazard_setter(name : String) -> Bool {
  hazard_setter_kind(name) != 0
}

///|
fn hazard_on_hit_kind(name : String) -> Int {
  if name == "がんせきアックス" {
    HAZARD_STEALTH
  } else if name == "ひけん・ちえなみ" {
    HAZARD_SPIKES
  } else {
    0
  }
}

///|
fn clears_user_hazards(name : String) -> Bool {
  name == "こうそくスピン" || name == "キラースピン"
}

///|
fn hazard_cap(kind : Int) -> Int {
  if kind == HAZARD_SPIKES {
    3
  } else if kind == HAZARD_TOXIC {
    2
  } else {
    1
  }
}

///|
fn bump_layer(cur : Int, cap : Int) -> Int {
  if cur >= cap {
    cur
  } else {
    cur + 1
  }
}

///|
fn state_any_hazard(state : SwitchingGameState) -> Bool {
  state.my_stealth > 0 ||
  state.opp_stealth > 0 ||
  state.my_spikes > 0 ||
  state.opp_spikes > 0 ||
  state.my_toxic > 0 ||
  state.opp_toxic > 0 ||
  state.my_web > 0 ||
  state.opp_web > 0
}

///|
fn side_has_hazard(stealth : Int, spikes : Int, toxic : Int, web : Int) -> Bool {
  stealth > 0 || spikes > 0 || toxic > 0 || web > 0
}

///|
/// 分母はソルバの HP プール。`effective_hp` は actual_stats が無いと
/// プールより大きくなる (status slip と同じ理由で使わない)。
fn hazard_max_hp(c : Combatant) -> Int {
  c.pokemon.hp
}

///|
/// `numer/denom` の床。正なのに床が 0 なら 1。
fn hazard_fraction(max_hp : Int, numer : Int, denom : Int) -> Int {
  if max_hp <= 0 || numer <= 0 || denom <= 0 {
    return 0
  }
  let d = max_hp * numer / denom
  if d < 1 {
    1
  } else {
    d
  }
}

///|
fn stealth_rock_damage(max_hp : Int, type1 : String, type2 : String) -> Int {
  let (e1, e2) = @damage.move_effectiveness_slots_x4(
    "ステルスロック",
    "いわ",
    type1,
    type2,
  )
  if e1 == 0 || e2 == 0 {
    return 0
  }
  hazard_fraction(max_hp, e1 * e2, 128)
}

///|
fn spikes_damage(max_hp : Int, layers : Int) -> Int {
  let numer = match layers {
    1 => 3
    2 => 4
    3 => 6
    _ => 0
  }
  hazard_fraction(max_hp, numer, 24)
}

///|
/// くろいてっきゅうはひこう・ふゆう・ふうせんより先に地面へ戻す。
fn hazard_grounded(
  type1 : String,
  type2 : String,
  ability : String,
  item : String,
) -> Bool {
  if item == "くろいてっきゅう" {
    return true
  }
  @damage.is_grounded(type1~, type2~, ability~, item~)
}

///|
fn hazard_chip(hps : Array[Int], slot : Int, dmg : Int) -> Unit {
  if dmg <= 0 || slot < 0 || slot >= hps.length() {
    return
  }
  let next = hps[slot] - dmg
  hps[slot] = if next < 0 { 0 } else { next }
}

///|
fn apply_web_drop(
  ability : String,
  type1 : String,
  type2 : String,
  ranks : Array[Int],
) -> Unit {
  if ranks.length() < 5 {
    return
  }
  if ability_blocks_opp_stat_drop(ability, 4, type1~, type2~) {
    return
  }
  if ability_reverses_stat_changes(ability) {
    ranks[4] = clamp_rank_for(ability, ranks[4] + 1)
  } else if apply_opp_stat_drop(ability, ranks, 4, -1) {
    apply_opp_drop_reaction(ability, ranks)
  }
}

///|
/// 交代先に設置を掛ける。戻り値はどくびしの残り層 (吸収で 0)。
/// 層が全部 0 のとき、または既にひんしのときは配列を変えない。
fn apply_entry_hazards(
  team : Array[Combatant],
  slot : Int,
  megaed : Array[Bool],
  hps : Array[Int],
  status : Array[@model.StatusCondition],
  ranks : Array[Int],
  stealth : Int,
  spikes : Int,
  toxic : Int,
  web : Int,
  weather : @model.Weather,
) -> Int {
  if !side_has_hazard(stealth, spikes, toxic, web) {
    return toxic
  }
  if slot < 0 ||
    slot >= team.length() ||
    slot >= hps.length() ||
    hps[slot] <= 0 {
    return toxic
  }
  let mega = slot < megaed.length() && megaed[slot]
  let eff = effective_combatant(team[slot], mega)
  let max_hp = hazard_max_hp(eff)
  let ability = eff.ability
  let t1 = eff.pokemon.type1
  let t2 = eff.pokemon.type2
  let item = eff.item
  let grounded = hazard_grounded(t1, t2, ability, item)
  let blocks_chip = ability == "マジックガード"
  if stealth > 0 && !blocks_chip {
    hazard_chip(hps, slot, stealth_rock_damage(max_hp, t1, t2))
  }
  if hps[slot] > 0 && spikes > 0 && grounded && !blocks_chip {
    hazard_chip(hps, slot, spikes_damage(max_hp, spikes))
  }
  if hps[slot] <= 0 {
    return toxic
  }
  if web > 0 && grounded {
    apply_web_drop(ability, t1, t2, ranks)
  }
  if toxic <= 0 || !grounded {
    return toxic
  }
  let poison_type = t1 == "どく" || t2 == "どく"
  if poison_type {
    return 0
  }
  if slot >= status.length() || status[slot] != @model.None {
    return toxic
  }
  let kind = if toxic >= 2 {
    @model.BadPoisonKind
  } else {
    @model.PoisonKind
  }
  if @model.immune_to_status(kind, t1, t2) {
    return toxic
  }
  if ability_blocks_status(ability, kind, weather~, type1=t1, type2=t2) {
    return toxic
  }
  status[slot] = @model.inflict_status(kind)
  toxic
}

///|
fn with_layer_on_side(
  state : SwitchingGameState,
  on_my_side : Bool,
  kind : Int,
) -> SwitchingGameState {
  let cap = hazard_cap(kind)
  if on_my_side {
    match kind {
      HAZARD_STEALTH =>
        if state.my_stealth >= cap {
          state
        } else {
          { ..state, my_stealth: bump_layer(state.my_stealth, cap) }
        }
      HAZARD_SPIKES =>
        if state.my_spikes >= cap {
          state
        } else {
          { ..state, my_spikes: bump_layer(state.my_spikes, cap) }
        }
      HAZARD_TOXIC =>
        if state.my_toxic >= cap {
          state
        } else {
          { ..state, my_toxic: bump_layer(state.my_toxic, cap) }
        }
      _ =>
        if state.my_web >= cap {
          state
        } else {
          { ..state, my_web: bump_layer(state.my_web, cap) }
        }
    }
  } else {
    match kind {
      HAZARD_STEALTH =>
        if state.opp_stealth >= cap {
          state
        } else {
          { ..state, opp_stealth: bump_layer(state.opp_stealth, cap) }
        }
      HAZARD_SPIKES =>
        if state.opp_spikes >= cap {
          state
        } else {
          { ..state, opp_spikes: bump_layer(state.opp_spikes, cap) }
        }
      HAZARD_TOXIC =>
        if state.opp_toxic >= cap {
          state
        } else {
          { ..state, opp_toxic: bump_layer(state.opp_toxic, cap) }
        }
      _ =>
        if state.opp_web >= cap {
          state
        } else {
          { ..state, opp_web: bump_layer(state.opp_web, cap) }
        }
    }
  }
}

///|
fn with_side_hazards_cleared(
  state : SwitchingGameState,
  my_side : Bool,
) -> SwitchingGameState {
  if my_side {
    if state.my_stealth == 0 &&
      state.my_spikes == 0 &&
      state.my_toxic == 0 &&
      state.my_web == 0 {
      state
    } else {
      { ..state, my_stealth: 0, my_spikes: 0, my_toxic: 0, my_web: 0 }
    }
  } else if state.opp_stealth == 0 &&
    state.opp_spikes == 0 &&
    state.opp_toxic == 0 &&
    state.opp_web == 0 {
    state
  } else {
    { ..state, opp_stealth: 0, opp_spikes: 0, opp_toxic: 0, opp_web: 0 }
  }
}

///|
fn with_hazards_swapped(state : SwitchingGameState) -> SwitchingGameState {
  if !state_any_hazard(state) {
    return state
  }
  {
    ..state,
    my_stealth: state.opp_stealth,
    opp_stealth: state.my_stealth,
    my_spikes: state.opp_spikes,
    opp_spikes: state.my_spikes,
    my_toxic: state.opp_toxic,
    opp_toxic: state.my_toxic,
    my_web: state.opp_web,
    opp_web: state.my_web,
    my_perish: state.my_perish,
    opp_perish: state.opp_perish,
  }
}

///|
fn self_stage_delta(ability : String, delta : Int) -> Int {
  if ability_reverses_stat_changes(ability) { -delta } else { delta }
}

///|
fn move_has_self_stat(mv : @model.Move, stat : Int) -> Bool {
  for eff in mv.stat_effects {
    if eff.target == 0 && eff.stat == stat && eff.delta != 0 {
      return true
    }
  }
  false
}

///|
fn with_self_stage(
  state : SwitchingGameState,
  is_me : Bool,
  ability : String,
  stat : Int,
  delta : Int,
) -> SwitchingGameState {
  let ranks = if is_me {
    state.my_ranks.copy()
  } else {
    state.opp_ranks.copy()
  }
  if stat < 0 || stat >= ranks.length() {
    return state
  }
  let d = self_stage_delta(ability, delta)
  let next = clamp_rank_for(ability, ranks[stat] + d)
  if next == ranks[stat] {
    return state
  }
  ranks[stat] = next
  if is_me {
    { ..state, my_ranks: ranks }
  } else {
    { ..state, opp_ranks: ranks }
  }
}

///|
fn with_user_bind_cleared(
  state : SwitchingGameState,
  is_me : Bool,
) -> SwitchingGameState {
  if is_me {
    if state.my_bind == 0 { state } else { { ..state, my_bind: 0 } }
  } else if state.opp_bind == 0 {
    state
  } else {
    { ..state, opp_bind: 0 }
  }
}

///|
fn with_user_leech_cleared(
  state : SwitchingGameState,
  is_me : Bool,
  slot : Int,
) -> SwitchingGameState {
  let arr = if is_me { state.my_leech_seeded } else { state.opp_leech_seeded }
  if slot < 0 || slot >= arr.length() || !arr[slot] {
    return state
  }
  let next = arr.copy()
  next[slot] = false
  if is_me {
    { ..state, my_leech_seeded: next }
  } else {
    { ..state, opp_leech_seeded: next }
  }
}

///|
/// 使用者の設置を相手側へ。マジックミラーなら使用者側へ。双方ミラーは不発。
fn hazard_set_outcomes(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  defender_slot : Int,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
) -> Array[(Double, SwitchingGameState)] {
  let base = with_protean_on_use_state(
    state,
    attacker_is_me,
    attacker_slot,
    attacker_team,
    mv,
  )
  let kind = hazard_setter_kind(mv.name)
  if kind == 0 {
    return [(1.0, base)]
  }
  let atk_mega = if attacker_is_me {
    attacker_slot < state.my_megaed.length() && state.my_megaed[attacker_slot]
  } else {
    attacker_slot < state.opp_megaed.length() && state.opp_megaed[attacker_slot]
  }
  let def_mega = if attacker_is_me {
    defender_slot < state.opp_megaed.length() && state.opp_megaed[defender_slot]
  } else {
    defender_slot < state.my_megaed.length() && state.my_megaed[defender_slot]
  }
  let atk_ab = if attacker_slot >= 0 && attacker_slot < attacker_team.length() {
    effective_combatant(attacker_team[attacker_slot], atk_mega).ability
  } else {
    ""
  }
  let def_ab = if defender_slot >= 0 && defender_slot < defender_team.length() {
    effective_combatant(defender_team[defender_slot], def_mega).ability
  } else {
    ""
  }
  let bounced = def_ab == "マジックミラー" && !is_mold_breaker_ability(atk_ab)
  if bounced && atk_ab == "マジックミラー" {
    return [(1.0, base)]
  }
  let on_my_side = if attacker_is_me { bounced } else { !bounced }
  [(1.0, with_layer_on_side(base, on_my_side, kind))]
}

///|
fn defender_has_hazard_ws(ws : TurnWorkspace, attacker_is_me : Bool) -> Bool {
  if attacker_is_me {
    side_has_hazard(ws.opp_stealth, ws.opp_spikes, ws.opp_toxic, ws.opp_web)
  } else {
    side_has_hazard(ws.my_stealth, ws.my_spikes, ws.my_toxic, ws.my_web)
  }
}

///|
fn clear_defender_hazards_ws(
  ws : TurnWorkspace,
  attacker_is_me : Bool,
) -> TurnWorkspace {
  if attacker_is_me {
    { ..ws, opp_stealth: 0, opp_spikes: 0, opp_toxic: 0, opp_web: 0 }
  } else {
    { ..ws, my_stealth: 0, my_spikes: 0, my_toxic: 0, my_web: 0 }
  }
}

///|
fn note_switch_hazards(
  team : Array[Combatant],
  slot : Int,
  megaed : Array[Bool],
  hps : Array[Int],
  status : Array[@model.StatusCondition],
  ranks : Array[Int],
  stealth : Int,
  spikes : Int,
  toxic : Int,
  web : Int,
  weather : @model.Weather,
) -> (Int, Bool) {
  if !side_has_hazard(stealth, spikes, toxic, web) {
    return (toxic, false)
  }
  if slot < 0 || slot >= hps.length() {
    return (toxic, false)
  }
  let before = hps[slot]
  let toxic_next = apply_entry_hazards(
    team, slot, megaed, hps, status, ranks, stealth, spikes, toxic, web, weather,
  )
  (toxic_next, before > 0 && hps[slot] <= 0)
}

///|
fn hazard_poison_if_needed(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  target_team : Array[Combatant],
  mv : @model.Move,
) -> SwitchingGameState {
  if mv.name != "キラースピン" || mv.status_effect is Some(_) {
    return state
  }
  let hps = if target_is_me { state.my_hps } else { state.opp_hps }
  let sts = if target_is_me { state.my_status } else { state.opp_status }
  if target_slot < 0 ||
    target_slot >= hps.length() ||
    hps[target_slot] <= 0 ||
    target_slot >= sts.length() ||
    sts[target_slot] != @model.None ||
    target_slot >= target_team.length() {
    return state
  }
  let megaed = if target_is_me { state.my_megaed } else { state.opp_megaed }
  let mega = target_slot < megaed.length() && megaed[target_slot]
  let eff = effective_combatant(target_team[target_slot], mega)
  let kind = @model.PoisonKind
  if @model.immune_to_status(kind, eff.pokemon.type1, eff.pokemon.type2) {
    return state
  }
  if ability_blocks_status(
    eff.ability,
    kind,
    weather=state.weather,
    type1=eff.pokemon.type1,
    type2=eff.pokemon.type2,
  ) {
    return state
  }
  with_status_set(state, target_is_me, target_slot, kind)
}

///|
fn apply_removal_to_state(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  defender_slot : Int,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
) -> SwitchingGameState {
  if mv.name == "コートチェンジ" {
    return with_hazards_swapped(state)
  }
  let user_ab = holder_ability_of(
    state, attacker_is_me, attacker_slot, attacker_team,
  )
  if mv.name == "おかたづけ" {
    let cleared = with_side_hazards_cleared(
      with_side_hazards_cleared(state, true),
      false,
    )
    let atk = if move_has_self_stat(mv, 0) {
      cleared
    } else {
      with_self_stage(cleared, attacker_is_me, user_ab, 0, 1)
    }
    if move_has_self_stat(mv, 4) {
      atk
    } else {
      with_self_stage(atk, attacker_is_me, user_ab, 4, 1)
    }
  } else if clears_user_hazards(mv.name) {
    let cleared = with_user_leech_cleared(
      with_user_bind_cleared(
        with_side_hazards_cleared(state, attacker_is_me),
        attacker_is_me,
      ),
      attacker_is_me,
      attacker_slot,
    )
    let sped = if mv.name == "こうそくスピン" && !move_has_self_stat(mv, 4) {
      with_self_stage(cleared, attacker_is_me, user_ab, 4, 1)
    } else {
      cleared
    }
    hazard_poison_if_needed(
      sped, !attacker_is_me, defender_slot, defender_team, mv,
    )
  } else {
    state
  }
}

///|
/// 命中後の設置。設置技でも除去技でもないときは同じ配列を返す。
fn hazard_after_hit_leaves(
  leaves : Array[(Double, SwitchingGameState)],
  attacker_is_me : Bool,
  attacker_slot : Int,
  defender_slot : Int,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
  attacker_ability : String,
) -> Array[(Double, SwitchingGameState)] {
  let on_hit = hazard_on_hit_kind(mv.name)
  if on_hit != 0 {
    if attacker_ability == "ちからずく" {
      return leaves
    }
    let on_my = !attacker_is_me
    let out : Array[(Double, SwitchingGameState)] = []
    for leaf in leaves {
      out.push((leaf.0, with_layer_on_side(leaf.1, on_my, on_hit)))
    }
    return out
  }
  if mv.name == "コートチェンジ" {
    if leaves.length() == 0 || !state_any_hazard(leaves[0].1) {
      return leaves
    }
    let out : Array[(Double, SwitchingGameState)] = []
    for leaf in leaves {
      out.push((leaf.0, with_hazards_swapped(leaf.1)))
    }
    return out
  }
  if mv.name != "おかたづけ" && !clears_user_hazards(mv.name) {
    return leaves
  }
  let out : Array[(Double, SwitchingGameState)] = []
  for leaf in leaves {
    out.push((
      leaf.0,
      apply_removal_to_state(
        leaf.1,
        attacker_is_me,
        attacker_slot,
        defender_slot,
        attacker_team,
        defender_team,
        mv,
      ),
    ))
  }
  out
}

///|
fn mc_hazard_ok(buf : Array[Int]) -> Bool {
  buf.length() >= 8
}

///|
fn mc_hazard_base(own_side : Bool) -> Int {
  if own_side { 0 } else { 4 }
}

///|
fn mc_side_has(buf : Array[Int], own_side : Bool) -> Bool {
  if !mc_hazard_ok(buf) {
    return false
  }
  let b = mc_hazard_base(own_side)
  side_has_hazard(buf[b], buf[b + 1], buf[b + 2], buf[b + 3])
}

///|
fn mc_add_layer(buf : Array[Int], own_side : Bool, kind : Int) -> Unit {
  if !mc_hazard_ok(buf) {
    return
  }
  let b = mc_hazard_base(own_side)
  let i = match kind {
    HAZARD_STEALTH => b
    HAZARD_SPIKES => b + 1
    HAZARD_TOXIC => b + 2
    _ => b + 3
  }
  buf[i] = bump_layer(buf[i], hazard_cap(kind))
}

///|
fn mc_clear_side(buf : Array[Int], own_side : Bool) -> Unit {
  if !mc_hazard_ok(buf) || !mc_side_has(buf, own_side) {
    return
  }
  let b = mc_hazard_base(own_side)
  buf[b] = 0
  buf[b + 1] = 0
  buf[b + 2] = 0
  buf[b + 3] = 0
}

///|
fn mc_swap_hazards(buf : Array[Int]) -> Unit {
  if !mc_hazard_ok(buf) {
    return
  }
  if !mc_side_has(buf, true) && !mc_side_has(buf, false) {
    return
  }
  for i in 0..<4 {
    let t = buf[i]
    buf[i] = buf[i + 4]
    buf[i + 4] = t
  }
}

///|
/// 交代先。層が 0 のときは何もしない。戻り値はひんしにしたか。
fn mc_entry_hazards(
  buf : Array[Int],
  own_side : Bool,
  team : Array[Combatant],
  slot : Int,
  hps : Array[Int],
  status : Array[@model.StatusCondition],
  ranks : Array[Int],
  weather : @model.Weather,
) -> Bool {
  if !mc_side_has(buf, own_side) {
    return false
  }
  if slot < 0 || slot >= hps.length() {
    return false
  }
  let b = mc_hazard_base(own_side)
  let before = hps[slot]
  let toxic_next = apply_entry_hazards(
    team,
    slot,
    Array::make(0, false),
    hps,
    status,
    ranks,
    buf[b],
    buf[b + 1],
    buf[b + 2],
    buf[b + 3],
    weather,
  )
  buf[b + 2] = toxic_next
  before > 0 && hps[slot] <= 0
}

///|
fn mc_commit_setter(
  buf : Array[Int],
  attacker_is_own : Bool,
  attacker : Combatant,
  defender : Combatant,
  mv : @model.Move,
) -> Unit {
  let kind = hazard_setter_kind(mv.name)
  if kind == 0 || !mc_hazard_ok(buf) {
    return
  }
  let bounced = defender.ability == "マジックミラー" &&
    !is_mold_breaker_ability(attacker.ability)
  if bounced && attacker.ability == "マジックミラー" {
    return
  }
  let on_own = if attacker_is_own { bounced } else { !bounced }
  mc_add_layer(buf, on_own, kind)
}

///|
fn mc_on_damaging_hazard(
  buf : Array[Int],
  attacker_is_own : Bool,
  attacker : Combatant,
  mv : @model.Move,
) -> Unit {
  if !mc_hazard_ok(buf) {
    return
  }
  if clears_user_hazards(mv.name) {
    mc_clear_side(buf, attacker_is_own)
    return
  }
  let kind = hazard_on_hit_kind(mv.name)
  if kind != 0 && attacker.ability != "ちからずく" {
    mc_add_layer(buf, !attacker_is_own, kind)
  }
}
