///|
/// トレース。champout は「登場した時、相手の特性と同じ特性になる」だけを書く。
/// 拒否リストは Showdown の notrace。長さ 0 の traced 配列は未追跡で、
/// 既存 fixture の遷移結果を変えない。

///|
fn tr_state() -> SwitchingGameState {
  {
    ..im_state(),
    my_traced: ["", "", ""],
    opp_traced: ["", "", ""],
  }
}

///|
fn tr_mon(
  name : String,
  ability : String,
  spe : Int,
  moves : Array[@model.Move],
) -> Combatant {
  im_combatant(im_pokemon(name, spe=spe), moves, ability=ability)
}

///|
test "トレース: コピーできる特性といかく・ふゆう" {
  @debug.assert_eq(trace_copied_ability("いかく"), "いかく")
  @debug.assert_eq(trace_copied_ability("ふゆう"), "ふゆう")
  @debug.assert_eq(trace_copied_ability("クリアボディ"), "クリアボディ")
  // Wonder Guard の flags に notrace は無い。
  @debug.assert_eq(trace_copied_ability("ふしぎなまもり"), "ふしぎなまもり")
}

///|
test "トレース: コピーできない特性は空文字" {
  @debug.assert_eq(trace_copied_ability(""), "")
  @debug.assert_eq(trace_copied_ability("トレース"), "")
  @debug.assert_eq(trace_copied_ability("ばけのかわ"), "")
  @debug.assert_eq(trace_copied_ability("イリュージョン"), "")
  @debug.assert_eq(trace_copied_ability("フラワーギフト"), "")
  @debug.assert_eq(trace_copied_ability("アイスフェイス"), "")
  @debug.assert_eq(trace_copied_ability("かわりもの"), "")
  @debug.assert_eq(trace_copied_ability("マイティチェンジ"), "")
}

///|
test "トレース: 同速のいかくとの同時登場は 1 本に畳む" {
  let mv = im_tackle()
  let tracer = tr_mon("トレース", "トレース", 100, [mv])
  let intim = tr_mon("いかく", "いかく", 100, [mv])
  let snaps = resolve_trace_entries(
    [tracer], 0, [false], [@model.None], [0, 0, 0, 0, 0], ["", ""],
    [intim], 0, [false], [@model.None], [0, 0, 0, 0, 0], ["", ""],
  )
  match snaps {
    None => abort("trace")
    Some(xs) => {
      @debug.assert_eq(xs.length(), 1)
      @debug.assert_eq(xs[0].prob, 1.0)
      @debug.assert_eq(xs[0].my_ranks[0], -1)
      @debug.assert_eq(xs[0].opp_ranks[0], -1)
      @debug.assert_eq(xs[0].my_traced[0], "いかく")
      @debug.assert_eq(xs[0].opp_traced[0], "")
    }
  }
}

///|
test "トレース: 速いいかくと遅いトレースも着地は同じ 1 本" {
  let mv = im_tackle()
  let tracer = tr_mon("トレース", "トレース", 50, [mv])
  let intim = tr_mon("いかく", "いかく", 200, [mv])
  let snaps = resolve_trace_entries(
    [tracer], 0, [false], [@model.None], [0, 0, 0, 0, 0], [""],
    [intim], 0, [false], [@model.None], [0, 0, 0, 0, 0], [""],
  )
  match snaps {
    None => abort("trace")
    Some(xs) => {
      @debug.assert_eq(xs.length(), 1)
      @debug.assert_eq(xs[0].my_ranks[0], -1)
      @debug.assert_eq(xs[0].opp_ranks[0], -1)
      @debug.assert_eq(xs[0].my_traced[0], "いかく")
    }
  }
}

///|
test "トレース: ばけのかわはコピーせず、ふしぎなまもりはコピーする" {
  let mv = im_tackle()
  let tracer = tr_mon("トレース", "トレース", 100, [mv])
  let disguise = tr_mon("化け", "ばけのかわ", 10, [mv])
  let blocked = resolve_trace_entries(
    [tracer], 0, [false], [@model.None], [0, 0, 0, 0, 0], [""],
    [disguise], 0, [false], [@model.None], [0, 0, 0, 0, 0], [""],
  )
  match blocked {
    None => abort("trace")
    Some(xs) => {
      @debug.assert_eq(xs[0].my_traced[0], "")
      @debug.assert_eq(xs[0].my_ranks[0], 0)
    }
  }
  let wonder = tr_mon("守り", "ふしぎなまもり", 10, [mv])
  let copied = resolve_trace_entries(
    [tracer], 0, [false], [@model.None], [0, 0, 0, 0, 0], [""],
    [wonder], 0, [false], [@model.None], [0, 0, 0, 0, 0], [""],
  )
  match copied {
    None => abort("trace")
    Some(xs) => @debug.assert_eq(xs[0].my_traced[0], "ふしぎなまもり")
  }
}

///|
test "トレース: どちらもトレースでなければ None" {
  let mv = im_tackle()
  let plain = tr_mon("ふつう", "", 100, [mv])
  let intim = tr_mon("いかく", "いかく", 100, [mv])
  match resolve_trace_entries(
    [plain], 0, [false], [@model.None], [0, 0, 0, 0, 0], [""],
    [intim], 0, [false], [@model.None], [0, 0, 0, 0, 0], [""],
  ) {
    None => ()
    Some(_) => abort("expected None")
  }
}

///|
test "トレース: 交代でいかくをコピーし、相手の攻撃を下げる" {
  let mv = im_tackle()
  let tracer = tr_mon("トレース", "トレース", 80, [mv])
  let intim = tr_mon("いかく", "いかく", 120, [mv])
  let plain = tr_mon("ふつう", "", 100, [mv])
  let outs = transition_with_cache(
    tr_state(),
    ActionKind::Switch(1),
    ActionKind::Switch(1),
    [plain, tracer, plain],
    [plain, intim, plain],
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].0, 1.0)
  let s = outs[0].1
  @debug.assert_eq(s.my_traced[1], "いかく")
  @debug.assert_eq(s.opp_traced[1], "")
  @debug.assert_eq(s.my_ranks[0], -1)
  @debug.assert_eq(s.opp_ranks[0], -1)
}

///|
test "トレース: 交代で出たふゆうがじしんを無効にする" {
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let eq = mk_move("じしん", "じめん", @model.Physical, 100)
  let tracer = tr_mon("トレース", "トレース", 50, [splash])
  let plain = tr_mon("ふつう", "", 100, [splash])
  let levitate = im_combatant(
    im_pokemon("ふゆう", hp=200, atk=200, def_=100, spe=200),
    [eq],
    ability="ふゆう",
  )
  let outs = transition_with_cache(
    { ..tr_state(), my_hps: [50, 50, 50] },
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    [plain, tracer, plain],
    [levitate, plain, plain],
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let s = outs[0].1
  @debug.assert_eq(s.my_traced[1], "ふゆう")
  @debug.assert_eq(s.my_hps[1], 50)
}

///|
test "トレース: ばけのかわは交代でもコピーしない" {
  let mv = im_tackle()
  let tracer = tr_mon("トレース", "トレース", 80, [mv])
  let disguise = tr_mon("化け", "ばけのかわ", 80, [mv])
  let plain = tr_mon("ふつう", "", 80, [mv])
  let outs = transition_with_cache(
    tr_state(),
    ActionKind::Switch(1),
    ActionKind::Switch(1),
    [plain, tracer, plain],
    [plain, disguise, plain],
    new_damage_cache(),
  )
  @debug.assert_eq(outs[0].1.my_traced[1], "")
  @debug.assert_eq(outs[0].1.my_ranks[0], 0)
}

///|
test "トレース: 交代で出ていくとコピーが消える" {
  let mv = im_tackle()
  let plain = tr_mon("ふつう", "", 100, [mv])
  let state = { ..tr_state(), my_traced: ["ふゆう", "", ""] }
  let outs = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    [plain, plain, plain],
    [plain, plain, plain],
    new_damage_cache(),
  )
  @debug.assert_eq(outs[0].1.my_traced[0], "")
}

///|
test "トレース: コピーした再生力は交代時に回復する" {
  let mv = im_tackle()
  let regen = tr_mon("再生", "再生力", 100, [mv])
  let plain = tr_mon("ふつう", "", 100, [mv])
  let state = {
    ..tr_state(),
    my_hps: [40, 100, 100],
    my_traced: ["再生力", "", ""],
  }
  let outs = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    [regen, plain, plain],
    [plain, plain, plain],
    new_damage_cache(),
  )
  // 最大 HP 100 の 1/3。40 + 33 = 73。
  @debug.assert_eq(outs[0].1.my_hps[0], 73)
  @debug.assert_eq(outs[0].1.my_traced[0], "")
}

///|
test "トレース: メガの瞬間にコピーを外し、そのターンはコピーしない" {
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let eq = mk_move("じしん", "じめん", @model.Physical, 100)
  let mega : @model.MegaForm = {
    atk: 200,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    type1: "ノーマル",
    type2: "",
    ability: "トレース",
    name_ja: "メガ",
  }
  let user = im_combatant(
    im_pokemon("メガ前", hp=80, atk=100, def_=50, spe=10),
    [splash],
    ability="",
    mega_form=Some(mega),
  )
  let quake = im_combatant(
    im_pokemon("じしん", hp=200, atk=250, def_=100, spe=200),
    [eq],
    ability="",
  )
  let plain = tr_mon("ふつう", "", 10, [splash])
  let state = {
    ..tr_state(),
    my_hps: [80, 80, 80],
    my_traced: ["ふゆう", "", ""],
  }
  let outs = transition_with_cache(
    state,
    ActionKind::Mega(0),
    ActionKind::UseMove(0),
    [user, plain, plain],
    [quake, plain, plain],
    new_damage_cache(),
  )
  let s = outs[0].1
  @debug.assert_eq(s.my_traced[0], "")
  @debug.assert_eq(s.my_megaed[0], true)
  // ふゆうを外したのでじめんが通る。
  assert_true(s.my_hps[0] < 80)
}

///|
test "トレース: 未追跡の配列ではコピーしない" {
  let mv = im_tackle()
  let tracer = tr_mon("トレース", "トレース", 80, [mv])
  let intim = tr_mon("いかく", "いかく", 120, [mv])
  let plain = tr_mon("ふつう", "", 100, [mv])
  let outs = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::Switch(1),
    [plain, tracer, plain],
    [plain, intim, plain],
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.my_traced.length(), 0)
  // 素のトレースはいかくではない。相手のいかくだけが自分の A を下げる。
  @debug.assert_eq(outs[0].1.my_ranks[0], -1)
  @debug.assert_eq(outs[0].1.opp_ranks[0], 0)
}

///|
fn tr_quake_pair(tracer_ability : String) -> (Array[Combatant], Array[Combatant]) {
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let eq = mk_move("じしん", "じめん", @model.Physical, 100)
  let me = im_combatant(
    im_pokemon("受け", hp=1, atk=1, def_=1, spe=1),
    [splash],
    ability=tracer_ability,
  )
  let foe = im_combatant(
    im_pokemon("攻め", hp=200, atk=250, def_=100, spe=200),
    [eq],
    ability="ふゆう",
  )
  ([me], [foe])
}

///|
test "トレース: 先発でふゆうをコピーするとじしんで落ちない" {
  let (traced, foe) = tr_quake_pair("トレース")
  let (plain, foe2) = tr_quake_pair("")
  let v_trace = switching_game_winrate(traced, foe, 1)
  let v_plain = switching_game_winrate(plain, foe2, 1)
  @debug.assert_eq(v_trace, 0.0)
  @debug.assert_eq(v_plain, -1.0)
  let mc_trace = team_monte_carlo_value(traced, foe, 4, 1UL, turn_limit=1)
  let mc_plain = team_monte_carlo_value(plain, foe2, 4, 1UL, turn_limit=1)
  @debug.assert_eq(mc_trace, 0.0)
  @debug.assert_eq(mc_plain, -1.0)
}
