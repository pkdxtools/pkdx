///|
/// まけんき / かちき の DP / MC parity。
///
/// fixture は 1v1 で、各側の技を単一に絞る (強制手) ことで DP の minimax と MC の
/// greedy が同じ軌道を辿るようにする。各 parity テストは (1) 反応の有無で value が
/// 有意に動く感度ガード、(2) DP と MC (ε=0 の単一 rollout) の value 一致、の 2 段で
/// pin する。regenerator parity と同じ posture。
///
/// 配線の確認対象:
///   - 交代時いかく (lead) → `apply_intimidate_on_entry` の `_` arm → まけんき /
///     かちき の反応。DP / MC とも同じ helper を通る。
///   - 相手ダウン技 (なきごえ) → `apply_stat_effects` (target = 1) → 反応。DP は
///     `with_post_hit_effects`、MC は `apply_stat_effects` の直接呼び出しで共有。
///   - 相手ダウン技の複数能力ダウン (くすぐる) は 1 技 1 反応 (Case 6)。

///|
fn dc_tackle() -> @model.Move {
  mk_move("のしかかり", "ノーマル", @model.Physical, 85)
}

///|
/// own / opp の攻撃役 (物理)。素早さ 100 で、`ability` を差し替えて反応の有無を比べる。
fn dc_attacker(ability : String) -> Combatant {
  let p = mk_pokemon("DefiantAtk", "ノーマル", "", 260, 130, 100, 60, 100, 100)
  pl_cmb(p, [dc_tackle()], ability=ability)
}

///|
/// いかく持ちの物理役。素早さ 90 (= attacker より遅い) で先攻を固定する。
fn dc_intimidator() -> Combatant {
  let p = mk_pokemon("IntimOpp", "ノーマル", "", 260, 110, 100, 60, 100, 90)
  pl_cmb(p, [dc_tackle()], ability="いかく")
}

///|
/// 特殊役。かちき の反応 (特攻 +2) を見るため、特殊技のみを持つ。
fn dc_special(ability : String) -> Combatant {
  let p = mk_pokemon("CompSpecial", "ノーマル", "", 260, 80, 100, 130, 100, 100)
  let beam = mk_move("ハイパーボイス", "ノーマル", @model.Special, 90)
  pl_cmb(p, [beam], ability=ability)
}

///|
fn dc_parity_dp(
  own : Array[Combatant],
  opp : Array[Combatant],
  turn_limit : Int,
) -> Double {
  switching_game_winrate(own, opp, turn_limit)
}

///|
fn dc_parity_mc(
  own : Array[Combatant],
  opp : Array[Combatant],
  turn_limit : Int,
  seed : UInt64,
) -> Double {
  let rng = seeded_rng(seed)
  team_rollout(own, opp, rng, turn_limit~, epsilon=0.0)
}

///|
/// **Case 1 (own まけんき × lead いかく)**: own の攻撃役が まけんき。相手 lead の
/// いかくで A -1 → まけんき 攻撃 +2 (実効 A +1)。plain (特性なし) は A -1 のまま
/// なので、攻撃ダメージが大きく違う。
test "select DP/MC parity: Defiant reacts to lead Intimidate (own side)" {
  let own = [dc_attacker("まけんき")]
  let own_plain = [dc_attacker("")]
  let opp = [dc_intimidator()]
  let dp = dc_parity_dp(own, opp, 2)
  let dp_plain = dc_parity_dp(own_plain, opp, 2)
  // 感度ガード: まけんき の反応で value が動く (A +1 vs A -1)。
  assert_true(dp - dp_plain > 0.03)
  let mc = dc_parity_mc(own, opp, 2, 74001UL)
  assert_true((dp - mc).abs() < 0.03)
}

///|
/// **Case 2 (opp まけんき × own いかく)**: Case 1 の対称。相手側の まけんき が
/// own のいかくで攻撃 +1 になるので、own の value は plain 相手より下がる。
test "select DP/MC parity: Defiant reacts to lead Intimidate (opp side)" {
  let opp = [dc_attacker("まけんき")]
  let opp_plain = [dc_attacker("")]
  let own = [dc_intimidator()]
  let dp = dc_parity_dp(own, opp, 2)
  let dp_plain = dc_parity_dp(own, opp_plain, 2)
  assert_true(dp_plain - dp > 0.03)
  let mc = dc_parity_mc(own, opp, 2, 74002UL)
  assert_true((dp - mc).abs() < 0.03)
}

///|
/// **Case 3 (own かちき × lead いかく)**: 特殊役の かちき は、相手 lead の
/// いかく (A -1) を受けても特攻 +2 する。特殊技の攻撃が plain より大きくなる。
test "select DP/MC parity: Competitive raises SpA after lead Intimidate (own side)" {
  let own = [dc_special("かちき")]
  let own_plain = [dc_special("")]
  let opp = [dc_intimidator()]
  let dp = dc_parity_dp(own, opp, 2)
  let dp_plain = dc_parity_dp(own_plain, opp, 2)
  assert_true(dp - dp_plain > 0.03)
  let mc = dc_parity_mc(own, opp, 2, 74003UL)
  assert_true((dp - mc).abs() < 0.03)
}

///|
/// **Case 4 (own まけんき × 相手ダウン技 なきごえ)**: 相手の なきごえ (相手 A-1) を
/// 技由来の stat_effects (target = 1) で受ける経路。DP は `with_post_hit_effects`、
/// MC は `apply_stat_effects` で、同じ反応 helper を通ることを pin する。
/// 相手は素早さ 60 で後攻。2 ターン目の攻撃から反応の効果が出る。
test "select DP/MC parity: Defiant reacts to opponent's Growl (own side)" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let growler = mk_pokemon("Growler", "ノーマル", "", 260, 60, 100, 60, 100, 60)
  let opp = [pl_cmb(growler, [growl])]
  let own = [dc_attacker("まけんき")]
  let own_plain = [dc_attacker("")]
  let dp = dc_parity_dp(own, opp, 2)
  let dp_plain = dc_parity_dp(own_plain, opp, 2)
  assert_true(dp - dp_plain > 0.03)
  let mc = dc_parity_mc(own, opp, 2, 74004UL)
  assert_true((dp - mc).abs() < 0.03)
}

///|
/// **Case 5 (MC no-op)**: 反応を起こすダウン・いかくがない相手では、まけんき の有無で
/// MC rollout 値が bit 一致する (特性の配線が無関係な経路に影響しないことの control)。
test "MC no-op: Defiant absent from drop events leaves rollout value bit-exact" {
  let wall = mk_pokemon("Wall", "ノーマル", "", 260, 60, 100, 60, 100, 60)
  let opp = [pl_cmb(wall, [dc_tackle()])]
  let v_def = dc_parity_mc([dc_attacker("まけんき")], opp, 2, 74005UL)
  let v_none = dc_parity_mc([dc_attacker("")], opp, 2, 74005UL)
  @debug.assert_eq(v_def, v_none)
  let v_again = dc_parity_mc([dc_attacker("まけんき")], opp, 2, 74005UL)
  @debug.assert_eq(v_def, v_again)
}

///|
/// **Case 6 (own まけんき × 相手 くすぐる = 2 能力ダウン)**: くすぐる (A-1 / B-1) は
/// 1 回の技なので反応は 1 回 (攻撃 +2)。1 能力だけ下げる なきごえ (A-1) と同じ
/// 反応量になるので、DP 値は一致する (own の B-1 は相手が攻撃しないので値に効かない)。
/// MC も同じ値に収束することを pin する。
test "select DP/MC parity: Defiant reacts once to opponent's Tickle (2 stats, own side)" {
  let tickle = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let tickler = mk_pokemon("Tickler", "ノーマル", "", 260, 60, 100, 60, 100, 60)
  let growler = mk_pokemon("Growler", "ノーマル", "", 260, 60, 100, 60, 100, 60)
  let opp_tickle = [pl_cmb(tickler, [tickle])]
  let opp_growl = [pl_cmb(growler, [growl])]
  let own = [dc_attacker("まけんき")]
  let own_plain = [dc_attacker("")]
  let dp_tickle = dc_parity_dp(own, opp_tickle, 2)
  let dp_growl = dc_parity_dp(own, opp_growl, 2)
  let dp_plain = dc_parity_dp(own_plain, opp_tickle, 2)
  // 感度ガード: まけんき の反応で value が動く (A +1 vs A -1)。
  assert_true(dp_tickle - dp_plain > 0.03)
  // 1 技 1 反応: 2 能力ダウンでも 1 能力ダウン (なきごえ) と同じ value。
  assert_true((dp_tickle - dp_growl).abs() < 0.000000001)
  let mc = dc_parity_mc(own, opp_tickle, 2, 74006UL)
  assert_true((dp_tickle - mc).abs() < 0.03)
}
