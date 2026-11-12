///|
/// Champions のひるみの MC 側と DP / MC の parity (switching_game_flinch_wbtest.mbt と対)。
/// - 真理値表: `mc_flinch_roll` のゲート (免疫 / HP 減少なし / 撃破 / ちからずく / せいしんりょく /
///   りんぷん / chance 0)。DP `maybe_apply_flinch_fanout` と同じ判定。
/// - 分布: seed 固定で `mc_flinch_roll` と `mc_resolve_pending_attempt` を大量に回し、ひるみの 30%、
///   凍結の 25% 解凍、眠り 1 回目の 1/3 目覚め (DP `flinched_outcomes` と同じ枝) を確認する。
/// - parity: 1v1 で DP (`switching_game_winrate`, exact) と MC (`team_monte_carlo_value`, rollout 平均)
///   が許容誤差内で一致する。感度ガード: ひるみを持たない対照 (flinch 0) との差が閾値より大きい。

///|
fn flchm_move(
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
fn flchm_pokemon(
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
fn flchm_cmb(
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
/// seed 固定の大量試行で、`hit` が真になった割合。
fn flchm_rate(seed : UInt64, trials : Int, hit : (@random.Rand) -> Bool) -> Double {
  let rng = seeded_rng(seed)
  let mut n = 0
  for _i = 0; _i < trials; _i = _i + 1 {
    if hit(rng) {
      n = n + 1
    }
  }
  n.to_double() / trials.to_double()
}

///|
fn flchm_close(a : Double, b : Double, tol : Double) -> Bool {
  (a - b).abs() < tol
}

///|
/// 真理値表: 命中して相手が生き、HP が減った先攻の技は、chance 100 でひるみ確率 1。
/// 各ゲートで 0 になることを確かめる (確率 1 の枝だけで判定できる)。
test "mc flinch roll truth table: gates block the flinch, a plain 100% hit always lands" {
  let bite = flchm_move("かみつく", "あく", @model.Physical, 60, 100, 100)
  let normal = flchm_pokemon("n", "ノーマル", 200, 60)
  let plain = flchm_cmb(normal, [bite], "")
  let focus = flchm_cmb(normal, [bite], "せいしんりょく")
  let shield = flchm_cmb(normal, [bite], "りんぷん")
  let rng = seeded_rng(20261112UL)
  // 通常: 100% 成立。
  assert_true(mc_flinch_roll(rng, bite, "", plain, 200, 170, false))
  // 免疫 (そうしょく / タイプ無効) / HP 減少なし / 撃破 は不成立。
  assert_false(mc_flinch_roll(rng, bite, "", plain, 200, 170, true))
  assert_false(mc_flinch_roll(rng, bite, "", plain, 200, 200, false))
  assert_false(mc_flinch_roll(rng, bite, "", plain, 200, 0, false))
  // ちからずく の攻撃側は追加効果を失う。
  assert_false(mc_flinch_roll(rng, bite, "ちからずく", plain, 200, 170, false))
  // せいしんりょく (ひるみ無効) / りんぷん (ダメージ技の追加効果を止める)。
  assert_false(mc_flinch_roll(rng, bite, "", focus, 200, 170, false))
  assert_false(mc_flinch_roll(rng, bite, "", shield, 200, 170, false))
  // chance 0 の技はひるまない。
  let no_flinch = flchm_move("たいあたり", "ノーマル", @model.Physical, 40, 100, 0)
  assert_false(mc_flinch_roll(rng, no_flinch, "", plain, 200, 170, false))
}

///|
/// 分布: chance 30 の抽選は seed 固定で約 30% 成立する (DP `flinch_probability(30, 1)`)。
test "mc flinch roll: 30% chance lands about 30% of seeded trials" {
  let bite = flchm_move("かみつく", "あく", @model.Physical, 60, 100, 30)
  let normal = flchm_pokemon("n", "ノーマル", 200, 60)
  let target = flchm_cmb(normal, [bite], "")
  let rate = flchm_rate(20261120UL, 8192, fn(rng) {
    mc_flinch_roll(rng, bite, "", target, 200, 170, false)
  })
  assert_true(flchm_close(rate, 0.3, 0.02))
}

///|
/// 分布 (凍結): 凍結の試行を flinched で引くと、25% で解凍して ふくつのこころ が発火し、75% は凍ったまま
/// (発火なし)。DP `flinched_outcomes(Freeze(2), false)` と同じ枝。
test "mc flinched pending: Freeze(2) thaws 25% (Steadfast fires) and stays frozen 75%" {
  let rng = seeded_rng(20261121UL)
  let mut thawed = 0
  let mut steady = 0
  let mut stuck = 0
  for _i = 0; _i < 8192; _i = _i + 1 {
    let (st, acts, missed, steadfast) = mc_resolve_pending_attempt(
      rng,
      @model.Freeze(2),
      100,
      false,
      true,
    )
    assert_false(acts)
    assert_false(missed)
    if st == @model.None {
      thawed = thawed + 1
    }
    if st == @model.Freeze(1) {
      stuck = stuck + 1
    }
    if steadfast {
      steady = steady + 1
    }
  }
  assert_true(flchm_close(thawed.to_double() / 8192.0, 0.25, 0.02))
  assert_true(flchm_close(stuck.to_double() / 8192.0, 0.75, 0.02))
  // 発火は解凍した枝だけ。
  assert_true(steady == thawed)
}

///|
/// 分布 (眠り): 眠り 1 回目 (Sleep(1)) の flinched は 1/3 で目覚め (発火)、2/3 は眠ったまま (発火なし)。
test "mc flinched pending: Sleep(1) wakes 1/3 (Steadfast fires), otherwise stays asleep" {
  let rng = seeded_rng(20261122UL)
  let mut woke = 0
  let mut steady = 0
  for _i = 0; _i < 8192; _i = _i + 1 {
    let (st, _, _, steadfast) = mc_resolve_pending_attempt(
      rng,
      @model.Sleep(1),
      100,
      false,
      true,
    )
    if st == @model.None {
      woke = woke + 1
    }
    if steadfast {
      steady = steady + 1
    }
  }
  assert_true(flchm_close(woke.to_double() / 8192.0, SLEEP_SECOND_TURN_WAKE_RATE, 0.02))
  assert_true(steady == woke)
}

///|
/// 非ひるみの保留試行は従来の `mc_resolve_attempt` と同じ (命中 100 なら必ず行動、発火なし)。
test "mc flinched pending: flinched=false keeps the plain attempt (accuracy 100 acts, no Steadfast)" {
  let rng = seeded_rng(20261123UL)
  let (st, acts, missed, steadfast) = mc_resolve_pending_attempt(
    rng,
    @model.None,
    100,
    false,
    false,
  )
  assert_true(acts)
  assert_false(missed)
  assert_false(steadfast)
  assert_true(st == @model.None)
}

///|
/// ふくつのこころ (MC): ひるみで止まった側の素早さランクを +1 する (clamp 込み)。
test "mc flinch speed boost: Steadfast raises the Speed rank by one, other abilities do not" {
  let ranks = [0, 0, 0, 0, 0]
  mc_flinch_speed_boost(ranks, "ふくつのこころ")
  assert_true(ranks[4] == 1)
  mc_flinch_speed_boost(ranks, "")
  assert_true(ranks[4] == 1)
  let capped = [0, 0, 0, 0, 2]
  mc_flinch_speed_boost(capped, "ふくつのこころ")
  assert_true(capped[4] == 2)
}

///|
/// parity (1v1): ひるみ 30% の速い攻撃 vs 遅い Tackle。DP (exact) と MC (rollout 平均) が一致する。
/// 感度ガード: ひるみのない対照 (flinch 0) との差が閾値より大きい (ひるみの経路が値に効いている)。
test "flinch DP/MC parity: a faster 50% flinch attacker against a slower Tackle target" {
  // 50% はテスト用の固定値 (DB の値は 10 / 20 / 30)。HP 1000 は KO の閾値を跨がせないため:
  // DP は平均ダメージ、MC は 16 乱数を抽選するので、HP が閾値付近だと値がずれる (既存の凍結 parity と同じ方針)。
  let bite = flchm_move("かみつく", "あく", @model.Physical, 60, 100, 50)
  let bite_nf = flchm_move("かみつく", "あく", @model.Physical, 60, 100, 0)
  let tackle = flchm_move("たいあたり", "ノーマル", @model.Physical, 80, 100, 0)
  let target = [flchm_cmb(flchm_pokemon("target", "ノーマル", 1000, 60), [tackle], "")]
  let flincher = [flchm_cmb(flchm_pokemon("bite", "ノーマル", 1000, 120), [bite], "")]
  let control = [flchm_cmb(flchm_pokemon("control", "ノーマル", 1000, 120), [bite_nf], "")]
  let dp_flinch = switching_game_winrate(flincher, target, 4)
  let dp_control = switching_game_winrate(control, target, 4)
  let mc_flinch = team_monte_carlo_value(flincher, target, 8192, 20261124UL, turn_limit=4)
  let mc_control = team_monte_carlo_value(control, target, 8192, 20261124UL, turn_limit=4)
  // 感度ガード: ひるみの経路が勝率に効いている。
  assert_true((dp_flinch - dp_control).abs() > 0.005)
  assert_true((dp_flinch - mc_flinch).abs() < 0.02)
  assert_true((dp_control - mc_control).abs() < 0.02)
}

