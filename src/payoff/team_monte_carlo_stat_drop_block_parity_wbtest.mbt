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
