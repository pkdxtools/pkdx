///|
/// しろいハーブ の DP / MC parity。DP は `switching_game_winrate` (exact)、MC は
/// `team_monte_carlo_value` (rollout の平均)。fixture は 1v1 で技を単一に絞る (強制手) ので、
/// 行動の探索は値に影響せず、MC と DP の差はダメージ乱数だけになる。
///
/// 配線の対応: DP は `with_post_hit_effects` / `transition_with_cache` の判定点、MC は
/// `team_apply_post_hit` 後 / 登場 (lead・switch) 後 / EOT 後の判定点で同じ
/// `apply_held_item_stat_reset` を通る。
/// 感度ガード: 持ち物なしとの DP 差が出ることを先に確認する (判定が効いている証拠)。

///|
fn wp_brawl() -> @model.Move {
  mk_move("インファイト", "かくとう", @model.Physical, 60, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 3, delta: -1, target: 0 },
  ])
}

///|
fn wp_hit() -> @model.Move {
  mk_move("たいあたり", "ノーマル", @model.Physical, 80)
}

///|
/// 持ち物を指定した 1 体 (`pl_cmb` は item が空なので差し替える)。
fn wp_cmb(
  name : String,
  moves : Array[@model.Move],
  spe : Int,
  ability : String,
  item : String,
) -> Combatant {
  let p = mk_pokemon(name, "ノーマル", "", 260, 100, 100, 60, 100, spe)
  let c = pl_cmb(p, moves, ability=ability)
  { ..c, item, }
}

///|
/// **Case 1 (自己ダウン後の被弾)**: own は速く B-1 / D-1 の自己ダウン技を撃つ。
/// しろいハーブ があれば 1 ターン目の技の直後に解除され、2 ターン目の被弾は B 0 で受ける。
/// 持ち物なしは B -1 のまま受けるので、DP の値は持ち物なしより own に有利になる。
test "select DP/MC parity: しろいハーブ で自己ダウン後の被弾が解除される (own 側)" {
  let opp = [wp_cmb("Hitter", [wp_hit()], 100, "", "")]
  let herb_own = [wp_cmb("Herb", [wp_brawl()], 200, "", "しろいハーブ")]
  let plain_own = [wp_cmb("Plain", [wp_brawl()], 200, "", "")]
  let dp_herb = switching_game_winrate(herb_own, opp, 2)
  let dp_plain = switching_game_winrate(plain_own, opp, 2)
  assert_true(dp_herb - dp_plain > 0.02)
  let mc_herb = team_monte_carlo_value(herb_own, opp, 256, 74007UL, turn_limit=2)
  assert_true((dp_herb - mc_herb).abs() < 0.05)
}

///|
/// **Case 2 (登場時いかく)**: own の いかく が相手 (しろいハーブ, 物理) の A を -1 し、
/// 判定で即解除される。DP と MC (lead 配線) が一致し、持ち物なしとは値が動く。
test "select DP/MC parity: しろいハーブ は登場時いかくの A-1 を解除する (lead)" {
  let intim = [wp_cmb("Intim", [wp_hit()], 100, "いかく", "")]
  let herb_opp = [wp_cmb("Herb", [wp_hit()], 100, "", "しろいハーブ")]
  let plain_opp = [wp_cmb("Plain", [wp_hit()], 100, "", "")]
  let dp_herb = switching_game_winrate(intim, herb_opp, 2)
  let dp_plain = switching_game_winrate(intim, plain_opp, 2)
  assert_true(dp_plain - dp_herb > 0.01)
  let mc_herb = team_monte_carlo_value(intim, herb_opp, 256, 74011UL, turn_limit=2)
  assert_true((dp_herb - mc_herb).abs() < 0.05)
}
