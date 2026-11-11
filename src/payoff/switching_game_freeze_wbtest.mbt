///|
/// Champions の こおり (Frozen) 規則の DP 単体テスト。
/// 本文 (EN help_syn.json:26184):
///   - 行動しようとするたびに 25% で解凍して行動する (1 回目・2 回目)。
///   - 凍ってから 3 ターン目に確定で解凍する (3 回目の試行は解凍して行動)。
///   - 炎タイプの技でダメージを受けると解凍、「certain other moves」(Scald 等) も解凍。
///   - こおりタイプは凍らない (help_syn.json:23193)。
/// 試行は「凍ったあとに技を出そうとした回数」で数える。着弾ターンに後攻が凍らされた場合は
/// その着弾ターンの試行が 1 回目になる (#203 の眠りと同じ数え方)。解凍技 (defrost) は
/// 使用者を試行前に解凍する (本文 wazainfo_syn.json:9816 / :7480 / :13396)。

///|
fn frz_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
fn frz_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
  accuracy : Int,
  status_effect : (@model.StatusKind, Int)?,
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
    status_effect,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
  }
}

///|
fn frz_pokemon(name : String, type1 : String, hp : Int, spe : Int) -> @model.Pokemon {
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
fn frz_cmb(
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
/// 両者 1 体ずつの同ターン状態。`my_st` / `opp_st` で凍結などを指定する。
fn frz_state(
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
fn frz_mass(
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
/// 凍結の試行を acc=100 で辿り、「凍ったまま消費した試行数 k」ごとの解凍確率
/// (index = k) を返す。`per_side_attempt` の枝をそのまま使う。
fn frz_thaw_distribution(
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
test "frz rule: Freeze(2) acc=100 -> 3/4 stay frozen as Freeze(1), 1/4 thaw and act" {
  let out = per_side_attempt(@model.Freeze(2), false, UseMove(0), 100)
  @debug.assert_eq(out.length(), 2)
  let mut stuck = 0.0
  let mut acted = 0.0
  for a in out {
    if a.acts {
      @debug.assert_eq(a.post_status, @model.None)
      acted += a.prob
    } else {
      @debug.assert_eq(a.post_status, @model.Freeze(1))
      assert_false(a.miss)
      stuck += a.prob
    }
  }
  assert_true(frz_close(stuck, 0.75))
  assert_true(frz_close(acted, 0.25))
}

///|
test "frz rule: Freeze(1) is the same 25% try, stuck state Freeze(0)" {
  let out = per_side_attempt(@model.Freeze(1), false, UseMove(0), 100)
  @debug.assert_eq(out.length(), 2)
  for a in out {
    if a.acts {
      @debug.assert_eq(a.post_status, @model.None)
      assert_true(frz_close(a.prob, 0.25))
    } else {
      @debug.assert_eq(a.post_status, @model.Freeze(0))
      assert_true(frz_close(a.prob, 0.75))
    }
  }
}

///|
test "frz rule: Freeze(0) (3rd try) thaws for sure and acts" {
  let out = per_side_attempt(@model.Freeze(0), false, UseMove(0), 100)
  @debug.assert_eq(out.length(), 1)
  assert_true(out[0].acts)
  assert_true(frz_close(out[0].prob, 1.0))
  @debug.assert_eq(out[0].post_status, @model.None)
}

///|
test "frz rule: acc=85 splits the 25% thaw into hit 0.2125 and thaw-miss 0.0375" {
  let out = per_side_attempt(@model.Freeze(2), false, UseMove(0), 85)
  @debug.assert_eq(out.length(), 3)
  let mut hit = 0.0
  let mut miss = 0.0
  let mut stuck = 0.0
  for a in out {
    if a.acts {
      @debug.assert_eq(a.post_status, @model.None)
      assert_false(a.miss)
      hit += a.prob
    } else if a.miss {
      // 解凍して外れた: 技は使ったうえで外れ (崩れ技の自傷判定に使う)。
      @debug.assert_eq(a.post_status, @model.None)
      miss += a.prob
    } else {
      @debug.assert_eq(a.post_status, @model.Freeze(1))
      stuck += a.prob
    }
  }
  assert_true(frz_close(hit, 0.25 * 0.85))
  assert_true(frz_close(miss, 0.25 * 0.15))
  assert_true(frz_close(stuck, 0.75))
}

///|
test "frz rule: defrost move by a frozen user thaws it first (no roll, accuracy kept)" {
  let out = per_side_attempt(
    @model.Freeze(2),
    false,
    UseMove(0),
    85,
    thaws_user=true,
  )
  // 凍っていても 75% の凍結枝は無い。命中 0.85 は行動、外れ 0.15 は解凍して外れ。
  @debug.assert_eq(out.length(), 2)
  let mut hit = 0.0
  let mut miss = 0.0
  for a in out {
    @debug.assert_eq(a.post_status, @model.None)
    if a.acts {
      hit += a.prob
    } else {
      assert_true(a.miss)
      miss += a.prob
    }
  }
  assert_true(frz_close(hit, 0.85))
  assert_true(frz_close(miss, 0.15))
}

///|
test "frz rule: try distribution is 1/4 on the first try, 3/16 on the second, 9/16 on the third" {
  let dist = frz_thaw_distribution(@model.Freeze(2), 3)
  assert_true(frz_close(dist[0], 0.25))
  assert_true(frz_close(dist[1], 0.1875))
  assert_true(frz_close(dist[2], 0.5625))
  assert_true(frz_close(dist[0] + dist[1] + dist[2], 1.0))
}

///|
test "frz rule: Switch never ticks the freeze counter (benched freezer is frozen)" {
  let out = per_side_attempt(@model.Freeze(1), false, Switch(1), 100)
  @debug.assert_eq(out.length(), 1)
  assert_true(out[0].acts)
  @debug.assert_eq(out[0].post_status, @model.Freeze(1))
}

///|
test "frz kind: こおり parses to FreezeKind, inflicts Freeze(2), and cli accepts freeze" {
  @debug.assert_eq(@model.status_kind_from_jp("こおり"), Some(@model.FreezeKind))
  @debug.assert_eq(@model.inflict_status(@model.FreezeKind), @model.Freeze(2))
  @debug.assert_eq(@model.status_condition_from_cli_str("freeze"), @model.Freeze(2))
  @debug.assert_eq(@model.status_condition_from_cli_str("こおり"), @model.Freeze(2))
}

///|
test "frz kind: only Ice types are immune to freeze" {
  assert_true(@model.immune_to_status(@model.FreezeKind, "こおり", "ひこう"))
  assert_true(@model.immune_to_status(@model.FreezeKind, "ノーマル", "こおり"))
  assert_false(@model.immune_to_status(@model.FreezeKind, "ノーマル", ""))
  assert_false(@model.immune_to_status(@model.FreezeKind, "ほのお", "みず"))
}

///|
test "frz infliction: a 10% freeze secondary gives 0.9 unfrozen, 0.1 Freeze(2)" {
  let ice_beam = frz_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 10)),
  )
  let opp_team = [frz_cmb(frz_pokemon("target", "ノーマル", 200, 60), [], "")]
  let state = frz_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_status_fanout(state, false, 0, opp_team, ice_beam)
  @debug.assert_eq(outs.length(), 2)
  let mut frozen = 0.0
  let mut clear = 0.0
  for item in outs {
    let (p, s) = item
    if s.opp_status[0] == @model.Freeze(2) {
      frozen += p
    } else {
      @debug.assert_eq(s.opp_status[0], @model.None)
      clear += p
    }
  }
  assert_true(frz_close(frozen, 0.1))
  assert_true(frz_close(clear, 0.9))
}

///|
test "frz infliction: an Ice-type target is never frozen" {
  let ice_beam = frz_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 100)),
  )
  let opp_team = [frz_cmb(frz_pokemon("ice", "こおり", 200, 60), [], "")]
  let state = frz_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_status_fanout(state, false, 0, opp_team, ice_beam)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
}

///|
test "frz infliction: sun blocks freeze (Showdown sunnyday onImmunity fallback)" {
  let ice_beam = frz_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 100)),
  )
  let opp_team = [frz_cmb(frz_pokemon("target", "ノーマル", 200, 60), [], "")]
  let sunny = { ..frz_state(200, 200, @model.None, @model.None), weather: @model.Weather::Sun }
  let outs = maybe_apply_status_fanout(sunny, false, 0, opp_team, ice_beam)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
}

///|
test "frz infliction: マグマのよろい blocks freeze (tokuseiinfo_syn.json:1348)" {
  let ice_beam = frz_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 100)),
  )
  let opp_team = [
    frz_cmb(frz_pokemon("camerupt", "ほのお", 200, 60), [], "マグマのよろい"),
  ]
  let state = frz_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_status_fanout(state, false, 0, opp_team, ice_beam)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
}

///|
test "frz infliction: りんぷん blocks a damaging move's freeze but not a status move's" {
  let ice_beam = frz_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 100)),
  )
  let status_freeze = frz_move(
    "テスト凍結技",
    "こおり",
    @model.Status,
    0,
    100,
    Some((@model.FreezeKind, 100)),
  )
  let opp_team = [frz_cmb(frz_pokemon("shed", "ノーマル", 200, 60), [], "りんぷん")]
  let state = frz_state(200, 200, @model.None, @model.None)
  // 追加効果 (power > 0) は止まる。
  @debug.assert_eq(
    maybe_apply_status_fanout(state, false, 0, opp_team, ice_beam).length(),
    1,
  )
  // 変化技の直接の凍結は止まらない。
  @debug.assert_eq(
    maybe_apply_status_fanout(state, false, 0, opp_team, status_freeze).length(),
    1,
  )
  @debug.assert_eq(
    maybe_apply_status_fanout(state, false, 0, opp_team, status_freeze)[0].1.opp_status[0],
    @model.Freeze(2),
  )
}

///|
test "frz infliction: Misty Terrain blocks freeze on a grounded target, Electric Terrain does not" {
  let ice_beam = frz_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 100)),
  )
  let opp_team = [frz_cmb(frz_pokemon("target", "ノーマル", 200, 60), [], "")]
  let misty = { ..frz_state(200, 200, @model.None, @model.None), field: @model.Field::Misty }
  let electric = { ..frz_state(200, 200, @model.None, @model.None), field: @model.Field::Electric }
  @debug.assert_eq(
    maybe_apply_status_fanout(misty, false, 0, opp_team, ice_beam).length(),
    1,
  )
  // chance 100 なので付与は確定 (単一枝)。Electric は凍結を止めない。
  @debug.assert_eq(
    maybe_apply_status_fanout(electric, false, 0, opp_team, ice_beam)[0].1.opp_status[0],
    @model.Freeze(2),
  )
}

///|
test "frz infliction: an existing burn blocks freeze (status exclusivity)" {
  let ice_beam = frz_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 100)),
  )
  let opp_team = [frz_cmb(frz_pokemon("target", "ノーマル", 200, 60), [], "")]
  let state = frz_state(200, 200, @model.None, @model.Burn)
  let outs = maybe_apply_status_fanout(state, false, 0, opp_team, ice_beam)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.Burn)
}

///|
test "frz landing: a slower target frozen by Ice Beam rolls its try on the landing turn (0.075 stuck)" {
  let ice_beam = frz_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 10)),
  )
  let tackle = frz_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [frz_cmb(frz_pokemon("ice", "ノーマル", 200, 120), [ice_beam], "")]
  let opp_team = [frz_cmb(frz_pokemon("tackler", "ノーマル", 200, 60), [tackle], "")]
  let state = frz_state(200, 200, @model.None, @model.None)
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  // 着弾ターンの後攻の試行 (1 回目) は 25% で解凍して行動、75% で凍ったまま (Freeze(1))。
  let stuck = frz_mass(outs, fn(s) { s.opp_status[0] == @model.Freeze(1) })
  let frozen_again = frz_mass(outs, fn(s) { s.opp_status[0] == @model.Freeze(2) })
  let total = frz_mass(outs, fn(_) { true })
  assert_true(frz_close(stuck, 0.1 * 0.75))
  assert_true(frz_close(frozen_again, 0.0))
  assert_true(frz_close(total, 1.0))
}

///|
test "frz landing: a faster target frozen by a slower Ice Beam keeps Freeze(2) (no roll that turn)" {
  let ice_beam = frz_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 10)),
  )
  let tackle = frz_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [frz_cmb(frz_pokemon("tackler", "ノーマル", 200, 120), [tackle], "")]
  let opp_team = [frz_cmb(frz_pokemon("ice", "ノーマル", 200, 60), [ice_beam], "")]
  let state = frz_state(200, 200, @model.None, @model.None)
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  // 先攻は行動後に凍るので、その turn の試行は無い。次ターンが 1 回目。
  let frozen = frz_mass(outs, fn(s) { s.my_status[0] == @model.Freeze(2) })
  assert_true(frz_close(frozen, 0.1))
}

///|
test "frz thaw: a damaging Fire hit thaws a frozen target before its second-actor try" {
  let fire = frz_move("テスト炎技", "ほのお", @model.Physical, 90, 100, None)
  let tackle = frz_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [frz_cmb(frz_pokemon("fire", "ほのお", 200, 120), [fire], "")]
  let opp_team = [frz_cmb(frz_pokemon("frozen", "ノーマル", 200, 60), [tackle], "")]
  let state = frz_state(200, 200, @model.None, @model.Freeze(2))
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  // 炎の命中で解凍 → 後攻は凍っていないので抽選なしで行動 (命中 1.0)。
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_status[0] == @model.None }), 1.0))
  // 行動した後攻の技 (たいあたり) が先攻に当たる: 先攻 HP は減る。
  assert_true(frz_close(frz_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "frz thaw: a non-Fire damaging hit does not thaw (stuck 0.75 on the second-actor try)" {
  let water = frz_move("テスト水技", "みず", @model.Special, 90, 100, None)
  let tackle = frz_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [frz_cmb(frz_pokemon("water", "みず", 200, 120), [water], "")]
  let opp_team = [frz_cmb(frz_pokemon("frozen", "ノーマル", 200, 60), [tackle], "")]
  let state = frz_state(200, 200, @model.None, @model.Freeze(2))
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_status[0] == @model.Freeze(1) }), 0.75))
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_status[0] == @model.None }), 0.25))
}

///|
test "frz thaw: a Fire-type status move does not thaw (only damage does)" {
  let ember_status = frz_move("テスト炎変化", "ほのお", @model.Status, 0, 100, None)
  let tackle = frz_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [frz_cmb(frz_pokemon("status", "ほのお", 200, 120), [ember_status], "")]
  let opp_team = [frz_cmb(frz_pokemon("frozen", "ノーマル", 200, 60), [tackle], "")]
  let state = frz_state(200, 200, @model.None, @model.Freeze(2))
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_status[0] == @model.Freeze(1) }), 0.75))
}

///|
test "frz thaw: thawsTarget (Scald) thaws after the hit, so its burn secondary cannot land first" {
  let scald = frz_move(
    "ねっとう",
    "みず",
    @model.Special,
    80,
    100,
    Some((@model.BurnKind, 100)),
  )
  let tackle = frz_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [frz_cmb(frz_pokemon("scald", "みず", 200, 120), [scald], "")]
  let opp_team = [frz_cmb(frz_pokemon("frozen", "ノーマル", 200, 60), [tackle], "")]
  let state = frz_state(200, 200, @model.None, @model.Freeze(2))
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  // 凍っている間は やけど が付かない。命中後に解凍され、後攻は行動する。
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_status[0] == @model.None }), 1.0))
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_status[0] == @model.Burn }), 0.0))
}

///|
test "frz thaw: a frozen user's defrost move (Flare Blitz) thaws it and executes with no roll" {
  let flare_blitz = frz_move("フレアドライブ", "ほのお", @model.Physical, 120, 100, None)
  let tackle = frz_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [frz_cmb(frz_pokemon("flare", "ほのお", 200, 60), [flare_blitz], "")]
  let opp_team = [frz_cmb(frz_pokemon("tackler", "ノーマル", 200, 120), [tackle], "")]
  let state = frz_state(200, 200, @model.Freeze(2), @model.None)
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  // 解凍技は乱数なしで行動する (凍結枝 0.75 は無い)。
  assert_true(frz_close(frz_mass(outs, fn(s) { s.my_status[0] == @model.None }), 1.0))
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
}

///|
test "frz thaw: a Freeze(0) user (3rd try) acts and is cured" {
  let tackle = frz_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [frz_cmb(frz_pokemon("third", "ノーマル", 200, 60), [tackle], "")]
  let opp_team = [frz_cmb(frz_pokemon("tackler", "ノーマル", 200, 120), [tackle], "")]
  let state = frz_state(200, 200, @model.Freeze(0), @model.None)
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  assert_true(frz_close(frz_mass(outs, fn(s) { s.my_status[0] == @model.None }), 1.0))
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
}

///|
test "frz switch: a benched frozen Pokémon keeps its counter when the bench is swapped in" {
  let tackle = frz_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [frz_cmb(frz_pokemon("a", "ノーマル", 200, 60), [tackle], "")]
  let opp_team = [
    frz_cmb(frz_pokemon("frozen", "ノーマル", 200, 60), [tackle], ""),
    frz_cmb(frz_pokemon("fresh", "ノーマル", 200, 60), [tackle], ""),
  ]
  let state = {
    ..frz_state(200, 200, @model.None, @model.None),
    opp_hps: [200, 200],
    opp_ranks: [0, 0, 0, 0, 0],
    opp_status: [@model.Freeze(1), @model.None],
    opp_megaed: [false, false],
    opp_must_recharge: [false, false],
    opp_item_consumed: [false, false],
    opp_disguise_busted: [false, false],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
  }
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    Switch(1),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  // 交代した先のスロットが動き、凍ったままのスロット 0 のカウンタは変わらない。
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_active == 1 }), 1.0))
  assert_true(frz_close(frz_mass(outs, fn(s) { s.opp_status[0] == @model.Freeze(1) }), 1.0))
}
