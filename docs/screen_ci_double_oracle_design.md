# 設計メモ: 信頼区間で打ち切る screening と double oracle

コードはまだ変えない。#174 マージ後に、並列化メモ（`docs/screen_parallel_design.md`）と一緒に実装する想定。既定の `pkdx select` の選出 JSON は変えない。新しい設定を付けたときだけ、試行を早く止め、double oracle で落とした選出を戻す。

## 狙い

Phase A は今、全 3600 セルを固定 `trials`（自動昇格では 1000）まで回す。勝率が明らかに低い選出のセルは、早い段階で「keep_top の境界より下」と分かる。そこを止める。境界付近は最後まで回す。止めたことで Nash の台から外れた選出があれば、double oracle がベストレスポンスとして検出して戻す。

ロールアウトの値域は `[-1, +1]`（幅 2）。trial が独立なら Hoeffding で、平均の半幅は

```
eps(T) = sqrt( 2 * ln(2/α) / T )
```

α = 0.05 なら `eps(32) ≈ 0.48`、`eps(128) ≈ 0.24`、`eps(1000) ≈ 0.086`。絶対幅を 0.05 未満にするには T > 1000 が要るので、「全セルを一定幅まで」では 1000 回より短くならない。打ち切りは**選出スコアの分離**で行う。

## アルゴリズム

候補は選出 1 つ（行列の行または列）とする。セルは候補スコアの材料である。

1. **バッチ。** `screen_min_trials` まで、全セルを同じ trial 添字 `0 .. min-1` で回す。その後は `screen_batch` 本ずつ足す。上限は `screen_max_trials`（既定 1000。今の `trials` と同じ）。
2. **セル平均。** セル `(i,j)` を `T_ij` 本で止めたときの平均を `A_ij`、半幅を `eps_ij = eps(T_ij)` とする。未計算の trial は足さない。
3. **スコア。** いまの点推定 `A` で `screen_nash_scores` と同じ Nash を解く。行スコア `s_i = Σ_j q_j A_ij`。半幅は `e_i = Σ_j q_j eps_ij`（`q` は確率なので `e_i ≤ max_j eps_ij`）。列も同様に符号を反転して扱う。Nash が解けないバッチでは、そのバッチのスコア更新をスキップして次のバッチへ進む（Phase B の失敗を `EmptyCombatants` にしない。最終バッチでも失敗なら、今と同じくエラー）。
4. **境界。** 行を `s_i` の降順に並べ、残す本数 `k = ceil(n * keep_top)` の境界を、k 番目と k+1 番目のスコアとする。行 `i` が凍結できるのは、保持側の下端の下限と、捨てる側の上限が `screen_sep_margin` 以上離れたとき。
   - 保持が確定: `s_i - e_i >= s_(k+1) + e_(k+1) + margin`
   - 除外が確定: `s_i + e_i <= s_(k) - e_(k) - margin`
   - どちらでもない行は境界。境界行に属するセルだけ次のバッチを回す。凍結した行のセルは `T` を増やさない。
5. **終了。** 境界行が無くなったか、全セルが `screen_max_trials` に達したら Phase A を終える。点推定 `A` で通常どおり `retain_top_indices` する。
6. **MC double oracle（補修）。** 制限ゲームは残した行・列。値を `v` とする。
   - 残っていない行 `i` について `s_i` を、相手の Nash `q`（制限ゲーム上。捨てた列の `q` は 0）で計算する。サンプルが `screen_min_trials` 未満のセルは、そのセルだけ min まで埋めてから計算する。
   - `s_i > v + screen_oracle_gap` なら行 `i` を戻す。列も対称。
   - 戻した行・列のセルは `screen_max_trials` まで埋める（境界だったセルは既に多めに回っているので、足りない分だけ）。
   - Nash を解き直す。増分が無くなるか `screen_oracle_iters` に達したら止める。達しても増分が残るときは、残った増分行を強制的に 1 回足してから DP に進む（無限ループにしない）。
7. **DP refine。** 補修後の行・列だけ、今の Phase C（`switching_game_winrate`、refine turn_limit）で埋める。
8. **DP oracle は 1 パスに限る。** 全 60 行を DP で評価し直すと screening の意味が無くなる。MC oracle で戻した集合に対し、DP 行列の Nash を解いたあと、**MC スコアが境界から `screen_oracle_gap` 以内の行だけ**を DP の相手戦略に対して追加評価する（相手サポートの列数 × その行数のセル）。そこで DP 値が `v_dp + screen_oracle_gap` を超えた行だけを足し、その行の DP セルを埋めて Nash を 1 回だけ解き直す。2 周目はしない。

決定性: バッチ番号と trial 添字が止まってよい行の集合を決める。乱数は壁時計もワーカー番号も見ない。同じ入力なら同じ `T_ij` と同じ平均になる。

試行の RNG は、並列メモで書いた **trial インデックスシード**をこのモードの定義にする。`trial_seed(mc_seed XOR cell_idx, t)`。打ち切り位置が変わっても、残した trial `t` の値はフルランの `t` と一致する。今日の「1 本の ChaCha8 を継続する」`team_monte_carlo_value` とは平均が一致しない。既定オフの理由はこれである。

## 変える場所

| 場所 | 変更 |
|---|---|
| `src/payoff/team_monte_carlo.mbt` | `team_rollout_seeded(own, opp, trial_seed, turn_limit)` を足す。既存 `team_monte_carlo_value` の ChaCha8 継続は触らない |
| `src/payoff/monte_carlo.mbt` | `splitmix` の trial 混ぜ。ベンチの `select_bench.mbt` にある splitmix をここに寄せるなら、ベンチ側はそれを呼ぶ（結果定義が変わらない範囲） |
| `src/payoff/screened_switching_game.mbt` | `team_payoff_matrix_screened` の Phase A を、設定がオフなら今のループのままにする。オンならバッチ打ち切り + MC oracle。`screen_nash_scores` / `retain_top_indices` は点推定用にそのまま使う |
| `src/payoff/cli_select.mbt` | `team_payoff_model` の任意フィールド、またはトップレベル `screen_ci` オブジェクトを解析。`__select-shard` はセルの `(trial_lo, trial_hi)` を受け取れるようにする。行シャードのまま、セルごとに `T` が違っても、各セルの trial 区間が決まっていれば並列と両立する |
| `src/payoff/semantics.mbt` | 既定値。自動昇格の `ScreenedSwitchingGame(1000, 42, 0.3, n)` は CI オフのまま |
| テスト | `screened_switching_game_test.mbt` に「オフなら全セル bit-exact」「オンでも oracle 後の MC exploitability」。`parallel_select_test.mbt` に「シャードしても `T_ij` と平均が一致」 |

`value`（DP）と `solve_with_fallback` は変えない。

## 設定項目

JSON に任意の `screen_ci` を足す。無い、または `"mode": "off"` のときは今と同一経路。

```json
"screen_ci": {
  "mode": "hoeffding",
  "alpha": 0.05,
  "min_trials": 32,
  "batch": 32,
  "max_trials": 1000,
  "sep_margin": 0.02,
  "oracle_gap": 0.02,
  "oracle_iters": 4
}
```

- `max_trials` を省略したときは、モデル文字列の `trials` を使う。
- `min_trials >= max_trials` は打ち切らない（全セルが max まで回る）が、RNG は trial インデックスシードなので、**オフの経路とはまだ一致しない**。ビット一致の比較はオフ経路だけで行う。
- `sep_margin` と `oracle_gap` は勝率単位（`[-1,1]` の値）。0 にするとノイズで oracle が全行を戻し、フル評価に近づく。

## 既存の選出が変わらないことの確かめ方

1. `screen_ci` 無し、または `mode=off` で、今の `team_payoff_matrix_screened` と全セル `FiniteMatrix.at` が一致するテストを足す。`keep_top=1` の short-circuit もそのまま。
2. 自動昇格の定数（1000 / 42 / 0.3）は CI を付けない。`select_golden_test.mbt` と `cli_select` の golden はオフのまま再実行する。
3. オンにしたときはビット一致を要求しない。代わりに、同じシードで max まで回した参照行列 `A_full` をテスト内の小さい盤面（3v3 や 4v4、trials は 64 以下）で作り、oracle 後の混合戦略 `σ` の exploitability `max_i (A_full σ_col)_i - v` が `oracle_gap` 以下であることを見る。これを「参照行列の上では、落とした手が gap を超えて後悔しない」の定義にする。
4. DP oracle を通した最終 `SelectResult` については、小さい盤面でオフ経路の `value` との差をログするだけで、一致は必須にしない。差の許容はベンチで見てから決める。

## ベンチでの比較

`scripts/bench_select.sh` のケースを増やさず、同じ `select_6v6_screened_prod` を 2 回取る。

| 実行 | 設定 | 見るもの |
|---|---|---|
| 基準 | CI オフ、trials=1000、tl=5。#174 後の再計測が基準 | 壁時計、位相（screening / nash-scoring / dp-refine）、`value`、確率が 1% を超える選出の集合 |
| 候補 | `screen_ci.mode=hoeffding`、max_trials=1000、min=32、batch=32 | 同じ項目に加え、セルあたりの `T` の平均・最大、oracle が戻した行数・列数、DP で追加した行数 |

比較の合格ライン（実装時の目安。このメモでは測っていない）:

- 候補の壁時計が基準の Phase A を下回る。対称で分離しないチームでは max まで回るので、ほぼ同じ時間で終わればよい（遅くならないこと）。
- 選出集合の対称差を報告する。空である必要はない。空でないときは、基準の行列に対する候補戦略の exploitability を一緒に出す。
- 並列メモの `--parallel=auto` と直交なので、第三の実行「CI オン + parallel=auto」は、上の 2 つが取れてからでよい。

公式ベースラインの `select_6v6_screened_prod` は自分と相手が同じ構築で value が 0 である。スコアが分離しにくく、CI の短縮は小さい見込みで、17.1 分の本体は refine の DP ノードである。CI は Phase A を縮める案であり、Phase C が残る。効果の確認には、ベンチの status ペアのような非対称 6v6 を 1 本足す方がよい。足すのは実装時で、このメモではケース名だけ予約する: `select_6v6_screened_prod_asym`。
