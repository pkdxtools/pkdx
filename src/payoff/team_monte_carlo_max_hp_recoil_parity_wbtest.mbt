///|
/// てっていこうせん の最大 HP 1/2 反動 (MC 側) と DP / MC parity。
///
/// MC は `team_perform_attack` の戻り値 (`res_eff` = 実ダメージ) を `team_apply_post_hit`
/// に渡し、命中は `dmg > 0`、免疫は `immune=true` で対象生存時に反動を入れる。
/// 外れは `team_rollout` の Step 3 (行動順の各 leg) で `own_missed` / `opp_missed` を
/// 見て入れる。`mc_resolve_attempt` の第 3 戻り値 `missed` は命中判定の外れだけ true。
///
/// parity fixture は乱数が入らない matchup: 命中率 0 (= 常に外れ) の てっていこうせん と、
/// 相手の はねる。毎ターン自分だけ 100 失うので、2 ターン目で ひんし になる。
/// DP `switching_game_winrate` と MC `team_rollout` (epsilon=0) の値が一致する。
/// 感度ガード: 同じ構造で技名だけ変えると (反動なし) 値は変わらず、差が大きい。
/// helper: `mk_move` / `mk_pokemon` / `pl_cmb` (team_monte_carlo_healing / protean_parity)、
/// `seeded_rng` (monte_carlo)、`team_perform_attack` / `team_apply_post_hit` (team_monte_carlo)。

///|
fn mr_user(name : String, accuracy : Int, ability : String) -> Combatant {
  let mv = mk_move(name, "はがね", @model.Special, 140, accuracy=accuracy)
  // DP / MC の初期 HP と HP 比率の分母は pokemon.hp (= 実数値) を使うため、actual_stats と揃える。
  let p = mk_pokemon("MrUser", "はがね", "", 200, 100, 100, 100, 100, 100)
  let c = pl_cmb(p, [mv], ability=ability)
  { ..c, actual_stats: Some([200, 100, 100, 100, 100, 100]) }
}

///|
fn mr_splash_foe() -> Combatant {
  let p = mk_pokemon("MrFoe", "ノーマル", "", 260, 60, 100, 60, 100, 60)
  pl_cmb(p, [mk_move("はねる", "ノーマル", @model.Status, 0)])
}

///|
/// 1 回の命中 leg (team_perform_attack → team_apply_post_hit) を行い、
/// (自分の HP, 相手の HP) を返す。
fn mr_attack(
  own : Combatant,
  opp : Combatant,
  mv : @model.Move,
  own_hp : Int,
  opp_hp : Int,
) -> (Int, Int) {
  let own_hps = [own_hp]
  let opp_ranks = [0, 0, 0, 0, 0]
  let (res_hp, res_eff, _res_bust, res_immune) = team_perform_attack(
    own,
    opp,
    opp_hp,
    mv,
    seeded_rng(9UL),
    [0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0],
  )
  let opp_hps = [res_hp]
  team_apply_post_hit(
    own_hps,
    0,
    [0, 0, 0, 0, 0],
    [false],
    [@model.None],
    [-1],
    [own],
    opp_hps,
    0,
    opp_ranks,
    [false],
    [opp],
    [false],
    [@model.Weather::None],
    [0],
    [@model.Field::None],
    [0],
    mv,
    res_eff,
    immune=res_immune,
  )
  (own_hps[0], opp_hps[0])
}

///|
/// MC 命中: 最大 HP 200 → 反動 100 (偶数)。
test "MC max-hp recoil: hit costs half of max HP (200 -> 100)" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let (own_after, opp_after) = mr_attack(
    mr_user("てっていこうせん", 100, ""),
    mr_splash_foe(),
    mv,
    200,
    200,
  )
  @debug.assert_eq(own_after, 100)
  assert_true(opp_after < 200)
}

///|
/// MC 奇数: 最大 HP 151 → Math.round(75.5) = 76 → 75 (floor の 76 と区別)。
/// 最大 HP は actual_stats で固定するため、mr_user の 200 ではなく 151 の使用者を作る。
test "MC max-hp recoil: odd max HP 151 rounds half up (151 -> 75)" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let base = mr_user("てっていこうせん", 100, "")
  let own = { ..base, actual_stats: Some([151, 100, 100, 100, 100, 100]) }
  let (own_after, _opp) = mr_attack(own, mr_splash_foe(), mv, 151, 200)
  @debug.assert_eq(own_after, 75)
}

///|
/// MC 感度ガード: 同じ命中で名前だけ変えると反動なし (HP 200 のまま)。
test "MC max-hp recoil: sensitivity guard (another name has no recoil)" {
  let mv = mk_move("テスト技", "はがね", @model.Special, 140)
  let (own_after, _opp) = mr_attack(
    mr_user("テスト技", 100, ""),
    mr_splash_foe(),
    mv,
    200,
    200,
  )
  @debug.assert_eq(own_after, 200)
}

///|
/// MC マジックガード: 命中でも反動なし。
test "MC max-hp recoil: Magic Guard blocks the hit recoil" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let (own_after, _opp) = mr_attack(
    mr_user("てっていこうせん", 100, "マジックガード"),
    mr_splash_foe(),
    mv,
    200,
    200,
  )
  @debug.assert_eq(own_after, 200)
}

///|
/// MC 自己 KO: 現在 HP 50 (最大 200) で命中すると反動 100 で ひんし。
test "MC max-hp recoil: user faints from the recoil" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let (own_after, _opp) = mr_attack(
    mr_user("てっていこうせん", 100, ""),
    mr_splash_foe(),
    mv,
    50,
    200,
  )
  @debug.assert_eq(own_after, 0)
}

///|
/// MC: 対象が既に ひんし (HP 0) なら命中 leg の実ダメージは 0 で反動も発動しない。
test "MC max-hp recoil: no recoil when the target is already fainted" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let (own_after, opp_after) = mr_attack(
    mr_user("てっていこうせん", 100, ""),
    mr_splash_foe(),
    mv,
    200,
    0,
  )
  @debug.assert_eq(own_after, 200)
  @debug.assert_eq(opp_after, 0)
}

///|
/// MC 免疫 (immune=true): 対象生存なら反動、対象 ひんし なら反動なし。
test "MC max-hp recoil: immune leg costs recoil only when the target is alive" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let own_hps = [200]
  team_apply_post_hit(
    own_hps,
    0,
    [0, 0, 0, 0, 0],
    [false],
    [@model.None],
    [-1],
    [mr_user("てっていこうせん", 100, "")],
    [100],
    0,
    [0, 0, 0, 0, 0],
    [false],
    [mr_splash_foe()],
    [false],
    [@model.Weather::None],
    [0],
    [@model.Field::None],
    [0],
    mv,
    0,
    immune=true,
  )
  @debug.assert_eq(own_hps[0], 100)
  let dead_hps = [200]
  team_apply_post_hit(
    dead_hps,
    0,
    [0, 0, 0, 0, 0],
    [false],
    [@model.None],
    [-1],
    [mr_user("てっていこうせん", 100, "")],
    [0],
    0,
    [0, 0, 0, 0, 0],
    [false],
    [mr_splash_foe()],
    [false],
    [@model.Weather::None],
    [0],
    [@model.Field::None],
    [0],
    mv,
    0,
    immune=true,
  )
  @debug.assert_eq(dead_hps[0], 200)
}

///|
/// MC ばけのかわ (初撃ブロック): 実ダメージ 0 (chip のみ) の leg は反動を発動しない。
/// Showdown では Disguise の onDamage が 0 を返すため `totalDamage` が偽になる。
test "MC max-hp recoil: disguise block (dealt 0) does not trigger the recoil" {
  let mv = mk_move("てっていこうせん", "はがね", @model.Special, 140)
  let own = mr_user("てっていこうせん", 100, "")
  let opp = {
    ..mr_splash_foe(),
    ability: "ばけのかわ",
    actual_stats: Some([200, 100, 100, 100, 100, 100]),
  }
  let (res_hp, res_eff, _bust, _immune) = team_perform_attack(
    own,
    opp,
    200,
    mv,
    seeded_rng(9UL),
    [0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0],
    def_disguise_intact=true,
  )
  // 初撃は chip (= 最大 HP / 8 = 25) のみ、実ダメージ (dmg_for_effects) は 0。
  @debug.assert_eq(res_eff, 0)
  @debug.assert_eq(res_hp, 175)
  let own_hps = [200]
  team_apply_post_hit(
    own_hps,
    0,
    [0, 0, 0, 0, 0],
    [false],
    [@model.None],
    [-1],
    [own],
    [res_hp],
    0,
    [0, 0, 0, 0, 0],
    [false],
    [opp],
    [false],
    [@model.Weather::None],
    [0],
    [@model.Field::None],
    [0],
    mv,
    res_eff,
    immune=false,
  )
  @debug.assert_eq(own_hps[0], 200)
}

///|
/// `mc_resolve_attempt` の第 3 戻り値: 命中判定の外れだけ true。睡眠の不発は false。
test "MC max-hp recoil: mc_resolve_attempt reports missed only for the accuracy miss" {
  let rng = seeded_rng(5UL)
  // accuracy 0 → 常に外れ (missed=true, acts=false)。
  let (st_miss, acts_miss, missed_miss) = mc_resolve_attempt(
    @model.None,
    0,
    rng,
  )
  @debug.assert_eq(st_miss, @model.None)
  @debug.assert_eq(acts_miss, false)
  @debug.assert_eq(missed_miss, true)
  // 睡眠 (Sleep(1)) は不発で、外れではない (missed=false)。
  let (st_sleep, acts_sleep, missed_sleep) = mc_resolve_attempt(
    @model.Sleep(1),
    100,
    rng,
  )
  @debug.assert_eq(st_sleep, @model.Sleep(0))
  @debug.assert_eq(acts_sleep, false)
  @debug.assert_eq(missed_sleep, false)
}

///|
/// DP / MC parity (値): 命中率 0 の てっていこうせん は毎ターン外れ、外れ反動で
/// 自分だけ 100 失う。2 ターン目に ひんし → 両者とも -1.0 (負け)。
/// 感度ガード: 技名だけ変えると反動が無く、値は負けにならない (差 > 0.5)。
test "select DP/MC parity: missed てっていこうせん recoils to fainting in 2 turns" {
  let own = [mr_user("てっていこうせん", 0, "")]
  let opp = [mr_splash_foe()]
  let dp = switching_game_winrate(own, opp, 2)
  let mc = team_rollout(own, opp, seeded_rng(74011UL), turn_limit=2, epsilon=0.0)
  assert_true((dp - mc).abs() < 0.001)
  assert_true((dp - (-1.0)).abs() < 0.001)
  let own_plain = [mr_user("テスト技", 0, "")]
  let dp_plain = switching_game_winrate(own_plain, opp, 2)
  let mc_plain = team_rollout(
    own_plain,
    opp,
    seeded_rng(74011UL),
    turn_limit=2,
    epsilon=0.0,
  )
  assert_true((dp_plain - mc_plain).abs() < 0.001)
  assert_true(dp_plain - dp > 0.5)
}

///|
/// DP / MC parity (マジックガード): 同じ外れ構造でも マジックガード なら反動が無く、
/// 負けにならない (感度: 差 > 0.5)。
test "select DP/MC parity: Magic Guard keeps the missed てっていこうせん from fainting" {
  let own = [mr_user("てっていこうせん", 0, "マジックガード")]
  let opp = [mr_splash_foe()]
  let dp = switching_game_winrate(own, opp, 2)
  let mc = team_rollout(own, opp, seeded_rng(74012UL), turn_limit=2, epsilon=0.0)
  assert_true((dp - mc).abs() < 0.001)
  let own_base = [mr_user("てっていこうせん", 0, "")]
  let dp_base = switching_game_winrate(own_base, opp, 2)
  assert_true(dp - dp_base > 0.5)
}
