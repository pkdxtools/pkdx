///|
/// 外れた自己消費技 (崩れ技 = `crash_hp_loss` / てっていこうせん = `max_hp_recoil_loss`) を
/// 同じ attempt 段で解決する `miss_self_loss_outcomes` の検証 (DP)。
///
/// - 片側ずつ / 両側とも外れた場合に、崩れと反動の両方の消費が入る (取りこぼし・二重計上なし)。
/// - 両者外し (両方 行動しない) で反動は対象の生死を見るため、行動順で結果が変わる。同速は両順序を平均。
/// - 着弾ターンに眠らされた てっていこうせん の使用者は反動を受けない (崩れと同じ規則)。
/// helper: `crash_mon` / `crash_turn` / `crash_mass` / `crash_hjk_never_hits` / `crash_spore`
/// (switching_game_crash_wbtest)。

///|
fn msl_steel_never_hits() -> @model.Move {
  mk_move("てっていこうせん", "はがね", @model.Special, 140, accuracy=0)
}

///|
/// 外れた てっていこうせん (自分: 200 → 100) と外れた とびひざげり (相手: 200 → 100) が同ターンに
/// 起きると、両方の消費が入る。対象は互いに生存したままなので行動順に依らない (1 leaf 確率 1)。
test "miss self-loss DP: 外れたてっていこうせんと外れた崩れ技は両方の自己消費が入る" {
  let own = crash_mon("MslOwn", [msl_steel_never_hits()], 200)
  let opp = crash_mon("MslOpp", [crash_hjk_never_hits()], 200)
  let outs = crash_turn([own], [opp], 200)
  @debug.assert_eq(
    crash_mass(outs, fn(s) { s.my_hps[0] == 100 && s.opp_hps[0] == 100 }),
    1.0,
  )
}

///|
/// 両者がてっていこうせんを外す (自分 100 HP、相手 200 HP、各 最大 200 → 反動 100)。
/// 自分が速い: 自分の反動で 100 → 0 (ひんし)。相手の外れ反動は対象 (自分) 不在で入らない → 相手 200。
test "miss self-loss DP: 両者てっていこうせん外しで自分が速いと、倒れた後の相手の反動は入らない" {
  let fast = crash_mon("MslFast", [msl_steel_never_hits()], 200, spe=150)
  let slow = crash_mon("MslSlow", [msl_steel_never_hits()], 200, spe=50)
  let outs = crash_turn([fast], [slow], 100)
  @debug.assert_eq(
    crash_mass(outs, fn(s) { s.my_hps[0] == 0 && s.opp_hps[0] == 200 }),
    1.0,
  )
}

///|
/// 同じ両者外しで相手が速い: 相手が先に 200 → 100 の反動を受け、対象 (相手) は生存するので
/// 自分の反動が入り 100 → 0。行動順で相手 HP が 200 / 100 と分かれる (感度)。
test "miss self-loss DP: 両者てっていこうせん外しで相手が速いと、相手の反動が先に入り自分の反動も入る" {
  let slow = crash_mon("MslSlow", [msl_steel_never_hits()], 200, spe=50)
  let fast = crash_mon("MslFast", [msl_steel_never_hits()], 200, spe=150)
  let outs = crash_turn([slow], [fast], 100)
  @debug.assert_eq(
    crash_mass(outs, fn(s) { s.my_hps[0] == 0 && s.opp_hps[0] == 100 }),
    1.0,
  )
}

///|
/// 同速の両者てっていこうせん外しは両順序を 0.5 ずつ平均する (確率質量 1 を保つ)。
test "miss self-loss DP: 同速の両者てっていこうせん外しは両順序を平均する" {
  let own = crash_mon("MslTieOwn", [msl_steel_never_hits()], 200, spe=100)
  let opp = crash_mon("MslTieOpp", [msl_steel_never_hits()], 200, spe=100)
  let outs = crash_turn([own], [opp], 100)
  @debug.assert_eq(
    crash_mass(outs, fn(s) { s.my_hps[0] == 0 && s.opp_hps[0] == 200 }),
    0.5,
  )
  @debug.assert_eq(
    crash_mass(outs, fn(s) { s.my_hps[0] == 0 && s.opp_hps[0] == 100 }),
    0.5,
  )
}

///|
/// 着弾ターンの眠り: 遅い てっていこうせん の使用者は先の相手の ねむりごな で眠らされ、外しても
/// 反動を受けない (`action_blocked_by_fresh_status` の枝)。HP 200 のまま、眠りは Sleep(1) に進む。
/// 崩れ技の `crash DP: 外れた崩れの使用者が着弾ターンに眠らされると...` と同じ規則。
test "miss self-loss DP: 外れたてっていこうせんの使用者が着弾ターンに眠らされると反動なし・Sleep(1)" {
  let slow = crash_mon("MslSlow", [msl_steel_never_hits()], 200, spe=50)
  let fast_spore = crash_mon("MslSpore", [crash_spore()], 200, spe=150)
  let outs = crash_turn([slow], [fast_spore], 200)
  @debug.assert_eq(
    crash_mass(outs, fn(s) { s.my_hps[0] == 200 && s.my_status[0] == @model.Sleep(1) }),
    1.0,
  )
}
