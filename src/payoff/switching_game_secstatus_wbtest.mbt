///|
/// Champions の攻撃技の二次状態異常 (やけど / まひ / どく / もうどく) の DP 単体テスト。
/// 本文 (champout/rom-txt/usa):
///   - 追加効果の確率は技ごとの本文 (wazainfo_syn.json、例: ほのおのパンチ :16 "10% ... burning")。
///   - 免疫: ほのお (help_syn.json:22637 "Cannot be burned") / でんき (:22714 "Cannot be paralyzed") /
///     どく・はがね (:23003 / :23500 "Cannot be poisoned or badly poisoned")。
///   - りんぷん (tokuseiinfo_syn.json:606)、ちからずく (:4170) は追加効果を止める / 失わせる。
///     ばけのかわ の初撃 (chip のみ) は HP を減らすので追加効果は付く (Showdown fallback。
///     本文 tokuseiinfo_syn.json:6600 は追加効果に触れない。`secondary_gated_move` が SSoT)。
///     HP を減らさない命中 (瀕死の対象) と タイプ / 特性による無効は付かない。
/// 変化技の状態異常 (おにび 等) は命中で決まり、追加効果の抽選を二重にしない (DB 経路の
/// normalize は database テストで確認)。

///|
fn ss_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
fn ss_move(
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
    flinch_chance: 0,
  }
}

///|
fn ss_pokemon(
  name : String,
  type1 : String,
  type2 : String,
  hp : Int,
  spe : Int,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2,
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
fn ss_cmb(
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
/// 両者 1 体ずつの状態。`my_st` / `opp_st` で状態異常を指定する。
fn ss_state(
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
    my_fresh: None,
    opp_fresh: None,
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
fn ss_mass(
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
/// 相手 (opp) の状態を `pred` で数える (fanout は my を攻撃する想定ではなく、対象を opp に置く)。
fn ss_opp_mass(
  outs : Array[(Double, SwitchingGameState)],
  pred : (@model.StatusCondition) -> Bool,
) -> Double {
  ss_mass(outs, fn(s) { pred(s.opp_status[0]) })
}

///|
/// 攻撃技 1 つを被弾側 (opp) に当てる fanout (`maybe_apply_status_fanout`) の結果。
/// `power > 0` の技は実際の攻撃と同じく、追加効果の前にダメージ > 0 を仮定する。
fn ss_fanout(
  target_team : Array[Combatant],
  state : SwitchingGameState,
  mv : @model.Move,
  hits : Int,
) -> Array[(Double, SwitchingGameState)] {
  maybe_apply_status_fanout(state, false, 0, target_team, mv, hits_count=hits)
}

///|
test "ss infliction: burn 10% secondary gives 0.9 clear, 0.1 Burn" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 10)),
  )
  let target = [ss_cmb(ss_pokemon("target", "ノーマル", "", 200, 60), [], "")]
  let outs = ss_fanout(target, ss_state(200, 200, @model.None, @model.None), fire_punch, 1)
  @debug.assert_eq(outs.length(), 2)
  assert_true(ss_close(ss_opp_mass(outs, fn(s) { s == @model.Burn }), 0.1))
  assert_true(ss_close(ss_opp_mass(outs, fn(s) { s == @model.None }), 0.9))
}

///|
test "ss infliction: paralysis 30% secondary gives 0.3 Paralyze; Zap Cannon 100% is deterministic" {
  let thunderbolt = ss_move(
    "かみなり",
    "でんき",
    @model.Special,
    110,
    100,
    Some((@model.ParalyzeKind, 30)),
  )
  let zap = ss_move(
    "でんじほう",
    "でんき",
    @model.Special,
    120,
    100,
    Some((@model.ParalyzeKind, 100)),
  )
  let target = [ss_cmb(ss_pokemon("target", "ノーマル", "", 200, 60), [], "")]
  let st = ss_state(200, 200, @model.None, @model.None)
  let outs = ss_fanout(target, st, thunderbolt, 1)
  assert_true(ss_close(ss_opp_mass(outs, fn(s) { s == @model.Paralyze }), 0.3))
  let zap_outs = ss_fanout(target, st, zap, 1)
  @debug.assert_eq(zap_outs.length(), 1)
  @debug.assert_eq(zap_outs[0].1.opp_status[0], @model.Paralyze)
}

///|
test "ss infliction: poison 30% gives Poison; toxic (どくどくのキバ 50%) gives BadPoison(0)" {
  let sludge = ss_move(
    "ヘドロばくだん",
    "どく",
    @model.Special,
    90,
    100,
    Some((@model.PoisonKind, 30)),
  )
  let fang = ss_move(
    "どくどくのキバ",
    "どく",
    @model.Physical,
    50,
    100,
    Some((@model.BadPoisonKind, 50)),
  )
  let target = [ss_cmb(ss_pokemon("target", "ノーマル", "", 200, 60), [], "")]
  let st = ss_state(200, 200, @model.None, @model.None)
  let outs = ss_fanout(target, st, sludge, 1)
  assert_true(ss_close(ss_opp_mass(outs, fn(s) { s == @model.Poison }), 0.3))
  let tox = ss_fanout(target, st, fang, 1)
  assert_true(ss_close(ss_opp_mass(tox, fn(s) { s == @model.BadPoison(0) }), 0.5))
}

///|
test "ss infliction: a 2-hit damaging move rolls the secondary per hit (1 - 0.9^2 = 0.19)" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 10)),
  )
  let target = [ss_cmb(ss_pokemon("target", "ノーマル", "", 200, 60), [], "")]
  let outs = ss_fanout(target, ss_state(200, 200, @model.None, @model.None), fire_punch, 2)
  assert_true(ss_close(ss_opp_mass(outs, fn(s) { s == @model.Burn }), 0.19))
}

///|
test "ss immunity: Fire types cannot be burned, Electric types cannot be paralyzed" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let thunder_punch = ss_move(
    "かみなりパンチ",
    "でんき",
    @model.Physical,
    75,
    100,
    Some((@model.ParalyzeKind, 100)),
  )
  let fire = [ss_cmb(ss_pokemon("fire", "ほのお", "", 200, 60), [], "")]
  let elec = [ss_cmb(ss_pokemon("elec", "でんき", "", 200, 60), [], "")]
  let st = ss_state(200, 200, @model.None, @model.None)
  @debug.assert_eq(ss_fanout(fire, st, fire_punch, 1)[0].1.opp_status[0], @model.None)
  @debug.assert_eq(ss_fanout(elec, st, thunder_punch, 1)[0].1.opp_status[0], @model.None)
  // 免疫の対象外 (ノーマル / こおり) には入る。
  let ice = [ss_cmb(ss_pokemon("ice", "こおり", "", 200, 60), [], "")]
  @debug.assert_eq(ss_fanout(ice, st, fire_punch, 1)[0].1.opp_status[0], @model.Burn)
}

///|
test "ss immunity: Poison and Steel types cannot be poisoned or badly poisoned" {
  let sludge = ss_move(
    "ヘドロばくだん",
    "どく",
    @model.Special,
    90,
    100,
    Some((@model.PoisonKind, 100)),
  )
  let fang = ss_move(
    "どくどくのキバ",
    "どく",
    @model.Physical,
    50,
    100,
    Some((@model.BadPoisonKind, 100)),
  )
  let st = ss_state(200, 200, @model.None, @model.None)
  let poison_type = [ss_cmb(ss_pokemon("p", "どく", "", 200, 60), [], "")]
  let steel_type = [ss_cmb(ss_pokemon("s", "はがね", "", 200, 60), [], "")]
  let mixed = [ss_cmb(ss_pokemon("m", "ノーマル", "どく", 200, 60), [], "")]
  for target in [poison_type, steel_type, mixed] {
    @debug.assert_eq(ss_fanout(target, st, sludge, 1)[0].1.opp_status[0], @model.None)
    @debug.assert_eq(ss_fanout(target, st, fang, 1)[0].1.opp_status[0], @model.None)
  }
}

///|
test "ss blocker: an existing major status blocks a new secondary (exclusivity)" {
  let thunderbolt = ss_move(
    "かみなり",
    "でんき",
    @model.Special,
    110,
    100,
    Some((@model.ParalyzeKind, 100)),
  )
  let target = [ss_cmb(ss_pokemon("target", "ノーマル", "", 200, 60), [], "")]
  let st = ss_state(200, 200, @model.None, @model.Burn)
  let outs = ss_fanout(target, st, thunderbolt, 1)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.Burn)
}

///|
test "ss blocker: Misty Terrain blocks a grounded target; Electric Terrain does not block burn" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let target = [ss_cmb(ss_pokemon("grounded", "ノーマル", "", 200, 60), [], "")]
  let base = ss_state(200, 200, @model.None, @model.None)
  let misty = { ..base, field: @model.Field::Misty }
  let electric = { ..base, field: @model.Field::Electric }
  @debug.assert_eq(ss_fanout(target, misty, fire_punch, 1)[0].1.opp_status[0], @model.None)
  @debug.assert_eq(ss_fanout(target, electric, fire_punch, 1)[0].1.opp_status[0], @model.Burn)
}

///|
test "ss blocker: Shield Dust blocks a damaging move's burn, not a status move's" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let will_o_wisp = ss_move(
    "おにび",
    "ほのお",
    @model.Status,
    0,
    100,
    Some((@model.BurnKind, 100)),
  )
  let shed = [ss_cmb(ss_pokemon("shed", "ノーマル", "", 200, 60), [], "りんぷん")]
  let st = ss_state(200, 200, @model.None, @model.None)
  @debug.assert_eq(ss_fanout(shed, st, fire_punch, 1)[0].1.opp_status[0], @model.None)
  // 変化技の直接の状態異常は止めない (おにび は Shield Dust でも入る)。
  @debug.assert_eq(ss_fanout(shed, st, will_o_wisp, 1)[0].1.opp_status[0], @model.Burn)
}

///|
test "ss blocker: Magma Armor and Harsh Sunlight block freeze only, not burn" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let magma = [ss_cmb(ss_pokemon("magma", "ノーマル", "", 200, 60), [], "マグマのよろい")]
  let base = ss_state(200, 200, @model.None, @model.None)
  let sunny = { ..base, weather: @model.Weather::Sun }
  @debug.assert_eq(ss_fanout(magma, base, fire_punch, 1)[0].1.opp_status[0], @model.Burn)
  @debug.assert_eq(
    ss_fanout(
      [ss_cmb(ss_pokemon("plain", "ノーマル", "", 200, 60), [], "")],
      sunny,
      fire_punch,
      1,
    )[0].1.opp_status[0],
    @model.Burn,
  )
}

///|
test "ss blocker: a fainted target gets no secondary status" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let target = [ss_cmb(ss_pokemon("target", "ノーマル", "", 200, 60), [], "")]
  let outs = ss_fanout(target, ss_state(200, 0, @model.None, @model.None), fire_punch, 1)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
}

///|
test "ss gate: secondary_gated_move keeps the secondary when HP is lost (Disguise chip), drops it for 0 HP lost and Sheer Force" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 10)),
  )
  let status_move = ss_move(
    "おにび",
    "ほのお",
    @model.Status,
    0,
    85,
    Some((@model.BurnKind, 85)),
  )
  let base = ss_state(200, 200, @model.None, @model.None)
  let plain = [ss_cmb(ss_pokemon("plain", "ノーマル", "", 200, 60), [fire_punch], "")]
  let sheer = [ss_cmb(ss_pokemon("sheer", "ノーマル", "", 200, 60), [fire_punch], "ちからずく")]
  // HP を減らした命中 (通常特性): 追加効果は残る。
  @debug.assert_eq(
    secondary_gated_move(base, true, 0, plain, fire_punch, 50).status_effect,
    Some((@model.BurnKind, 10)),
  )
  // ばけのかわ の初撃吸収 (chip 25 = 最大 HP 200 / 8 の HP 減少): 追加効果は残る (Showdown fallback)。
  @debug.assert_eq(
    secondary_gated_move(base, true, 0, plain, fire_punch, 25).status_effect,
    Some((@model.BurnKind, 10)),
  )
  // HP を 1 も減らさない命中 (瀕死の対象など): 追加効果は付かない。
  @debug.assert_eq(
    secondary_gated_move(base, true, 0, plain, fire_punch, 0).status_effect,
    None,
  )
  // ちからずく の使用者: 追加効果を失う。威力 1.3 倍は同じ集合の技だけ
  // (`move_has_sheer_force_effect`)。
  @debug.assert_eq(
    secondary_gated_move(base, true, 0, sheer, fire_punch, 50).status_effect,
    None,
  )
  // 変化技は dealt=0 でも写さない (追加効果ではなく状態技の直接効果)。
  @debug.assert_eq(
    secondary_gated_move(base, true, 0, plain, status_move, 0).status_effect,
    Some((@model.BurnKind, 85)),
  )
}

///|
test "ss e2e: a Fire hit thaws a frozen target and then its 100% burn applies" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [ss_cmb(ss_pokemon("fire", "ほのお", "", 200, 120), [fire_punch], "")]
  let opp_team = [ss_cmb(ss_pokemon("frozen", "ノーマル", "", 200, 60), [tackle], "")]
  let state = ss_state(200, 200, @model.None, @model.Freeze(2))
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  // 解凍 (命中前の炎ダメージ) → 二次効果の やけど が入る (確率 1.0)。
  assert_true(ss_close(ss_opp_mass(outs, fn(s) { s == @model.Burn }), 1.0))
}

///|
test "ss e2e: a 100% burn from the faster attacker halves the slower physical attack" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let no_status = ss_move("ほのおのパンチ", "ほのお", @model.Physical, 75, 100, None)
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 90, 100, None)
  let opp_team = [ss_cmb(ss_pokemon("slow", "ノーマル", "", 200, 60), [tackle], "")]
  let burn_team = [ss_cmb(ss_pokemon("fast", "ほのお", "", 200, 120), [fire_punch], "")]
  let plain_team = [ss_cmb(ss_pokemon("fast", "ほのお", "", 200, 120), [no_status], "")]
  let st = ss_state(200, 200, @model.None, @model.None)
  let with_burn = attempt_turn_with_cache(
    st,
    UseMove(0),
    UseMove(0),
    burn_team,
    opp_team,
    new_damage_cache(),
  )
  let control = attempt_turn_with_cache(
    st,
    UseMove(0),
    UseMove(0),
    plain_team,
    opp_team,
    new_damage_cache(),
  )
  // 期待残 HP (自分側): 後攻の物理攻撃が やけど で半減する分だけ、やけど の枝の方が多く残る。
  let mut hp_burn = 0.0
  for item in with_burn {
    let (p, s) = item
    hp_burn = hp_burn + p * s.my_hps[0].to_double()
  }
  let mut hp_control = 0.0
  for item in control {
    let (p, s) = item
    hp_control = hp_control + p * s.my_hps[0].to_double()
  }
  assert_true(hp_burn > hp_control)
}

///|
test "ss e2e: a Shield Dust target keeps its HP and gets no burn from a 100% burn hit" {
  let fire_punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [ss_cmb(ss_pokemon("fire", "ほのお", "", 200, 120), [fire_punch], "")]
  let opp_team = [ss_cmb(ss_pokemon("shed", "ノーマル", "", 200, 60), [tackle], "りんぷん")]
  let outs = attempt_turn_with_cache(
    ss_state(200, 200, @model.None, @model.None),
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  assert_true(ss_close(ss_opp_mass(outs, fn(s) { s == @model.None }), 1.0))
  // ダメージは通る (追加効果だけが止まる)。
  assert_true(ss_close(ss_mass(outs, fn(s) { s.opp_hps[0] < 200 }), 1.0))
}

///|
/// ばけのかわ (intact) の対象へ 100% まひの技 (ほっぺすりすり 相当、でんき 物理)。初撃は chip のみ
/// (最大 HP / 8 = 25 だけ減り、ばけのかわ は剥がれる) だが、HP が減っているので まひ は必ず付く
/// (Showdown fallback。`secondary_gated_move` は HP 減少のある命中を通す)。
test "ss disguise: a 100% paralysis hit (ほっぺすりすり) still paralyzes through an intact Disguise chip" {
  let nuzzle = ss_move(
    "ほっぺすりすり",
    "でんき",
    @model.Physical,
    20,
    100,
    Some((@model.ParalyzeKind, 100)),
  )
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [ss_cmb(ss_pokemon("pika", "でんき", "", 200, 120), [nuzzle], "")]
  // actual_stats で HP を 200 に固定する (chip = 200 / 8 = 25 を effective_hp と engine の両方で一致させる)。
  let mimikyu = { ..ss_cmb(ss_pokemon("mimikyu", "ゴースト", "フェアリー", 200, 60), [tackle], "ばけのかわ"), actual_stats: Some([200, 100, 100, 100, 100, 100]) }
  let outs = attempt_turn_with_cache(
    ss_state(200, 200, @model.None, @model.None),
    UseMove(0),
    UseMove(0),
    my_team,
    [mimikyu],
    new_damage_cache(),
  )
  assert_true(ss_close(ss_opp_mass(outs, fn(s) { s == @model.Paralyze }), 1.0))
  // chip のみ (200 の 1/8 = 25) が入り、ばけのかわ は剥がれる。
  assert_true(ss_close(ss_mass(outs, fn(s) { s.opp_hps[0] == 175 }), 1.0))
  assert_true(ss_close(ss_mass(outs, fn(s) { s.opp_disguise_busted[0] }), 1.0))
}

///|
/// ばけのかわ (intact) の対象へ 100% 凍結の技。初撃の chip でも凍結は付く (base b102445 の挙動を
/// 戻す。Showdown fallback)。対象の方が速いので、凍らせた後の試行は次ターン (frz landing の規則)。
test "ss disguise: a 100% freeze hit still freezes through an intact Disguise chip" {
  let ice_hit = ss_move(
    "こおりのつぶて",
    "こおり",
    @model.Physical,
    40,
    100,
    Some((@model.FreezeKind, 100)),
  )
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let my_team = [ss_cmb(ss_pokemon("ice", "こおり", "", 200, 60), [ice_hit], "")]
  let opp_team = [
    ss_cmb(ss_pokemon("mimikyu", "ゴースト", "フェアリー", 200, 120), [tackle], "ばけのかわ"),
  ]
  let outs = attempt_turn_with_cache(
    ss_state(200, 200, @model.None, @model.None),
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  assert_true(ss_close(ss_opp_mass(outs, fn(s) { s == @model.Freeze(2) }), 1.0))
  assert_true(ss_close(ss_mass(outs, fn(s) { s.opp_disguise_busted[0] }), 1.0))
}

///|
/// HP を 1 も減らさない命中には 100% まひも付かない: タイプ無効 (でんき → じめん) と 特性無効
/// (そうしょく が くさ を吸収、モデル化済みの吸収特性)。どちらも呼び出し元で hits_count = 0 /
/// `move_absorbed_by_holder` として抜けるため fanout に来ない。対照 (特性なし) は まひ が入る。
test "ss gate: a type-immune hit and a Sap Sipper absorbed hit give no paralysis" {
  let nuzzle = ss_move(
    "ほっぺすりすり",
    "でんき",
    @model.Physical,
    20,
    100,
    Some((@model.ParalyzeKind, 100)),
  )
  let leaf = ss_move(
    "はっぱカッター",
    "くさ",
    @model.Physical,
    50,
    100,
    Some((@model.ParalyzeKind, 100)),
  )
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let pika = [ss_cmb(ss_pokemon("pika", "でんき", "", 200, 120), [nuzzle], "")]
  let leafy = [ss_cmb(ss_pokemon("leafy", "くさ", "", 200, 120), [leaf], "")]
  let ground = [ss_cmb(ss_pokemon("ground", "じめん", "", 200, 60), [tackle], "")]
  let sipper = [ss_cmb(ss_pokemon("sipper", "ノーマル", "", 200, 60), [tackle], "そうしょく")]
  let plain = [ss_cmb(ss_pokemon("plain", "ノーマル", "", 200, 60), [tackle], "")]
  let st = ss_state(200, 200, @model.None, @model.None)
  // タイプ無効: でんき の まひ 技は じめん に入らない。
  let immune = attempt_turn_with_cache(st, UseMove(0), UseMove(0), pika, ground, new_damage_cache())
  assert_true(ss_close(ss_opp_mass(immune, fn(s) { s == @model.Paralyze }), 0.0))
  // 吸収: くさ の まひ 技は そうしょく に吸収され、まひ も HP 減少も起きない。
  let absorbed = attempt_turn_with_cache(st, UseMove(0), UseMove(0), leafy, sipper, new_damage_cache())
  assert_true(ss_close(ss_opp_mass(absorbed, fn(s) { s == @model.Paralyze }), 0.0))
  assert_true(ss_close(ss_mass(absorbed, fn(s) { s.opp_hps[0] == 200 }), 1.0))
  // 対照: 特性なしの相手には同じ くさ の まひ 技が 100% 入る。
  let control = attempt_turn_with_cache(st, UseMove(0), UseMove(0), leafy, plain, new_damage_cache())
  assert_true(ss_close(ss_opp_mass(control, fn(s) { s == @model.Paralyze }), 1.0))
}
