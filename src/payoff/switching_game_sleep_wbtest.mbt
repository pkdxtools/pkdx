///|
/// Champions の眠り規則の DP 単体テスト。
/// 本文 (EN help_syn.json:26333 / JP jpn help_syn.json:23848):
///   - 眠らされた後の 1 ターン目は眠ったまま (確定)。
///   - 2 ターン目は 1/3 の確率で目覚める (目覚めた試行はそのまま行動)。
///   - 3 ターン目は確定で目覚める。
///   - ねむる (wazainfo_syn.json:2130 "falls asleep for 2 turns") は 3 ターン目まで
///     目覚めない (2 回確定で眠ったまま、3 回目で目覚める)。
/// 試行は「眠ったあとに技を出そうとした回数」で数える。着弾ターンに後攻が眠らされた
/// 場合はその着弾ターンの試行が 1 回目になる (Showdown `slp.onBeforeMove` と同じ)。

///|
fn slp_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
fn slp_move(
  name : String,
  category : @model.MoveCategory,
  power : Int,
  accuracy : Int,
  status_effect : (@model.StatusKind, Int)?,
  healing : @model.HealingEffect?,
) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category,
    power,
    accuracy,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing,
    weather_set: None,
    field_set: None,
    flinch_chance: 0,
  }
}

///|
fn slp_pokemon(name : String, hp : Int, spe : Int) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1: "ノーマル",
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
fn slp_cmb(pokemon : @model.Pokemon, moves : Array[@model.Move]) -> Combatant {
  {
    pokemon,
    moves,
    ability: "",
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
fn slp_same_turn_state(
  my_hp : Int,
  opp_hp : Int,
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
    my_status: zero_status(1),
    opp_status: zero_status(1),
    my_must_recharge: [false],
    opp_must_recharge: [false],
    my_item_consumed: [false],
    my_disguise_busted: [false],
    opp_item_consumed: [false],
    opp_disguise_busted: [false],
    my_flinched: false,
    opp_flinched: false,
    my_fresh: None,
    opp_fresh: None,
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false],
    my_protean_locked: [""],
    opp_leech_seeded: [false],
    opp_protean_locked: [""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
/// 眠りの試行を acc=100 で辿り、「眠ったまま消費した試行数 k」ごとの目覚め確率
/// (index = k) を返す。`per_side_attempt` の枝をそのまま使うので DP の定義そのもの。
fn slp_wake_distribution(
  start : @model.StatusCondition,
  max_attempts : Int,
) -> Array[Double] {
  let dist : Array[Double] = Array::make(max_attempts + 1, 0.0)
  let mut frontier : Array[(@model.StatusCondition, Int, Double)] = [
    (start, 0, 1.0),
  ]
  for _step in 0..<(max_attempts + 1) {
    let next : Array[(@model.StatusCondition, Int, Double)] = []
    for item in frontier {
      let (st, skips, p) = item
      for a in per_side_attempt(st, false, UseMove(0), 100) {
        let q = p * a.prob
        if a.acts {
          dist[skips] = dist[skips] + q
        } else {
          next.push((a.post_status, skips + 1, q))
        }
      }
    }
    frontier = next
  }
  dist
}

///|
test "sleep rule: Sleep(2) is a sure skip and steps the counter to Sleep(1)" {
  let out = per_side_attempt(@model.Sleep(2), false, UseMove(0), 100)
  @debug.assert_eq(out.length(), 1)
  assert_false(out[0].acts)
  assert_true(slp_close(out[0].prob, 1.0))
  @debug.assert_eq(out[0].post_status, @model.Sleep(1))
}

///|
test "sleep rule: Sleep(1) acc=100 -> 2/3 stay asleep (Sleep(0)), 1/3 wake and act" {
  let out = per_side_attempt(@model.Sleep(1), false, UseMove(0), 100)
  @debug.assert_eq(out.length(), 2)
  let mut asleep = 0.0
  let mut awake = 0.0
  for a in out {
    if a.acts {
      assert_true(a.post_status == @model.None)
      awake += a.prob
    } else {
      @debug.assert_eq(a.post_status, @model.Sleep(0))
      asleep += a.prob
    }
  }
  assert_true(slp_close(awake, 1.0 / 3.0))
  assert_true(slp_close(asleep, 2.0 / 3.0))
}

///|
test "sleep rule: Sleep(1) acc=85 -> wake-hit 1/3*0.85, wake-miss 1/3*0.15, skip 2/3" {
  let out = per_side_attempt(@model.Sleep(1), false, UseMove(0), 85)
  @debug.assert_eq(out.length(), 3)
  let mut hit = 0.0
  let mut miss = 0.0
  let mut skip = 0.0
  for a in out {
    if a.acts {
      @debug.assert_eq(a.post_status, @model.None)
      hit += a.prob
    } else if a.post_status == @model.None {
      miss += a.prob
    } else {
      @debug.assert_eq(a.post_status, @model.Sleep(0))
      skip += a.prob
    }
  }
  assert_true(slp_close(hit, 0.85 / 3.0))
  assert_true(slp_close(miss, 0.15 / 3.0))
  assert_true(slp_close(skip, 2.0 / 3.0))
  assert_true(slp_close(hit + miss + skip, 1.0))
}

///|
test "sleep rule: Sleep(0) (3rd attempt) wakes for sure, accuracy split unchanged" {
  let out = per_side_attempt(@model.Sleep(0), false, UseMove(0), 85)
  @debug.assert_eq(out.length(), 2)
  for a in out {
    @debug.assert_eq(a.post_status, @model.None)
    if a.acts {
      assert_true(slp_close(a.prob, 0.85))
    } else {
      assert_true(slp_close(a.prob, 0.15))
    }
  }
}

///|
test "sleep rule: normal sleep wakes after 1 skip w.p. 1/3, after 2 skips w.p. 2/3" {
  let dist = slp_wake_distribution(@model.Sleep(2), 6)
  assert_true(slp_close(dist[0], 0.0))
  assert_true(slp_close(dist[1], 1.0 / 3.0))
  assert_true(slp_close(dist[2], 2.0 / 3.0))
  assert_true(slp_close(dist[3], 0.0))
  assert_true(slp_close(dist[4], 0.0))
}

///|
test "sleep rule: Rest sleep (RestSleep(2)) always skips exactly 2 attempts" {
  let dist = slp_wake_distribution(@model.RestSleep(2), 6)
  assert_true(slp_close(dist[0], 0.0))
  assert_true(slp_close(dist[1], 0.0))
  assert_true(slp_close(dist[2], 1.0))
  assert_true(slp_close(dist[3], 0.0))
}

///|
test "sleep rule: RestSleep(n>0) is a sure skip with no 1/3 check; RestSleep(0) wakes" {
  let out1 = per_side_attempt(@model.RestSleep(1), false, UseMove(0), 100)
  @debug.assert_eq(out1.length(), 1)
  assert_false(out1[0].acts)
  @debug.assert_eq(out1[0].post_status, @model.RestSleep(0))
  let out0 = per_side_attempt(@model.RestSleep(0), false, UseMove(0), 100)
  @debug.assert_eq(out0.length(), 1)
  assert_true(out0[0].acts)
  @debug.assert_eq(out0[0].post_status, @model.None)
}

///|
test "sleep rule: Yawn (Drowsy) -> Sleep(2) follows the normal 1/3 rule, not Rest" {
  // あくび: Drowsy(1) -> (EOT) Drowsy(0) -> (EOT) Sleep(2)。
  let (_hp1, d0) = eot_slip_active(100, 100, @model.Drowsy(1))
  @debug.assert_eq(d0, @model.Drowsy(0))
  let (_hp2, s2) = eot_slip_active(100, 100, d0)
  @debug.assert_eq(s2, @model.Sleep(2))
  let dist = slp_wake_distribution(s2, 6)
  assert_true(slp_close(dist[1], 1.0 / 3.0))
  assert_true(slp_close(dist[2], 2.0 / 3.0))
}

///|
test "sleep rule: Switch never ticks the counter (benched sleeper is frozen)" {
  let out = per_side_attempt(@model.Sleep(1), false, Switch(1), 100)
  @debug.assert_eq(out.length(), 1)
  assert_true(out[0].acts)
  @debug.assert_eq(out[0].post_status, @model.Sleep(1))
  let out_rest = per_side_attempt(@model.RestSleep(2), false, Switch(1), 100)
  @debug.assert_eq(out_rest.length(), 1)
  @debug.assert_eq(out_rest[0].post_status, @model.RestSleep(2))
  // 交代で眠りカウンタは残る (BadPoison と違いリセットされない)。
  @debug.assert_eq(
    reset_toxic_counter_on_switch(@model.Sleep(1)),
    @model.Sleep(1),
  )
  @debug.assert_eq(
    reset_toxic_counter_on_switch(@model.RestSleep(1)),
    @model.RestSleep(1),
  )
}

///|
test "sleep rule: sleep_turns reads both sleep counters" {
  @debug.assert_eq(sleep_turns(@model.Sleep(2)), Some(2))
  @debug.assert_eq(sleep_turns(@model.RestSleep(1)), Some(1))
  @debug.assert_eq(sleep_turns(@model.RestSleep(0)), Some(0))
  @debug.assert_eq(sleep_turns(@model.Drowsy(0)), None)
}

///|
test "sleep rule: landing-turn block steps Sleep(2) to Sleep(1), leaves others alone" {
  @debug.assert_eq(
    consume_sleep_attempt_on_block(@model.Sleep(2)),
    @model.Sleep(1),
  )
  @debug.assert_eq(
    consume_sleep_attempt_on_block(@model.Sleep(1)),
    @model.Sleep(1),
  )
  @debug.assert_eq(consume_sleep_attempt_on_block(@model.None), @model.None)
  assert_true(slp_close(SLEEP_SECOND_TURN_WAKE_RATE, 1.0 / 3.0))
}

///|
test "sleep rule: slower target put to sleep by faster Spore stays at Sleep(1)" {
  let spore = slp_move(
    "キノコのほうし",
    @model.Status,
    0,
    100,
    Some((@model.SleepKind, 100)),
    None,
  )
  let tackle = slp_move("たいあたり", @model.Physical, 40, 100, None, None)
  let my_team = [slp_cmb(slp_pokemon("spore", 200, 120), [spore])]
  let opp_team = [slp_cmb(slp_pokemon("target", 200, 60), [tackle])]
  let state = slp_same_turn_state(200, 200)
  let outs = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_p, ns) = outs[0]
  // 着弾ターンの後攻の行動 (眠ったまま) が 1 回目の試行として消費される。
  @debug.assert_eq(ns.opp_status[0], @model.Sleep(1))
  @debug.assert_eq(ns.opp_hps[0], 200)
}

///|
test "sleep rule: faster target put to sleep by slower Spore keeps Sleep(2)" {
  // 先攻 (target) は既に行動済み。眠りの 1 回目は翌ターンなので消費しない。
  let spore = slp_move(
    "キノコのほうし",
    @model.Status,
    0,
    100,
    Some((@model.SleepKind, 100)),
    None,
  )
  let tackle = slp_move("たいあたり", @model.Physical, 40, 100, None, None)
  let my_team = [slp_cmb(slp_pokemon("spore", 200, 60), [spore])]
  let opp_team = [slp_cmb(slp_pokemon("target", 200, 120), [tackle])]
  let state = slp_same_turn_state(200, 200)
  let outs = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_p, ns) = outs[0]
  @debug.assert_eq(ns.opp_status[0], @model.Sleep(2))
}

///|
test "sleep rule: attempt_turn_with_cache on Sleep(1) target: awake 1/3, asleep 2/3" {
  let tackle = slp_move("たいあたり", @model.Physical, 40, 100, None, None)
  let my_team = [slp_cmb(slp_pokemon("hitter", 200, 120), [tackle])]
  let opp_team = [slp_cmb(slp_pokemon("sleeper", 200, 60), [tackle])]
  let base = slp_same_turn_state(200, 200)
  let state = { ..base, opp_status: [@model.Sleep(1)] }
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let mut awake = 0.0
  let mut asleep = 0.0
  let mut total = 0.0
  for item in outs {
    let (p, ns) = item
    total += p
    if ns.opp_status[0] == @model.None {
      awake += p
    } else {
      @debug.assert_eq(ns.opp_status[0], @model.Sleep(0))
      asleep += p
    }
  }
  assert_true(slp_close(total, 1.0))
  assert_true(slp_close(awake, 1.0 / 3.0))
  assert_true(slp_close(asleep, 2.0 / 3.0))
}
