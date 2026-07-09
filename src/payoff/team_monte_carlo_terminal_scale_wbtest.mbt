///|
/// team_rollout の horizon-draw スケール `(own_ratio - opp_ratio) / 2.0` の
/// ベースライン回帰テスト (特性非依存)。
///
/// 背景: 本 PR で team_rollout の turn-limit 引き分け終端を旧
/// `own_ratio - opp_ratio` から `(own_ratio - opp_ratio) / 2.0` に修正した。これは
/// DP 側 `terminal_value` (switching_game.mbt: `(my_r - opp_r) / 2`) との
/// スケール不一致 (MC が 2 倍) を直す **横断的な correctness fix** で、いかく /
/// あまのじゃく / ばけのかわ に限らず「turn_limit に引き分けで到達する全 rollout」の
/// 値を変える。ScreenedSwitchingGame Phase A はこの MC 値で選出をランク付けするため、
/// 通常 (特性なし) チームの screening/pruning 順序も変わりうる (= MC screening 経路は
/// 非該当構成でも bit 一致しない。DP 経路は不変)。
///
/// 本ファイルは特性を一切持たない通常チームで、修正後スケールを 2 面から pin する:
///   1. 決定論ピン (tol 1e-9): 定数ダメージ 1v1 (16 ロール全一定 → seed 非依存) で
///      MC (`team_monte_carlo_value`) と DP (`switching_game_winrate`) が float 精度で
///      一致すること。DP は `/2` を使う SSoT なので、MC が旧 `/1` スケールなら引き分け
///      値が 2 倍になり一致が崩れる → このピンがスケール係数そのものを固定する。
///   2. サンプリング parity (tol 0.15): 可変ダメージの非飽和引き分けでも MC/DP が
///      value-tol で一致すること (他の parity fixture と同 posture)。

///|
/// **(1) 決定論スケールピン**: own = 高速・威力1 の chipper (低攻撃 × 高防御で
/// 16 ロールが全て最小 1 に潰れ、ダメージ定数 → rollout が seed 非依存)。opp =
/// 高 HP・はねる のみの壁。turn_limit=3 で opp は KO されず両者生存の引き分け。
/// own は被弾 0 なので own_ratio=1.0、opp_ratio<1.0 の正の引き分け。
///   - 2 つの seed で `team_monte_carlo_value` が bit 一致 (定数ダメージ = 分岐/
///     サンプリング変動なしの確認)
///   - MC と DP が `< 1e-9` で一致 (共有 `/2` スケールの決定論ピン。旧 `/1` なら
///     MC が 2 倍で mismatch)
///   - 値が `(0, 0.5)` の非飽和引き分け (`/2` の値域。KO の ±1.0 とは別物)
test "team_rollout draw scale: MC == DP under shared /2 (ordinary team, deterministic)" {
  let chipper = mk_pokemon(
    "Chipper", "ノーマル", "", 250, 1, 100, 1, 100, 200,
  )
  let wall = mk_pokemon("Wall", "はがね", "", 800, 60, 250, 60, 250, 10)
  // 威力1・攻撃1 → base ダメージが極小で 16 ロール全て最小 1 に潰れる (定数)。
  let tap = mk_move("tap", "ノーマル", @model.Physical, 1)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let own = [pl_cmb(chipper, [tap])]
  let opp = [pl_cmb(wall, [splash])]
  let turn_limit = 3
  // 定数ダメージ → seed 非依存。異なる seed / trials で bit 一致することで、
  // サンプリング変動と分岐が無いこと (= 以降の DP との厳密一致が妥当) を担保する。
  let mc_a = team_monte_carlo_value(own, opp, 4, 111UL, turn_limit~)
  let mc_b = team_monte_carlo_value(own, opp, 16, 987654321UL, turn_limit~)
  @debug.assert_eq(mc_a, mc_b)
  // DP は `/2` を使う SSoT。定数ダメージなので MC 単一サンプル = DP 平均となり、
  // 両者は float 精度で一致するはず。旧 `/1` スケールなら MC が引き分け値の 2 倍に
  // なり、この 1e-9 ピンが破れる (= スケール係数そのものの回帰ガード)。
  let dp = switching_game_winrate(own, opp, turn_limit)
  assert_true((mc_a - dp).abs() < 1.0e-9)
  // 非飽和の正の引き分け: own 有利だが KO 未到達。`/2` の値域 (0, 0.5) に収まる
  // (旧 `/1` なら同じ引き分けが 2 倍で 0.5 を超えうる)。
  assert_true(mc_a > 0.0)
  assert_true(mc_a < 0.5)
}

///|
/// **(2) サンプリング parity (通常チーム、可変ダメージ)**: own = 中火力アタッカー、
/// opp = 高耐久・はねる のみの壁。turn_limit=2 で opp を KO しきれず非飽和引き分け。
/// 可変ダメージ (通常威力) を多 trial で平均し、MC (`team_monte_carlo_value`) と DP
/// (`switching_game_winrate`) が `< 0.15` で一致することを pin する。特性を一切
/// 持たない構成での MC/DP スケール整合を、決定論ピンとは別に非定数ダメージでも確認する。
test "team_rollout draw scale: MC/DP value parity on variable-damage draw (ordinary team)" {
  let attacker = mk_pokemon("Atk", "みず", "", 220, 130, 100, 130, 100, 130)
  let wall = mk_pokemon("Wall", "はがね", "", 520, 70, 200, 70, 200, 40)
  let hydro = mk_move("みずのは", "みず", @model.Physical, 60)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let own = [pl_cmb(attacker, [hydro])]
  let opp = [pl_cmb(wall, [splash])]
  let turn_limit = 2
  let dp = switching_game_winrate(own, opp, turn_limit)
  // 非飽和引き分けであること (±1.0 に張り付いていないこと) を確認 — 飽和 fixture の
  // 「trivially 一致」を排除し、スケール差 (|draw|/2) が parity に効く構成を保証する。
  assert_true(dp.abs() < 0.9)
  assert_true(dp.abs() > 0.0)
  let mc = team_monte_carlo_value(own, opp, 256, 424242UL, turn_limit~)
  assert_true((dp - mc).abs() < 0.15)
}
