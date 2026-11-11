///|
/// Champions の眠り規則 (help_syn.json:26333 / jpn help_syn.json:23848) の MC 側と
/// DP / MC の parity。
/// - 分布: `mc_resolve_attempt` を seed 固定で大量に回し、通常ねむりは 1 回目確定 skip、
///   2 回目 1/3 目覚め、3 回目確定目覚め (skip 回数 1 w.p. 1/3 / 2 w.p. 2/3)、
///   ねむる (RestSleep) は skip 回数が常に 2 であることを確認する。
/// - parity: 1v1 の眠り fixture で `switching_game_winrate` (DP, exact) と
///   `team_monte_carlo_value` (MC, rollout 平均) が許容誤差内で一致する。
/// - 感度ガード: 眠らせない対照 (nop 技) との DP / MC の差が閾値より大きいことを先に
///   確認する。眠りの経路が値に効いていないのに parity が自明に通る事態を防ぐ。
/// fixture は「眠らせ役が後攻 (= 眠りの着弾ターンに標的が行動前にブロックされる)」を
/// 使わない。その場合は、目覚めた標的が同ターンの再眠り (先攻の Spore) で行動前に
/// 眠らされる既存の順序近似 (wake を pre-turn に適用) が入り、標的が一度も行動しない
/// 値 (0.0) になる。DP / MC で同じ値になるが本家とはずれるため、期待値として固定
/// しない (follow-up で扱う)。着弾ブロックの消費は switching_game_sleep_wbtest.mbt
/// の DP 単体テストと `team_monte_carlo_test.mbt` の回帰で確認する。

///|
fn slm_move(
  name : String,
  category : @model.MoveCategory,
  power : Int,
  status_effect : (@model.StatusKind, Int)?,
  healing : @model.HealingEffect?,
) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category,
    power,
    accuracy: 100,
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
  }
}

///|
fn slm_pokemon(name : String, hp : Int, spe : Int) -> @model.Pokemon {
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
fn slm_cmb(pokemon : @model.Pokemon, moves : Array[@model.Move]) -> Combatant {
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
/// 眠りの試行を繰り返し、目覚めて行動するまでに眠ったまま消費した回数を返す。
fn slm_skips_until_wake(
  start : @model.StatusCondition,
  rng : @random.Rand,
) -> Int {
  let mut st = start
  let mut skips = 0
  for _step in 0..<6 {
    let (next, acts, _missed) = mc_resolve_attempt(st, 100, rng)
    if acts {
      return skips
    }
    skips += 1
    st = next
  }
  skips
}

///|
test "mc_resolve_attempt: Sleep(2) is a sure skip; RestSleep(n>0) never wakes early" {
  let rng = seeded_rng(7UL)
  for _i in 0..<200 {
    let (st, acts, missed) = mc_resolve_attempt(@model.Sleep(2), 100, rng)
    assert_false(acts)
    // A sleep skip never reaches the move, so it is not a miss (no crash).
    assert_false(missed)
    @debug.assert_eq(st, @model.Sleep(1))
    let (rst, racts, rmissed) = mc_resolve_attempt(@model.RestSleep(1), 100, rng)
    assert_false(racts)
    assert_false(rmissed)
    @debug.assert_eq(rst, @model.RestSleep(0))
  }
}

///|
test "mc_resolve_attempt: Sleep(1) wakes on 1/3 of seeded 2nd attempts (distribution)" {
  let rng = seeded_rng(20261110UL)
  let n = 30000
  let mut woke = 0
  let mut acted = 0
  for _i in 0..<n {
    let (st, acts, _missed) = mc_resolve_attempt(@model.Sleep(1), 100, rng)
    if st == @model.None {
      woke += 1
    }
    if acts {
      acted += 1
    }
  }
  let p = woke.to_double() / n.to_double()
  assert_true((p - 1.0 / 3.0).abs() < 0.01)
  // acc=100: the waking attempt always acts.
  @debug.assert_eq(acted, woke)
}

///|
test "mc_resolve_attempt: Sleep(1) acc=85 -> wake-and-act ~ 1/3*0.85, wake-miss ~ 1/3*0.15" {
  let rng = seeded_rng(20261111UL)
  let n = 30000
  let mut acted = 0
  let mut woke_miss = 0
  let mut missed_n = 0
  for _i in 0..<n {
    let (st, acts, missed) = mc_resolve_attempt(@model.Sleep(1), 85, rng)
    if acts {
      acted += 1
    } else if st == @model.None {
      woke_miss += 1
    }
    // `missed` (crash flag) is the wake-and-miss branch only: the move was used
    // and missed. The 2/3 sleep skip (Sleep(0), no move) is never missed.
    if missed {
      missed_n += 1
      assert_true(!acts && st == @model.None)
    }
  }
  let nf = n.to_double()
  assert_true((acted.to_double() / nf - 0.85 / 3.0).abs() < 0.01)
  assert_true((woke_miss.to_double() / nf - 0.15 / 3.0).abs() < 0.01)
  @debug.assert_eq(missed_n, woke_miss)
}

///|
test "mc skip-count distribution: normal sleep 1 w.p. 1/3 and 2 w.p. 2/3; Rest exactly 2" {
  let rng = seeded_rng(20261112UL)
  let n = 30000
  let mut normal1 = 0
  let mut normal_other = 0
  let mut rest2 = 0
  let mut rest_other = 0
  for _i in 0..<n {
    let k = slm_skips_until_wake(@model.Sleep(2), rng)
    if k == 1 {
      normal1 += 1
    } else if k != 2 {
      normal_other += 1
    }
    let r = slm_skips_until_wake(@model.RestSleep(2), rng)
    if r == 2 {
      rest2 += 1
    } else {
      rest_other += 1
    }
  }
  let nf = n.to_double()
  // 通常ねむり: 2 回目で目覚める 1/3 (skip 1 回)、眠ったまま 2/3 (skip 2 回)。
  assert_true((normal1.to_double() / nf - 1.0 / 3.0).abs() < 0.01)
  @debug.assert_eq(normal_other, 0)
  // ねむる: 3 回目まで目覚めない (skip は必ず 2 回)。
  @debug.assert_eq(rest2, n)
  @debug.assert_eq(rest_other, 0)
}

///|
/// parity fixture (Spore): 標的が速く先攻で行動し、後攻の眠らせ役 (遅い) が Spore を撃つ。
/// 眠りは行動後に付与されるので着弾ターンのブロックは起きず、以後の 2 回目 (1/3 の
/// 目覚め) と 3 回目 (確定目覚め) が値に効く。対照 (`nop`) は眠らせず毎ターン被弾する。
/// 期待 (手計算): 4 ターン内の被弾は標的の目覚め方によらず 2 回 (1 ターン目と、
/// 2 回目で目覚めた場合は 3 ターン目、3 回目で目覚めた場合は 4 ターン目)。対照は 4 回。
/// 1 hit は約 35 HP (200 HP 基準) なので、値は (-70 / 200 vs -140 / 200) / 2 = -0.175 / -0.35。
test "sleep DP/MC parity: Spore on a faster target (sleep from the next attempt)" {
  let spore = slm_move(
    "キノコのほうし",
    @model.Status,
    0,
    Some((@model.SleepKind, 100)),
    None,
  )
  let nop = slm_move("はねる", @model.Status, 0, None, None)
  let hit = slm_move("たいあたり", @model.Physical, 40, None, None)
  let target = [slm_cmb(slm_pokemon("target", 200, 120), [hit])]
  let sleeper = [slm_cmb(slm_pokemon("spore", 200, 60), [spore])]
  let control = [slm_cmb(slm_pokemon("nop", 200, 60), [nop])]
  let dp_sleep = switching_game_winrate(sleeper, target, 4)
  let dp_control = switching_game_winrate(control, target, 4)
  // 感度ガード: 眠りの経路が値に効いている (観測差 0.175)。
  assert_true((dp_sleep - dp_control).abs() > 0.05)
  let mc_sleep = team_monte_carlo_value(sleeper, target, 2048, 20261110UL, turn_limit=4)
  let mc_control = team_monte_carlo_value(control, target, 2048, 20261110UL, turn_limit=4)
  assert_true((mc_sleep - mc_control).abs() > 0.05)
  assert_true((dp_sleep - mc_sleep).abs() < 0.02)
  assert_true((dp_control - mc_control).abs() < 0.02)
}

///|
/// parity fixture (Rest): 速い側が ねむる。1 ターン目は満タンで失敗し、被弾後の
/// 2 ターン目に全回復して RestSleep(2) になる (3 回目まで目覚めない)。
/// 対照 (`nop`) は回復も眠りもせず被弾し続ける。
test "sleep DP/MC parity: Rest (RestSleep) heals and sleeps 2 attempts" {
  let rest = slm_move(
    "ねむる",
    @model.Status,
    0,
    None,
    Some(@model.Rest),
  )
  let nop = slm_move("はねる", @model.Status, 0, None, None)
  let hit = slm_move("たいあたり", @model.Physical, 40, None, None)
  let target = [slm_cmb(slm_pokemon("target", 200, 60), [hit])]
  let resting = [slm_cmb(slm_pokemon("rest", 200, 120), [rest])]
  let control = [slm_cmb(slm_pokemon("nop", 200, 120), [nop])]
  let dp_rest = switching_game_winrate(resting, target, 4)
  let dp_control = switching_game_winrate(control, target, 4)
  assert_true((dp_rest - dp_control).abs() > 0.05)
  let mc_rest = team_monte_carlo_value(resting, target, 2048, 20261113UL, turn_limit=4)
  let mc_control = team_monte_carlo_value(control, target, 2048, 20261113UL, turn_limit=4)
  assert_true((mc_rest - mc_control).abs() > 0.05)
  assert_true((dp_rest - mc_rest).abs() < 0.02)
  assert_true((dp_control - mc_control).abs() < 0.02)
}

///|
/// parity fixture (Yawn): あくび (Drowsy) は EOT 2 回で Sleep(2) になり、以後は通常
/// ねむりの規則 (1 回目確定、2 回目 1/3、3 回目確定)。Drowsy は着弾ターンに行動を
/// 止めないため、同ターンの再付与による順序近似は入らない。対照 (`nop`) は眠らせない。
test "sleep DP/MC parity: Yawn -> Sleep(2) follows the normal rule" {
  let yawn = slm_move(
    "あくび",
    @model.Status,
    0,
    Some((@model.DrowsyKind, 100)),
    None,
  )
  let nop = slm_move("はねる", @model.Status, 0, None, None)
  let hit = slm_move("たいあたり", @model.Physical, 40, None, None)
  let target = [slm_cmb(slm_pokemon("target", 200, 60), [hit])]
  let yawner = [slm_cmb(slm_pokemon("yawn", 200, 120), [yawn])]
  let control = [slm_cmb(slm_pokemon("nop", 200, 120), [nop])]
  let dp_yawn = switching_game_winrate(yawner, target, 5)
  let dp_control = switching_game_winrate(control, target, 5)
  // 感度ガード: 観測差 0.146。
  assert_true((dp_yawn - dp_control).abs() > 0.05)
  let mc_yawn = team_monte_carlo_value(yawner, target, 2048, 20261114UL, turn_limit=5)
  let mc_control = team_monte_carlo_value(control, target, 2048, 20261114UL, turn_limit=5)
  assert_true((mc_yawn - mc_control).abs() > 0.05)
  assert_true((dp_yawn - mc_yawn).abs() < 0.02)
  assert_true((dp_control - mc_control).abs() < 0.02)
}
