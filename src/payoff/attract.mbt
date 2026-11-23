///|
/// メロメロ (Infatuated)。Champions の本文:
/// - 技 `WAZAINFO_SYN_213`: 「相手をメロメロ状態にする。同性　性別不明の相手には失敗する。」
///   技データ上の付与技は メロメロ だけ (`WAZANAME_213`)。
/// - 状態 `BTR_STATE_SYN_13_02`: 「メロメロ状態にした相手が場にいると５０％の確率で技が使えない。」
///   ターン数は無い。付与した側が場を離れたら効果は終わる。
/// - 特性 `TOKUSEIINFO_SYN_056` メロメロボディ: 「異性から接触技を受けると３０％の確率で相手をメロメロ状態にする。」
/// - どんかんはメロメロにならない。アロマベールは自分 (シングル。味方は対象外) がならない。
///   かたやぶりは「相手の特性に関係なく技を出す」(`TOKUSEIINFO_SYN_104`) ので、
///   技の付与ではどんかんとアロマベールを無視する。メロメロボディ側のかたやぶりは
///   攻撃側のどんかんを無視しない。攻撃側のかたやぶりは接触特性そのものを出さない。
/// - メンタルハーブはメロメロを治して消費する (iteminfo)。付与が成功したときだけ。
/// - ミストフィールドの本文は状態異常とこんらんだけで、メロメロは止めない。
/// - あかいいとは champout の道具に無い。反射は入れない。
///
/// 行動前の順は Showdown `onBeforeMove` の優先度 (本文は順を書かない):
/// 眠り / こおり、ひるみ、メロメロ (priority 2)、まひ (1)、こんらん (0)。
/// メロメロで動けない枝はまひもこんらんも振らない。確定で眠っている間は 50% を振らない。
///
/// 付与が起きない入力では fanout が `(1.0, 同じ state)` を返し、試行も遅らせない。
/// `compose_fanouts` の `p * 1.0` は元の確率とビット一致する。

///|
/// 行動不能。本文の 50%。`1/2` として正確な 0.5 を使う (50/100 の別表現にはしない)。
const ATTRACT_IMMOBILIZE_RATE : Double = 0.5

///|
/// メロメロボディ。本文の 30%。他の百分率追加効果と同じ `flinch_probability` に渡す。
const CUTE_CHARM_CHANCE : Int = 30

///|
/// シングルの性別。`Unknown` は性別不明と、メタモンのような性別不明の種族。
/// どちらもメロメロは失敗する (本文は同性と性別不明で失敗)。
pub(all) enum Gender {
  Unknown
  Male
  Female
} derive(Debug, Eq)

///|
pub extend Gender with Debug::{to_repr}

///|
pub extend Gender with Eq::{not_equal, equal}

///|
fn attract_move(mv : @model.Move) -> Bool {
  mv.name == "メロメロ"
}

///|
fn species_named(name : String, species : String) -> Bool {
  name == species || name.has_prefix(species + "（")
}

///|
/// `personal.json` の `sex == "2"` (性別不明)。フォームの表示名も含む。
/// 明示の `gender` より先に見る。メタモンをオスにはできない。
fn species_genderless(name : String) -> Bool {
  if name == "ヒートロトム" ||
    name == "ウォッシュロトム" ||
    name == "フロストロトム" ||
    name == "スピンロトム" ||
    name == "カットロトム" ||
    name == "ロトムのすがた" ||
    name == "メガスターミー" ||
    name == "メガメタグロス" ||
    name == "メガゴルーグ" ||
    name == "メガタイレーツ" {
    return true
  }
  species_named(name, "スターミー") ||
  species_named(name, "メタモン") ||
  species_named(name, "メタグロス") ||
  species_named(name, "ロトム") ||
  species_named(name, "ゴルーグ") ||
  species_named(name, "ポットデス") ||
  species_named(name, "タイレーツ") ||
  species_named(name, "イッカネズミ") ||
  species_named(name, "サーフゴー") ||
  species_named(name, "ヤバソチャ")
}

///|
fn gender_mark_female(name : String) -> Bool {
  name.contains("（メス）") ||
  name.contains("メスのすがた") ||
  name.contains("(Female)") ||
  name.contains(" (Female)")
}

///|
fn gender_mark_male(name : String) -> Bool {
  name.contains("（オス）") ||
  name.contains("オスのすがた") ||
  name.contains("(Male)") ||
  name.contains(" (Male)")
}

///|
/// `sex == "3"` の種族。フラエッテはえいえんのはなとメガだけ (他フォームは両性)。
/// メガニャオニクスはオス形とメス形が同じ表示名なので、ここでは決めない。
fn species_fixed_female(name : String) -> Bool {
  if name.contains("えいえんのはな") ||
    name == "メガガルーラ" ||
    name == "メガユキメノコ" ||
    name == "メガフラエッテ" {
    return true
  }
  species_named(name, "ガルーラ") ||
  species_named(name, "ユキメノコ") ||
  species_named(name, "フラージェス") ||
  species_named(name, "エンニュート") ||
  species_named(name, "アマージョ") ||
  species_named(name, "ブリムオン") ||
  species_named(name, "マホイップ") ||
  species_named(name, "デカヌチャン")
}

///|
/// `sex == "1"`。ニャオニクス / イエッサン / イダイトウの無印はオス形
/// (フォーム 0)。メスの表記は呼び出し側が先に女と判定する。
fn species_fixed_male(name : String) -> Bool {
  if name == "メガエルレイド" ||
    name == "ニャオニクス" ||
    name == "イエッサン" ||
    name == "イダイトウ" {
    return true
  }
  species_named(name, "ケンタロス") ||
  species_named(name, "エルレイド") ||
  species_named(name, "オーロンゲ")
}

///|
/// 名前と、あれば明示の `gender` から性別を決める。
/// 性別不明の種族は明示より優先する。それ以外は明示が種族表より優先する。
/// 両性の種族で明示が無ければ `Unknown` (メロメロは失敗。既存入力を変えない)。
pub fn resolve_gender(c : Combatant) -> Gender {
  let name = c.pokemon.name_ja
  if species_genderless(name) {
    return Gender::Unknown
  }
  if c.gender != Gender::Unknown {
    return c.gender
  }
  if gender_mark_female(name) {
    return Gender::Female
  }
  if gender_mark_male(name) {
    return Gender::Male
  }
  if species_fixed_female(name) {
    return Gender::Female
  }
  if species_fixed_male(name) {
    return Gender::Male
  }
  Gender::Unknown
}

///|
fn opposite_genders(a : Gender, b : Gender) -> Bool {
  match (a, b) {
    (Gender::Male, Gender::Female) | (Gender::Female, Gender::Male) => true
    _ => false
  }
}

///|
/// どんかん / アロマベール。かたやぶりは技の付与側だけこれらの無効を外す。
/// いかく用の無視リスト (`ability_ignored_by_mold_breaker`) には入れない。
fn attract_blocked(attacker_ability : String, defender_ability : String) -> Bool {
  if is_mold_breaker_ability(attacker_ability) {
    return false
  }
  defender_ability == "どんかん" || defender_ability == "アロマベール"
}

///|
fn attract_identity(
  state : SwitchingGameState,
) -> Array[(Double, SwitchingGameState)] {
  [(1.0, state)]
}

///|
fn slot_hp(hps : Array[Int], slot : Int) -> Int {
  if slot < 0 || slot >= hps.length() {
    0
  } else {
    hps[slot]
  }
}

///|
fn attract_flag_of(state : SwitchingGameState, is_me : Bool) -> Int {
  if is_me {
    state.my_attract
  } else {
    state.opp_attract
  }
}

///|
/// 両者とも場にいる (HP > 0) ときだけフラグを残す。ひんしの付与元は場にいない。
fn attract_kept_flags(
  my_flag : Int,
  opp_flag : Int,
  my_hp : Int,
  opp_hp : Int,
) -> (Int, Int) {
  if (my_flag == 0 && opp_flag == 0) || my_hp <= 0 || opp_hp <= 0 {
    (0, 0)
  } else {
    (my_flag, opp_flag)
  }
}

///|
fn attract_live_state(state : SwitchingGameState, is_me : Bool) -> Bool {
  let (my_flag, opp_flag) = attract_kept_flags(
    state.my_attract,
    state.opp_attract,
    slot_hp(state.my_hps, state.my_active),
    slot_hp(state.opp_hps, state.opp_active),
  )
  if is_me {
    my_flag > 0
  } else {
    opp_flag > 0
  }
}

///|
fn scrub_attract_workspace(ws : TurnWorkspace) -> TurnWorkspace {
  if ws.my_attract == 0 && ws.opp_attract == 0 {
    return ws
  }
  let (my_flag, opp_flag) = attract_kept_flags(
    ws.my_attract,
    ws.opp_attract,
    slot_hp(ws.my_hps, ws.my_active),
    slot_hp(ws.opp_hps, ws.opp_active),
  )
  if my_flag == ws.my_attract && opp_flag == ws.opp_attract {
    ws
  } else {
    { ..ws, my_attract: my_flag, opp_attract: opp_flag }
  }
}

///|
fn attract_live_ws(ws : TurnWorkspace, is_me : Bool) -> Bool {
  let flag = if is_me { ws.my_attract } else { ws.opp_attract }
  flag > 0 &&
  slot_hp(ws.my_hps, ws.my_active) > 0 &&
  slot_hp(ws.opp_hps, ws.opp_active) > 0
}

///|
/// 交代が片方でもあれば両方のフラグを消す。付与された側が出ても、付与した側が
/// 出ても効果は終わる (シングルの付与元は相手の場のポケモン)。
/// 交代が無いときはひんしだけ落とす。両方 0 のままなら `(0, 0)`。
fn attract_flags_after_switch(
  state : SwitchingGameState,
  my_action : ActionKind,
  opp_action : ActionKind,
) -> (Int, Int) {
  let switched = match my_action {
    Switch(_) => true
    _ =>
      match opp_action {
        Switch(_) => true
        _ => false
      }
  }
  if switched {
    (0, 0)
  } else {
    attract_kept_flags(
      state.my_attract,
      state.opp_attract,
      slot_hp(state.my_hps, state.my_active),
      slot_hp(state.opp_hps, state.opp_active),
    )
  }
}

///|
fn with_attract(
  state : SwitchingGameState,
  target_is_me : Bool,
) -> SwitchingGameState {
  if target_is_me {
    { ..state, my_attract: 1 }
  } else {
    { ..state, opp_attract: 1 }
  }
}

///|
fn consume_holder_item(
  state : SwitchingGameState,
  target_is_me : Bool,
  slot : Int,
) -> SwitchingGameState {
  let consumed = if target_is_me {
    state.my_item_consumed
  } else {
    state.opp_item_consumed
  }
  if slot < 0 || slot >= consumed.length() {
    return state
  }
  let next = consumed.copy()
  next[slot] = true
  if target_is_me {
    { ..state, my_item_consumed: next }
  } else {
    { ..state, opp_item_consumed: next }
  }
}

///|
/// 付与が成功したときだけ。メンタルハーブならフラグは立てず、道具だけ消費する。
/// すでに消費済みならフラグを立てる。
fn attract_landed(
  state : SwitchingGameState,
  target_is_me : Bool,
  slot : Int,
  holder : Combatant,
) -> SwitchingGameState {
  let consumed = if target_is_me {
    state.my_item_consumed
  } else {
    state.opp_item_consumed
  }
  let herb = holder.item == "メンタルハーブ" &&
    slot >= 0 &&
    slot < consumed.length() &&
    !consumed[slot]
  if herb {
    consume_holder_item(state, target_is_me, slot)
  } else {
    with_attract(state, target_is_me)
  }
}

///|
fn holder_at(
  team : Array[Combatant],
  slot : Int,
  is_mega : Bool,
) -> Combatant? {
  if slot < 0 || slot >= team.length() {
    None
  } else {
    Some(effective_combatant(team[slot], is_mega))
  }
}

///|
fn mega_at(megaed : Array[Bool], slot : Int) -> Bool {
  slot >= 0 && slot < megaed.length() && megaed[slot]
}

///|
/// メロメロの fanout。技名が違う、ひんし、同性、性別不明、無効特性、
/// すでにメロメロ、のときは同じ state を確率 1 で返す。
/// 本文に百分率が無いので、命中したときは確定で 1 本 (分岐を増やさない)。
fn maybe_apply_attract_fanout(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  attacker_slot : Int,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
  attacker_ability? : String = "",
) -> Array[(Double, SwitchingGameState)] {
  if !attract_move(mv) {
    return attract_identity(state)
  }
  let target_hps = if target_is_me { state.my_hps } else { state.opp_hps }
  let atk_hps = if target_is_me { state.opp_hps } else { state.my_hps }
  if slot_hp(target_hps, target_slot) <= 0 || slot_hp(atk_hps, attacker_slot) <= 0 {
    return attract_identity(state)
  }
  if attract_flag_of(state, target_is_me) > 0 {
    return attract_identity(state)
  }
  let atk_megaed = if target_is_me { state.opp_megaed } else { state.my_megaed }
  let def_megaed = if target_is_me { state.my_megaed } else { state.opp_megaed }
  match (
    holder_at(attacker_team, attacker_slot, mega_at(atk_megaed, attacker_slot)),
    holder_at(defender_team, target_slot, mega_at(def_megaed, target_slot)),
  ) {
    (Some(atk), Some(def)) => {
      let atk_ability = if attacker_ability != "" {
        attacker_ability
      } else {
        atk.ability
      }
      if attract_blocked(atk_ability, def.ability) {
        return attract_identity(state)
      }
      if !opposite_genders(resolve_gender(atk), resolve_gender(def)) {
        return attract_identity(state)
      }
      [(1.0, attract_landed(state, target_is_me, target_slot, def))]
    }
    _ => attract_identity(state)
  }
}

///|
/// メロメロボディ。接触が成立した hit 数で `1 - 0.7^n`。失敗枝を先に置く。
/// 防御側がひんし、または攻撃側がひんしのときは乱数も分岐も作らない
/// (付与元が場に残らない)。攻撃側のかたやぶり / どんかん / アロマベールも不発。
fn maybe_apply_cute_charm_fanout(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  defender_slot : Int,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
  hits_count? : Int = 1,
) -> Array[(Double, SwitchingGameState)] {
  let atk_megaed = if attacker_is_me { state.my_megaed } else { state.opp_megaed }
  let def_megaed = if attacker_is_me { state.opp_megaed } else { state.my_megaed }
  let def_mega = mega_at(def_megaed, defender_slot)
  match holder_at(defender_team, defender_slot, def_mega) {
    None => attract_identity(state)
    Some(def) => {
      if def.ability != "メロメロボディ" {
        return attract_identity(state)
      }
      if hits_count <= 0 {
        return attract_identity(state)
      }
      let atk_hps = if attacker_is_me { state.my_hps } else { state.opp_hps }
      let def_hps = if attacker_is_me { state.opp_hps } else { state.my_hps }
      if slot_hp(atk_hps, attacker_slot) <= 0 || slot_hp(def_hps, defender_slot) <= 0 {
        return attract_identity(state)
      }
      if attract_flag_of(state, attacker_is_me) > 0 {
        return attract_identity(state)
      }
      let atk_mega = mega_at(atk_megaed, attacker_slot)
      match holder_at(attacker_team, attacker_slot, atk_mega) {
        None => attract_identity(state)
        Some(atk) => {
          if is_mold_breaker_ability(atk.ability) ||
            attract_blocked("", atk.ability) {
            return attract_identity(state)
          }
          let sr = @damage.resolve_stat_resolution(
            mv,
            atk_atk=atk.pokemon.atk,
            atk_spa=atk.pokemon.spa,
            def_def=def.pokemon.def_,
            def_spd=def.pokemon.spd,
            atk_ability=atk.ability,
            def_ability=def.ability,
            critical=false,
          )
          if !@damage.resolve_move_contact(mv, sr.force_contact) {
            return attract_identity(state)
          }
          if !opposite_genders(resolve_gender(atk), resolve_gender(def)) {
            return attract_identity(state)
          }
          let p = flinch_probability(CUTE_CHARM_CHANCE, hits_count)
          if p <= 0.0 {
            return attract_identity(state)
          }
          let landed = attract_landed(state, attacker_is_me, attacker_slot, atk)
          if p >= 1.0 {
            return [(1.0, landed)]
          }
          [(1.0 - p, state), (p, landed)]
        }
      }
    }
  }
}

///|
/// すでにメロメロ、または相手の メロメロ が今ターン付与しうるときだけ試行を遅らせる。
/// 技名が違い、フラグも 0 なら false。交代相手には付与できないので遅らせない
/// (事前抽選のまま。交代側がフラグを消してから攻撃する)。
fn attract_roll_deferred(
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
  // 相手が交代するときは遅らせない。50% は振らず、交代がフラグを消してから
  // 攻撃する。試行はフラグ 0 のときと同じ位置に残る。
  let opp_is_move = match opp_action {
    UseMove(_) | Mega(_) => true
    Switch(_) => false
  }
  if !opp_is_move {
    return false
  }
  if attract_live_state(state, is_me) {
    return true
  }
  let opp_active = if is_me { state.opp_active } else { state.my_active }
  match action_move_of(opp_team, opp_active, opp_action) {
    None => false
    Some(mv) => {
      if !attract_move(mv) {
        return false
      }
      let atk_megaed = if is_me { state.opp_megaed } else { state.my_megaed }
      let def_megaed = if is_me { state.my_megaed } else { state.opp_megaed }
      match (
        holder_at(opp_team, opp_active, mega_at(atk_megaed, opp_active)),
        holder_at(team, active, mega_at(def_megaed, active)),
      ) {
        (Some(atk), Some(def)) => {
          if slot_hp(if is_me { state.my_hps } else { state.opp_hps }, active) <= 0 {
            return false
          }
          if attract_blocked(atk.ability, def.ability) {
            return false
          }
          opposite_genders(resolve_gender(atk), resolve_gender(def))
        }
        _ => false
      }
    }
  }
}

///|
/// 行動前のメロメロ。起きている枝だけ 50% で技を出さない (まひ・こんらんは振らない)。
/// 動けた 50% は既存の `resolve_pending_after_flinch` (まひ、それからこんらん)。
/// 眠ったまま / 凍ったままは 50% を掛けない。
fn resolve_while_attracted(
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
  let thaws = freeze_move_thaws_user(pre_state, is_me, user_team, UseMove(mv_idx))
  let prefixes = confusion_awake_prefixes(status_now, thaws)
  let result : Array[(Double, SwitchingGameState)] = []
  for i = 0; i < prefixes.length(); i = i + 1 {
    let (p_pre, st, awake) = prefixes[i]
    let ws_st = ws_with_status(ws, is_me, slot, st)
    if !awake {
      result.push((p_pre, ws_to_state(ws_st, bump_turn=false)))
    } else {
      result.push((p_pre * ATTRACT_IMMOBILIZE_RATE, ws_to_state(ws_st, bump_turn=false)))
      let acted = resolve_pending_after_flinch(
        ws_st, is_me, mv, mv_idx, mega_now, def_mega_now, pre_state, my_team, opp_team,
        dmg_cache, foe_move,
      )
      for j = 0; j < acted.length(); j = j + 1 {
        let (p, s) = acted[j]
        result.push((p_pre * ATTRACT_IMMOBILIZE_RATE * p, s))
      }
    }
  }
  result
}

///|
/// MC: メロメロ技。名前が違うときは乱数を引かず `cur` を返す。
fn mc_apply_attract_move(
  defender : Combatant,
  defender_hp : Int,
  attacker : Combatant,
  attacker_hp : Int,
  attacker_ability : String,
  mv : @model.Move,
  cur : Int,
  defender_consumed : Array[Bool],
  defender_slot : Int,
) -> Int {
  if !attract_move(mv) || cur > 0 || defender_hp <= 0 || attacker_hp <= 0 {
    return cur
  }
  if attract_blocked(attacker_ability, defender.ability) {
    return cur
  }
  if !opposite_genders(resolve_gender(attacker), resolve_gender(defender)) {
    return cur
  }
  let herb = defender.item == "メンタルハーブ" &&
    defender_slot >= 0 &&
    defender_slot < defender_consumed.length() &&
    !defender_consumed[defender_slot]
  if herb {
    defender_consumed[defender_slot] = true
    return cur
  }
  1
}

///|
/// MC: メロメロボディ。特性が違う、接触でない、性別が合わないときは乱数を引かない。
/// 命中数は 1 (こんらんの MC と同じ。DP は `1 - 0.7^n`)。
fn mc_apply_cute_charm(
  rng : @random.Rand,
  mv : @model.Move,
  attacker : Combatant,
  attacker_hp : Int,
  attacker_attract : Int,
  attacker_consumed : Array[Bool],
  attacker_slot : Int,
  defender : Combatant,
  defender_hp : Int,
  immune : Bool,
  hp_lost : Int,
) -> Int {
  if defender.ability != "メロメロボディ" ||
    attacker_attract > 0 ||
    immune ||
    attacker_hp <= 0 ||
    defender_hp <= 0 {
    return attacker_attract
  }
  if mv.power > 0 && hp_lost <= 0 {
    return attacker_attract
  }
  if is_mold_breaker_ability(attacker.ability) || attract_blocked("", attacker.ability) {
    return attacker_attract
  }
  let sr = @damage.resolve_stat_resolution(
    mv,
    atk_atk=attacker.pokemon.atk,
    atk_spa=attacker.pokemon.spa,
    def_def=defender.pokemon.def_,
    def_spd=defender.pokemon.spd,
    atk_ability=attacker.ability,
    def_ability=defender.ability,
    critical=false,
  )
  if !@damage.resolve_move_contact(mv, sr.force_contact) {
    return attacker_attract
  }
  if !opposite_genders(resolve_gender(attacker), resolve_gender(defender)) {
    return attacker_attract
  }
  if !rand_bool(rng, flinch_probability(CUTE_CHARM_CHANCE, 1)) {
    return attacker_attract
  }
  let herb = attacker.item == "メンタルハーブ" &&
    attacker_slot >= 0 &&
    attacker_slot < attacker_consumed.length() &&
    !attacker_consumed[attacker_slot]
  if herb {
    attacker_consumed[attacker_slot] = true
    return attacker_attract
  }
  1
}

///|
/// 先攻の技のあと。メロメロ技は乱数なし。メロメロボディは付与しうるときだけ 1 回引く。
fn mc_apply_attract_effects(
  rng : @random.Rand,
  mv : @model.Move,
  attacker : Combatant,
  attacker_hp : Int,
  attacker_attract : Int,
  attacker_consumed : Array[Bool],
  attacker_slot : Int,
  defender : Combatant,
  defender_hp : Int,
  defender_attract : Int,
  defender_consumed : Array[Bool],
  defender_slot : Int,
  immune : Bool,
  hp_lost : Int,
) -> (Int, Int) {
  let def_next = mc_apply_attract_move(
    defender, defender_hp, attacker, attacker_hp, attacker.ability, mv, defender_attract,
    defender_consumed, defender_slot,
  )
  let atk_next = mc_apply_cute_charm(
    rng, mv, attacker, attacker_hp, attacker_attract, attacker_consumed, attacker_slot,
    defender, defender_hp, immune, hp_lost,
  )
  (atk_next, def_next)
}

///|
/// フラグが生きている、または相手の メロメロ が付与しうる。反動・交代では false。
fn mc_attract_pending(
  flag : Int,
  self_hp : Int,
  source_hp : Int,
  recharging : Bool,
  foe_mv : @model.Move,
  foe : Combatant,
  self_c : Combatant,
) -> Bool {
  if recharging {
    return false
  }
  if flag > 0 && self_hp > 0 && source_hp > 0 {
    return true
  }
  if !attract_move(foe_mv) || self_hp <= 0 || source_hp <= 0 {
    return false
  }
  if attract_blocked(foe.ability, self_c.ability) {
    return false
  }
  opposite_genders(resolve_gender(foe), resolve_gender(self_c))
}

///|
fn mc_attract_live(flag : Int, self_hp : Int, source_hp : Int) -> Bool {
  flag > 0 && self_hp > 0 && source_hp > 0
}

///|
/// MC の行動前メロメロ。戻り値は (状態, 行動するか, 外れたか, こんらんカウンタ, 自傷したか)。
/// 呼び出しはフラグが生きていて、ひるみでないときだけ。
/// 眠り / こおりで止まったときは 50% を引かない。動けたあとは既存のまひ・こんらん。
fn mc_resolve_attracted(
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
  let awake = match status {
    @model.Freeze(_) | @model.Sleep(_) | @model.RestSleep(_) => @model.StatusCondition::None
    other => other
  }
  if rand_bool(rng, ATTRACT_IMMOBILIZE_RATE) {
    return (awake, false, false, time, false)
  }
  if time > 0 {
    return mc_resolve_confused(rng, awake, mv_acc, false, time)
  }
  let (st, acts, missed) = mc_resolve_attempt(awake, mv_acc, rng, thaws_user=false)
  (st, acts, missed, time, false)
}
