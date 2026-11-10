///|
/// 再生力の DP / MC parity。
///
/// 1 ターン目はオーバーヒート（C-2）が控えの打点を上回るので、DP も MC も撃つ。
/// 被弾で再生力持ちが削れたあと、2 ターン目は C-2 の打点が控えを下回り、
/// 居座ると大ダメージを受ける。DP（minimax）も MC（greedy, ε=0）もここで交代し、
/// 出ていく側が最大 HP / 3（上限クランプ込み）を回復する。turn_limit=2 なので
/// ランクが戻った先発へ切り返す手は存在しない。
///
/// 2 体チームの 1 回回復は value を約 0.04 動かす。ε-greedy の探索を載せると
/// その差分が埋もれるため、MC は `team_rollout` を ε=0 で 1 本だけ回す
/// （`team_monte_carlo_value` の中身と同じ遷移）。配線が MC に無いと mc は
/// plain 側に落ち、|dp - mc| が tol を超える。

///|
fn rg_overheat() -> @model.Move {
  mk_move(
    "オーバーヒート",
    "ほのお",
    @model.Special,
    130,
    stat_effects=[@model.StatEffect::{ stat: 2, delta: -2, target: 0 }],
  )
}

///|
fn rg_parity_teams(
  lead_ability : String,
) -> (Array[Combatant], Array[Combatant]) {
  // 実測 (turn_limit=2, ε=0):
  //   T1 UseMove: lead 150→82、相手 450→326、C=-2
  //   T2 Switch: lead 82+50→132（150/3、上限 150）、bench 220→178
  //   T2 Stay:   lead 82→14、相手 326→265
  // Switch の value が Stay を上回り、かつ -2 の打点は控えを下回る。
  let lead = mk_pokemon("RegenLead", "ほのお", "", 150, 40, 90, 200, 90, 180)
  let bench = mk_pokemon("Bench", "ドラゴン", "", 220, 40, 160, 190, 160, 20)
  let wall = mk_pokemon("Wall", "ノーマル", "", 450, 130, 100, 40, 160, 30)
  let overheat = rg_overheat()
  let dragon = mk_move("りゅうのはどう", "ドラゴン", @model.Special, 110)
  let tickle = mk_move("たいあたり", "ノーマル", @model.Physical, 60)
  let regen_side = [
    pl_cmb(lead, [overheat], ability=lead_ability),
    pl_cmb(bench, [dragon]),
  ]
  let wall_side = [pl_cmb(wall, [tickle])]
  (regen_side, wall_side)
}

///|
fn rg_parity_dp(own : Array[Combatant], opp : Array[Combatant]) -> Double {
  switching_game_winrate(own, opp, 2)
}

///|
fn rg_parity_mc(
  own : Array[Combatant],
  opp : Array[Combatant],
  seed : UInt64,
) -> Double {
  let rng = seeded_rng(seed)
  team_rollout(own, opp, rng, turn_limit=2, epsilon=0.0)
}

///|
test "select DP/MC parity: Regenerator heals the switched-out lead (own side)" {
  let (own, opp) = rg_parity_teams("再生力")
  let (own_plain, _opp_plain) = rg_parity_teams("")
  let dp = rg_parity_dp(own, opp)
  let dp_plain = rg_parity_dp(own_plain, opp)
  assert_true(dp - dp_plain > 0.03)
  let mc = rg_parity_mc(own, opp, 73001UL)
  assert_true((dp - mc).abs() < 0.03)
}

///|
test "select DP/MC parity: Regenerator heals the switched-out lead (opp side)" {
  let (opp, own) = rg_parity_teams("再生力")
  let (opp_plain, _own_plain) = rg_parity_teams("")
  let dp = rg_parity_dp(own, opp)
  let dp_plain = rg_parity_dp(own, opp_plain)
  // 相手が回復するとこちらの value は下がる。
  assert_true(dp_plain - dp > 0.03)
  let mc = rg_parity_mc(own, opp, 73002UL)
  assert_true((dp - mc).abs() < 0.03)
}

///|
test "MC no-op: non-Regenerator switch does not change rollout value" {
  let (empty, opp) = rg_parity_teams("")
  let (stench, _opp2) = rg_parity_teams("あくしゅう")
  let v_empty = rg_parity_mc(empty, opp, 73003UL)
  let v_stench = rg_parity_mc(stench, opp, 73003UL)
  @debug.assert_eq(v_empty, v_stench)
  let v_again = rg_parity_mc(empty, opp, 73003UL)
  @debug.assert_eq(v_empty, v_again)
}
