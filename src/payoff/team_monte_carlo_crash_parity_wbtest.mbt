///|
/// 崩れ技 (とびひざげり 等) の MC 配線と DP / MC parity。
///
/// MC 側は `team_perform_attack` が `is_immune` を 4 番目で返し、leg の中で `mc_apply_crash`
/// が使用者 HP を減らす。外れは `mc_resolve_attempt` の 3 番目 (`missed`) で判定する。
/// parity fixture は乱数が入らない matchup (命中 0 / 100 の崩れ技、はねる、100% の眠り技) に
/// 限り、DP の期待値と MC の平均が一致する。感度ガード: マジックガード / 非崩れ技 / 行動順で
/// 値が変わることを確かめ、parity が空回りでないことを示す。
/// helper: `crash_mon` / `crash_hjk_never_hits` / `crash_tackle` 等
/// (switching_game_crash_wbtest)、`seeded_rng` (monte_carlo)。

///|
fn crash_hjk_sure() -> @model.Move {
  mk_move("とびひざげり", "かくとう", @model.Physical, 130, accuracy=100)
}

///|
test "crash MC: 免疫の とびひざげり は immune を返し、mc_apply_crash で使用者 HP が 1/2 減る" {
  let own = crash_mon("CrashOwn", [crash_hjk_sure()], 200)
  let opp = crash_mon("CrashGhost", [crash_tackle()], 200, type1="ゴースト")
  let (res_hp, _res_eff, _bust, immune) = team_perform_attack(
    own,
    opp,
    200,
    crash_hjk_sure(),
    seeded_rng(9UL),
    [0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0],
  )
  assert_true(immune)
  @debug.assert_eq(res_hp, 200)
  let own_hps = [200]
  mc_apply_crash(own_hps, 0, own, crash_hjk_sure())
  @debug.assert_eq(own_hps[0], 100)
  // 対照: マジックガードは減らない / 非崩れ技は減らない。
  let guarded = crash_mon("CrashOwnMG", [crash_hjk_sure()], 200, ability="マジックガード")
  let guarded_hps = [200]
  mc_apply_crash(guarded_hps, 0, guarded, crash_hjk_sure())
  @debug.assert_eq(guarded_hps[0], 200)
  let plain_hps = [200]
  mc_apply_crash(plain_hps, 0, own, crash_tackle())
  @debug.assert_eq(plain_hps[0], 200)
}

///|
test "crash MC: 外れ (命中 0) は missed=true、眠りで行動できない skip は missed=false" {
  let (_st1, acts1, missed1) = mc_resolve_attempt(@model.None, 0, seeded_rng(9UL))
  assert_true(!acts1)
  assert_true(missed1)
  let (_st2, acts2, missed2) = mc_resolve_attempt(@model.Sleep(2), 100, seeded_rng(9UL))
  assert_true(!acts2)
  assert_true(!missed2)
}

///|
/// **Parity 1 (免疫の崩れ)**: 相手ゴーストへの とびひざげり (命中 100) は免疫で、使用者は
/// 毎ターン 100 を失い 2 ターン目に ひんし。DP と MC の値は -1 で一致する。
/// 感度: マジックガードなら負けない (値が変わる)。
test "crash parity: 免疫の とびひざげり で使用者が 2 ターンで ひんし (DP / MC)" {
  let own = [crash_mon("CrashOwn", [crash_hjk_sure()], 200)]
  let opp = [crash_mon("CrashGhost", [crash_splash()], 200, type1="ゴースト")]
  let dp = switching_game_winrate(own, opp, 2)
  let mc = team_monte_carlo_value(own, opp, 16, 74007UL, turn_limit=2)
  assert_true((dp - mc).abs() < 0.001)
  assert_true(dp < -0.5)
  let own_mg = [crash_mon("CrashOwnMG", [crash_hjk_sure()], 200, ability="マジックガード")]
  let dp_mg = switching_game_winrate(own_mg, opp, 2)
  let mc_mg = team_monte_carlo_value(own_mg, opp, 16, 74007UL, turn_limit=2)
  assert_true((dp_mg - mc_mg).abs() < 0.001)
  assert_true((dp_mg - dp).abs() > 0.5)
}

///|
/// **Parity 2 (外れの崩れ)**: 命中 0 の とびひざげり は毎ターン外れ、崩れで 2 ターン目に ひんし。
/// DP と MC は -1 で一致。感度: 非崩れ技 (命中 0 の たいあたり) は負けない。
test "crash parity: 外れた とびひざげり の崩れで 2 ターンで ひんし (DP / MC)" {
  let own = [crash_mon("CrashOwn", [crash_hjk_never_hits()], 200)]
  let opp = [crash_mon("CrashOpp", [crash_splash()], 200)]
  let dp = switching_game_winrate(own, opp, 2)
  let mc = team_monte_carlo_value(own, opp, 16, 74007UL, turn_limit=2)
  assert_true((dp - mc).abs() < 0.001)
  assert_true(dp < -0.5)
  let own_plain = [crash_mon("CrashPlain", [crash_tackle_never_hits()], 200)]
  let dp_plain = switching_game_winrate(own_plain, opp, 2)
  let mc_plain = team_monte_carlo_value(own_plain, opp, 16, 74007UL, turn_limit=2)
  assert_true((dp_plain - mc_plain).abs() < 0.001)
  assert_true((dp_plain - dp).abs() > 0.5)
}

///|
/// **Parity 3 (眠りで崩れが起きない / 行動順)**: 遅い使用者は先の相手の ねむりごな で眠り、
/// 外しても崩れない。速い使用者は眠りより先に崩れる。DP / MC の値は両方で一致し、行動順で
/// 値が変わる (感度)。
test "crash parity: 遅い使用者は眠らされると崩れない / 速い使用者は先に崩れる (DP / MC)" {
  let slow = [crash_mon("CrashSlow", [crash_hjk_never_hits()], 200, spe=50)]
  let fast_spore = [crash_mon("CrashSpore", [crash_spore()], 200, spe=150)]
  let dp_slow = switching_game_winrate(slow, fast_spore, 2)
  let mc_slow = team_monte_carlo_value(slow, fast_spore, 16, 74007UL, turn_limit=2)
  assert_true((dp_slow - mc_slow).abs() < 0.001)
  let fast = [crash_mon("CrashFast", [crash_hjk_never_hits()], 200, spe=150)]
  let slow_spore = [crash_mon("CrashSlowSpore", [crash_spore()], 200, spe=50)]
  let dp_fast = switching_game_winrate(fast, slow_spore, 2)
  let mc_fast = team_monte_carlo_value(fast, slow_spore, 16, 74007UL, turn_limit=2)
  assert_true((dp_fast - mc_fast).abs() < 0.001)
  assert_true((dp_fast - dp_slow).abs() > 0.001)
}
