///|
/// 特性の状態異常免疫 (DP fanout / MC / 接触 / あくび発動 / Rest / parity)。
/// 本文は champout `50e7233` の tokuseiinfo_syn.json。付与を止め、既にある状態は治さない。
/// リーフガードははれだけ。フラワーベールは自分がくさのときだけ (ねむるは通す)。

///|
fn simm_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
fn simm_status_move(kind : @model.StatusKind) -> @model.Move {
  let (name, ty) = match kind {
    @model.ParalyzeKind => ("でんじは", "でんき")
    @model.BurnKind => ("おにび", "ほのお")
    @model.PoisonKind => ("どくのこな", "どく")
    @model.BadPoisonKind => ("どくどく", "どく")
    @model.SleepKind => ("ねむりごな", "くさ")
    @model.FreezeKind => ("こごえるかぜ", "こおり")
    @model.DrowsyKind => ("あくび", "ノーマル")
  }
  ss_move(name, ty, @model.Status, 0, 100, Some((kind, 100)))
}

///|
fn simm_secondary(kind : @model.StatusKind) -> @model.Move {
  let (name, ty) = match kind {
    @model.ParalyzeKind => ("かみなりパンチ", "でんき")
    @model.BurnKind => ("ほのおのパンチ", "ほのお")
    @model.PoisonKind => ("どくづき", "どく")
    @model.BadPoisonKind => ("どくどくのキバ", "どく")
    @model.SleepKind => ("テスト眠り", "ノーマル")
    @model.FreezeKind => ("れいとうビーム", "こおり")
    @model.DrowsyKind => ("テストあくび", "ノーマル")
  }
  ss_move(name, ty, @model.Physical, 40, 100, Some((kind, 100)))
}

///|
fn simm_holder(
  ability : String,
  type1 : String,
  type2 : String,
) -> Array[Combatant] {
  [ss_cmb(ss_pokemon("holder", type1, type2, 200, 60), [], ability)]
}

///|
fn simm_landed(kind : @model.StatusKind) -> @model.StatusCondition {
  match kind {
    @model.ParalyzeKind => @model.Paralyze
    @model.BurnKind => @model.Burn
    @model.PoisonKind => @model.Poison
    @model.BadPoisonKind => @model.BadPoison(0)
    @model.SleepKind => @model.Sleep(2)
    @model.FreezeKind => @model.Freeze(2)
    @model.DrowsyKind => @model.Drowsy(1)
  }
}

///|
fn simm_state(status : @model.StatusCondition, weather : @model.Weather) -> SwitchingGameState {
  { ..ss_state(200, 200, @model.None, status), weather }
}

///|
/// 変化技と追加効果の両方。`blocked` なら None のまま。そうでなければ `landed`。
fn simm_expect_gate(
  ability : String,
  type1 : String,
  type2 : String,
  kind : @model.StatusKind,
  weather : @model.Weather,
  blocked : Bool,
) -> Unit raise {
  let holder = simm_holder(ability, type1, type2)
  let want = if blocked { @model.StatusCondition::None } else { simm_landed(kind) }
  let clear = simm_state(@model.StatusCondition::None, weather)
  let dp_status = ss_fanout(holder, clear, simm_status_move(kind), 1)
  assert_true(dp_status.length() == 1)
  assert_true(dp_status[0].1.opp_status[0] == want)
  let dp_sec = ss_fanout(holder, clear, simm_secondary(kind), 1)
  assert_true(dp_sec.length() == 1)
  assert_true(dp_sec[0].1.opp_status[0] == want)
  let rng = seeded_rng(20261113UL)
  let st_status : Array[@model.StatusCondition] = [@model.StatusCondition::None]
  mc_try_apply_status(
    rng,
    simm_status_move(kind),
    holder,
    [200],
    st_status,
    0,
    weather~,
  )
  assert_true(st_status[0] == want)
  let st_sec : Array[@model.StatusCondition] = [@model.StatusCondition::None]
  mc_try_apply_status(
    rng,
    simm_secondary(kind),
    holder,
    [200],
    st_sec,
    0,
    weather~,
    hp_lost=40,
  )
  assert_true(st_sec[0] == want)
  if blocked {
    // 既にある状態は治さない (変化技を当てても同じ kind のまま)。
    let already = simm_landed(kind)
    let dp_keep = ss_fanout(holder, simm_state(already, weather), simm_status_move(kind), 1)
    assert_true(dp_keep.length() == 1)
    assert_true(dp_keep[0].1.opp_status[0] == already)
    let st_keep : Array[@model.StatusCondition] = [already]
    mc_try_apply_status(
      rng,
      simm_status_move(kind),
      holder,
      [200],
      st_keep,
      0,
      weather~,
    )
    assert_true(st_keep[0] == already)
  }
}

///|
test "status immunity: じゅうなん blocks paralysis move and secondary, keeps existing paralysis" {
  simm_expect_gate("じゅうなん", "ノーマル", "", @model.ParalyzeKind, @model.Weather::None, true)
  // まひ以外は通る。
  simm_expect_gate("じゅうなん", "ノーマル", "", @model.BurnKind, @model.Weather::None, false)
}

///|
test "status immunity: めんえき blocks poison and bad poison, keeps existing poison" {
  simm_expect_gate("めんえき", "ノーマル", "", @model.PoisonKind, @model.Weather::None, true)
  simm_expect_gate("めんえき", "ノーマル", "", @model.BadPoisonKind, @model.Weather::None, true)
  simm_expect_gate("めんえき", "ノーマル", "", @model.ParalyzeKind, @model.Weather::None, false)
}

///|
test "status immunity: すいほう and ねつこうかん block burn move and secondary" {
  simm_expect_gate("すいほう", "みず", "", @model.BurnKind, @model.Weather::None, true)
  simm_expect_gate("ねつこうかん", "こおり", "", @model.BurnKind, @model.Weather::None, true)
  simm_expect_gate("すいほう", "みず", "", @model.PoisonKind, @model.Weather::None, false)
}

///|
test "status immunity: きよめのしお blocks every modelled status, including yawn and freeze" {
  simm_expect_gate("きよめのしお", "いわ", "", @model.ParalyzeKind, @model.Weather::None, true)
  simm_expect_gate("きよめのしお", "いわ", "", @model.BurnKind, @model.Weather::None, true)
  simm_expect_gate("きよめのしお", "いわ", "", @model.PoisonKind, @model.Weather::None, true)
  simm_expect_gate("きよめのしお", "いわ", "", @model.BadPoisonKind, @model.Weather::None, true)
  simm_expect_gate("きよめのしお", "いわ", "", @model.SleepKind, @model.Weather::None, true)
  simm_expect_gate("きよめのしお", "いわ", "", @model.FreezeKind, @model.Weather::None, true)
  simm_expect_gate("きよめのしお", "いわ", "", @model.DrowsyKind, @model.Weather::None, true)
}

///|
test "status immunity: リーフガード blocks status only in sun" {
  simm_expect_gate("リーフガード", "くさ", "", @model.BurnKind, @model.Weather::Sun, true)
  simm_expect_gate("リーフガード", "くさ", "", @model.ParalyzeKind, @model.Weather::Sun, true)
  simm_expect_gate("リーフガード", "くさ", "", @model.SleepKind, @model.Weather::Sun, true)
  simm_expect_gate("リーフガード", "くさ", "", @model.DrowsyKind, @model.Weather::Sun, true)
  simm_expect_gate("リーフガード", "くさ", "", @model.PoisonKind, @model.Weather::None, false)
  simm_expect_gate("リーフガード", "くさ", "", @model.BurnKind, @model.Weather::Rain, false)
  simm_expect_gate("リーフガード", "くさ", "", @model.ParalyzeKind, @model.Weather::Sand, false)
}

///|
test "status immunity: フラワーベール blocks status only when the holder is Grass" {
  simm_expect_gate("フラワーベール", "くさ", "", @model.BurnKind, @model.Weather::None, true)
  simm_expect_gate("フラワーベール", "フェアリー", "くさ", @model.ParalyzeKind, @model.Weather::None, true)
  simm_expect_gate("フラワーベール", "くさ", "", @model.DrowsyKind, @model.Weather::None, true)
  simm_expect_gate("フラワーベール", "フェアリー", "", @model.BurnKind, @model.Weather::None, false)
  simm_expect_gate("フラワーベール", "ノーマル", "", @model.SleepKind, @model.Weather::None, false)
}

///|
test "status immunity: マイペース does not block a modelled status move" {
  simm_expect_gate("マイペース", "ノーマル", "", @model.ParalyzeKind, @model.Weather::None, false)
  simm_expect_gate("マイペース", "ノーマル", "", @model.DrowsyKind, @model.Weather::None, false)
}

///|
/// あくびの EOT 発動。Drowsy(0) が眠りになる直前に特性を見る。予告中 (Drowsy(1)) は進む。
test "status immunity: yawn conversion is blocked by all-status abilities" {
  let (_hp, salt) = eot_slip_active(
    100,
    100,
    @model.Drowsy(0),
    ability="きよめのしお",
  )
  @debug.assert_eq(salt, @model.None)
  let (_hp2, sun) = eot_slip_active(
    100,
    100,
    @model.Drowsy(0),
    ability="リーフガード",
    weather=@model.Weather::Sun,
  )
  @debug.assert_eq(sun, @model.None)
  let (_hp3, nosun) = eot_slip_active(
    100,
    100,
    @model.Drowsy(0),
    ability="リーフガード",
  )
  @debug.assert_eq(nosun, @model.Sleep(2))
  let (_hp4, grass) = eot_slip_active(
    100,
    100,
    @model.Drowsy(0),
    ability="フラワーベール",
    type1="くさ",
  )
  @debug.assert_eq(grass, @model.None)
  let (_hp5, not_grass) = eot_slip_active(
    100,
    100,
    @model.Drowsy(0),
    ability="フラワーベール",
    type1="ノーマル",
  )
  @debug.assert_eq(not_grass, @model.Sleep(2))
  let (_hp6, ticking) = eot_slip_active(
    100,
    100,
    @model.Drowsy(1),
    ability="きよめのしお",
  )
  @debug.assert_eq(ticking, @model.Drowsy(0))
}

///|
test "status immunity: Rest fails for purifying salt and leaf guard in sun, not flower veil" {
  let rest = mk_rest_move()
  let salt_hp = [40]
  let salt_st : Array[@model.StatusCondition] = [@model.Burn]
  apply_healing(
    rest,
    0,
    salt_hp,
    100,
    @model.Weather::None,
    salt_st,
    "きよめのしお",
    0,
    "",
  )
  @debug.assert_eq(salt_hp[0], 40)
  @debug.assert_eq(salt_st[0], @model.Burn)
  let sun_hp = [40]
  let sun_st : Array[@model.StatusCondition] = [@model.None]
  apply_healing(
    rest,
    0,
    sun_hp,
    100,
    @model.Weather::Sun,
    sun_st,
    "リーフガード",
    0,
    "",
  )
  @debug.assert_eq(sun_hp[0], 40)
  @debug.assert_eq(sun_st[0], @model.None)
  let clear_hp = [40]
  let clear_st : Array[@model.StatusCondition] = [@model.None]
  apply_healing(
    rest,
    0,
    clear_hp,
    100,
    @model.Weather::None,
    clear_st,
    "リーフガード",
    0,
    "",
  )
  @debug.assert_eq(clear_hp[0], 100)
  @debug.assert_eq(clear_st[0], @model.RestSleep(2))
  // フラワーベールのくさは自分のねむるを止めない (Showdown fallback)。
  let veil_hp = [40]
  let veil_st : Array[@model.StatusCondition] = [@model.None]
  apply_healing(
    rest,
    0,
    veil_hp,
    100,
    @model.Weather::None,
    veil_st,
    "フラワーベール",
    0,
    "",
    attacker_type1="くさ",
  )
  @debug.assert_eq(veil_hp[0], 100)
  @debug.assert_eq(veil_st[0], @model.RestSleep(2))
}

///|
fn simm_contact(
  atk_ability : String,
  atk_type : String,
  def_ability : String,
  def_item : String,
  weather : @model.Weather,
) -> Array[(Double, SwitchingGameState)] {
  let attacker = cp_combatant(
    cp_pokemon("attacker", atk_type, ""),
    ability=atk_ability,
  )
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""),
    ability=def_ability,
    item=def_item,
  )
  let state = { ..cp_state(), weather }
  apply_contact_proc_fanout(
    state,
    true,
    0,
    0,
    [attacker, attacker, attacker],
    [defender, defender, defender],
    cp_move("たいあたり"),
  )
}

///|
fn simm_contact_mass(
  outs : Array[(Double, SwitchingGameState)],
  pred : (@model.StatusCondition) -> Bool,
) -> Double {
  let mut total = 0.0
  for item in outs {
    let (p, s) = item
    if pred(s.my_status[0]) {
      total = total + p
    }
  }
  total
}

///|
test "status immunity: contact ability and item procs respect the same gate" {
  // せいでんき 30% まひは じゅうなんで消える。
  let limber = simm_contact("じゅうなん", "ノーマル", "せいでんき", "", @model.Weather::None)
  @debug.assert_eq(limber.length(), 1)
  assert_true(simm_close(limber[0].0, 1.0))
  @debug.assert_eq(limber[0].1.my_status[0], @model.None)
  // どくしゅは めんえきで消える。
  let immune = simm_contact("めんえき", "ノーマル", "どくしゅ", "", @model.Weather::None)
  @debug.assert_eq(immune.length(), 1)
  @debug.assert_eq(immune[0].1.my_status[0], @model.None)
  // ほのおのからだは すいほう / ねつこうかんで消える。
  let bubble = simm_contact("すいほう", "みず", "ほのおのからだ", "", @model.Weather::None)
  @debug.assert_eq(bubble.length(), 1)
  let thermal = simm_contact("ねつこうかん", "こおり", "ほのおのからだ", "", @model.Weather::None)
  @debug.assert_eq(thermal.length(), 1)
  // とびだすハバネロ (100% やけど) も すいほうで消える。とびだすなかみは じゅうなん。
  let pepper = simm_contact("すいほう", "ノーマル", "", "とびだすハバネロ", @model.Weather::None)
  @debug.assert_eq(pepper.length(), 1)
  @debug.assert_eq(pepper[0].1.my_status[0], @model.None)
  let herb = simm_contact("じゅうなん", "ノーマル", "", "とびだすなかみ", @model.Weather::None)
  @debug.assert_eq(herb.length(), 1)
  // きよめのしおは ほうしの 3 分岐を全部止める。
  let salt = simm_contact("きよめのしお", "ノーマル", "ほうし", "", @model.Weather::None)
  @debug.assert_eq(salt.length(), 1)
  // リーフガードははれのときだけほのおのからだを止める。
  let leaf_sun = simm_contact("リーフガード", "くさ", "ほのおのからだ", "", @model.Weather::Sun)
  @debug.assert_eq(leaf_sun.length(), 1)
  let leaf_clear = simm_contact(
    "リーフガード",
    "くさ",
    "ほのおのからだ",
    "",
    @model.Weather::None,
  )
  assert_true(
    simm_close(
      simm_contact_mass(leaf_clear, fn(s) { s == @model.Burn }),
      0.3,
    ),
  )
  // フラワーベールはくさだけ。
  let veil = simm_contact("フラワーベール", "くさ", "せいでんき", "", @model.Weather::None)
  @debug.assert_eq(veil.length(), 1)
  let veil_off = simm_contact(
    "フラワーベール",
    "ノーマル",
    "せいでんき",
    "",
    @model.Weather::None,
  )
  assert_true(
    simm_close(
      simm_contact_mass(veil_off, fn(s) { s == @model.Paralyze }),
      0.3,
    ),
  )
  // じゅうなんは ほうしのまひだけを落とし、どくとねむりは残す。
  let spore = simm_contact("じゅうなん", "ノーマル", "ほうし", "", @model.Weather::None)
  assert_true(
    simm_close(
      simm_contact_mass(spore, fn(s) { s == @model.Paralyze }),
      0.0,
    ),
  )
  assert_true(simm_contact_mass(spore, fn(s) { s == @model.Poison }) > 0.0)
  assert_true(simm_contact_mass(spore, fn(s) { s == @model.Sleep(2) }) > 0.0)
}

///|
fn simm_pair(
  mv : @model.Move,
  ability : String,
  type1 : String,
  weather : @model.Weather,
) -> (Double, Double) {
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 50, 100, None)
  let atk = [ss_cmb(ss_pokemon("atk", "ノーマル", "", 200, 120), [mv], "")]
  let def = [ss_cmb(ss_pokemon("def", type1, "", 200, 60), [tackle], ability)]
  let dp = if weather == @model.Weather::None {
    switching_game_winrate(atk, def, 4)
  } else {
    let state = h1_state_from_weather_field(weather, @model.Field::None, atk, def)
    let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
    let stats = new_stats_with_progress(noop_progress, 0)
    value(state, atk, def, 4, cache, stats, new_damage_cache())
  }
  let mc = team_monte_carlo_value(atk, def, 8192, 20261113UL, turn_limit=4, weather~)
  (dp, mc)
}

///|
test "status immunity DP/MC parity: じゅうなん makes Thunder Wave a no-op (< 0.02)" {
  let wave = ss_move(
    "でんじは",
    "でんき",
    @model.Status,
    0,
    100,
    Some((@model.ParalyzeKind, 100)),
  )
  let (dp_open, mc_open) = simm_pair(wave, "", "ノーマル", @model.Weather::None)
  let (dp_limber, mc_limber) = simm_pair(wave, "じゅうなん", "ノーマル", @model.Weather::None)
  assert_true((dp_open - dp_limber).abs() > 0.005)
  assert_true((dp_open - mc_open).abs() < 0.02)
  assert_true((dp_limber - mc_limber).abs() < 0.02)
}

///|
test "status immunity DP/MC parity: すいほう makes a 30% burn secondary a no-op (< 0.02)" {
  let burn = ss_move(
    "かえんほうしゃ",
    "ほのお",
    @model.Special,
    50,
    100,
    Some((@model.BurnKind, 30)),
  )
  let plain = ss_move("かえんほうしゃ", "ほのお", @model.Special, 50, 100, None)
  let (dp_burn, mc_burn) = simm_pair(burn, "すいほう", "みず", @model.Weather::None)
  let (dp_plain, mc_plain) = simm_pair(plain, "すいほう", "みず", @model.Weather::None)
  let (dp_open, _) = simm_pair(burn, "", "みず", @model.Weather::None)
  assert_true((dp_burn - dp_plain).abs() < 1.0e-9)
  assert_true((dp_open - dp_burn).abs() > 0.005)
  assert_true((dp_burn - mc_burn).abs() < 0.02)
  assert_true((dp_plain - mc_plain).abs() < 0.02)
}

///|
test "status immunity DP/MC parity: リーフガード blocks 30% burn only in sun (< 0.02)" {
  let burn = ss_move(
    "かえんほうしゃ",
    "ほのお",
    @model.Special,
    50,
    100,
    Some((@model.BurnKind, 30)),
  )
  let plain = ss_move("かえんほうしゃ", "ほのお", @model.Special, 50, 100, None)
  // リーフガードはタイプを見ない。相手をノーマルにしてほのおが等倍になり、
  // はれ以外では 30% やけどが値を動かす (くさだと抜群で差が潰れる)。
  let (dp_sun, mc_sun) = simm_pair(burn, "リーフガード", "ノーマル", @model.Weather::Sun)
  let (dp_sun_plain, mc_sun_plain) = simm_pair(
    plain,
    "リーフガード",
    "ノーマル",
    @model.Weather::Sun,
  )
  let (dp_clear, mc_clear) = simm_pair(burn, "リーフガード", "ノーマル", @model.Weather::None)
  let (dp_clear_plain, _) = simm_pair(plain, "リーフガード", "ノーマル", @model.Weather::None)
  assert_true((dp_sun - dp_sun_plain).abs() < 1.0e-9)
  assert_true((dp_clear - dp_clear_plain).abs() > 0.005)
  assert_true((dp_sun - mc_sun).abs() < 0.02)
  assert_true((dp_sun_plain - mc_sun_plain).abs() < 0.02)
  assert_true((dp_clear - mc_clear).abs() < 0.02)
}
