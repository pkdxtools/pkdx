///|
/// しろいハーブ (held_item_stat_reset.mbt) の unit 仕様。DP / MC の配線は
/// switching_game_white_herb_wbtest.mbt と team_monte_carlo_white_herb_parity_wbtest.mbt。

///|
fn wh_holder(item : String) -> Combatant {
  let c = im_combatant(im_pokemon("WhHolder"), [], ability="")
  { ..c, item, }
}

///|
test "しろいハーブ: 判定対象は名前が完全一致する しろいハーブ だけ" {
  @debug.assert_eq(item_clears_negative_stages("しろいハーブ"), true)
  @debug.assert_eq(item_clears_negative_stages("メンタルハーブ"), false)
  @debug.assert_eq(item_clears_negative_stages("きあいのタスキ"), false)
  @debug.assert_eq(item_clears_negative_stages(""), false)
}

///|
test "apply_held_item_stat_reset: 負のランクを全て 0 に戻して消費、正のランクは残す" {
  let team = [wh_holder("しろいハーブ")]
  let ranks = [-2, -1, 0, 3, -1]
  let consumed = [false]
  apply_held_item_stat_reset(team, 0, [100], ranks, consumed)
  @debug.assert_eq(ranks, [0, 0, 0, 3, 0])
  @debug.assert_eq(consumed, [true])
}

///|
test "apply_held_item_stat_reset: 負のランクが無ければ何もせず未消費のまま" {
  let team = [wh_holder("しろいハーブ")]
  let ranks = [1, 0, 2, 0, 0]
  let consumed = [false]
  apply_held_item_stat_reset(team, 0, [100], ranks, consumed)
  @debug.assert_eq(ranks, [1, 0, 2, 0, 0])
  @debug.assert_eq(consumed, [false])
}

///|
test "apply_held_item_stat_reset: 消費済みの所持者は no-op (2 回目は効かない)" {
  let team = [wh_holder("しろいハーブ")]
  let ranks = [-1, 0, 0, 0, 0]
  let consumed = [true]
  apply_held_item_stat_reset(team, 0, [100], ranks, consumed)
  @debug.assert_eq(ranks, [-1, 0, 0, 0, 0])
  @debug.assert_eq(consumed, [true])
}

///|
test "apply_held_item_stat_reset: 別の持ち物 / ひんし / 範囲外スロットは no-op" {
  let ranks = [-1, 0, 0, 0, 0]
  let sash = [wh_holder("きあいのタスキ")]
  let sash_consumed = [false]
  apply_held_item_stat_reset(sash, 0, [100], ranks, sash_consumed)
  @debug.assert_eq(ranks, [-1, 0, 0, 0, 0])
  @debug.assert_eq(sash_consumed, [false])
  // ひんし の所持者は判定しない (Showdown の getAllActive は ひんし を含まない)
  let herb = [wh_holder("しろいハーブ")]
  let herb_consumed = [false]
  apply_held_item_stat_reset(herb, 0, [0], ranks, herb_consumed)
  @debug.assert_eq(ranks, [-1, 0, 0, 0, 0])
  @debug.assert_eq(herb_consumed, [false])
  // 範囲外スロットは落ちずに no-op
  apply_held_item_stat_reset(herb, 3, [100], ranks, herb_consumed)
  @debug.assert_eq(ranks, [-1, 0, 0, 0, 0])
  @debug.assert_eq(herb_consumed, [false])
}

///|
test "apply_held_item_stat_reset_pair: 両側を独立に判定する" {
  let my_team = [wh_holder("しろいハーブ")]
  let opp_team = [wh_holder("")]
  let my_ranks = [0, -2, 0, 0, 0]
  let opp_ranks = [-1, 0, 0, 0, 0]
  let my_consumed = [false]
  let opp_consumed = [false]
  apply_held_item_stat_reset_pair(
    my_team, 0, [100], my_ranks, my_consumed,
    opp_team, 0, [100], opp_ranks, opp_consumed,
  )
  // 自分の herb は解除、相手は持ち物なしなので -1 のまま
  @debug.assert_eq(my_ranks, [0, 0, 0, 0, 0])
  @debug.assert_eq(my_consumed, [true])
  @debug.assert_eq(opp_ranks, [-1, 0, 0, 0, 0])
  @debug.assert_eq(opp_consumed, [false])
}

///|
test "consumed_item_view: 消費済みの所持者は itemless、未消費は元の個体をそのまま返す" {
  let team = [wh_holder("しろいハーブ")]
  @debug.assert_eq(consumed_item_view(team, 0, [true]).item, "")
  @debug.assert_eq(consumed_item_view(team, 0, [false]).item, "しろいハーブ")
  // 配列が短い (legacy fixture) 場合は未消費扱い
  @debug.assert_eq(consumed_item_view(team, 0, []).item, "しろいハーブ")
}
