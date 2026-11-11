///|
/// Mega 進化のターン頭タイミングの検証 (DP、attempt 段)。
///
/// Showdown では megaEvo は独立した行動 (battle-queue.ts: order 104、技は 200) で、
/// 技より前に実行される。`runMegaEvo` (battle-actions.ts) は命中・まひ・ねむり・外れ・
/// 免疫・先制 KO のいずれも見ないので、使用者の技が行動しなくても進化は起きる。
/// 以下は使用者の技が行動しない枝 (`partial_act_outcomes` の非行動側 / `pass_turn_state` /
/// `miss_self_loss_outcomes`) でメガ状態 (`*_megaed` / `*_mega_used`) が落ちないことを固定する。
/// 免疫・先制 KO は両者行動の枝 (`transition_with_cache`) で既に正しいので対照として置く。
/// helper: `crash_mon` / `crash_hjk_never_hits` (switching_game_crash_wbtest) と
/// `im_pokemon` / `im_combatant` / `im_state` (switching_game_intimidate_wbtest)。

///|
fn mm_mega_form(type1 : String, spe : Int) -> @model.MegaForm {
  {
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe,
    type1,
    type2: "",
    ability: "",
    name_ja: "メガテスト",
  }
}

///|
/// Mega 進化できる使用者 (`mega_form = Some`)。`mega_type` はメガ後のタイプ。
fn mm_mon(
  name : String,
  moves : Array[@model.Move],
  max_hp : Int,
  spe? : Int = 100,
  mega_type? : String = "ノーマル",
) -> Combatant {
  let p = im_pokemon(name, spe=spe)
  let c = im_combatant(p, moves, mega_form=Some(mm_mega_form(mega_type, spe)))
  { ..c, actual_stats: Some([max_hp, 100, 100, 100, 100, spe]) }
}

///|
fn mm_hit() -> @model.Move {
  mk_move("テスト技", "ノーマル", @model.Physical, 40)
}

///|
fn mm_never_hits() -> @model.Move {
  mk_move("はずれ技", "ノーマル", @model.Physical, 120, accuracy=0)
}

///|
fn mm_state(
  my_hp : Int,
  opp_hp : Int,
  my_status? : @model.StatusCondition = @model.None,
  opp_status? : @model.StatusCondition = @model.None,
) -> SwitchingGameState {
  let s = im_state(my_hps=[my_hp], opp_hps=[opp_hp], my_megaed=[false])
  {
    ..s,
    my_status: [my_status, @model.None, @model.None],
    opp_status: [opp_status, @model.None, @model.None],
  }
}

///|
/// 述語を満たす leaf の確率和。
fn mm_mass(
  outs : Array[(Double, SwitchingGameState)],
  pred : (SwitchingGameState) -> Bool,
) -> Double {
  let mut total = 0.0
  for o in outs {
    if pred(o.1) {
      total = total + o.0
    }
  }
  total
}

///|
/// 自分の Mega 状態 (進化フラグと使用済みフラグ) が立っているか。
fn mm_mega_applied(s : SwitchingGameState) -> Bool {
  s.my_megaed[0] && s.my_mega_used
}

///|
/// 自分の Mega 技が外れても (accuracy 0)、ターン頭で進化したので使用済み・進化状態が立つ。
test "mega miss DP: 自分の Mega 技が外れてもメガ進化は適用される" {
  let own = mm_mon("MmOwn", [mm_never_hits()], 200)
  let opp = crash_mon("MmOpp", [mm_hit()], 200)
  let outs = attempt_turn_with_cache(
    mm_state(200, 200),
    Mega(0),
    UseMove(0),
    [own],
    [opp],
    new_damage_cache(),
  )
  @debug.assert_eq(mm_mass(outs, mm_mega_applied), 1.0)
}

///|
/// 相手側 (opp) の Mega 技が外れても、相手の進化フラグが立つ (対称)。
test "mega miss DP: 相手の Mega 技が外れても相手のメガ進化は適用される" {
  let own = crash_mon("MmOwn", [mm_hit()], 200)
  let opp = mm_mon("MmOpp", [mm_never_hits()], 200)
  let outs = attempt_turn_with_cache(
    mm_state(200, 200),
    UseMove(0),
    Mega(0),
    [own],
    [opp],
    new_damage_cache(),
  )
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_megaed[0] && s.opp_mega_used }), 1.0)
}

///|
/// 外れた Mega 技の同ターンに相手の技を受ける: メガ後タイプ (ゴースト) でノーマル技は無効。
/// 進化が落ちると ノーマル技 が通常タイプに当たり HP が減る (効果レベルの観測)。
test "mega miss DP: 外れた Mega 技の同ターンでもメガ後タイプで相手のノーマル技を受けない" {
  let own = mm_mon("MmOwn", [mm_never_hits()], 200, mega_type="ゴースト")
  let opp = crash_mon("MmOpp", [mm_hit()], 200)
  let outs = attempt_turn_with_cache(
    mm_state(200, 200),
    Mega(0),
    UseMove(0),
    [own],
    [opp],
    new_damage_cache(),
  )
  @debug.assert_eq(mm_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0)
}

///|
/// まひ (12.5% の全身まひ枝) で行動できなくても進化は起きる。命中枝は既に正しい。
test "mega paralysis DP: まひで行動できなくてもメガ進化は適用される" {
  let own = mm_mon("MmOwn", [mm_hit()], 200)
  let opp = crash_mon("MmOpp", [mm_hit()], 200)
  let outs = attempt_turn_with_cache(
    mm_state(200, 200, my_status=@model.Paralyze),
    Mega(0),
    UseMove(0),
    [own],
    [opp],
    new_damage_cache(),
  )
  @debug.assert_eq(mm_mass(outs, mm_mega_applied), 1.0)
}

///|
/// 眠り (Sleep(2): 確定で眠ったまま) で行動できなくても進化は起きる。
test "mega sleep DP: ねむりで行動できなくてもメガ進化は適用される" {
  let own = mm_mon("MmOwn", [mm_hit()], 200)
  let opp = crash_mon("MmOpp", [mm_hit()], 200)
  let outs = attempt_turn_with_cache(
    mm_state(200, 200, my_status=@model.Sleep(2)),
    Mega(0),
    UseMove(0),
    [own],
    [opp],
    new_damage_cache(),
  )
  @debug.assert_eq(mm_mass(outs, mm_mega_applied), 1.0)
}

///|
/// 両者が眠って行動しない枝 (`pass_turn_state`) でも進化は起きる。
test "mega sleep DP: 両者が眠って行動しなくてもメガ進化は適用される" {
  let own = mm_mon("MmOwn", [mm_hit()], 200)
  let opp = crash_mon("MmOpp", [mm_hit()], 200)
  let outs = attempt_turn_with_cache(
    mm_state(200, 200, my_status=@model.Sleep(2), opp_status=@model.Sleep(2)),
    Mega(0),
    UseMove(0),
    [own],
    [opp],
    new_damage_cache(),
  )
  @debug.assert_eq(mm_mass(outs, mm_mega_applied), 1.0)
}

///|
/// 外れた崩れ技 (HJK) の Mega 使用者も、崩れ経路 (`miss_self_loss_outcomes`) で進化が落ちない。
test "mega miss DP: 外れた崩れ技の Mega 使用者もメガ進化は適用される" {
  let own = mm_mon("MmOwn", [crash_hjk_never_hits()], 200)
  let opp = crash_mon("MmOpp", [mm_hit()], 200)
  let outs = attempt_turn_with_cache(
    mm_state(200, 200),
    Mega(0),
    UseMove(0),
    [own],
    [opp],
    new_damage_cache(),
  )
  @debug.assert_eq(mm_mass(outs, mm_mega_applied), 1.0)
}

///|
/// 対照 (既に正しい経路): 相手が眠っていて、Mega 技が無効化される (ゴースト へのノーマル技) 枝。
/// 行動した側の Mega は `partial_act_outcomes` の行動側で立つ。
test "mega immune DP (対照): 無効化される技を出した Mega 使用者もメガ進化は適用される" {
  let own = mm_mon("MmOwn", [mm_hit()], 200)
  let opp = crash_mon("MmOpp", [mm_hit()], 200, type1="ゴースト")
  let outs = attempt_turn_with_cache(
    mm_state(200, 200, opp_status=@model.Sleep(2)),
    Mega(0),
    UseMove(0),
    [own],
    [opp],
    new_damage_cache(),
  )
  @debug.assert_eq(mm_mass(outs, mm_mega_applied), 1.0)
}

///|
/// 対照 (既に正しい経路): 先制技で倒された Mega 使用者 (両者行動の枝) も進化は起きている。
test "mega KO-first DP (対照): 先に倒された Mega 使用者もメガ進化は適用される" {
  let own = mm_mon("MmOwn", [mm_hit()], 200, spe=50)
  let opp = crash_mon(
    "MmOpp",
    [mk_move("つよい技", "ノーマル", @model.Physical, 150)],
    200,
    spe=150,
  )
  let outs = attempt_turn_with_cache(
    mm_state(1, 200),
    Mega(0),
    UseMove(0),
    [own],
    [opp],
    new_damage_cache(),
  )
  @debug.assert_eq(mm_mass(outs, mm_mega_applied), 1.0)
}

///|
/// parity + 感度ガード: 命中 (両者行動) / 外れ / まひ / ねむり の各枝で、Mega 状態と
/// Protean ロック解除が同一になる。感度ガード: 同じ使用者が通常技 (`UseMove`) を出した
/// 枝では Mega 状態が立たない (述語が常に真にならないことを確認)。
test "mega parity DP: 命中・外れ・まひ・ねむりの各枝で同じメガ状態になる (通常技では付かない)" {
  let scenarios : Array[(Int, @model.StatusCondition)] = [
    (100, @model.None),
    (0, @model.None),
    (100, @model.Paralyze),
    (100, @model.Sleep(2)),
  ]
  for sc in scenarios {
    let own = mm_mon(
      "MmOwn",
      [mk_move("テスト技", "ノーマル", @model.Physical, 40, accuracy=sc.0)],
      200,
    )
    let opp = crash_mon("MmOpp", [mm_hit()], 200)
    let base = mm_state(200, 200, my_status=sc.1)
    let s : SwitchingGameState = { ..base, my_protean_locked: ["ほのお", "", ""] }
    let mega_outs = attempt_turn_with_cache(
      s,
      Mega(0),
      UseMove(0),
      [own],
      [opp],
      new_damage_cache(),
    )
    @debug.assert_eq(
      mm_mass(mega_outs, fn(st) {
        mm_mega_applied(st) && st.my_protean_locked[0] == ""
      }),
      1.0,
    )
    let plain_outs = attempt_turn_with_cache(
      s,
      UseMove(0),
      UseMove(0),
      [own],
      [opp],
      new_damage_cache(),
    )
    @debug.assert_eq(
      mm_mass(plain_outs, fn(st) { st.my_megaed[0] || st.my_mega_used }),
      0.0,
    )
  }
}
