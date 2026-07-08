///|
/// ばけのかわ (Disguise, ミミッキュ専用) の MC/DP parity テスト。DP 側
/// (switching_game_turn.mbt / switching_game.mbt) は damage transform で初段
/// ブロック + chip を、fanout で busted フラグと dmg_for_effects を配線済み。本
/// ファイルは MC rollout (`team_rollout` / `team_monte_carlo_value`) 側の配線
/// (`team_perform_attack` の初段ブロック + per-slot `*_disguise_busted` +
/// `best_expected_damage` の greedy reduced 評価) が DP と同一セマンティクスで
/// あることを pin する。単体の transform / busted / recoil / drain 挙動は
/// switching_game_disguise_wbtest.mbt が担う。
///
/// pin する観点 (protean / intimidate / contrary parity と同 posture):
///   1. value-tol parity (own 側 ばけのかわ): `|dp - mc| < 0.15` (sign-agreement
///      のみでは不可)。fixture 感度ガード `|dp_disguise - dp_plain| > 0.15` 付き
///      — MC 配線が欠落すれば mc は ばけのかわ なし側 (≈ dp_plain) に張り付き、
///      parity が tol を超えて fail する構成であることの自己検証。
///   2. value-tol parity (opp 側 ばけのかわ): 対称。
///   3. 非ばけのかわ no-op: ability="" と "ばけのかわ以外" で同 seed MC 値が bit
///      一致 (配線が非 ばけのかわ entrant に対して分岐・乱数消費を一切変えない +
///      同 seed 再現の決定性)。
///   4. MC 単体 方向性: ばけのかわ 持ち defender 入りの rollout 値が ability=""
///      版より defender 有利方向。
///
/// 方針メモ: fixture は 1v1・単発技 (連続技の単一ロール近似誤差を排除) で、
/// disguise 効果 (初段ブロック) を turn_limit=1 に閉じ込めた無飽和構成。防御側
/// ミミッキュ は受け側 (はねる のみ) で、攻撃側の 1 発が chip でブロックされる分
/// が terminal HP 比率差にそのまま現れる (±1 に飽和しない)。DP は minimax、MC は
/// ε-greedy だが、単発 1 ターンなので方策乖離は無く value-tol で厳密に一致する。
/// MC は mega 未モデルなので raw ability を読む (ばけのかわ を持つ mega form は
/// 存在しないため raw = 実効)。連続技の初段ブロックは most-likely variant の初段
/// を単一ロールで近似する点のみ DP (variant 加重) と厳密一致しないため、本 fixture
/// では単発技のみを使う。

///|
/// **Case 1 (value-tol parity, own 側 ばけのかわ)**: own = ミミッキュ (ばけのかわ,
/// はねる のみの受け)、opp = みず 単発物理アタッカー。turn_limit=1 で opp の 1 発が
/// own の ばけのかわ でブロックされ chip のみになる分、own の HP 比率が高く保たれ
/// value が own 有利方向へ動く。DP (`switching_game_winrate`) と MC
/// (`team_monte_carlo_value`) が `|dp - mc| < 0.15` で一致することを pin。感度ガード
/// として「ばけのかわ 有無の DP 差 > 0.15」も assert する。
test "MC/DP value parity under own-side Disguise (single-hit block)" {
  let mimikyu = mk_pokemon(
    "Mimikyu", "ゴースト", "フェアリー", 300, 60, 80, 60, 100, 50,
  )
  let basher = mk_pokemon("Basher", "みず", "", 260, 150, 100, 95, 100, 120)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let aquatail = mk_move("アクアテール", "みず", @model.Physical, 135)
  let own = [pl_cmb(mimikyu, [splash], ability="ばけのかわ")]
  let own_plain = [pl_cmb(mimikyu, [splash])]
  let opp = [pl_cmb(basher, [aquatail])]
  let turn_limit = 1
  let dp_value = switching_game_winrate(own, opp, turn_limit)
  let dp_plain = switching_game_winrate(own_plain, opp, turn_limit)
  // fixture 感度ガード: ばけのかわ の有無が tol を超えて value を動かす構成である
  // こと (= 飽和 fixture の「trivially |dp-mc|=0」を排除)。実測 sens≈0.228。
  assert_true((dp_value - dp_plain).abs() > 0.15)
  let mc_value = team_monte_carlo_value(own, opp, 128, 4242UL, turn_limit~)
  // value-tol parity: 実測 |dp-mc|≈0.007。
  assert_true((dp_value - mc_value).abs() < 0.15)
}

///|
/// **Case 2 (value-tol parity, opp 側 ばけのかわ)**: Case 1 の対称。opp = ミミッキュ
/// (ばけのかわ 受け)、own = みず 単発物理アタッカー。own の 1 発が opp の ばけのかわ
/// でブロックされ value が own 不利方向へ動く。DP / MC が value-tol で一致することを
/// pin する。感度ガードも対称に置く。
test "MC/DP value parity under opp-side Disguise (single-hit block)" {
  let mimikyu = mk_pokemon(
    "Mimikyu", "ゴースト", "フェアリー", 300, 60, 80, 60, 100, 50,
  )
  let basher = mk_pokemon("Basher", "みず", "", 260, 150, 100, 95, 100, 120)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let aquatail = mk_move("アクアテール", "みず", @model.Physical, 135)
  let own = [pl_cmb(basher, [aquatail])]
  let opp = [pl_cmb(mimikyu, [splash], ability="ばけのかわ")]
  let opp_plain = [pl_cmb(mimikyu, [splash])]
  let turn_limit = 1
  let dp_value = switching_game_winrate(own, opp, turn_limit)
  let dp_plain = switching_game_winrate(own, opp_plain, turn_limit)
  assert_true((dp_value - dp_plain).abs() > 0.15)
  let mc_value = team_monte_carlo_value(own, opp, 128, 5151UL, turn_limit~)
  assert_true((dp_value - mc_value).abs() < 0.15)
}

///|
/// **Case 3 (非ばけのかわ no-op 証明)**: `disguise_intact_mc` は ability が
/// ばけのかわ 以外なら false を返し、`team_perform_attack` は非 intact パス
/// (単一ロール、従来と bit-exact) を通る。ばけのかわ 配線が非 ばけのかわ チームの
/// rollout に対して「分岐も乱数消費も一切変えない」ことを、
///   (a) ability="" と ability="ふゆう" (どの disguise 分岐にも一致しない中立特性)
///       の同 seed MC 値が bit 一致すること
///   (b) 同 seed で 2 回呼んで bit 一致する決定性
/// の 2 点で pin する。
test "MC no-op: non-Disguise team value is bit-exact across neutral abilities" {
  let attacker = mk_pokemon(
    "PlainA", "みず", "", 220, 120, 100, 100, 100, 100,
  )
  let wall = mk_pokemon("PlainB", "ノーマル", "", 260, 90, 110, 90, 110, 80)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 60)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let opp = [pl_cmb(wall, [splash])]
  let own_empty = [pl_cmb(attacker, [tackle], ability="")]
  let own_levitate = [pl_cmb(attacker, [tackle], ability="ふゆう")]
  let v_empty = team_monte_carlo_value(
    own_empty,
    opp,
    64,
    31415UL,
    turn_limit=4,
  )
  let v_levitate = team_monte_carlo_value(
    own_levitate,
    opp,
    64,
    31415UL,
    turn_limit=4,
  )
  @debug.assert_eq(v_empty, v_levitate)
  let v_again = team_monte_carlo_value(
    own_empty,
    opp,
    64,
    31415UL,
    turn_limit=4,
  )
  @debug.assert_eq(v_empty, v_again)
}

///|
/// **Case 4 (MC 単体 方向性)**: ばけのかわ 持ち defender 入りチームの rollout 値が
/// ability="" 版より defender 有利方向に動くことを pin する。own = ミミッキュ
/// (受け) vs opp = 単発物理アタッカー。ばけのかわ が own の初段被弾を無効化する分、
/// own 側 value が高くなる (DP を経由しない MC 単体の効き確認)。
test "MC direction: Disguise holder improves own-side rollout value" {
  let mimikyu = mk_pokemon(
    "Mimikyu", "ゴースト", "フェアリー", 300, 60, 80, 60, 100, 50,
  )
  let basher = mk_pokemon("Basher", "みず", "", 260, 150, 100, 95, 100, 120)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let aquatail = mk_move("アクアテール", "みず", @model.Physical, 135)
  let own_disguise = [pl_cmb(mimikyu, [splash], ability="ばけのかわ")]
  let own_plain = [pl_cmb(mimikyu, [splash])]
  let opp = [pl_cmb(basher, [aquatail])]
  let v_disguise = team_monte_carlo_value(
    own_disguise,
    opp,
    128,
    6060UL,
    turn_limit=2,
  )
  let v_plain = team_monte_carlo_value(
    own_plain,
    opp,
    128,
    6060UL,
    turn_limit=2,
  )
  // turn_limit=2: ばけのかわ 有りは初段ブロック (chip) → 2 段目でフルダメージ
  // (busted 持続) を受けるが生存し graded value (実測≈-0.39)。ばけのかわ 無しは
  // 2 発フルで KO (実測 -1.0)。busted フラグが 2 ターン目に持続する (= 初段のみ
  // ブロック) ことの間接確認も兼ねる。
  assert_true(v_disguise > v_plain)
}

///|
/// **Case 5 (回帰: codex review 指摘、bug 2)**: MC greedy の move 選択
/// (`pick_best_move`) が `def_disguise_intact` を反映することを直接 pin する。
///
/// バグ: `best_expected_damage` (stay/switch スコアリング) と `team_perform_attack`
/// (実ダメージ) は disguise reduced を見るのに、`pick_best_move` (実際に撃つ技の
/// 選択) だけ素の avg_damage を見ていた。intact な ばけのかわ 相手では高威力単発技は
/// 初段ブロックで chip のみになり、連続技 (chip + 2 段目以降) の方が実効ダメージが
/// 大きい。素の avg で選ぶと「実際は無効化される高威力単発技」を選び、実ダメージと
/// 乖離して DP/MC parity を崩す。
///
/// 検証: 攻撃側に [高威力単発 (アクアテール 135), 連続技 (タネマシンガン 25×2-5)] を
/// 持たせ、ミミッキュ (ゴースト/フェアリー) を defender にする。
///   - `def_disguise_intact=false`: 素の raw で比較 → 高威力単発 (index 0) を選ぶ
///   - `def_disguise_intact=true` : reduced で比較 → 単発は chip のみ、連続技は
///     chip + 後続ヒットで上回る → 連続技 (index 1) を選ぶ
/// 選択が index 0 → 1 に切り替わることで、bug 2 の欠落 (pick_best_move が disguise を
/// 見ない) を pin する。
test "pick_best_move honours def_disguise_intact (bug 2 regression)" {
  let attacker_pkm = mk_pokemon(
    "Attacker", "みず", "", 260, 150, 100, 95, 100, 120,
  )
  let mimikyu_pkm = mk_pokemon(
    "Mimikyu", "ゴースト", "フェアリー", 300, 60, 80, 60, 100, 50,
  )
  // index 0 = 高威力単発 (みず、ゴースト/フェアリーに等倍)。
  let aquatail = mk_move("アクアテール", "みず", @model.Physical, 135)
  // index 1 = 連続技 (くさ、Random2to5、ゴースト/フェアリーに等倍)。
  let bulletseed = mk_move(
    "タネマシンガン",
    "くさ",
    @model.Physical,
    25,
  )
  let attacker = pl_cmb(attacker_pkm, [aquatail, bulletseed])
  let mimikyu = pl_cmb(mimikyu_pkm, [
    mk_move("はねる", "ノーマル", @model.Status, 0),
  ])
  // 非 intact: 素の raw で高威力単発を選ぶ。
  let pick_plain = pick_best_move(attacker, mimikyu, def_disguise_intact=false)
  @debug.debug_inspect(pick_plain, content="Some(0)")
  // intact: 単発は chip のみ、連続技は chip + 後続 → 連続技を選ぶ。
  let pick_intact = pick_best_move(attacker, mimikyu, def_disguise_intact=true)
  @debug.debug_inspect(pick_intact, content="Some(1)")
}
