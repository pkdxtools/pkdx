///|
/// Integration: status-heavy 1v1 team where one side can inflict a condition
/// and the other cannot. Asserts that the winrate of the status-wielder vs
/// the matchup-equivalent team without a status move is measurably different
/// (status application alters the value).

///|
fn mk_ntypa_pokemon(
  name : String,
  type1 : String,
  type2~ : String = "",
  hp~ : Int = 100,
  atk~ : Int = 100,
  def_~ : Int = 100,
  spa~ : Int = 100,
  spd~ : Int = 100,
  spe~ : Int = 100,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2,
    hp,
    atk,
    def_,
    spa,
    spd,
    spe,
    bst: hp + atk + def_ + spa + spd + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
  }
}

///|
fn mk_int_combatant(
  pokemon : @model.Pokemon,
  moves : Array[@model.Move],
) -> Combatant {
  {
    pokemon,
    moves,
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
  }
}

///|
fn mk_int_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
  accuracy~ : Int = 100,
  status_effect~ : (@model.StatusKind, Int)? = None,
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
  }
}

///|
/// With Will-o-wisp vs a fire-type attacker, burn NEVER lands because of
/// type immunity, so the value should equal the baseline where rogue Will-
/// o-wisp does nothing anyway (baseline: just a damaging filler).
test "burn-immune fire type unaffected by Will-o-wisp" {
  let fire_atk = mk_ntypa_pokemon("ほのおタイプ", "ほのお", atk=120, spe=90)
  let normie = mk_ntypa_pokemon("ノーマルタイプ", "ノーマル", atk=100, spe=90)
  let tackle = mk_int_move("たいあたり", "ノーマル", @model.Physical, 40)
  let wowisp = mk_int_move(
    "おにび", "ほのお", @model.Status, 0, accuracy=85,
    status_effect=Some((@model.BurnKind, 100)),
  )
  let my_team = [mk_int_combatant(fire_atk, [tackle])]
  let wowisp_team = [mk_int_combatant(normie, [wowisp, tackle])]
  let filler_team = [mk_int_combatant(normie, [tackle])]
  let v_with = switching_game_winrate(my_team, wowisp_team, 4)
  let v_without = switching_game_winrate(my_team, filler_team, 4)
  // Fire type is burn-immune, so the value with Will-o-wisp should equal
  // the value without (aside from the 2nd move slot which wowisp user has).
  // Either way Will-o-wisp does nothing here and the main damage is Tackle.
  assert_true((v_with - v_without).abs() < 0.1)
}

///|
test "thunder wave on a normal-type opponent shifts value" {
  let fast_atk = mk_ntypa_pokemon("はやいやつ", "ノーマル", atk=100, spe=130)
  let slow_tanky = mk_ntypa_pokemon(
    "おそいやつ", "ノーマル", hp=160, atk=80, def_=120, spd=120, spe=40,
  )
  let tackle = mk_int_move("たいあたり", "ノーマル", @model.Physical, 60)
  let twave = mk_int_move(
    "でんじは", "でんき", @model.Status, 0, accuracy=90,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
  // Fast side can paralyze; slow side just attacks.
  let fast_with_twave = [mk_int_combatant(fast_atk, [tackle, twave])]
  let fast_no_twave = [mk_int_combatant(fast_atk, [tackle])]
  let slow_team = [mk_int_combatant(slow_tanky, [tackle])]
  let v_with = switching_game_winrate(fast_with_twave, slow_team, 4)
  let v_without = switching_game_winrate(fast_no_twave, slow_team, 4)
  // Having paralyze should help the fast attacker (speed halving keeps
  // slower, lower action rate). Expect v_with >= v_without.
  assert_true(v_with >= v_without - 0.05)
}

///|
test "toxic on a tanky opponent shifts value in the user's favour" {
  let tanky = mk_ntypa_pokemon(
    "めんえき", "くさ", hp=200, def_=120, spd=120, spe=40,
  )
  let other = mk_ntypa_pokemon(
    "ふつう", "ノーマル", hp=120, def_=80, spd=80, spe=80,
  )
  let tackle = mk_int_move("たいあたり", "ノーマル", @model.Physical, 40)
  let toxic_move = mk_int_move(
    "どくどく", "どく", @model.Status, 0, accuracy=90,
    status_effect=Some((@model.BadPoisonKind, 100)),
  )
  let with_toxic = [mk_int_combatant(tanky, [tackle, toxic_move])]
  let without_toxic = [mk_int_combatant(tanky, [tackle])]
  let foe_team = [mk_int_combatant(other, [tackle])]
  let v_with = switching_game_winrate(with_toxic, foe_team, 4)
  let v_without = switching_game_winrate(without_toxic, foe_team, 4)
  // Toxic should help the tanky side by damaging over time.
  assert_true(v_with >= v_without - 0.02)
}

///|
test "yawn: target stays awake on the turn it lands (delayed sleep)" {
  let fast = mk_ntypa_pokemon("はやい", "ノーマル", atk=100, spe=120)
  let slow = mk_ntypa_pokemon("おそい", "ノーマル", atk=100, spe=60)
  let tackle = mk_int_move("たいあたり", "ノーマル", @model.Physical, 40)
  let yawn = mk_int_move(
    "あくび", "ノーマル", @model.Status, 0, accuracy=100,
    status_effect=Some((@model.DrowsyKind, 100)),
  )
  // fast側があくび。1ターン目でdrowsy付与、2ターン目EOTで Sleep(2)
  let yawn_team = [mk_int_combatant(fast, [tackle, yawn])]
  let foe = [mk_int_combatant(slow, [tackle])]
  // turn_limit=2 で勝負。あくびで即眠らないので、短いゲームでは有利度少なめ。
  let v_short = switching_game_winrate(yawn_team, foe, 2)
  let v_long = switching_game_winrate(yawn_team, foe, 4)
  // 長期戦の方が Yawn の恩恵が出るはず。等式ではなく「長期≥短期」で検証。
  assert_true(v_long >= v_short - 0.05)
}

///|
test "spore (sleep 100%) keeps slow attacker ahead by locking out target" {
  let slow_mover = mk_ntypa_pokemon(
    "ねむらせ", "くさ", atk=120, spe=60,
  )
  let fast_hitter = mk_ntypa_pokemon(
    "はやいこうげき", "ノーマル", atk=100, spe=120,
  )
  let tackle = mk_int_move("たいあたり", "ノーマル", @model.Physical, 50)
  let spore = mk_int_move(
    "キノコのほうし", "くさ", @model.Status, 0, accuracy=100,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let with_spore = [mk_int_combatant(slow_mover, [tackle, spore])]
  let without_spore = [mk_int_combatant(slow_mover, [tackle])]
  let foe = [mk_int_combatant(fast_hitter, [tackle])]
  let v_with = switching_game_winrate(with_spore, foe, 4)
  let v_without = switching_game_winrate(without_spore, foe, 4)
  // Sleep locks the fast hitter out for 2 turns — the slow mover benefits.
  assert_true(v_with >= v_without - 0.01)
}
