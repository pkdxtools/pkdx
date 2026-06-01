///|
/// Stage 14 — 回復技モデル投入後の性能 (cached_states) ベースラインを記録し、
/// 退行を検知する観測テスト。Plan の方針通り、**速度改善は本 PR では行わない**:
/// 単に「現状値を記録して、将来のリファクタで肥大化したら検知する」ガード。
///
/// 計測対象: `switching_game_winrate_stats` の `stats.cached_states`
/// (= 探索した distinct SwitchingGameState 数)。runtime ではなく state count
/// にしている理由は、CI machine 間で wall-clock がブレやすいのに対し
/// state count は決定論的だから (memoization key は state value のみに依存)。
///
/// **ベースライン (Stage 14 段階での実測値):**
/// - 2v2 (HP=200, atk=100, def=100, recover 入り, turn_limit=5):
///     cached_states = 702 → `BASELINE_2V2 = 702`
/// - 3v3 (3 types, recover 入り, turn_limit=3):
///     cached_states = 122 → `BASELINE_3V3 = 122`
///
/// **退行検知しきい値**: ベースラインの **2 倍** を超えたら fail。
/// 2x は「state 表現を 1 軸増やしたら state space が乗算的に倍増しうる」のを
/// 1 軸分許容する保守的な余白。これ以上肥大化したら設計の見直しが必要なサイン。
///
/// 速度改善 (αβ pruning 強化 / state hash 最適化 / EOT 順序の早期 fail-fast)
/// は別 PR で行い、そのタイミングでベースライン値を下方修正する。

///|
const BASELINE_2V2 : Int = 702

///|
const BASELINE_3V3 : Int = 122

///|
/// 2v2 perf baseline: 片チームに じこさいせい (FixedFraction(1, 2)) を 1 体配置
/// し、もう一方は たいあたり のみ。回復技あり版の cached_states を観測する。
///
/// 観測したベースライン値で `BASELINE_2V2` を初期化済み。退行検知だけが目的
/// なので、値そのものは下方修正自由。実装変更で増減した場合は
/// `BASELINE_2V2` を更新するだけで pass する。
test "perf baseline (healing): 2v2 with Recover cached_states ≤ 2 × baseline" {
  let recover : @model.Move = {
    ..mk_move("じこさいせい", "ノーマル", @model.Status, 0),
    healing: Some(@model.FixedFraction(1, 2)),
  }
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 30)
  let a0 = mk_combatant(
    mk_pokemon("Healer", "ノーマル", "", 200, 100, 100, 100, 100, 120),
    [recover, tackle],
  )
  let a1 = mk_combatant(
    mk_pokemon("A1", "ノーマル", "", 200, 100, 100, 100, 100, 100),
    [tackle],
  )
  let b0 = mk_combatant(
    mk_pokemon("B0", "ノーマル", "", 200, 100, 100, 100, 100, 110),
    [tackle],
  )
  let b1 = mk_combatant(
    mk_pokemon("B1", "ノーマル", "", 200, 100, 100, 100, 100, 90),
    [tackle],
  )
  let (v, stats, _) = switching_game_winrate_stats([a0, a1], [b0, b1], 5)
  println(
    "perf 2v2 healing tl=5: value=\{v}, cached_states=\{stats.cached_states}, hits=\{stats.hits}, misses=\{stats.misses} (baseline=\{BASELINE_2V2})",
  )
  assert_true(!v.is_nan())
  assert_true(v >= -1.0 && v <= 1.0)
  assert_true(stats.cached_states > 0)
  // 退行検知: ベースラインの 2 倍を超えたら state explosion なので fail。
  assert_true(stats.cached_states <= BASELINE_2V2 * 2)
}

///|
/// 3v3 perf baseline: 3 体片チームに じこさいせい (FixedFraction(1, 2)) を
/// 持たせ、3 types 異なる healing-less チームと対戦。turn_limit=3 で CI 内に
/// 収まる範囲で計測。
test "perf baseline (healing): 3v3 with Recover cached_states ≤ 2 × baseline" {
  let recover : @model.Move = {
    ..mk_move("じこさいせい", "ノーマル", @model.Status, 0),
    healing: Some(@model.FixedFraction(1, 2)),
  }
  let mk = fn(
    name : String,
    t1 : String,
    hp : Int,
    atk : Int,
    spe : Int,
    extra : Array[@model.Move],
  ) -> Combatant {
    let moves : Array[@model.Move] = [mk_move("m", t1, @model.Physical, 30)]
    for m in extra {
      moves.push(m)
    }
    mk_combatant(mk_pokemon(name, t1, "", hp, atk, 100, atk, 100, spe), moves)
  }
  let team_a = [
    mk("A0", "ほのお", 150, 100, 120, [recover]),
    mk("A1", "みず", 150, 100, 100, []),
    mk("A2", "くさ", 150, 100, 110, []),
  ]
  let team_b = [
    mk("B0", "でんき", 150, 100, 115, []),
    mk("B1", "じめん", 150, 100, 95, []),
    mk("B2", "ノーマル", 150, 100, 105, []),
  ]
  let (v, stats, _) = switching_game_winrate_stats(team_a, team_b, 3)
  println(
    "perf 3v3 healing tl=3: value=\{v}, cached_states=\{stats.cached_states}, hits=\{stats.hits}, misses=\{stats.misses} (baseline=\{BASELINE_3V3})",
  )
  assert_true(!v.is_nan())
  assert_true(v >= -1.0 && v <= 1.0)
  assert_true(stats.cached_states > 0)
  assert_true(stats.cached_states <= BASELINE_3V3 * 2)
}
