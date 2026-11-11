///|
/// Champions の こおり 規則の MC 側と DP / MC の parity (switching_game_freeze_wbtest.mbt と対)。
/// - 分布: `mc_resolve_attempt` を seed 固定で大量に回し、凍結の 1 / 2 回目は 25% で解凍、
///   3 回目は確定解凍 (DP `per_side_attempt` と同じ枝)。
/// - 規則の真理値表: 解凍技 (defrost) / 凍結の行動時抽選 (`mc_freeze_deferred`) /
///   炎の命中での解凍 / thawsTarget の解凍 / 付与ブロック (はれ / マグマのよろい / りんぷん)。
/// - parity: 1v1 (Ice Beam vs たいあたり) で DP (`switching_game_winrate`, exact) と MC
///   (`team_monte_carlo_value`, rollout 平均) が許容誤差内で一致する。
/// - 感度ガード: 凍結させない対照 (nop) との差が閾値より大きいことを先に確認する。

///|
fn frzm_move(
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
fn frzm_pokemon(name : String, type1 : String, hp : Int, spe : Int) -> @model.Pokemon {
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
fn frzm_cmb(
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
test "mc frz: Freeze(2) thaws-and-acts on ~1/4 of seeded tries, the stuck try is Freeze(1)" {
  let rng = seeded_rng(20261112UL)
  let n = 30000
  let mut acted = 0
  let mut stuck = 0
  for _i in 0..<n {
    let (st, acts, missed) = mc_resolve_attempt(@model.Freeze(2), 100, rng)
    assert_false(missed)
    if acts {
      acted += 1
      @debug.assert_eq(st, @model.None)
    } else {
      @debug.assert_eq(st, @model.Freeze(1))
      stuck += 1
    }
  }
  let p = acted.to_double() / n.to_double()
  assert_true((p - 0.25).abs() < 0.01)
  @debug.assert_eq(acted + stuck, n)
}

///|
test "mc frz: Freeze(0) always acts and cures; Freeze(0) acc=85 wakes split 0.85 / miss 0.15" {
  let rng = seeded_rng(20261113UL)
  let n = 30000
  let mut acted = 0
  let mut missed_n = 0
  for _i in 0..<n {
    let (st, acts, missed) = mc_resolve_attempt(@model.Freeze(0), 85, rng)
    @debug.assert_eq(st, @model.None)
    if acts {
      acted += 1
    }
    if missed {
      missed_n += 1
      assert_false(acts)
    }
  }
  let nf = n.to_double()
  assert_true((acted.to_double() / nf - 0.85).abs() < 0.01)
  assert_true((missed_n.to_double() / nf - 0.15).abs() < 0.01)
}

///|
test "mc frz: defrost user (thaws_user) is cured before the move, hit or miss" {
  let rng = seeded_rng(20261114UL)
  for _i in 0..<200 {
    let (st, _acts, _missed) = mc_resolve_attempt(
      @model.Freeze(2),
      85,
      rng,
      thaws_user=true,
    )
    @debug.assert_eq(st, @model.None)
  }
}

///|
test "mc frz: mc_move_thaws_user lists the defrost moves and Burn Up is Fire-user only" {
  let fire_user = frzm_cmb(frzm_pokemon("fire", "ほのお", 200, 60), [], "")
  let normal_user = frzm_cmb(frzm_pokemon("normal", "ノーマル", 200, 60), [], "")
  let flare = frzm_move("フレアドライブ", "ほのお", @model.Physical, 120, 100, None)
  let burn_up = frzm_move("もえつきる", "ほのお", @model.Special, 130, 100, None)
  let tackle = frzm_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  assert_true(mc_move_thaws_user(normal_user, flare))
  assert_true(mc_move_thaws_user(fire_user, burn_up))
  assert_false(mc_move_thaws_user(normal_user, burn_up))
  assert_false(mc_move_thaws_user(normal_user, tackle))
}

///|
test "mc frz: mc_freeze_deferred truth table" {
  assert_false(mc_freeze_deferred(@model.Freeze(2), true, false, true))
  assert_false(mc_freeze_deferred(@model.Freeze(2), false, true, true))
  assert_true(mc_freeze_deferred(@model.Freeze(2), false, false, false))
  assert_true(mc_freeze_deferred(@model.None, false, false, true))
  assert_false(mc_freeze_deferred(@model.None, false, false, false))
  assert_false(mc_freeze_deferred(@model.Burn, false, false, true))
}

///|
test "mc frz: mc_try_apply_status blocks ice / sun / Magma Armor / Shield Dust, applies otherwise" {
  let rng = seeded_rng(20261115UL)
  let ice_beam = frzm_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    90,
    100,
    Some((@model.FreezeKind, 100)),
  )
  let plain = [frzm_cmb(frzm_pokemon("plain", "ノーマル", 200, 60), [], "")]
  let ice = [frzm_cmb(frzm_pokemon("ice", "こおり", 200, 60), [], "")]
  let magma = [frzm_cmb(frzm_pokemon("magma", "ほのお", 200, 60), [], "マグマのよろい")]
  let shed = [frzm_cmb(frzm_pokemon("shed", "ノーマル", 200, 60), [], "りんぷん")]
  // 対象ごとに新しい status 配列で試す (chance 100 なので適用されれば必ず凍る)。
  let mut st : Array[@model.StatusCondition] = [@model.StatusCondition::None]
  mc_try_apply_status(rng, ice_beam, plain, [200], st, 0)
  @debug.assert_eq(st[0], @model.Freeze(2))
  st = [@model.StatusCondition::None]
  mc_try_apply_status(rng, ice_beam, ice, [200], st, 0)
  @debug.assert_eq(st[0], @model.None)
  st = [@model.StatusCondition::None]
  mc_try_apply_status(rng, ice_beam, plain, [200], st, 0, weather=@model.Weather::Sun)
  @debug.assert_eq(st[0], @model.None)
  st = [@model.StatusCondition::None]
  mc_try_apply_status(rng, ice_beam, magma, [200], st, 0)
  @debug.assert_eq(st[0], @model.None)
  st = [@model.StatusCondition::None]
  mc_try_apply_status(rng, ice_beam, shed, [200], st, 0)
  @debug.assert_eq(st[0], @model.None)
}

///|
test "mc frz: a Fire damaging hit thaws only when it deals damage; Fire status and dealt=false do not" {
  let fire = frzm_move("テスト炎技", "ほのお", @model.Physical, 90, 100, None)
  let fire_status = frzm_move("テスト炎変化", "ほのお", @model.Status, 0, 100, None)
  let water = frzm_move("テスト水技", "みず", @model.Special, 90, 100, None)
  let st1 : Array[@model.StatusCondition] = [@model.Freeze(2)]
  mc_thaw_on_fire_hit(st1, 0, fire, @model.Weather::None, "", true)
  @debug.assert_eq(st1[0], @model.None)
  let st2 = [@model.Freeze(2)]
  mc_thaw_on_fire_hit(st2, 0, fire, @model.Weather::None, "", false)
  @debug.assert_eq(st2[0], @model.Freeze(2))
  let st3 = [@model.Freeze(2)]
  mc_thaw_on_fire_hit(st3, 0, fire_status, @model.Weather::None, "", true)
  @debug.assert_eq(st3[0], @model.Freeze(2))
  let st4 = [@model.Freeze(2)]
  mc_thaw_on_fire_hit(st4, 0, water, @model.Weather::None, "", true)
  @debug.assert_eq(st4[0], @model.Freeze(2))
}

///|
test "mc frz: thawsTarget (Scald) thaws a dealt hit only" {
  let scald = frzm_move("ねっとう", "みず", @model.Special, 80, 100, None)
  let st1 = [@model.Freeze(1)]
  mc_thaw_target_after_secondary(st1, 0, scald, true)
  @debug.assert_eq(st1[0], @model.None)
  let st2 = [@model.Freeze(1)]
  mc_thaw_target_after_secondary(st2, 0, scald, false)
  @debug.assert_eq(st2[0], @model.Freeze(1))
}

///|
/// 1v1 の parity fixture: 速い側が れいとうビーム (威力 40、10% 凍結)、遅い側が 威力 80 の
/// たいあたり。対照は同じ威力・命中の凍結なし技 (差は凍結の経路だけ)。値が飽和しない
/// (両者とも 0 / 1 に張り付かない) ように HP と威力を選んでいる。
test "freeze DP/MC parity: Ice Beam (10% freeze) against a slower Tackle target" {
  let ice_beam = frzm_move(
    "れいとうビーム",
    "こおり",
    @model.Special,
    40,
    100,
    Some((@model.FreezeKind, 10)),
  )
  let no_freeze = frzm_move("れいとうビーム", "こおり", @model.Special, 40, 100, None)
  let tackle = frzm_move("たいあたり", "ノーマル", @model.Physical, 80, 100, None)
  let target = [frzm_cmb(frzm_pokemon("target", "ノーマル", 200, 60), [tackle], "")]
  let freezer = [frzm_cmb(frzm_pokemon("ice", "ノーマル", 200, 120), [ice_beam], "")]
  let control = [frzm_cmb(frzm_pokemon("control", "ノーマル", 200, 120), [no_freeze], "")]
  let dp_freeze = switching_game_winrate(freezer, target, 4)
  let dp_control = switching_game_winrate(control, target, 4)
  let mc_freeze = team_monte_carlo_value(freezer, target, 8192, 20261110UL, turn_limit=4)
  let mc_control = team_monte_carlo_value(control, target, 8192, 20261110UL, turn_limit=4)
  // 感度ガード: 凍結の経路が値に効いている (対照との差が閾値より大きい)。
  assert_true((dp_freeze - dp_control).abs() > 0.005)
  assert_true((dp_freeze - mc_freeze).abs() < 0.02)
  assert_true((dp_control - mc_control).abs() < 0.02)
}
