///|
/// Champions の優先度特性。
///
/// いたずらごころ (`TOKUSEIINFO_SYN_158`, Prankster):
/// "Increases the priority of the Pokémon’s status moves by 1 stage.
/// However, the Pokémon’s status moves no longer work against Dark-type Pokémon."
/// 日本語: 「変化技の優先度が１段階上がる。代わりに　あくタイプの　ポケモンには
/// 変化技が効かなくなる。」
///
/// はやてのつばさ (`TOKUSEIINFO_SYN_177`, Gale Wings):
/// "Increases the priority of the Pokémon’s Flying-type moves by 1 stage while
/// its HP is full."
/// 日本語: 「ＨＰが満タンの時　ひこうタイプの技の優先度が１段階上がる。」
///
/// ヒーリングシフト (Triage) は `champout/rom-txt/*/tokusei.json` に名前が無く、
/// `tokuseiinfo_syn.json` にも本文が無い。Showdown の heal フラグ +3 は入れない。
///
/// 満タンは戦闘状態の HP がスロット初期値 `pokemon.hp` 以上であること。
/// `effective_hp` (ダメ計の実数値) は初期 HP とスケールが違うので使わない。
/// `max_hp <= 0` は満タンにしない。
///
/// 行動順・はやてがえし・サイコフィールドの既存ブロックは、この実効優先度を見る。
/// ねこだまし / であいがしらの fresh 失敗は優先度ゲートではない。

///|
/// 特性が足す優先度。該当しなければ 0 (既存の `Move.priority` のまま)。
pub fn ability_priority_bonus(
  ability : String,
  mv : @model.Move,
  hp : Int,
  max_hp : Int,
) -> Int {
  if ability == "いたずらごころ" && mv.category == @model.Status {
    1
  } else if ability == "はやてのつばさ" &&
    mv.type_ == "ひこう" &&
    max_hp > 0 &&
    hp >= max_hp {
    1
  } else {
    0
  }
}

///|
/// `Move.priority` に特性補正を足した行動順の優先度。
pub fn effective_priority(
  ability : String,
  mv : @model.Move,
  hp : Int,
  max_hp : Int,
) -> Int {
  mv.priority + ability_priority_bonus(ability, mv, hp, max_hp)
}

///|
/// メガ後の実効特性と、状態 HP / `pokemon.hp` で実効優先度を決める。
pub fn combatant_move_priority(
  c : Combatant,
  mv : @model.Move,
  hp : Int,
  is_mega : Bool,
) -> Int {
  let eff = effective_combatant(c, is_mega)
  effective_priority(eff.ability, mv, hp, eff.pokemon.hp)
}

///|
/// 変化技が相手に効くペイロードを持つか。自分強化・天候・フィールドだけでは false。
/// 効果未モデルの変化技 (まもる 等) も false。あく無効はここが true のときだけ掛ける。
fn status_move_hits_foe(mv : @model.Move) -> Bool {
  match mv.status_effect {
    Some(_) => return true
    None => ()
  }
  for e in mv.stat_effects {
    if e.target != 0 {
      return true
    }
  }
  match mv.healing {
    Some(@model.LeechSeed) | Some(@model.PainSplit) => true
    _ => false
  }
}

///|
/// いたずらごころの変化技が、あくタイプの相手には効かない。
/// 自分対象だけの変化技、ダメージ技、あく以外には false。
/// 防御タイプはメガ後 + へんげんじざいのロック (テラスタルは既存どおり置き換えない)。
pub fn prankster_status_blocked(
  attacker : Combatant,
  attacker_mega : Bool,
  mv : @model.Move,
  defender : Combatant,
  defender_mega : Bool,
  defender_protean : String,
) -> Bool {
  let atk = effective_combatant(attacker, attacker_mega)
  if atk.ability != "いたずらごころ" {
    return false
  }
  if mv.category != @model.Status || !status_move_hits_foe(mv) {
    return false
  }
  let def = effective_combatant(
    defender,
    defender_mega,
    protean_locked=defender_protean,
  )
  def.pokemon.type1 == "あく" || def.pokemon.type2 == "あく"
}
