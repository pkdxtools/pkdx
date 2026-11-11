///|
/// 攻撃技の二次状態異常 (やけど / まひ / どく / もうどく) の MC 側と DP / MC の parity
/// (switching_game_secstatus_wbtest.mbt と対)。
/// - 分布: `mc_try_apply_status` を seed 固定で大量に回し、二次効果の確率 (10%) が一致する。
/// - 真理値表: 免疫 (ほのお / でんき / どく / はがね)、既存の状態異常、Misty (grounded)、
///   りんぷん (ダメージ技のみ)、HP を減らさない命中 (瀕死)、ちからずく。ばけのかわ の吸収 chip は
///   HP を減らすので追加効果は付く (Showdown fallback。DP `secondary_gated_move` と同じ規則)。
/// - parity: 1v1 で DP (`switching_game_winrate`, exact) と MC (`team_monte_carlo_value`,
///   rollout 平均) が許容誤差内で一致する。
/// - 感度ガード: 追加効果のない対照との差が閾値より大きいことを先に確認する (経路が値に効いている)。

///|
fn sss_move(
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
fn sss_pokemon(
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
fn sss_cmb(
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
/// seed 固定で `mc_try_apply_status` を `trials` 回回し、状態異常の付与頻度を返す。
fn sss_freq(
  rng : @random.Rand,
  mv : @model.Move,
  defender : Array[Combatant],
  trials : Int,
  want : @model.StatusCondition,
  hp_lost? : Int = 1,
  attacker_ability? : String = "",
) -> Double {
  let mut hits = 0
  for _i = 0; _i < trials; _i = _i + 1 {
    let st : Array[@model.StatusCondition] = [@model.StatusCondition::None]
    mc_try_apply_status(
      rng,
      mv,
      defender,
      [200],
      st,
      0,
      hp_lost~,
      attacker_ability~,
    )
    if st[0] == want {
      hits = hits + 1
    }
  }
  hits.to_double() / trials.to_double()
}

///|
test "mc ss: a 10% burn secondary lands on about 10% of seeded tries" {
  let rng = seeded_rng(20261111UL)
  let fire_punch = sss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 10)),
  )
  let target = [sss_cmb(sss_pokemon("target", "ノーマル", "", 200, 60), [], "")]
  let f = sss_freq(rng, fire_punch, target, 30000, @model.Burn)
  assert_true((f - 0.1).abs() < 0.01)
}

///|
test "mc ss: 30% paralysis and 50% toxic secondaries land at their rates" {
  let rng = seeded_rng(20261112UL)
  let thunderbolt = sss_move(
    "かみなり",
    "でんき",
    @model.Special,
    110,
    100,
    Some((@model.ParalyzeKind, 30)),
  )
  let fang = sss_move(
    "どくどくのキバ",
    "どく",
    @model.Physical,
    50,
    100,
    Some((@model.BadPoisonKind, 50)),
  )
  let target = [sss_cmb(sss_pokemon("target", "ノーマル", "", 200, 60), [], "")]
  let p = sss_freq(rng, thunderbolt, target, 30000, @model.Paralyze)
  let t = sss_freq(rng, fang, target, 30000, @model.BadPoison(0))
  assert_true((p - 0.3).abs() < 0.01)
  assert_true((t - 0.5).abs() < 0.01)
}

///|
test "mc ss: immunities and the existing-status exclusivity hold for the MC roll" {
  let rng = seeded_rng(20261113UL)
  let fire_punch = sss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let sludge = sss_move(
    "ヘドロばくだん",
    "どく",
    @model.Special,
    90,
    100,
    Some((@model.PoisonKind, 100)),
  )
  let fire = [sss_cmb(sss_pokemon("fire", "ほのお", "", 200, 60), [], "")]
  let poison = [sss_cmb(sss_pokemon("poison", "どく", "", 200, 60), [], "")]
  let steel = [sss_cmb(sss_pokemon("steel", "はがね", "", 200, 60), [], "")]
  let plain = [sss_cmb(sss_pokemon("plain", "ノーマル", "", 200, 60), [], "")]
  assert_true(sss_freq(rng, fire_punch, fire, 200, @model.Burn) == 0.0)
  assert_true(sss_freq(rng, sludge, poison, 200, @model.Poison) == 0.0)
  assert_true(sss_freq(rng, sludge, steel, 200, @model.Poison) == 0.0)
  assert_true(sss_freq(rng, fire_punch, plain, 200, @model.Burn) == 1.0)
  // 既存の状態異常があれば付かない (`mc_try_apply_status` は cur != None で戻る)。
  let st : Array[@model.StatusCondition] = [@model.StatusCondition::Paralyze]
  mc_try_apply_status(rng, fire_punch, plain, [200], st, 0)
  @debug.assert_eq(st[0], @model.Paralyze)
}

///|
test "mc ss: Shield Dust blocks a damaging move's secondary only; Sheer Force and 0 HP lost drop it; a Disguise chip keeps it" {
  let rng = seeded_rng(20261114UL)
  let fire_punch = sss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let will_o_wisp = sss_move(
    "おにび",
    "ほのお",
    @model.Status,
    0,
    100,
    Some((@model.BurnKind, 100)),
  )
  let shed = [sss_cmb(sss_pokemon("shed", "ノーマル", "", 200, 60), [], "りんぷん")]
  let plain = [sss_cmb(sss_pokemon("plain", "ノーマル", "", 200, 60), [], "")]
  // りんぷん: ダメージ技の追加効果だけ止まる (変化技は入る)。
  assert_true(sss_freq(rng, fire_punch, shed, 200, @model.Burn) == 0.0)
  assert_true(sss_freq(rng, will_o_wisp, shed, 200, @model.Burn) == 1.0)
  // 既定引数 (dmg 1 / 特性なし) は従来どおり付く。
  assert_true(sss_freq(rng, fire_punch, plain, 200, @model.Burn) == 1.0)
  // この命中で相手の HP が減らない (瀕死など) なら付かない。
  assert_true(sss_freq(rng, fire_punch, plain, 200, @model.Burn, hp_lost=0) == 0.0)
  // ばけのかわ の吸収 chip (HP 25 減) は付く (Showdown fallback)。
  assert_true(sss_freq(rng, fire_punch, plain, 200, @model.Burn, hp_lost=25) == 1.0)
  // ちからずく の使用者は追加効果を失う。
  assert_true(
    sss_freq(rng, fire_punch, plain, 200, @model.Burn, attacker_ability="ちからずく") == 0.0,
  )
}

///|
test "mc ss: Misty Terrain blocks a grounded target's secondary; Electric Terrain does not" {
  let rng = seeded_rng(20261115UL)
  let fire_punch = sss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let plain = [sss_cmb(sss_pokemon("plain", "ノーマル", "", 200, 60), [], "")]
  let st_misty : Array[@model.StatusCondition] = [@model.StatusCondition::None]
  mc_try_apply_status(rng, fire_punch, plain, [200], st_misty, 0, field=@model.Field::Misty)
  @debug.assert_eq(st_misty[0], @model.None)
  let st_electric : Array[@model.StatusCondition] = [@model.StatusCondition::None]
  mc_try_apply_status(
    rng,
    fire_punch,
    plain,
    [200],
    st_electric,
    0,
    field=@model.Field::Electric,
  )
  @debug.assert_eq(st_electric[0], @model.Burn)
}

///|
/// 1v1 の parity fixture: 速い側が かえんほうしゃ 相当の 特殊 威力 50 の技 (30% やけど、
/// タイプはノーマルで STAB なし)、遅い側が 威力 50 の たいあたり (物理)。対照は同じ威力・命中
/// の追加効果なし技 (差は追加効果の経路だけ)。値は飽和しない (対照 -0.14、30% やけど 0.09)。
/// 火傷は遅い側の物理攻撃を半減させる (行動時点の後攻 `atk_burn`)。STAB 付きの同種 fixture では
/// 対照の DP / MC が既に一致しない領域があるので (本 PR の範囲外)、STAB を外している。
test "ss DP/MC parity: 30% burn secondary against a slower Tackle target" {
  let burn_special = sss_move(
    "かえんほうしゃ",
    "ほのお",
    @model.Special,
    50,
    100,
    Some((@model.BurnKind, 30)),
  )
  let no_status = sss_move("かえんほうしゃ", "ほのお", @model.Special, 50, 100, None)
  let tackle = sss_move("たいあたり", "ノーマル", @model.Physical, 50, 100, None)
  let target = [sss_cmb(sss_pokemon("target", "ノーマル", "", 200, 60), [tackle], "")]
  let burner = [sss_cmb(sss_pokemon("burner", "ノーマル", "", 200, 120), [burn_special], "")]
  let control = [sss_cmb(sss_pokemon("control", "ノーマル", "", 200, 120), [no_status], "")]
  let dp_burn = switching_game_winrate(burner, target, 4)
  let dp_control = switching_game_winrate(control, target, 4)
  let mc_burn = team_monte_carlo_value(burner, target, 8192, 20261116UL, turn_limit=4)
  let mc_control = team_monte_carlo_value(control, target, 8192, 20261116UL, turn_limit=4)
  // 感度ガード: 火傷の経路が値に効いている (対照との差が閾値より大きい)。
  assert_true((dp_burn - dp_control).abs() > 0.005)
  assert_true((dp_burn - mc_burn).abs() < 0.02)
  assert_true((dp_control - mc_control).abs() < 0.02)
}

///|
/// りんぷん の対象では追加効果が付かないので、DP / MC とも対照 (追加効果なし) と一致する。
test "ss DP/MC parity: a Shield Dust target makes the 30% burn a no-op (equals the control)" {
  let burn_special = sss_move(
    "かえんほうしゃ",
    "ほのお",
    @model.Special,
    50,
    100,
    Some((@model.BurnKind, 30)),
  )
  let no_status = sss_move("かえんほうしゃ", "ほのお", @model.Special, 50, 100, None)
  let tackle = sss_move("たいあたり", "ノーマル", @model.Physical, 50, 100, None)
  let shed = [sss_cmb(sss_pokemon("shed", "ノーマル", "", 200, 60), [tackle], "りんぷん")]
  let burner = [sss_cmb(sss_pokemon("burner", "ノーマル", "", 200, 120), [burn_special], "")]
  let control = [sss_cmb(sss_pokemon("control", "ノーマル", "", 200, 120), [no_status], "")]
  let dp_shed = switching_game_winrate(burner, shed, 4)
  let dp_control = switching_game_winrate(control, shed, 4)
  let mc_shed = team_monte_carlo_value(burner, shed, 8192, 20261117UL, turn_limit=4)
  let mc_control = team_monte_carlo_value(control, shed, 8192, 20261117UL, turn_limit=4)
  assert_true((dp_shed - dp_control).abs() < 1.0e-9)
  assert_true((dp_shed - mc_shed).abs() < 0.02)
  assert_true((dp_control - mc_control).abs() < 0.02)
}

///|
/// ばけのかわ (intact) の対象への 100% まひ (ほっぺすりすり 相当): 吸収 chip で HP が減るので
/// 追加効果は付く (Showdown fallback)。瀕死の対象と 命中無効 (immune) の leg には付かない。
test "mc ss: a Disguise chip hit still paralyzes (100%); a fainted target and an immune leg do not" {
  let rng = seeded_rng(20261120UL)
  let nuzzle = sss_move(
    "ほっぺすりすり",
    "でんき",
    @model.Physical,
    20,
    100,
    Some((@model.ParalyzeKind, 100)),
  )
  let mimikyu = [
    sss_cmb(sss_pokemon("mimikyu", "ゴースト", "フェアリー", 200, 60), [], "ばけのかわ"),
  ]
  assert_true(sss_freq(rng, nuzzle, mimikyu, 200, @model.Paralyze, hp_lost=25) == 1.0)
  assert_true(sss_freq(rng, nuzzle, mimikyu, 200, @model.Paralyze, hp_lost=0) == 0.0)
  // 瀕死 (防御側 HP 0) の対象には付かない。
  let fainted : Array[@model.StatusCondition] = [@model.StatusCondition::None]
  mc_try_apply_status(rng, nuzzle, mimikyu, [0], fainted, 0, hp_lost=25)
  @debug.assert_eq(fainted[0], @model.StatusCondition::None)
  // 命中無効 (immune) の leg には付かない。
  let immune_st : Array[@model.StatusCondition] = [@model.StatusCondition::None]
  mc_try_apply_status(rng, nuzzle, mimikyu, [200], immune_st, 0, immune=true, hp_lost=25)
  @debug.assert_eq(immune_st[0], @model.StatusCondition::None)
}

///|
/// ばけのかわ の対象 (ゴースト / フェアリー、ばけのかわ) への 100% まひ 技 (威力 50、STAB なし)。
/// 初撃は chip のみで、まひ は HP 減少のある命中として付く。まひ は EOT ダメージを持たないので
/// DP / MC の既知の差 (やけど / どく) は出ない。対照は追加効果のない同技。
test "ss DP/MC parity: a Disguise target takes a 100% paralysis from a physical hit (chip, then the status)" {
  let nuzzle = sss_move(
    "ほっぺすりすり",
    "でんき",
    @model.Physical,
    50,
    100,
    Some((@model.ParalyzeKind, 100)),
  )
  let no_status = sss_move("ほっぺすりすり", "でんき", @model.Physical, 50, 100, None)
  let tackle = sss_move("たいあたり", "ノーマル", @model.Physical, 50, 100, None)
  let mimikyu = [
    sss_cmb(sss_pokemon("mimikyu", "ゴースト", "フェアリー", 200, 60), [tackle], "ばけのかわ"),
  ]
  let burner = [sss_cmb(sss_pokemon("burner", "ノーマル", "", 200, 120), [nuzzle], "")]
  let control = [sss_cmb(sss_pokemon("control", "ノーマル", "", 200, 120), [no_status], "")]
  let dp_para = switching_game_winrate(burner, mimikyu, 4)
  let dp_control = switching_game_winrate(control, mimikyu, 4)
  let mc_para = team_monte_carlo_value(burner, mimikyu, 8192, 20261121UL, turn_limit=4)
  let mc_control = team_monte_carlo_value(control, mimikyu, 8192, 20261121UL, turn_limit=4)
  // 感度ガード: まひの経路が値に効いている (対照との差が閾値より大きい)。
  assert_true((dp_para - dp_control).abs() > 0.005)
  assert_true((dp_para - mc_para).abs() < 0.02)
  assert_true((dp_control - mc_control).abs() < 0.02)
}
