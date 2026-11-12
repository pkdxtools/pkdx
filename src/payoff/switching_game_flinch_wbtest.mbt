///|
/// Champions のひるみ (追加効果 `flinch_chance`) の DP 単体テスト。
/// 本文は wazainfo_syn.json の「N% chance of making the target flinch」(命中ごと)。
/// - 先攻の技が命中して相手が生存すると、N% で相手はそのターンの後攻の行動を失う (持ち越さない)。
/// - 特性: せいしんりょく は受けない (tokuseiinfo_syn.json:039)。りんぷん はダメージ技の追加効果を
///   止める。ちからずく の使用者は追加効果を失う。
/// - ふくつのこころ: ひるみで行動を止められた側の素早さ +1 (tokuseiinfo_syn.json:080)。
/// 優先度の順序 (Showdown `conditions.ts`): flinch 8 / slp・frz 10 (先に止まる) / par 1 (ひるみが先)
/// / mustrecharge 11。ひるみの発火 (ふくつのこころ) は行動前に効いた枝だけ。

///|
fn flch_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-6
}

///|
fn flch_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
  accuracy : Int,
  flinch_chance : Int,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
    accuracy,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
    flinch_chance,
  }
}

///|
fn flch_pokemon(
  name : String,
  type1 : String,
  hp : Int,
  spe : Int,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2: "",
    hp,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe,
    bst: hp + 400 + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
}

///|
fn flch_cmb(
  pokemon : @model.Pokemon,
  moves : Array[@model.Move],
  ability : String,
) -> Combatant {
  {
    pokemon,
    moves,
    ability,
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
}

///|
/// 両者 1 体ずつの状態。`my_st` / `opp_st` で状態異常を指定する (ランク・フラグは 0 / false)。
fn flch_state(
  my_hp : Int,
  opp_hp : Int,
  my_st : @model.StatusCondition,
  opp_st : @model.StatusCondition,
) -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [my_hp],
    opp_hps: [opp_hp],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false],
    my_status: [my_st],
    opp_status: [opp_st],
    my_must_recharge: [false],
    opp_must_recharge: [false],
    my_item_consumed: [false],
    opp_item_consumed: [false],
    my_disguise_busted: [false],
    opp_disguise_busted: [false],
    my_flinched: false,
    opp_flinched: false,
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false],
    opp_leech_seeded: [false],
    my_protean_locked: [""],
    opp_protean_locked: [""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
/// 結果の確率で `pred` を満たすものを足し込む。
fn flch_mass(
  outs : Array[(Double, SwitchingGameState)],
  pred : (SwitchingGameState) -> Bool,
) -> Double {
  let mut total = 0.0
  for item in outs {
    let (p, s) = item
    if pred(s) {
      total = total + p
    }
  }
  total
}

///|
/// 1 ターン分の DP。先攻 (`my`) の技 `my_mv` を速い側に置き、相手の技 `opp_mv` と組ませる。
fn flch_turn(
  state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> Array[(Double, SwitchingGameState)] {
  attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
}

///|
/// 標準の 1v1: 自分の技は速い (spe 120)、相手の技は遅い (spe 60)。相手の技は命中 100 で
/// 自分の HP を減らすので、相手が行動したかは自分の HP で分かる。
fn flch_my_first_team(
  my_mv : @model.Move,
  my_ability : String,
) -> Array[Combatant] {
  [flch_cmb(flch_pokemon("fast", "ノーマル", 200, 120), [my_mv], my_ability)]
}

///|
fn flch_opp_team(
  opp_mv : @model.Move,
  opp_ability : String,
) -> Array[Combatant] {
  [flch_cmb(flch_pokemon("slow", "ノーマル", 200, 60), [opp_mv], opp_ability)]
}

///|
fn flch_bite(chance : Int) -> @model.Move {
  flch_move("かみつく", "あく", @model.Physical, 60, 100, chance)
}

///|
fn flch_tackle() -> @model.Move {
  flch_move("たいあたり", "ノーマル", @model.Physical, 40, 100, 0)
}

///|
test "flinch 100: a faster flinching Bite stops the slower Tackle (my HP never drops)" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  // ひるみはターン末に持ち越さない (両フラグとも false)。
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_flinched || s.opp_flinched }), 0.0))
}

///|
test "flinch 0: the slower Tackle acts, so my HP always drops" {
  let my_team = flch_my_first_team(flch_bite(0), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "flinch 30: the slower Tackle acts with probability 0.7" {
  let my_team = flch_my_first_team(flch_bite(30), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 0.7))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 0.3))
}

///|
test "せいしんりょく (Inner Focus) on the target: the flinch never applies" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "せいしんりょく")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "りんぷん (Shield Dust) on the target blocks the flinch of a damaging move" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "りんぷん")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "ちからずく (Sheer Force) attacker loses the flinch" {
  let my_team = flch_my_first_team(flch_bite(100), "ちからずく")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "ふくつのこころ (Steadfast): a flinched target gains +1 Speed rank" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "ふくつのこころ")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_ranks[4] == 1 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
}

///|
test "ふくつのこころ does not fire when the flinch never lands (chance 0)" {
  let my_team = flch_my_first_team(flch_bite(0), "")
  let opp_team = flch_opp_team(flch_tackle(), "ふくつのこころ")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_ranks[4] == 0 }), 1.0))
}

///|
test "眠り (Sleep(2)) keeps the target asleep: the flinch does not reach it, Steadfast stays off" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "ふくつのこころ")
  let outs = flch_turn(
    flch_state(200, 200, @model.None, @model.Sleep(2)),
    my_team,
    opp_team,
  )
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_status[0] == @model.Sleep(1) }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_ranks[4] == 0 }), 1.0))
}

///|
test "眠り 3 回目 (Sleep(0)): the target wakes and is then stopped by the flinch (Steadfast fires)" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "ふくつのこころ")
  let outs = flch_turn(
    flch_state(200, 200, @model.None, @model.Sleep(0)),
    my_team,
    opp_team,
  )
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_status[0] == @model.None }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_ranks[4] == 1 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
}

///|
test "まひ (Paralyze): the flinch comes first, so no paralysis roll and Steadfast fires" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "ふくつのこころ")
  let outs = flch_turn(
    flch_state(200, 200, @model.None, @model.Paralyze),
    my_team,
    opp_team,
  )
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_status[0] == @model.Paralyze }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_ranks[4] == 1 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
}

///|
test "こおり (Freeze(2)): flinched, it thaws with 25% (Steadfast) and stays frozen with 75%" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "ふくつのこころ")
  let outs = flch_turn(
    flch_state(200, 200, @model.None, @model.Freeze(2)),
    my_team,
    opp_team,
  )
  assert_true(
    flch_close(
      flch_mass(outs, fn(s) { s.opp_status[0] == @model.None && s.opp_ranks[4] == 1 }),
      0.25,
    ),
  )
  assert_true(
    flch_close(
      flch_mass(outs, fn(s) { s.opp_status[0] == @model.Freeze(1) && s.opp_ranks[4] == 0 }),
      0.75,
    ),
  )
}

///|
test "defrost move user (frozen): flinched, it stays frozen (no thaw) and Steadfast fires" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let flare = flch_move("フレアドライブ", "ほのお", @model.Physical, 120, 100, 0)
  let opp_team = flch_opp_team(flare, "ふくつのこころ")
  let outs = flch_turn(
    flch_state(200, 200, @model.None, @model.Freeze(2)),
    my_team,
    opp_team,
  )
  assert_true(
    flch_close(
      flch_mass(outs, fn(s) { s.opp_status[0] == @model.Freeze(2) && s.opp_ranks[4] == 1 }),
      1.0,
    ),
  )
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
}

///|
test "recharging target: the flinch does nothing (no Steadfast, no action)" {
  let my_team = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "ふくつのこころ")
  let state = {
    ..flch_state(200, 200, @model.None, @model.None),
    opp_must_recharge: [true],
  }
  let outs = flch_turn(state, my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_ranks[4] == 0 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] == 200 }), 1.0))
}

///|
test "a flinch on a side that already moved does nothing (the slower side is the one hit)" {
  // 相手が先攻 (速い)。自分の Bite は後攻で相手に当たるが、相手は既に行動しているので
  // ひるみは効かない (Steadfast も発火しない) し、相手の Tackle は通常どおり当たる。
  let my_team = [flch_cmb(flch_pokemon("slowbite", "ノーマル", 200, 60), [flch_bite(100)], "")]
  let opp_team = [flch_cmb(flch_pokemon("fasttackle", "ノーマル", 200, 120), [flch_tackle()], "ふくつのこころ")]
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_ranks[4] == 0 }), 1.0))
}

///|
test "carry-over: a flinch lasts only its own turn (the next turn the target acts)" {
  let my_team1 = flch_my_first_team(flch_bite(100), "")
  let opp_team = flch_opp_team(flch_tackle(), "")
  let my_team2 = flch_my_first_team(flch_bite(0), "")
  let outs1 = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team1, opp_team)
  let mut acted2 = 0.0
  let mut total1 = 0.0
  for item in outs1 {
    let (p1, s1) = item
    total1 = total1 + p1
    let outs2 = flch_turn(s1, my_team2, opp_team)
    let hit2 = flch_mass(
      outs2,
      fn(s) { s.my_hps[0] < s1.my_hps[0] },
    )
    acted2 = acted2 + p1 * hit2
  }
  assert_true(flch_close(total1, 1.0))
  assert_true(flch_close(acted2, 1.0))
}

///|
test "flinched_outcomes: each status row sums to 1 and Steadfast fires only where the flinch reaches" {
  let rows : Array[(@model.StatusCondition, Bool)] = [
    (@model.None, false),
    (@model.Paralyze, false),
    (@model.Burn, false),
    (@model.Poison, false),
    (@model.BadPoison(0), false),
    (@model.Sleep(2), false),
    (@model.Sleep(1), false),
    (@model.Sleep(0), false),
    (@model.RestSleep(1), false),
    (@model.RestSleep(0), false),
    (@model.Freeze(2), false),
    (@model.Freeze(1), false),
    (@model.Freeze(0), false),
    (@model.Freeze(2), true),
  ]
  for row in rows {
    let (st, thaws) = row
    let outs = flinched_outcomes(st, thaws)
    let mut sum = 0.0
    for o in outs {
      let (p, _, _) = o
      sum = sum + p
    }
    assert_true(flch_close(sum, 1.0))
  }
  // 眠り 1 回目 (Sleep(1)) の目覚め 1/3 だけが発火する。
  let mut fire = 0.0
  for o in flinched_outcomes(@model.Sleep(1), false) {
    let (p, _, steadfast) = o
    if steadfast {
      fire = fire + p
    }
  }
  assert_true(flch_close(fire, SLEEP_SECOND_TURN_WAKE_RATE))
  // 凍結 (Freeze(n >= 1)) の解凍 25% だけが発火する。defrost 使用者は凍ったまま発火する。
  let mut thaw_fire = 0.0
  for o in flinched_outcomes(@model.Freeze(1), false) {
    let (p, _, steadfast) = o
    if steadfast {
      thaw_fire = thaw_fire + p
    }
  }
  assert_true(flch_close(thaw_fire, FREEZE_THAW_RATE))
  let defrost = flinched_outcomes(@model.Freeze(2), true)
  assert_true(defrost.length() == 1)
  let (p0, post0, steady0) = defrost[0]
  assert_true(flch_close(p0, 1.0))
  assert_true(post0 == @model.Freeze(2))
  assert_true(steady0)
}

///|
test "flinch_probability: 1 - (1 - p)^hits, with hits < 1 read as one hit" {
  assert_true(flch_close(flinch_probability(30, 1), 0.3))
  assert_true(flch_close(flinch_probability(30, 2), 0.51))
  assert_true(flch_close(flinch_probability(10, 3), 0.271))
  assert_true(flch_close(flinch_probability(30, 0), 0.3))
  assert_true(flch_close(flinch_probability(100, 1), 1.0))
  assert_true(flch_close(flinch_probability(0, 3), 0.0))
}

///|
test "maybe_apply_flinch_fanout: a KO'd target gets no flag, a live one gets the chance" {
  let mv = flch_bite(30)
  let team = flch_opp_team(flch_tackle(), "")
  let dead = flch_state(200, 0, @model.None, @model.None)
  let dead_outs = maybe_apply_flinch_fanout(dead, false, 0, team, mv)
  assert_true(dead_outs.length() == 1)
  assert_false(dead_outs[0].1.opp_flinched)
  let live = flch_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_flinch_fanout(live, false, 0, team, mv, hits_count=2)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_flinched }), 0.51))
  assert_true(flch_close(flch_mass(outs, fn(s) { s.my_flinched }), 0.0))
  // 自分が対象 (my_flinched) を立てる経路。
  let mine = maybe_apply_flinch_fanout(live, true, 0, [flch_cmb(flch_pokemon("me", "ノーマル", 200, 60), [flch_tackle()], "")], mv)
  assert_true(flch_close(flch_mass(mine, fn(s) { s.my_flinched }), 0.3))
}

///|
test "maybe_apply_flinch_fanout: Inner Focus target and chance 0 never flag" {
  let live = flch_state(200, 200, @model.None, @model.None)
  let focus = [flch_cmb(flch_pokemon("focus", "ノーマル", 200, 60), [flch_tackle()], "せいしんりょく")]
  let focus_outs = maybe_apply_flinch_fanout(live, false, 0, focus, flch_bite(100))
  assert_true(flch_close(flch_mass(focus_outs, fn(s) { s.opp_flinched }), 0.0))
  let plain = [flch_cmb(flch_pokemon("plain", "ノーマル", 200, 60), [flch_tackle()], "")]
  let zero_outs = maybe_apply_flinch_fanout(live, false, 0, plain, flch_bite(0))
  assert_true(flch_close(flch_mass(zero_outs, fn(s) { s.opp_flinched }), 0.0))
}
