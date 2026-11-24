///|
/// まもる系 (champout `50e7233`)。
///
/// 対象は `available = 1` の全身ガードだけ。
/// - まもる / みきり (`WAZAINFO_SYN_182` / `_197`): そのターンの技を防ぐ。
/// - キングシールド (`_588`): 攻撃を防ぐ。接触で攻撃 -1。シールドフォルムは未モデル。
/// - ニードルガード (`_596`): 技を防ぐ。接触で最大 HP の 1/8。
/// - トーチカ (`_661`): 技を防ぐ。接触でどく。
///
/// 連続成功率は本文「連続で使うと成功率が前に使った時の１／３」。
/// 初回は連続ではないので 1。失敗・不使用・交代で 0 に戻す。
/// 下限 1/729 は本文に無い。Showdown `conditions.ts` の stall (`counterMax` 729)
/// と同じ段 (1, 1/3, 1/9, …, 1/729) で止める。
///
/// 守りの解除: フェイント (`_364`)、ゴーストダイブの解放 (`_566`)。
/// なみだめ (`_715`) は守るを無視して当たる。本文は解除と書かないので旗は残す。
/// ふかしのこぶし (`TOKUSEIINFO_SYN_260`) とかんつうドリル (`_311`) は接触技の
/// ダメージを 1/4 にし、守りの追加効果は残す。えんかく (`_203`) は接触ではない。
/// 1/4 の丸めは本文に無い。`round5(_, 1024)` を使う。
///
/// 入れない (`available = 0` または道具が itemname に無い):
/// ブロッキング、スレッドトラップ、かえんのまもり、シャドーダイブ、
/// ハイパードリル、パワフルエッジ、たたみがえし、トリックガード、パワフルハーブ。
/// こらえるは同じ 1/3 文だが攻撃を無効にしない。ワイドガード / ファストガード /
/// サイドチェンジはダブル向き。くちばしキャノンは守るではない。

const PROTECT_FULL : Int = 1

const PROTECT_KINGS : Int = 2

const PROTECT_SPIKY : Int = 3

const PROTECT_BUNKER : Int = 4

const PROTECT_STALL_CAP : Int = 6

priv enum ProtectVs {
  PvBlock
  PvBreak
  PvThrough
  PvQuarter
}

///|
fn protect_kind(name : String) -> Int {
  if name == "まもる" || name == "みきり" {
    PROTECT_FULL
  } else if name == "キングシールド" {
    PROTECT_KINGS
  } else if name == "ニードルガード" {
    PROTECT_SPIKY
  } else if name == "トーチカ" {
    PROTECT_BUNKER
  } else {
    0
  }
}

///|
fn is_protect_move(name : String) -> Bool {
  protect_kind(name) != 0
}

///|
/// level 0 は 1 (分岐を作らない)。1 以上は 3^level。6 以上は 729。
fn stall_denominator(level : Int) -> Int {
  if level <= 0 {
    1
  } else if level == 1 {
    3
  } else if level == 2 {
    9
  } else if level == 3 {
    27
  } else if level == 4 {
    81
  } else if level == 5 {
    243
  } else {
    729
  }
}

///|
fn stall_next(level : Int) -> Int {
  if level < 0 {
    1
  } else if level >= PROTECT_STALL_CAP {
    PROTECT_STALL_CAP
  } else {
    level + 1
  }
}

///|
/// 交代した側だけ 0。交代していない側はそのまま。
fn stall_after_switch(level : Int, action : ActionKind) -> Int {
  match action {
    Switch(_) => 0
    _ => level
  }
}

///|
fn protect_move_contacts(mv : @model.Move, ability : String) -> Bool {
  @damage.is_contact_move(mv.name) && ability != "えんかく"
}

///|
fn protect_interaction(
  shield : Int,
  mv : @model.Move,
  attacker_ability : String,
) -> ProtectVs {
  if mv.name == "フェイント" || mv.name == "ゴーストダイブ" {
    return PvBreak
  }
  if mv.name == "なみだめ" {
    return PvThrough
  }
  if protect_move_contacts(mv, attacker_ability) &&
    (attacker_ability == "ふかしのこぶし" || attacker_ability == "かんつうドリル") {
    return PvQuarter
  }
  if shield == PROTECT_KINGS &&
    (mv.category == @model.Status || mv.power <= 0) {
    return PvThrough
  }
  PvBlock
}

///|
fn scale_protect_quarter(
  outcomes : Array[@model.DamageOutcome],
) -> Array[@model.DamageOutcome] {
  let out : Array[@model.DamageOutcome] = []
  for i = 0; i < outcomes.length(); i = i + 1 {
    let o = outcomes[i]
    out.push(
      {
        probability: o.probability,
        mean_damage: @damage.round5(o.mean_damage, 1024),
        hits_count: o.hits_count,
        hit_steps: o.hit_steps,
      },
    )
  }
  out
}

///|
fn with_side_stall_shield(
  state : SwitchingGameState,
  is_me : Bool,
  stall : Int,
  shield : Int,
) -> SwitchingGameState {
  if is_me {
    if state.my_stall == stall && state.my_protect == shield {
      return state
    }
    { ..state, my_stall: stall, my_protect: shield }
  } else if state.opp_stall == stall && state.opp_protect == shield {
    state
  } else {
    { ..state, opp_stall: stall, opp_protect: shield }
  }
}

///|
/// まもるを選べたときだけ呼ぶ。level 0 は確率 1 の 1 枚。それ以外は成功を先に足す。
fn protect_use_outcomes(
  state : SwitchingGameState,
  is_me : Bool,
  slot : Int,
  team : Array[Combatant],
  mv : @model.Move,
) -> Array[(Double, SwitchingGameState)] {
  let base = with_protean_on_use_state(state, is_me, slot, team, mv)
  let level = if is_me { base.my_stall } else { base.opp_stall }
  let den = stall_denominator(level)
  let kind = protect_kind(mv.name)
  let success = with_side_stall_shield(base, is_me, stall_next(level), kind)
  if den <= 1 {
    return [(1.0, success)]
  }
  let p = 1.0 / den.to_double()
  let fail = with_side_stall_shield(base, is_me, 0, 0)
  [(p, success), (1.0 - p, fail)]
}

///|
fn spiky_chip(ability : String, max_hp : Int) -> Int {
  if ability == "マジックガード" || max_hp <= 0 {
    0
  } else {
    max_hp / 8
  }
}

///|
fn bunker_can_poison(
  ability : String,
  type1 : String,
  type2 : String,
  item : String,
  status : @model.StatusCondition,
  weather : @model.Weather,
  field : @model.Field,
) -> Bool {
  match status {
    None => ()
    _ => return false
  }
  if @model.immune_to_status(@model.PoisonKind, type1, type2) {
    return false
  }
  if ability_blocks_status(
    ability,
    @model.PoisonKind,
    weather~,
    type1~,
    type2~,
  ) {
    return false
  }
  if field_blocks_status(field, @model.PoisonKind) &&
    @damage.is_grounded(type1~, type2~, ability~, item~) {
    return false
  }
  true
}

///|
fn apply_kings_shield_atk(
  ability : String,
  type1 : String,
  type2 : String,
  ranks : Array[Int],
) -> Unit {
  if ranks.length() == 0 {
    return
  }
  let delta = if ability_reverses_stat_changes(ability) { 1 } else { -1 }
  if delta < 0 {
    if !ability_blocks_opp_stat_drop(ability, 0, type1~, type2~) {
      if apply_opp_stat_drop(ability, ranks, 0, delta) {
        apply_opp_drop_reaction(ability, ranks)
      }
    }
  } else {
    ranks[0] = clamp_rank_for(ability, ranks[0] + delta)
  }
}

///|
fn ranks_equal(a : Array[Int], b : Array[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// 接触の追加効果。フェイント解除と非接触では state を返す。
fn apply_protect_contact(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  attacker_team : Array[Combatant],
  mv : @model.Move,
  shield : Int,
) -> SwitchingGameState {
  if attacker_slot < 0 || attacker_slot >= attacker_team.length() || shield == 0 {
    return state
  }
  let megaed = if attacker_is_me { state.my_megaed } else { state.opp_megaed }
  let is_mega = attacker_slot < megaed.length() && megaed[attacker_slot]
  let eff = effective_combatant(attacker_team[attacker_slot], is_mega)
  if !protect_move_contacts(mv, eff.ability) {
    return state
  }
  if shield == PROTECT_KINGS {
    let old = if attacker_is_me { state.my_ranks } else { state.opp_ranks }
    let ranks = old.copy()
    apply_kings_shield_atk(
      eff.ability,
      eff.pokemon.type1,
      eff.pokemon.type2,
      ranks,
    )
    if ranks_equal(old, ranks) {
      return state
    }
    if attacker_is_me {
      return { ..state, my_ranks: ranks }
    }
    return { ..state, opp_ranks: ranks }
  }
  if shield == PROTECT_SPIKY {
    let hps = if attacker_is_me { state.my_hps } else { state.opp_hps }
    if attacker_slot >= hps.length() || hps[attacker_slot] <= 0 {
      return state
    }
    let chip = spiky_chip(eff.ability, effective_hp(eff))
    if chip <= 0 {
      return state
    }
    return with_hp_damage(state, attacker_is_me, attacker_slot, chip)
  }
  if shield == PROTECT_BUNKER {
    let arr = if attacker_is_me { state.my_status } else { state.opp_status }
    if attacker_slot >= arr.length() {
      return state
    }
    if !bunker_can_poison(
      eff.ability,
      eff.pokemon.type1,
      eff.pokemon.type2,
      eff.item,
      arr[attacker_slot],
      state.weather,
      state.field,
    ) {
      return state
    }
    let next = arr.copy()
    next[attacker_slot] = @model.Poison
    if attacker_is_me {
      return { ..state, my_status: next }
    }
    return { ..state, opp_status: next }
  }
  state
}

///|
/// 防いだ技。ダメージと追加効果は無く、プロテアン・自爆・崩れ・てっていこうせんは残す。
fn protect_blocked_state(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  defender_slot : Int,
  attacker_team : Array[Combatant],
  mv : @model.Move,
  shield : Int,
  defender_alive : Bool,
) -> SwitchingGameState {
  let _ = defender_slot
  let immune = with_immune_effects(
    state, attacker_is_me, attacker_slot, attacker_team, mv,
  )
  let touched = apply_protect_contact(
    immune, attacker_is_me, attacker_slot, attacker_team, mv, shield,
  )
  let crashed = with_crash_damage(
    touched, attacker_is_me, attacker_slot, attacker_team, mv,
  )
  with_max_hp_recoil(
    crashed, attacker_is_me, attacker_slot, attacker_team, mv, defender_alive,
  )
}

///|
fn map_protect_contact(
  leaves : Array[(Double, SwitchingGameState)],
  attacker_is_me : Bool,
  attacker_slot : Int,
  attacker_team : Array[Combatant],
  mv : @model.Move,
  shield : Int,
) -> Array[(Double, SwitchingGameState)] {
  let out : Array[(Double, SwitchingGameState)] = []
  for i = 0; i < leaves.length(); i = i + 1 {
    let (p, s) = leaves[i]
    out.push((
      p,
      apply_protect_contact(
        s, attacker_is_me, attacker_slot, attacker_team, mv, shield,
      ),
    ))
  }
  out
}

///|
/// ターン末。旗が立った側の stall だけ残し、旗は消す。全部 0 なら同じ state。
fn settle_protect(state : SwitchingGameState) -> SwitchingGameState {
  if state.my_protect == 0 &&
    state.opp_protect == 0 &&
    state.my_stall == 0 &&
    state.opp_stall == 0 {
    return state
  }
  let my_stall = if state.my_protect != 0 { state.my_stall } else { 0 }
  let opp_stall = if state.opp_protect != 0 { state.opp_stall } else { 0 }
  if my_stall == state.my_stall &&
    opp_stall == state.opp_stall &&
    state.my_protect == 0 &&
    state.opp_protect == 0 {
    return state
  }
  { ..state, my_stall, opp_stall, my_protect: 0, opp_protect: 0 }
}

///|
/// `io` は `[stall, shield]`。level 0 は rng を使わない。
fn mc_commit_protect(
  name : String,
  io : Array[Int],
  rng : @random.Rand,
) -> Unit {
  if io.length() < 2 {
    return
  }
  let level = io[0]
  let den = stall_denominator(level)
  let ok = if den <= 1 {
    true
  } else {
    rand_bool(rng, 1.0 / den.to_double())
  }
  if ok {
    io[0] = stall_next(level)
    io[1] = protect_kind(name)
  } else {
    io[0] = 0
    io[1] = 0
  }
}

///|
fn mc_apply_protect_contact(
  shield : Int,
  mv : @model.Move,
  attacker : Combatant,
  hps : Array[Int],
  status : Array[@model.StatusCondition],
  ranks : Array[Int],
  slot : Int,
  weather : @model.Weather,
  field : @model.Field,
) -> Unit {
  if shield == 0 || slot < 0 || !protect_move_contacts(mv, attacker.ability) {
    return
  }
  if shield == PROTECT_KINGS {
    apply_kings_shield_atk(
      attacker.ability,
      attacker.pokemon.type1,
      attacker.pokemon.type2,
      ranks,
    )
    return
  }
  if shield == PROTECT_SPIKY {
    if slot >= hps.length() || hps[slot] <= 0 {
      return
    }
    let chip = spiky_chip(attacker.ability, effective_hp(attacker))
    if chip > 0 {
      hps[slot] = clamp_zero(hps[slot] - chip)
    }
    return
  }
  if shield == PROTECT_BUNKER {
    if slot >= status.length() {
      return
    }
    if bunker_can_poison(
      attacker.ability,
      attacker.pokemon.type1,
      attacker.pokemon.type2,
      attacker.item,
      status[slot],
      weather,
      field,
    ) {
      status[slot] = @model.Poison
    }
  }
}
