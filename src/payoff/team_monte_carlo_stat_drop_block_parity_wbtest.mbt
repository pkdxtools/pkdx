///|
/// 技由来の相手ダウン (post-hit stat_effects, target = 1) を クリアボディ が防ぐ経路の
/// DP / MC parity。DP は `with_post_hit_effects`、MC は `apply_stat_effects` で、同じ
/// ブロック helper (`ability_blocks_opp_stat_drop`) を通ることを pin する。
///
/// fixture は 1v1 で技を単一に絞る (強制手)。own は素早さで opp (なきごえ使い) に勝つので、
/// 1 ターン目の攻撃は なきごえ の前に出る。2 ターン目の攻撃だけが A-1 の影響を受ける。
/// 感度ガード: plain は A が -1 で与ダメが落ちるが、クリアボディ は A が 0 のまま。
///
/// horizon は 2 ターン (`regenerator_parity` と同じ posture)。MC は team_rollout を
/// ε=0 で単一 rollout するため、damage roll の抽選が 1 本だけ入る。3 ターン以上では
/// その抽選の影響が積み上がり、DP 期待値との差が tolerance を超える (DP 1.0 に対し
/// MC 単一 0.48 / 16 seed 平均 0.87 を実測)。

///|
fn sdb_tackle() -> @model.Move {
  mk_move("のしかかり", "ノーマル", @model.Physical, 85)
}

///|
/// own の攻撃役 (物理)。素早さ 100 で、`ability` を差し替えてブロックの有無を比べる。
fn sdb_attacker(ability : String) -> Combatant {
  let p = mk_pokemon("BlockAtk", "ノーマル", "", 260, 130, 100, 60, 100, 100)
  pl_cmb(p, [sdb_tackle()], ability=ability)
}

///|
fn sdb_parity_dp(
  own : Array[Combatant],
  opp : Array[Combatant],
  turn_limit : Int,
) -> Double {
  switching_game_winrate(own, opp, turn_limit)
}

///|
fn sdb_parity_mc(
  own : Array[Combatant],
  opp : Array[Combatant],
  turn_limit : Int,
  seed : UInt64,
) -> Double {
  let rng = seeded_rng(seed)
  team_rollout(own, opp, rng, turn_limit~, epsilon=0.0)
}

///|
/// **Case 1 (own クリアボディ × 相手ダウン技 なきごえ)**: 相手の なきごえ (A-1) は
/// クリアボディ で不発。plain は A が下がって与ダメが落ちるので、クリアボディ の方が
/// 有利になる (DP 側の感度ガード)。MC の単一 rollout も DP と一致する。
test "select DP/MC parity: Clear Body blocks opponent's Growl (own side)" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let growler = mk_pokemon("Growler", "ノーマル", "", 260, 60, 100, 60, 100, 60)
  let opp = [pl_cmb(growler, [growl])]
  let own = [sdb_attacker("クリアボディ")]
  let own_plain = [sdb_attacker("")]
  let dp = sdb_parity_dp(own, opp, 2)
  let dp_plain = sdb_parity_dp(own_plain, opp, 2)
  assert_true(dp - dp_plain > 0.03)
  let mc = sdb_parity_mc(own, opp, 2, 74007UL)
  assert_true((dp - mc).abs() < 0.03)
}

///|
/// **Case 2 (own はとむね × 攻撃技の防御ダウン)**: 相手が先に物理技を撃ち、確定の
/// B-1 が次の被弾を重くする。はとむね はその B-1 を不発にするので、plain より
/// 残 HP が多い (DP の感度ガード)。MC の単一 rollout も DP と一致する。
/// 変化技のなきごえ経路 (Case 1) と同じ `apply_stat_effects` を通る。
test "select DP/MC parity: Big Pecks blocks a damaging move's Defense drop" {
  let crunch = mk_move(
    "かみくだく",
    "あく",
    @model.Physical,
    80,
    stat_effects=[@model.StatEffect::{ stat: 1, delta: -1, target: 1 }],
  )
  let hitter = mk_pokemon("Cruncher", "あく", "", 260, 150, 100, 60, 100, 120)
  let opp = [pl_cmb(hitter, [crunch])]
  let wall = mk_pokemon("Pecks", "ノーマル", "", 220, 40, 100, 40, 100, 40)
  let own = [pl_cmb(wall, [sdb_tackle()], ability="はとむね")]
  let own_plain = [pl_cmb(wall, [sdb_tackle()])]
  let dp = sdb_parity_dp(own, opp, 2)
  let dp_plain = sdb_parity_dp(own_plain, opp, 2)
  assert_true(dp - dp_plain > 0.03)
  let mc = sdb_parity_mc(own, opp, 2, 74011UL)
  assert_true((dp - mc).abs() < 0.03)
}

///|
/// **フラワーベール × なきごえ**: 所持者がくさのときだけクリアボディと同じ経路で
/// A-1 を不発にする。フェアリーは plain と DP / MC とも bit 一致 (ブロックが
/// 効かない入力は値を変えない)。
test "select DP/MC parity: Grass Flower Veil blocks Growl, Fairy does not" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let growler = mk_pokemon("Growler", "ノーマル", "", 260, 60, 100, 60, 100, 60)
  let opp = [pl_cmb(growler, [growl])]
  let grass = mk_pokemon("GrassVeil", "くさ", "", 260, 130, 100, 60, 100, 100)
  let own = [pl_cmb(grass, [sdb_tackle()], ability="フラワーベール")]
  let own_plain = [pl_cmb(grass, [sdb_tackle()])]
  let dp = sdb_parity_dp(own, opp, 2)
  let dp_plain = sdb_parity_dp(own_plain, opp, 2)
  assert_true(dp - dp_plain > 0.03)
  let mc = sdb_parity_mc(own, opp, 2, 74021UL)
  assert_true((dp - mc).abs() < 0.03)
  let fairy = mk_pokemon("FairyVeil", "フェアリー", "", 260, 130, 100, 60, 100, 100)
  let own_fairy = [pl_cmb(fairy, [sdb_tackle()], ability="フラワーベール")]
  let own_fairy_plain = [pl_cmb(fairy, [sdb_tackle()])]
  let dp_fairy = sdb_parity_dp(own_fairy, opp, 2)
  let dp_fairy_plain = sdb_parity_dp(own_fairy_plain, opp, 2)
  @debug.assert_eq(dp_fairy, dp_fairy_plain)
  let mc_fairy = sdb_parity_mc(own_fairy, opp, 2, 74022UL)
  let mc_fairy_plain = sdb_parity_mc(own_fairy_plain, opp, 2, 74022UL)
  @debug.assert_eq(mc_fairy, mc_fairy_plain)
}

///|
/// **フラワーベール × 登場時いかく**: くさの所持者は lead の A-1 を受けない。
/// フェアリーは plain と bit 一致。DP の初期 lead と MC の lead 配線が同じタイプを見る。
/// いかくは毎ヒットに効くので、MC は 64 試行の平均で DP と |dp-mc| < 0.02 に揃える。
test "select DP/MC parity: Grass Flower Veil blocks lead Intimidate, Fairy does not" {
  let intim = mk_pokemon("Intim", "ノーマル", "", 260, 150, 100, 60, 100, 80)
  let opp = [pl_cmb(intim, [sdb_tackle()], ability="いかく")]
  let grass = mk_pokemon("GrassVeil", "くさ", "", 260, 130, 100, 60, 100, 100)
  let own = [pl_cmb(grass, [sdb_tackle()], ability="フラワーベール")]
  let own_plain = [pl_cmb(grass, [sdb_tackle()])]
  let dp = sdb_parity_dp(own, opp, 2)
  let dp_plain = sdb_parity_dp(own_plain, opp, 2)
  // いかくは毎ターンの物理与ダメに乗る。単一 rollout の 16 段階乱数は DP 期待値から
  // 0.03 をわずかに超える (実測 |dp-mc| ≈ 0.031)。64 試行の平均で揃える。
  // 感度ガードはブロックが無いと |dp-plain| ≈ 0.07 なので、MC が plain 側に
  // 張り付くと 0.02 を超えて落ちる。
  assert_true(dp - dp_plain > 0.05)
  let mc = team_monte_carlo_value(own, opp, 64, 74031UL, turn_limit=2)
  assert_true((dp - mc).abs() < 0.02)
  let fairy = mk_pokemon("FairyVeil", "フェアリー", "", 260, 130, 100, 60, 100, 100)
  let own_fairy = [pl_cmb(fairy, [sdb_tackle()], ability="フラワーベール")]
  let own_fairy_plain = [pl_cmb(fairy, [sdb_tackle()])]
  @debug.assert_eq(
    sdb_parity_dp(own_fairy, opp, 2),
    sdb_parity_dp(own_fairy_plain, opp, 2),
  )
  @debug.assert_eq(
    sdb_parity_mc(own_fairy, opp, 2, 74032UL),
    sdb_parity_mc(own_fairy_plain, opp, 2, 74032UL),
  )
}
