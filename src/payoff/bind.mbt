///|
/// バインド (Bound)。Champions `champout` `50e7233` の `BTR_STATE_SYN_54_02`:
/// 「４ー５ターンの間 / ターン終わりに最大ＨＰの１／８のダメージを受ける。 / 交代ができない。」
/// 英語は "For 4–5 turns ... 1/8 of its max HP ... cannot be switched out"。
///
/// 4 と 5 の比率は本文に無い。等確率 (`0.5` / `0.5`) にする。Showdown 現行の
/// `partiallytrapped.durationCallback` (`random(5, 7)` で 5 か 6) は採らない。
/// 本文が 4–5 と書く。
///
/// ダメージは切り捨ての `max / 8`。1 未満は 0 (砂・どくと同じ。Showdown の
/// 間接ダメージ下限 1 は使わない)。分母は `status_slip_max_hp` (バトルの HP)。
/// しめつけバンド (`ITEMINFO_SYN_544`) は付与した側の持ち物で 1/8 を 1/6 にする。
/// 持続は延ばさない。ねばりのかぎづめもこうこうのしっぽも `itemname` に無い。
///
/// マジックガード (`TOKUSEIINFO_SYN_098`: 「攻撃以外ではダメージが効かない」)
/// はダメージだけ 0。カウンタと交代不可は残る。
///
/// 付与した側がひんし、または交代で場を離れるとダメージを入れずに解除する。
/// シングルの付与元は相手のアクティブなので、どちらかの交代で両方 0。
/// 本文は解除条件を書かない。Showdown `partiallytrapped.onResidual` が
/// source が場にいない / HP 0 ならダメージ前に volatile を消す。
///
/// きれいなぬけがら (`ITEMINFO_SYN_295`) と にげあし (`TOKUSEIINFO_SYN_050`) は
/// 「交代を邪魔する効果を無視して交代できる」。バインドの「交代ができない」
/// をこれで抜ける。ダメージは受ける。
///
/// ゴーストの交代はバインド本文に無い。`help_10_05_00` はにげられない状態
/// (Can't Escape) だけ「Ghost-type Pokémon are unaffected」。Showdown の
/// `tryTrap` は partiallytrapped でもゴーストを捕えない。交代だけ許可し、
/// ダメージは入れる。

///|
/// 付与ターン数。短い方を先に fanout する (等確率の加算順を固定する)。
const BIND_TURNS_SHORT : Int = 4

///|
const BIND_TURNS_LONG : Int = 5

///|
/// `wazainfo_syn` が「相手をバインド状態にする。」と書く技。
/// `waza.json` の `available = 1` かつ本文があるものだけ。
/// からではさむは `available = 0` で `buf_ref` も本文も無い。
/// マグマストーム / サンダープリズンは `buf_ref` に 45 があるが
/// `available = 0` で `WAZAINFO_SYN_463` / `819` の本文が無い。入れない。
fn move_binds(name : String) -> Bool {
  name == "しめつける" ||
  name == "まきつく" ||
  name == "ほのおのうず" ||
  name == "うずしお" ||
  name == "すなじごく" ||
  name == "まとわりつく" ||
  name == "トラバサミ"
}

///|
/// バインド中でも交代できるか。`turns <= 0` は常に true (技も乱数も増やさない)。
/// メガ後のタイプ・特性と Protean ロックを見る。道具はメガで変わらない。
fn bind_switch_free(
  turns : Int,
  holder : Combatant,
  is_mega : Bool,
  protean_locked : String,
) -> Bool {
  if turns <= 0 {
    return true
  }
  let eff = effective_combatant(holder, is_mega, protean_locked~)
  if eff.pokemon.type1 == "ゴースト" || eff.pokemon.type2 == "ゴースト" {
    return true
  }
  if eff.item == "きれいなぬけがら" || eff.ability == "にげあし" {
    return true
  }
  false
}

///|
fn with_bind(
  state : SwitchingGameState,
  target_is_me : Bool,
  turns : Int,
) -> SwitchingGameState {
  if target_is_me {
    if state.my_bind == turns {
      state
    } else {
      { ..state, my_bind: turns }
    }
  } else if state.opp_bind == turns {
    state
  } else {
    { ..state, opp_bind: turns }
  }
}

///|
/// 命中して生き残った相手への付与。バインド技でない、すでにバインド、ひんしは
/// 同じ state を確率 1 で返す (分岐を増やさない)。免疫 leg は呼び出し側が
/// この関数に来ない (`hits_count == 0`)。成功時は 4 ターンを先、5 ターンを後に
/// 等分する。上書きしない。
fn maybe_apply_bind_fanout(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  mv : @model.Move,
) -> Array[(Double, SwitchingGameState)] {
  if !move_binds(mv.name) {
    return [(1.0, state)]
  }
  let hps = if target_is_me { state.my_hps } else { state.opp_hps }
  if target_slot < 0 || target_slot >= hps.length() || hps[target_slot] <= 0 {
    return [(1.0, state)]
  }
  let cur = if target_is_me { state.my_bind } else { state.opp_bind }
  if cur > 0 {
    return [(1.0, state)]
  }
  [
    (0.5, with_bind(state, target_is_me, BIND_TURNS_SHORT)),
    (0.5, with_bind(state, target_is_me, BIND_TURNS_LONG)),
  ]
}

///|
/// 交代が片方でもあれば両方 0。付与された側が出ても、付与した側が出ても終わる。
/// 交代が無いときはカウンタを動かさない (EOT が減算する)。
fn bind_flags_after_switch(
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
    (state.my_bind, state.opp_bind)
  }
}

///|
/// 1 体分。`turns <= 0` は HP も 0 のまま。source か自分の HP が 0 なら
/// ダメージを入れずに 0。マジックガードはダメージ 0 でカウンタだけ減る。
/// しめつけバンドは source の持ち物。
fn tick_one_bind(
  turns : Int,
  self_hp : Int,
  source_hp : Int,
  self_max : Int,
  self_ability : String,
  source_item : String,
) -> (Int, Int) {
  if turns <= 0 {
    return (self_hp, 0)
  }
  if self_hp <= 0 || source_hp <= 0 {
    return (self_hp, 0)
  }
  let dmg = if self_ability == "マジックガード" {
    0
  } else {
    let div = if source_item == "しめつけバンド" { 6 } else { 8 }
    self_max / div
  }
  let hp = if self_hp - dmg < 0 { 0 } else { self_hp - dmg }
  (hp, turns - 1)
}

///|
/// ターン終了のバインド。両方 0 のときは引数をそのまま返す (HP を計算しない)。
/// 自分側を先、相手側を後。自分側のダメージで付与元がひんしになったら、
/// 相手側はダメージを入れずに解除する。素早さ順は採らない (やどりぎと同じ固定順)。
fn apply_bind_eot_pair(
  my_bind : Int,
  opp_bind : Int,
  my_hp : Int,
  opp_hp : Int,
  my_max : Int,
  opp_max : Int,
  my_ability : String,
  opp_ability : String,
  my_item : String,
  opp_item : String,
) -> (Int, Int, Int, Int) {
  if my_bind <= 0 && opp_bind <= 0 {
    return (my_hp, opp_hp, my_bind, opp_bind)
  }
  // 自分のバインドの付与元は相手。相手のバインドの付与元は自分。
  let (my_hp1, my_bind1) = tick_one_bind(
    my_bind, my_hp, opp_hp, my_max, my_ability, opp_item,
  )
  let (opp_hp1, opp_bind1) = tick_one_bind(
    opp_bind, opp_hp, my_hp1, opp_max, opp_ability, my_item,
  )
  (my_hp1, opp_hp1, my_bind1, opp_bind1)
}

///|
/// MC の付与。バインド技でない、免疫、すでにバインド、ひんしは乱数を引かない。
/// 成功時だけ `rng.int(limit=2)` で 4 か 5。
fn mc_apply_bind(
  rng : @random.Rand,
  mv : @model.Move,
  defender_hp : Int,
  cur : Int,
  immune : Bool,
) -> Int {
  if !move_binds(mv.name) || immune || cur > 0 || defender_hp <= 0 {
    return cur
  }
  if rng.int(limit=2) == 0 {
    BIND_TURNS_SHORT
  } else {
    BIND_TURNS_LONG
  }
}
