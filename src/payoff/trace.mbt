///|
/// トレース (Trace)。
///
/// champout `50e7233` `rom-txt/jpn/tokuseiinfo_syn.json` の
/// `TOKUSEIINFO_SYN_036`: 「登場した時　相手の特性と同じ特性になる。」
/// 英語 (`usa/tokuseiinfo_syn.json`): "When the Pokémon enters a battle, it
/// changes its Ability to match that of an opponent."
/// コピーできない特性の一覧は champout に無い。拒否リストは Showdown
/// (`data/abilities.ts`) の `flags.notrace` を二番目の根拠にする。
/// ふしぎなまもり (Wonder Guard) の flags に `notrace` は無いのでコピーする。
///
/// モデルはシングルだけ。相手は場にいる 1 体。コピーした特性は
/// `SwitchingGameState.{my,opp}_traced` に置き、`overlay_traced_team` が
/// 実効特性にする。配列が全 `""`（または長さ 0）のときは元の team 参照を
/// そのまま返す。トレースが無い入力はこの分岐に入らない。
///
/// コピーした登場時特性のうち、この層がモデルしているのはいかくだけ。
/// Showdown の `setAbility` はコピー先の `onStart` を走らせる。champout は
/// その文を書かない。いかくだけ、コピーした直後に既存の登場時処理へ渡す。
/// 天候を変える特性をコピーしても天候は変えない（所持していても未モデル）。
///
/// メガ進化の瞬間にはコピーしない。champout は「登場した時」とだけ書き、
/// いかくもメガでは再発動しない。次に登場したとき、メガ後の特性がトレース
/// ならそこでコピーする。

///|
/// Showdown `notrace` のうち、champout の tokusei に日本語名があるもの。
/// フラワーギフトとアイスフェイスは tokusei に無いが、Showdown が `notrace`
/// で、呼び方が日本語として安定しているので拒否する。
fn ability_uncopyable_by_trace(ability : String) -> Bool {
  match ability {
    "" => true
    "トレース" => true
    "ばけのかわ" => true
    "てんきや" => true
    "はらぺこスイッチ" => true
    "イリュージョン" => true
    "かわりもの" => true
    "レシーバー" => true
    "バトルスイッチ" => true
    "マイティチェンジ" => true
    "フラワーギフト" => true
    "アイスフェイス" => true
    _ => false
  }
}

///|
/// コピー結果。`""` はコピー失敗で、スロットはトレースのまま。
pub fn trace_copied_ability(source : String) -> String {
  if ability_uncopyable_by_trace(source) {
    ""
  } else {
    source
  }
}

///|
fn slot_is_mega(megaed : Array[Bool], slot : Int) -> Bool {
  slot >= 0 && slot < megaed.length() && megaed[slot]
}

///|
/// その slot の実効特性。トレース配列が非空ならそれを優先する。
/// メガ進化した直後（`mega_now`）は配列を見ず、メガ後の特性を返す。
fn traced_slot_ability(
  team : Array[Combatant],
  slot : Int,
  megaed : Array[Bool],
  traced : Array[String],
  mega_now? : Bool = false,
) -> String {
  if slot < 0 || slot >= team.length() {
    return ""
  }
  if !mega_now && slot < traced.length() && traced[slot] != "" {
    return traced[slot]
  }
  let mega = mega_now || slot_is_mega(megaed, slot)
  effective_combatant(team[slot], mega).ability
}

///|
fn with_ability(c : Combatant, ability : String, mega : Bool) -> Combatant {
  match (mega, c.mega_form) {
    (true, Some(m)) => { ..c, mega_form: Some({ ..m, ability }) }
    _ => { ..c, ability }
  }
}

///|
/// `traced` が全 `""` または長さ 0 なら `base` を同じ参照で返す。
/// メガ済み slot は `mega_form.ability` を書き換えた複製にする
/// （`effective_combatant` はメガ中 `c.ability` を見ない）。
pub fn overlay_traced_team(
  base : Array[Combatant],
  traced : Array[String],
  megaed : Array[Bool],
) -> Array[Combatant] {
  let n = if traced.length() < base.length() {
    traced.length()
  } else {
    base.length()
  }
  let mut any = false
  for i in 0..<n {
    if traced[i] != "" {
      any = true
      break
    }
  }
  if !any {
    return base
  }
  let out = base.copy()
  for i in 0..<n {
    if traced[i] != "" {
      out[i] = with_ability(out[i], traced[i], slot_is_mega(megaed, i))
    }
  }
  out
}

///|
/// このターンにメガ進化する active のトレースだけ外してから重ねる。
/// メガしない、またはその slot が `""` のときは `overlay_traced_team` と同じ。
pub fn overlay_except_mega_trigger(
  base : Array[Combatant],
  traced : Array[String],
  megaed : Array[Bool],
  active : Int,
  mega_trigger : Bool,
) -> Array[Combatant] {
  if !mega_trigger || active < 0 || active >= traced.length() || traced[active] == "" {
    return overlay_traced_team(base, traced, megaed)
  }
  let cleared = traced.copy()
  cleared[active] = ""
  overlay_traced_team(base, cleared, megaed)
}

///|
/// 交代先の実効特性がトレースのときだけ、相手の特性を載せた team を返す。
/// それ以外は `switching_team` と同じ参照。
pub fn preview_incoming_trace(
  switching_team : Array[Combatant],
  switch_slot : Int,
  switching_mega : Bool,
  stayer_ability : String,
) -> Array[Combatant] {
  if switch_slot < 0 || switch_slot >= switching_team.length() {
    return switching_team
  }
  let natural = effective_combatant(
    switching_team[switch_slot],
    switching_mega,
  ).ability
  if natural != "トレース" {
    return switching_team
  }
  let copied = trace_copied_ability(stayer_ability)
  if copied == "" {
    return switching_team
  }
  let out = switching_team.copy()
  out[switch_slot] = with_ability(out[switch_slot], copied, switching_mega)
  out
}

///|
/// MC 用。交代せず、またはトレースでないときは `incoming` と同じ参照。
pub fn preview_traced_combatant(
  incoming : Combatant,
  switching : Bool,
  stayer_ability : String,
) -> Combatant {
  if !switching || incoming.ability != "トレース" {
    return incoming
  }
  let copied = trace_copied_ability(stayer_ability)
  if copied == "" {
    return incoming
  }
  { ..incoming, ability: copied }
}

///|
fn clear_traced_slot(traced : Array[String], slot : Int) -> Unit {
  if slot >= 0 && slot < traced.length() {
    traced[slot] = ""
  }
}

///|
priv struct TraceEntrySnap {
  prob : Double
  my_ranks : Array[Int]
  opp_ranks : Array[Int]
  my_traced : Array[String]
  opp_traced : Array[String]
}

///|
fn copy_ints(dst : Array[Int], src : Array[Int]) -> Unit {
  let n = if dst.length() < src.length() { dst.length() } else { src.length() }
  for i in 0..<n {
    dst[i] = src[i]
  }
}

///|
fn copy_strs(dst : Array[String], src : Array[String]) -> Unit {
  let n = if dst.length() < src.length() { dst.length() } else { src.length() }
  for i in 0..<n {
    dst[i] = src[i]
  }
}

///|
fn ints_eq(a : Array[Int], b : Array[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn strs_eq(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn trace_snaps_equal(a : TraceEntrySnap, b : TraceEntrySnap) -> Bool {
  ints_eq(a.my_ranks, b.my_ranks) &&
  ints_eq(a.opp_ranks, b.opp_ranks) &&
  strs_eq(a.my_traced, b.my_traced) &&
  strs_eq(a.opp_traced, b.opp_traced)
}

///|
fn install_trace_snap(
  snap : TraceEntrySnap,
  my_ranks : Array[Int],
  opp_ranks : Array[Int],
  my_traced : Array[String],
  opp_traced : Array[String],
) -> Unit {
  copy_ints(my_ranks, snap.my_ranks)
  copy_ints(opp_ranks, snap.opp_ranks)
  copy_strs(my_traced, snap.my_traced)
  copy_strs(opp_traced, snap.opp_traced)
}

///|
fn entry_speed_of(
  team : Array[Combatant],
  slot : Int,
  megaed : Array[Bool],
  ranks : Array[Int],
  status : Array[@model.StatusCondition],
) -> Int {
  if slot < 0 || slot >= team.length() {
    return 0
  }
  let spe = effective_combatant(team[slot], slot_is_mega(megaed, slot)).pokemon.spe
  let boosted = if ranks.length() > 4 {
    effective_speed(spe, ranks[4])
  } else {
    spe
  }
  let para = slot < status.length() && is_paralyzed(status[slot])
  if para {
    boosted / 2
  } else {
    boosted
  }
}

///|
fn apply_one_entrant(
  entrant_team : Array[Combatant],
  entrant_slot : Int,
  entrant_megaed : Array[Bool],
  entrant_traced : Array[String],
  entrant_ranks : Array[Int],
  target_team : Array[Combatant],
  target_slot : Int,
  target_megaed : Array[Bool],
  target_traced : Array[String],
  target_ranks : Array[Int],
) -> Unit {
  if entrant_slot < 0 || entrant_slot >= entrant_team.length() {
    return
  }
  if entrant_slot < entrant_traced.length() {
    entrant_traced[entrant_slot] = ""
  }
  let natural = effective_combatant(
    entrant_team[entrant_slot],
    slot_is_mega(entrant_megaed, entrant_slot),
  ).ability
  let target_ab = traced_slot_ability(
    target_team, target_slot, target_megaed, target_traced,
  )
  let target_eff = if target_slot >= 0 && target_slot < target_team.length() {
    effective_combatant(
      target_team[target_slot],
      slot_is_mega(target_megaed, target_slot),
    )
  } else {
    entrant_team[entrant_slot]
  }
  if natural == "トレース" {
    let copied = trace_copied_ability(target_ab)
    if entrant_slot < entrant_traced.length() {
      entrant_traced[entrant_slot] = copied
    }
    if copied == "いかく" {
      apply_intimidate_on_entry(
        "いかく",
        target_ab,
        target_ranks,
        entrant_ranks,
        target_type1=target_eff.pokemon.type1,
        target_type2=target_eff.pokemon.type2,
      )
    }
  } else if natural == "いかく" {
    apply_intimidate_on_entry(
      "いかく",
      target_ab,
      target_ranks,
      entrant_ranks,
      target_type1=target_eff.pokemon.type1,
      target_type2=target_eff.pokemon.type2,
    )
  }
}

///|
/// 片側だけ交代したあとに呼ぶ。トレースでなければ何もしない。
/// 長さ 0 の配列も何もしない（未追跡の fixture）。
fn apply_trace_after_switch(
  entrant_team : Array[Combatant],
  entrant_slot : Int,
  entrant_megaed : Array[Bool],
  entrant_traced : Array[String],
  entrant_ranks : Array[Int],
  target_team : Array[Combatant],
  target_slot : Int,
  target_megaed : Array[Bool],
  target_traced : Array[String],
  target_ranks : Array[Int],
) -> Unit {
  if entrant_traced.length() == 0 {
    return
  }
  if entrant_slot < 0 || entrant_slot >= entrant_team.length() {
    return
  }
  let natural = effective_combatant(
    entrant_team[entrant_slot],
    slot_is_mega(entrant_megaed, entrant_slot),
  ).ability
  if natural != "トレース" {
    return
  }
  apply_one_entrant(
    entrant_team,
    entrant_slot,
    entrant_megaed,
    entrant_traced,
    entrant_ranks,
    target_team,
    target_slot,
    target_megaed,
    target_traced,
    target_ranks,
  )
}

///|
fn entrant_is_trace(
  team : Array[Combatant],
  slot : Int,
  megaed : Array[Bool],
) -> Bool {
  if slot < 0 || slot >= team.length() {
    return false
  }
  effective_combatant(team[slot], slot_is_mega(megaed, slot)).ability == "トレース"
}

///|
fn simulate_trace_order(
  my_first : Bool,
  my_team : Array[Combatant],
  my_slot : Int,
  my_megaed : Array[Bool],
  my_ranks : Array[Int],
  my_traced : Array[String],
  opp_team : Array[Combatant],
  opp_slot : Int,
  opp_megaed : Array[Bool],
  opp_ranks : Array[Int],
  opp_traced : Array[String],
) -> TraceEntrySnap {
  let my_ranks_s = my_ranks.copy()
  let opp_ranks_s = opp_ranks.copy()
  let my_traced_s = my_traced.copy()
  let opp_traced_s = opp_traced.copy()
  if my_first {
    apply_one_entrant(
      my_team, my_slot, my_megaed, my_traced_s, my_ranks_s,
      opp_team, opp_slot, opp_megaed, opp_traced_s, opp_ranks_s,
    )
    apply_one_entrant(
      opp_team, opp_slot, opp_megaed, opp_traced_s, opp_ranks_s,
      my_team, my_slot, my_megaed, my_traced_s, my_ranks_s,
    )
  } else {
    apply_one_entrant(
      opp_team, opp_slot, opp_megaed, opp_traced_s, opp_ranks_s,
      my_team, my_slot, my_megaed, my_traced_s, my_ranks_s,
    )
    apply_one_entrant(
      my_team, my_slot, my_megaed, my_traced_s, my_ranks_s,
      opp_team, opp_slot, opp_megaed, opp_traced_s, opp_ranks_s,
    )
  }
  {
    prob: 1.0,
    my_ranks: my_ranks_s,
    opp_ranks: opp_ranks_s,
    my_traced: my_traced_s,
    opp_traced: opp_traced_s,
  }
}

///|
/// 双方同時登場。どちらもトレースでない、または配列が未追跡なら `None`
/// （呼び出し側は従来のいかく 2 回を同じ順で実行する）。
/// 素早さが違うときは速い側から 1 本。同速で結果が同じなら 1 本（確率 1）。
/// 結果が違うときだけ 0.5 が 2 本。シングルではいかくとトレースの組は
/// 順序によらず同じ着地になる。
fn resolve_trace_entries(
  my_team : Array[Combatant],
  my_slot : Int,
  my_megaed : Array[Bool],
  my_status : Array[@model.StatusCondition],
  my_ranks : Array[Int],
  my_traced : Array[String],
  opp_team : Array[Combatant],
  opp_slot : Int,
  opp_megaed : Array[Bool],
  opp_status : Array[@model.StatusCondition],
  opp_ranks : Array[Int],
  opp_traced : Array[String],
) -> Array[TraceEntrySnap]? {
  if my_traced.length() == 0 || opp_traced.length() == 0 {
    return None
  }
  let my_trace = entrant_is_trace(my_team, my_slot, my_megaed)
  let opp_trace = entrant_is_trace(opp_team, opp_slot, opp_megaed)
  if !my_trace && !opp_trace {
    return None
  }
  let my_sp = entry_speed_of(my_team, my_slot, my_megaed, my_ranks, my_status)
  let opp_sp = entry_speed_of(opp_team, opp_slot, opp_megaed, opp_ranks, opp_status)
  if my_sp != opp_sp {
    let snap = simulate_trace_order(
      my_sp > opp_sp,
      my_team, my_slot, my_megaed, my_ranks, my_traced,
      opp_team, opp_slot, opp_megaed, opp_ranks, opp_traced,
    )
    return Some([snap])
  }
  let mine_first = simulate_trace_order(
    true,
    my_team, my_slot, my_megaed, my_ranks, my_traced,
    opp_team, opp_slot, opp_megaed, opp_ranks, opp_traced,
  )
  let opp_first = simulate_trace_order(
    false,
    my_team, my_slot, my_megaed, my_ranks, my_traced,
    opp_team, opp_slot, opp_megaed, opp_ranks, opp_traced,
  )
  if trace_snaps_equal(mine_first, opp_first) {
    Some([mine_first])
  } else {
    Some([
      { ..mine_first, prob: 0.5 },
      { ..opp_first, prob: 0.5 },
    ])
  }
}
