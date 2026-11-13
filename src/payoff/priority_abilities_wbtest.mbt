///|
/// いたずらごころ / はやてのつばさ。ヒーリングシフトは本文が無いので補正しない。
/// 行動順・はやてがえし・サイコフィールドは実効優先度。fresh ゲートは変えない。

///|
fn pab_gap(a : Double, b : Double) -> Double {
  let d = a - b
  if d < 0.0 { 0.0 - d } else { d }
}

///|
fn pab_status(
  name : String,
  type_ : String,
  priority : Int,
) -> @model.Move {
  { ..flch_move(name, type_, @model.Status, 0, 100, 0), priority }
}

///|
fn pab_wowisp() -> @model.Move {
  {
    ..pab_status("おにび", "ほのお", 0),
    status_effect: Some((@model.BurnKind, 100)),
  }
}

///|
fn pab_flying(power : Int) -> @model.Move {
  flch_move("エアスラッシュ", "ひこう", @model.Physical, power, 100, 0)
}

///|
fn pab_side(
  name : String,
  type1 : String,
  hp : Int,
  spe : Int,
  mv : @model.Move,
  ability : String,
) -> Array[Combatant] {
  [flch_cmb(flch_pokemon(name, type1, hp, spe), [mv], ability)]
}

///|
test "ability priority: prankster status +1, gale wings flying at full HP +1" {
  let status = pab_status("でんじは", "でんき", 0)
  let trick = pab_status("トリックルーム", "エスパー", -7)
  let protect = pab_status("まもる", "ノーマル", 4)
  let tackle = flch_tackle()
  let flying = pab_flying(80)
  assert_true(ability_priority_bonus("いたずらごころ", status, 10, 100) == 1)
  assert_true(effective_priority("いたずらごころ", trick, 100, 100) == -6)
  assert_true(effective_priority("いたずらごころ", protect, 100, 100) == 5)
  assert_true(ability_priority_bonus("いたずらごころ", tackle, 100, 100) == 0)
  assert_true(ability_priority_bonus("はやてのつばさ", flying, 100, 100) == 1)
  assert_true(ability_priority_bonus("はやてのつばさ", flying, 99, 100) == 0)
  assert_true(ability_priority_bonus("はやてのつばさ", flying, 0, 0) == 0)
  assert_true(ability_priority_bonus("はやてのつばさ", tackle, 100, 100) == 0)
  // ひこうの変化技も本文どおり +1。HP は見ないのはいたずらごころだけ。
  let roost = pab_status("はねやすめ", "ひこう", 0)
  assert_true(ability_priority_bonus("はやてのつばさ", roost, 100, 100) == 1)
  assert_true(ability_priority_bonus("いたずらごころ", roost, 50, 100) == 1)
  // ヒーリングシフトは Champions に本文が無い。heal フラグ +3 は足さない。
  assert_true(ability_priority_bonus("ヒーリングシフト", roost, 100, 100) == 0)
  assert_true(ability_priority_bonus("", status, 100, 100) == 0)
}

///|
test "upper hand sees ability-modified priority, including a prankster status move" {
  let uh = {
    ..flch_move("はやてがえし", "かくとう", @model.Physical, 65, 100, 100),
    priority: 3,
  }
  let wave = pab_status("でんじは", "でんき", 0)
  let flying = pab_flying(40)
  let tackle = flch_tackle()
  // 省略時は base priority のまま (既存フィクスチャと同じ)。
  assert_true(upper_hand_fails(uh, Some(wave)))
  assert_true(!upper_hand_fails(uh, Some(uh_at("でんこうせっか", 1))))
  // いたずらごころの変化技は実効 +1。Showdown は Status で失敗させるが、本文は切らない。
  assert_true(
    !upper_hand_fails(uh, Some(wave), foe_ability="いたずらごころ", foe_hp=100, foe_max_hp=100),
  )
  assert_true(
    upper_hand_fails(
      uh,
      Some(pab_status("トリックルーム", "エスパー", -7)),
      foe_ability="いたずらごころ",
      foe_hp=100,
      foe_max_hp=100,
    ),
  )
  // ダメージ技はいたずらごころでは先制にならない。
  assert_true(
    upper_hand_fails(uh, Some(tackle), foe_ability="いたずらごころ", foe_hp=100, foe_max_hp=100),
  )
  assert_true(
    !upper_hand_fails(
      uh, Some(flying), foe_ability="はやてのつばさ", foe_hp=80, foe_max_hp=80,
    ),
  )
  assert_true(
    upper_hand_fails(
      uh, Some(flying), foe_ability="はやてのつばさ", foe_hp=79, foe_max_hp=80,
    ),
  )
  assert_true(
    upper_hand_fails(
      uh, Some(tackle), foe_ability="はやてのつばさ", foe_hp=80, foe_max_hp=80,
    ),
  )
  // ひこう変化技も満タンなら先制。Status 除外は入れない。
  let roost = pab_status("はねやすめ", "ひこう", 0)
  assert_true(
    !upper_hand_fails(
      uh, Some(roost), foe_ability="はやてのつばさ", foe_hp=80, foe_max_hp=80,
    ),
  )
}

///|
test "prankster status fails on dark only when the move hits that foe" {
  let wow = pab_wowisp()
  let charm = {
    ..pab_status("あまえる", "フェアリー", 0),
    stat_effects: [@model.StatEffect::{ stat: 0, delta: -2, target: 1 }],
  }
  let dance = {
    ..pab_status("つるぎのまい", "ノーマル", 0),
    stat_effects: [@model.StatEffect::{ stat: 0, delta: 2, target: 0 }],
  }
  let seed = {
    ..pab_status("やどりぎのタネ", "くさ", 0),
    healing: Some(@model.LeechSeed),
  }
  let rain = {
    ..pab_status("あまごい", "みず", 0),
    weather_set: Some(@model.Weather::Rain),
  }
  let prank = flch_cmb(flch_pokemon("p", "ノーマル", 100, 100), [wow], "いたずらごころ")
  let dark = flch_cmb(flch_pokemon("d", "あく", 100, 100), [flch_tackle()], "")
  let dual = flch_cmb(
    { ..flch_pokemon("d2", "ゴースト", 100, 100), type2: "あく" },
    [flch_tackle()],
    "",
  )
  let normal = flch_cmb(flch_pokemon("n", "ノーマル", 100, 100), [flch_tackle()], "")
  let plain = flch_cmb(flch_pokemon("x", "ノーマル", 100, 100), [wow], "")
  assert_true(prankster_status_blocked(prank, false, wow, dark, false, ""))
  assert_true(prankster_status_blocked(prank, false, charm, dark, false, ""))
  assert_true(prankster_status_blocked(prank, false, seed, dual, false, ""))
  assert_true(!prankster_status_blocked(prank, false, dance, dark, false, ""))
  assert_true(!prankster_status_blocked(prank, false, rain, dark, false, ""))
  assert_true(!prankster_status_blocked(prank, false, wow, normal, false, ""))
  assert_true(!prankster_status_blocked(prank, false, flch_tackle(), dark, false, ""))
  assert_true(!prankster_status_blocked(plain, false, wow, dark, false, ""))
  // へんげんじざいで あく になった相手も本文のあくタイプ。
  assert_true(prankster_status_blocked(prank, false, wow, normal, false, "あく"))
}

///|
test "slow prankster Will-O-Wisp burns before the faster physical move" {
  let my_team = pab_side("slow", "ノーマル", 200, 60, pab_wowisp(), "いたずらごころ")
  let heavy = flch_move("じしん", "じめん", @model.Physical, 100, 100, 0)
  let opp_team = pab_side("fast", "ノーマル", 200, 120, heavy, "")
  let normal = compute_mean_damage(opp_team[0], my_team[0], heavy, 0, 0)
  let halved = compute_mean_damage(opp_team[0], my_team[0], heavy, 0, 0, atk_burn=true)
  assert_true(normal > halved)
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_status[0] == @model.Burn }), 1.0))
  assert_true(flch_close(flch_mass(outs, fn(s) { 200 - s.my_hps[0] == halved }), 1.0))
  // 特性が無いと同じ技順なら、やけどは後から付き、このターンの物理は満額。
  let plain = pab_side("slow", "ノーマル", 200, 60, pab_wowisp(), "")
  let plain_outs = flch_turn(
    flch_state(200, 200, @model.None, @model.None),
    plain,
    opp_team,
  )
  assert_true(flch_close(flch_mass(plain_outs, fn(s) { 200 - s.my_hps[0] == normal }), 1.0))
}

///|
test "prankster Will-O-Wisp does not burn a dark target, and swords dance still works" {
  let my_team = pab_side("slow", "ノーマル", 200, 60, pab_wowisp(), "いたずらごころ")
  let heavy = flch_move("じしん", "じめん", @model.Physical, 80, 100, 0)
  let dark = pab_side("fast", "あく", 200, 120, heavy, "")
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, dark)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_status[0] == @model.None }), 1.0))
  let full = compute_mean_damage(dark[0], my_team[0], heavy, 0, 0)
  assert_true(flch_close(flch_mass(outs, fn(s) { 200 - s.my_hps[0] == full }), 1.0))
  let dance = {
    ..pab_status("つるぎのまい", "ノーマル", 0),
    stat_effects: [@model.StatEffect::{ stat: 0, delta: 2, target: 0 }],
  }
  let dancer = pab_side("d", "ノーマル", 200, 60, dance, "いたずらごころ")
  let dance_outs = flch_turn(
    flch_state(200, 200, @model.None, @model.None),
    dancer,
    dark,
  )
  assert_true(flch_close(flch_mass(dance_outs, fn(s) { s.my_ranks[0] == 2 }), 1.0))
}

///|
test "gale wings at full HP moves before a faster foe; not when HP is missing or the move is not flying" {
  let fly = pab_flying(250)
  let mine = pab_side("slow", "ひこう", 40, 40, fly, "はやてのつばさ")
  // じめん技はひこうに当たらない。ノーマル威力 250 なら HP 40 を確定で落とす。
  let foe = pab_side(
    "fast",
    "ノーマル",
    1,
    200,
    flch_move("のしかかり", "ノーマル", @model.Physical, 250, 100, 0),
    "",
  )
  let full = flch_turn(flch_state(40, 1, @model.None, @model.None), mine, foe)
  assert_true(flch_close(flch_mass(full, fn(s) { s.opp_hps[0] == 0 && s.my_hps[0] == 40 }), 1.0))
  let chipped = flch_turn(flch_state(39, 1, @model.None, @model.None), mine, foe)
  assert_true(flch_close(flch_mass(chipped, fn(s) { s.my_hps[0] == 0 && s.opp_hps[0] == 1 }), 1.0))
  let normal_mv = flch_move("たいあたり", "ノーマル", @model.Physical, 250, 100, 0)
  let normal_user = pab_side("slow", "ひこう", 40, 40, normal_mv, "はやてのつばさ")
  let no_fly = flch_turn(flch_state(40, 1, @model.None, @model.None), normal_user, foe)
  assert_true(flch_close(flch_mass(no_fly, fn(s) { s.my_hps[0] == 0 && s.opp_hps[0] == 1 }), 1.0))
  // ダメージ技にいたずらごころは乗らない。同じ対面は先に倒される。
  let prank = pab_side("slow", "ひこう", 40, 40, fly, "いたずらごころ")
  let prank_outs = flch_turn(flch_state(40, 1, @model.None, @model.None), prank, foe)
  assert_true(
    flch_close(flch_mass(prank_outs, fn(s) { s.my_hps[0] == 0 && s.opp_hps[0] == 1 }), 1.0),
  )
}

///|
test "upper hand connects on prankster status and full-HP gale wings, and fails otherwise" {
  let uh = {
    ..flch_move("はやてがえし", "かくとう", @model.Physical, 65, 100, 100),
    priority: 3,
  }
  let mine = pab_side("me", "かくとう", 200, 50, uh, "")
  let wave_user = pab_side("foe", "でんき", 200, 180, pab_wowisp(), "いたずらごころ")
  let hit = flch_turn(flch_state(200, 200, @model.None, @model.None), mine, wave_user)
  assert_true(flch_close(flch_mass(hit, fn(s) { s.opp_hps[0] < 200 && s.my_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(hit, fn(s) { s.my_status[0] == @model.None }), 1.0))
  let plain = pab_side("foe", "でんき", 200, 180, pab_wowisp(), "")
  let miss = flch_turn(flch_state(200, 200, @model.None, @model.None), mine, plain)
  assert_true(flch_close(flch_mass(miss, fn(s) { s.opp_hps[0] == 200 }), 1.0))
  assert_true(flch_close(flch_mass(miss, fn(s) { s.my_status[0] == @model.Burn }), 1.0))
  let bird = pab_side("foe", "ひこう", 200, 180, pab_flying(40), "はやてのつばさ")
  let gw = flch_turn(flch_state(200, 200, @model.None, @model.None), mine, bird)
  assert_true(flch_close(flch_mass(gw, fn(s) { s.opp_hps[0] < 200 && s.my_hps[0] == 200 }), 1.0))
  let gw_low = flch_turn(flch_state(200, 199, @model.None, @model.None), mine, bird)
  assert_true(flch_close(flch_mass(gw_low, fn(s) { s.opp_hps[0] == 199 && s.my_hps[0] < 200 }), 1.0))
}

///|
test "psychic terrain blocks ability-boosted priority and still allows unboosted priority 0" {
  let my_team = pab_side("p", "ノーマル", 200, 80, pab_wowisp(), "いたずらごころ")
  let grounded = pab_side("g", "ノーマル", 200, 80, flch_tackle(), "")
  let psychic = {
    ..flch_state(200, 200, @model.None, @model.None),
    field: @model.Field::Psychic,
  }
  let blocked = flch_turn(psychic, my_team, grounded)
  assert_true(flch_close(flch_mass(blocked, fn(s) { s.opp_status[0] == @model.None }), 1.0))
  let open = flch_turn(flch_state(200, 200, @model.None, @model.None), my_team, grounded)
  assert_true(flch_close(flch_mass(open, fn(s) { s.opp_status[0] == @model.Burn }), 1.0))
  let flyer = pab_side("f", "ひこう", 200, 80, flch_tackle(), "")
  let air = flch_turn(psychic, my_team, flyer)
  assert_true(flch_close(flch_mass(air, fn(s) { s.opp_status[0] == @model.Burn }), 1.0))
  // 特性が無い priority 0 のひこう技は、サイコフィールドでも止まらない。
  let plain_fly = pab_side("a", "ひこう", 200, 120, pab_flying(80), "")
  let slow = pab_side("b", "ノーマル", 200, 40, flch_tackle(), "")
  let still = flch_turn(psychic, plain_fly, slow)
  assert_true(flch_close(flch_mass(still, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  // 満タンのはやてのつばさは実効 +1 なので地上相手には止まる。HP が減ると通る。
  let gw = pab_side("a", "ひこう", 200, 120, pab_flying(80), "はやてのつばさ")
  let gw_block = flch_turn(psychic, gw, slow)
  assert_true(flch_close(flch_mass(gw_block, fn(s) { s.opp_hps[0] == 200 }), 1.0))
  let gw_open = flch_turn(
    { ..psychic, my_hps: [199] },
    gw,
    slow,
  )
  assert_true(flch_close(flch_mass(gw_open, fn(s) { s.opp_hps[0] < 200 }), 1.0))
  // 既存のサイコフィールドは自分対象も priority>0 なら止める。つるぎのまいは実効 +1 で乗らない。
  let dance = {
    ..pab_status("つるぎのまい", "ノーマル", 0),
    stat_effects: [@model.StatEffect::{ stat: 0, delta: 2, target: 0 }],
  }
  let dancer = pab_side("d", "ノーマル", 200, 80, dance, "いたずらごころ")
  let dance_block = flch_turn(psychic, dancer, grounded)
  assert_true(flch_close(flch_mass(dance_block, fn(s) { s.my_ranks[0] == 0 }), 1.0))
  let dance_open = flch_turn(flch_state(200, 200, @model.None, @model.None), dancer, grounded)
  assert_true(flch_close(flch_mass(dance_open, fn(s) { s.my_ranks[0] == 2 }), 1.0))
}

///|
test "fake out fresh gate is unchanged by prankster" {
  let fo = {
    ..flch_move("ねこだまし", "ノーマル", @model.Physical, 40, 100, 100),
    priority: 3,
  }
  let mine = pab_side("me", "ノーマル", 200, 40, fo, "いたずらごころ")
  let foe = pab_side("foe", "ノーマル", 200, 180, flch_tackle(), "")
  let stale = {
    ..flch_state(200, 200, @model.None, @model.None),
    my_fresh: Some(false),
  }
  let outs = flch_turn(stale, mine, foe)
  assert_true(flch_close(flch_mass(outs, fn(s) { s.opp_hps[0] == 200 && s.my_hps[0] < 200 }), 1.0))
  let fresh = { ..stale, my_fresh: Some(true) }
  let first = flch_turn(fresh, mine, foe)
  assert_true(flch_close(flch_mass(first, fn(s) { s.opp_hps[0] < 200 && s.my_hps[0] == 200 }), 1.0))
}

///|
test "pick_best_move skips gale wings flying under psychic only at full HP" {
  let flying = pab_flying(120)
  let normal = flch_move("たいあたり", "ノーマル", @model.Physical, 40, 100, 0)
  let atk = flch_cmb(
    flch_pokemon("t", "ひこう", 200, 100),
    [flying, normal],
    "はやてのつばさ",
  )
  let dfn = flch_cmb(flch_pokemon("g", "ノーマル", 200, 80), [normal], "")
  match pick_best_move(
    atk, dfn, field=@model.Field::Psychic, atk_hp=200, atk_max_hp=200,
  ) {
    Some(i) => assert_true(i == 1)
    None => assert_true(false)
  }
  match pick_best_move(
    atk, dfn, field=@model.Field::Psychic, atk_hp=199, atk_max_hp=200,
  ) {
    Some(i) => assert_true(i == 0)
    None => assert_true(false)
  }
  match pick_best_move(atk, dfn, field=@model.Field::None, atk_hp=200, atk_max_hp=200) {
    Some(i) => assert_true(i == 0)
    None => assert_true(false)
  }
  let plain = flch_cmb(flch_pokemon("t", "ひこう", 200, 100), [flying, normal], "")
  match pick_best_move(
    plain, dfn, field=@model.Field::Psychic, atk_hp=200, atk_max_hp=200,
  ) {
    Some(i) => assert_true(i == 0)
    None => assert_true(false)
  }
}

///|
fn pab_value(my : Array[Combatant], opp : Array[Combatant]) -> (Double, Double) {
  let dp = switching_game_winrate(my, opp, 1)
  let mc = team_monte_carlo_value(my, opp, 32, 20261112UL, turn_limit=1)
  (dp, mc)
}

///|
test "DP and MC agree on gale wings priority and on moves it does not boost" {
  let fly = pab_flying(250)
  let foe_mv = flch_move("のしかかり", "ノーマル", @model.Physical, 250, 100, 0)
  let gw = pab_side("slow", "ひこう", 20, 40, fly, "はやてのつばさ")
  let plain = pab_side("slow", "ひこう", 20, 40, fly, "")
  let normal_user = pab_side(
    "slow",
    "ひこう",
    20,
    40,
    flch_move("たいあたり", "ノーマル", @model.Physical, 250, 100, 0),
    "はやてのつばさ",
  )
  let foe = pab_side("fast", "ノーマル", 1, 200, foe_mv, "")
  let (dp_gw, mc_gw) = pab_value(gw, foe)
  let (dp_plain, mc_plain) = pab_value(plain, foe)
  let (dp_norm, mc_norm) = pab_value(normal_user, foe)
  assert_true(pab_gap(dp_gw, mc_gw) < 0.03)
  assert_true(pab_gap(dp_plain, mc_plain) < 0.03)
  assert_true(pab_gap(dp_norm, mc_norm) < 0.03)
  assert_true(dp_gw > 0.5)
  assert_true(dp_plain < -0.5)
  assert_true(dp_norm < -0.5)
  assert_true(pab_gap(dp_norm, dp_plain) < 0.03)
}
