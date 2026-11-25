///|
/// ほろびのうた。Champions `champout` `50e7233`。
/// `waza.json` id 195 だけが `buf_ref` 40 で `available = 1`。
/// `WAZAINFO_SYN_195`: 「場の全員をほろび状態にする。」
/// `BTR_STATE_SYN_47_02`: 「ほろび状態になった３ターン後にひんしになる。」
/// `BTL_STRID_STD_HorobiNoUta`: 「ほろびのうたを聴いたポケモンは３ターン後に滅びてしまう！」
///
/// 開始値 4 は champout に無い。Showdown `conditions.ts` の perishsong
/// `duration: 4` と `test/sim/moves/perishsong.js`（4 回の行動のあとひんし）
/// を採る。使ったターンの終了も含めて 1 ずつ減り、1 の終了でひんし。
/// 画面に出る最初の数字が 3 なので、本文の「３ターン後」と一致する。
///
/// まもるは防がない。Showdown `moves.ts` の perishsong に `protect` フラグが
/// 無い。champout の音のヘルプ (`help_11_15_02`) はぼうおんとみがわりだけで、
/// まもるを抜けるとは書いていない。音技一般はここでは変えない。
///
/// ぼうおん (`TOKUSEIINFO_SYN_043`: 「音の技が効かない。」) は自分を含めて
/// カウントを受けない。Showdown 現行は使用者本人には付く (`target !== source`)。
/// その例外は champout にも依頼にも無いので採らない。かたやぶりは相手の
/// ぼうおんだけを、このファイルの中で無視する。ディスクキーの特性リストには
/// 足さない。
///
/// マジックガードでは防げない。ひんしはダメージではないので HP を 0 にする。
/// きあいのタスキもがんじょうも見ない。
///
/// 交代した側のカウントだけ消える。相手側は残る。すでに 1 以上なら重ねない。
/// バトンタッチは揮発を渡さない（バインドと同じく範囲外）。
/// 交代不可は既存のバインドだけ。ここから新しい捕縛は足さない。

///|
/// 付与直後の内部カウント。最初のターン終了で 3 になる。
const PERISH_START : Int = 4

///|
fn is_perish_song(name : String) -> Bool {
  name == "ほろびのうた"
}

///|
/// 交代した側だけ 0。技を撃った側はそのまま。0 のまま交代しても 0。
fn perish_after_switch(count : Int, action : ActionKind) -> Int {
  match action {
    Switch(_) => 0
    _ => count
  }
}

///|
/// ぼうおんで受けないか。使用者自身のぼうおんはかたやぶりで貫かない。
/// 相手のぼうおんだけ、使用者のかたやぶりで貫く。
fn perish_blocked(
  singer_ability : String,
  target_ability : String,
  target_is_singer : Bool,
) -> Bool {
  if target_ability != "ぼうおん" {
    return false
  }
  if target_is_singer {
    return true
  }
  !is_mold_breaker_ability(singer_ability)
}

///|
/// ひんし、ぼうおん、すでにカウントがあるときは今の値を返す。
fn perish_grant(current : Int, hp : Int, blocked : Bool) -> Int {
  if hp <= 0 || blocked || current > 0 {
    current
  } else {
    PERISH_START
  }
}

///|
fn perish_side_count(state : SwitchingGameState, is_me : Bool) -> Int {
  if is_me { state.my_perish } else { state.opp_perish }
}

///|
fn perish_side_hp(state : SwitchingGameState, is_me : Bool, slot : Int) -> Int {
  let hps = if is_me { state.my_hps } else { state.opp_hps }
  if slot < 0 || slot >= hps.length() {
    0
  } else {
    hps[slot]
  }
}

///|
fn perish_side_mega(state : SwitchingGameState, is_me : Bool, slot : Int) -> Bool {
  let megaed = if is_me { state.my_megaed } else { state.opp_megaed }
  slot >= 0 && slot < megaed.length() && megaed[slot]
}

///|
/// ほろびのうたの単一 leaf。確率は 1。Protean は残す。
/// `foe_vanished` の相手には付けない。使用者には付ける。
fn perish_song_outcomes(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  defender_slot : Int,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
  foe_vanished : Bool,
) -> Array[(Double, SwitchingGameState)] {
  let state = with_protean_on_use_state(
    state, attacker_is_me, attacker_slot, attacker_team, mv,
  )
  if attacker_slot < 0 ||
    attacker_slot >= attacker_team.length() ||
    defender_slot < 0 ||
    defender_slot >= defender_team.length() {
    return [(1.0, state)]
  }
  let singer_mega = perish_side_mega(state, attacker_is_me, attacker_slot)
  let foe_mega = perish_side_mega(state, !attacker_is_me, defender_slot)
  let singer = effective_combatant(attacker_team[attacker_slot], singer_mega)
  let foe = effective_combatant(defender_team[defender_slot], foe_mega)
  let singer_next = perish_grant(
    perish_side_count(state, attacker_is_me),
    perish_side_hp(state, attacker_is_me, attacker_slot),
    perish_blocked(singer.ability, singer.ability, true),
  )
  let foe_cur = perish_side_count(state, !attacker_is_me)
  let foe_next = if foe_vanished {
    foe_cur
  } else {
    perish_grant(
      foe_cur,
      perish_side_hp(state, !attacker_is_me, defender_slot),
      perish_blocked(singer.ability, foe.ability, false),
    )
  }
  let next = if attacker_is_me {
    { ..state, my_perish: singer_next, opp_perish: foe_next }
  } else {
    { ..state, opp_perish: singer_next, my_perish: foe_next }
  }
  [(1.0, next)]
}

///|
/// アクティブ以外に生きているポケモンがいるか。
fn perish_other_alive(hps : Array[Int], active : Int) -> Bool {
  let mut i = 0
  for hp in hps {
    if i != active && hp > 0 {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// 残カウントを 1 減らす。1 ならひんし。すでにひんし、または 0 はそのまま。
fn perish_decrement(count : Int, hp : Int) -> (Int, Int) {
  if count <= 0 {
    (hp, 0)
  } else if hp <= 0 {
    (hp, count)
  } else if count == 1 {
    (0, 0)
  } else {
    (hp, count - 1)
  }
}

///|
/// ターン終了の素早さ。技の優先度は見ない。まひは最後に 1/2。
fn perish_speed(
  c : Combatant,
  mega : Bool,
  ranks : Array[Int],
  para : Bool,
  item_consumed : Bool,
) -> Int {
  let eff = effective_combatant(c, mega)
  let staged = if ranks.length() > 4 {
    effective_speed(eff.pokemon.spe, ranks[4])
  } else {
    eff.pokemon.spe
  }
  let scarf = speed_after_choice_scarf(staged, eff.item, item_consumed)
  if para { scarf / 2 } else { scarf }
}

///|
/// ターン終了。両方 0 のときは HP を読まない。
/// 両方ともこの終了でひんしになるときだけ素早さ順。速い側が最後の 1 体なら
/// 遅い側は減らさない。Showdown は `faint` で戦闘が終わると残りの residual
/// を打たない (`test/sim/moves/perishsong.js` の Speed 順)。同速は両方ひんし。
fn apply_perish_eot_pair(
  my_count : Int,
  opp_count : Int,
  my_hp : Int,
  opp_hp : Int,
  my_c : Combatant,
  opp_c : Combatant,
  my_mega : Bool,
  opp_mega : Bool,
  my_ranks : Array[Int],
  opp_ranks : Array[Int],
  my_para : Bool,
  opp_para : Bool,
  my_item_consumed : Bool,
  opp_item_consumed : Bool,
  my_other_alive : Bool,
  opp_other_alive : Bool,
) -> (Int, Int, Int, Int) {
  if my_count <= 0 && opp_count <= 0 {
    return (my_hp, opp_hp, 0, 0)
  }
  let my_would = my_count == 1 && my_hp > 0
  let opp_would = opp_count == 1 && opp_hp > 0
  if my_would && opp_would {
    let my_spd = perish_speed(my_c, my_mega, my_ranks, my_para, my_item_consumed)
    let opp_spd = perish_speed(
      opp_c, opp_mega, opp_ranks, opp_para, opp_item_consumed,
    )
    if my_spd >= opp_spd {
      if my_spd > opp_spd && !my_other_alive {
        (0, opp_hp, 0, opp_count)
      } else {
        (0, 0, 0, 0)
      }
    } else if !opp_other_alive {
      (my_hp, 0, my_count, 0)
    } else {
      (0, 0, 0, 0)
    }
  } else {
    let (my_hp1, my_c1) = perish_decrement(my_count, my_hp)
    let (opp_hp1, opp_c1) = perish_decrement(opp_count, opp_hp)
    (my_hp1, opp_hp1, my_c1, opp_c1)
  }
}

///|
/// ほろびのうたなら単一 leaf。それ以外は `None`（呼び出し側は従来の解決に進む）。
fn perish_song_or_none(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  defender_slot : Int,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
  foe_vanished_name : String,
) -> Array[(Double, SwitchingGameState)]? {
  if !is_perish_song(mv.name) {
    return None
  }
  let vanished = foe_vanished_name != "" &&
    !two_turn_hits(mv.name, foe_vanished_name)
  Some(
    perish_song_outcomes(
      state,
      attacker_is_me,
      attacker_slot,
      defender_slot,
      attacker_team,
      defender_team,
      mv,
      vanished,
    ),
  )
}

///|
/// MC の付与。ほろびのうた以外は引数をそのまま返す。乱数は引かない。
/// `foe_vanished` は姿を消している技名。空なら場にいる。
fn mc_apply_perish(
  mv : @model.Move,
  singer : Combatant,
  singer_hp : Int,
  singer_count : Int,
  foe : Combatant,
  foe_hp : Int,
  foe_count : Int,
  foe_vanished : String,
) -> (Int, Int) {
  if !is_perish_song(mv.name) {
    return (singer_count, foe_count)
  }
  let singer_eff = effective_combatant(singer, false)
  let foe_eff = effective_combatant(foe, false)
  let singer_next = perish_grant(
    singer_count,
    singer_hp,
    perish_blocked(singer_eff.ability, singer_eff.ability, true),
  )
  let foe_next = if foe_vanished != "" {
    foe_count
  } else {
    perish_grant(
      foe_count,
      foe_hp,
      perish_blocked(singer_eff.ability, foe_eff.ability, false),
    )
  }
  (singer_next, foe_next)
}
