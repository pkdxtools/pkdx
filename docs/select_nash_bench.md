# pkdx select / Nash ベンチ

ツールチェーン更新後に rebase して再計測予定（現在の数値は暫定）。

この文書の数値は、下の計測環境で release ビルドを 1 回走らせた暫定値である。MoonBit のバージョンが変わると codegen と実行時間が変わる。正式ベースラインは、ツールチェーン更新が main に入ったあとに同じ手順で取り直す。

## 計測環境（暫定）

| 項目 | 値 |
|---|---|
| moon | `moon 0.1.20261028 (e1e1f15 2026-10-28)` |
| uname | Linux 6.12.94+ x86_64 |
| CPU | Intel Xeon, 4 vCPU |
| MemTotal | 16,387,280 kB |
| バイナリ | `_build/native/release/build/src/main/main.exe`（`moon build --target native --release src/main`） |
| 並列 | なし。`select-bench` は in-process（`pkdx select --parallel=1` と同じ呼び出し） |
| damage cache | なし（`disk = None`）。SQLite のヒットで時間が揺れない |
| RSS | GNU time の `Maximum resident set size`（KB）。プロセス起動を含む |

`moon 0.1.20261028` は `moon.mod.json` を拒否する。計測のときだけ、作業ツリーで `moon fmt` による `moon.mod` 移行と、`.mooncakes/` 内の依存パッケージの同様の移行を行った。その差分はコミットしていない。ソルバの戻り値を変える変更は入っていない。

`vm_hwm_kb` 列は -1 になる。`@db.read_file` はファイルサイズで読むため、サイズ 0 の `/proc/self/status` を取れない。ピーク RSS はスクリプトが付ける `gnu_time_max_rss_kb` を使う。

## 実行手順

リポジトリルートで、このブランチを release ビルドした `main.exe` があること。

```bash
bash scripts/configure_native_link_flags.sh
moon build --target native --release src/main
bash scripts/bench_select.sh -t smoke     # テストと同じ小さいケース
bash scripts/bench_select.sh -t default   # 中規模 + 状態異常ペア + 60 選出の浅い DP
bash scripts/bench_select.sh -t full      # 6v6 tl=3 と、auto-upgrade と同じ screening 形。長い
bash scripts/bench_select.sh -c nash_rps_3
bash scripts/bench_select.sh -c select_status_heavy -n 1
```

スクリプトはケースごとにプロセスを分け、TSV に GNU time の max RSS を足す。seed はケース内で固定（行列は `42`、screening は `42`、退化フィクスチャは `tests/fixtures/nash_simplex_failure_60x60.json`）。同じバイナリなら `value` / `solver` / `dp_*` は繰り返して一致する。時間と RSS は一致しない。

スモークは `moon test --target native src/payoff/select_bench_test.mbt`。時間の上限は assert しない。2 回走らせて value・ソルバ・DP カウンタが一致すること、状態異常セルが状態を剥がしたペアより DP ノードが多いこと、を見る。

`select-bench` は `auto_upgrade_team_model` を通さない。`pkdx select` が `switching_game` の N ≥ 4 で screening に昇格する経路は、`select_6v6_screened_prod` が同じ定数（trials=1000, seed=42, keep=0.3, refine tl=5, MC tl=5）で直接呼ぶ。

## 呼び出し経路

```
pkdx select
  run_select_typed
    parse team_payoff_model
    auto_upgrade_team_model
      SwitchingGame(n) かつ n >= AUTO_SCREEN_TURN_LIMIT (4)
        → ScreenedSwitchingGame(1000, 42, 0.3, n)
      明示 screened_switching_game:... はそのまま
    compute_select_with_team_model
      parallel > 1 かつ screened
        → team_payoff_matrix_screened_parallel（子プロセス。bit-exact）
      screened
        → team_payoff_matrix_screened
      それ以外
        → team_payoff_matrix_switching
    build_select_result
      → solve_with_fallback   # 選出行列の 1 回だけ
```

`AUTO_SCREEN_TURN_LIMIT` は `src/payoff/semantics.mbt` で **4**。skill 文書の「N ≥ 5 で昇格」とは一致していない。コードが正。

### 選出行列の作り方

シングル 6 体、3 体選出、先頭付き。選出数は `6 × C(5, 2) = 60`。セル数は `60² = 3600`。

`SwitchingGame`（`team_payoff_matrix_switching`）は全セルを `switching_game_winrate` で埋める。位相名 `dp-full`。

`ScreenedSwitchingGame`（`team_payoff_matrix_screened`）:

1. `keep_top >= 1` なら screening をスキップし、上の full DP に落ちる。
2. Phase A `screening`。全セルを `team_monte_carlo_value`。seed は `mc_seed XOR cell_idx`。MC の turn_limit は `MC_TURN_LIMIT = 5`（CLI から上書きできない。bench の small ケースだけ関数引数で 1 にしている）。
3. Phase B `nash-scoring`。`@nash.solve_zero_sum` を **1 回**。fallback はない。失敗は `EmptyCombatants`。Nash 戦略で行・列をスコアし、`ceil(n * keep_top)` を残す。
4. Phase C `dp-refine`。残った部分行列だけ `switching_game_winrate`。refine turn_limit はモデルの第 4 引数。

### 各ソルバが使われる条件

選出行列（`solve_with_fallback`、`src/payoff/nash_solver.mbt`）だけが fallback を持つ。

1. `@nash.solve_zero_sum`（`ushironoko/nash-mbt` 0.1.1）
   - `max_i min_j A = min_j max_i A` が `SADDLE_TOL = 1e-10` 以内なら純戦略を返して simplex に入らない。戻り値は `Optimal` なので、bench の `solver` は `simplex` のままになる（鞍点と本 simplex は区別しない）。
   - そうでなければ shift-and-normalize のあと、行 LP と列 LP を二相 simplex（Bland、`MAX_ITERS = 5000`）で解く。
2. `SimplexFailure` のときだけ `fictitious_play(iterations)`。既定 `iterations = 10000`。`exploitability < tol`（既定 0.05）なら採用。
3. まだ超えていれば `mwu`。`η = sqrt(ln(max(rows, cols)) / iterations)`。同じ tol。
4. 両方だめなら `NashFallbackExhausted`。bench は `solver=exhausted` として記録し、スイートは続行する。
5. `InconsistentGame` / `Infeasible` / `Unbounded` は fictitious play に落ちない。`InnerError` になる。

DP ノード（`value`、`switching_game_turn.mbt`）は `@nash.solve_zero_sum` を直接呼ぶ。fallback しない。失敗時は 0 を返し `silent_dp_fallback_count` を増やす。

ノード内の分岐:

- キャッシュヒットは展開しない。
- 行動行列を埋める。子は常に `alpha = -1, beta = +1`。
- `lower >= beta` で残り行を捨てる（`pruned`）。既定 beta が 1 なので、ほぼ「このノードが +1 確定」のときだけ。
- `upper <= alpha` で `alpha_pruned`。既定 alpha が -1 なのでほぼ発火しない。
- `upper - lower <= 1e-10` なら鞍点。LP しない。
- それ以外だけ LP。

Phase B の screening Nash も fallback しない。bench の `screen_lp` はここに成功した回数。

### 計算量の支配項

| 経路 | 支配項 |
|---|---|
| full DP | `Nsel² × (セルあたりの展開ノード) × |A|² × 確率分岐`。`Nsel = n × C(n-1, k-1)`。ノードの大半は鞍点で、LP は非鞍点だけ |
| screening Phase A | `Nsel² × trials × MC_TURN_LIMIT × (ターンあたりの行動)` |
| screening Phase C | `(keep × Nsel)² × DP(refine_tl)`。keep=0.3 なら 60 選出で約 18² = 324 セル（全体の 9%） |
| 選出レベルの Nash | 行列 1 枚。成功する 60×60 simplex は数十 ms。反復上限で落ちると fictitious play が `O(iterations × n²)`、既定 10000 回 |
| ノード内 LP | 行動数 × 行動数。技 2 + 交代だと一辺が数個。60×60 よりずっと小さい |

## 暫定結果

release、上の環境。時間は ms。`dp_*` は最終 repeat の 1 回分。RSS は GNU time の KB。

| case | tier | wall ms | RSS KB | matrix | solver | dp_nodes | dp_hits | dp_lp | dp_saddle | dp_pruned | screen_lp |
|---|---|---:|---:|---|---|---:|---:|---:|---:|---:|---:|
| nash_rps_3 | smoke | 0.0026 | 3736 | 3×3 | simplex | 0 | 0 | 0 | 0 | 0 | 0 |
| nash_skew_8 | smoke | 0.014 | 3752 | 8×8 | simplex | 0 | 0 | 0 | 0 | 0 | 0 |
| nash_skew_20 | default | 0.42 | 3648 | 20×20 | simplex | 0 | 0 | 0 | 0 | 0 | 0 |
| nash_near_copy_20 | default | 0.36 | 3712 | 20×20 | simplex | 0 | 0 | 0 | 0 | 0 | 0 |
| nash_skew_60 | default | 30.2 | 3872 | 60×60 | simplex | 0 | 0 | 0 | 0 | 0 | 0 |
| nash_degenerate_60 | default | 271 | 4084 | 60×60 | fictitious_play | 0 | 0 | 0 | 0 | 0 | 0 |
| select_3v3_tl1 | smoke | 0.38 | 3816 | 3×3 | simplex | 9 | 0 | 0 | 9 | 0 | 0 |
| select_screened_3v3 | smoke | 0.33 | 3824 | 2×2 | simplex | 4 | 0 | 0 | 4 | 0 | 1 |
| select_4v4_tl2 | default | 305 | 3840 | 12×12 | simplex | 3744 | 144 | 16 | 3728 | 0 | 0 |
| select_status_heavy | default | 526 | 4008 | 12×12 | simplex | 5328 | 234 | 672 | 4656 | 0 | 0 |
| select_6v6_tl1 | default | 114 | 3932 | 60×60 | simplex | 3600 | 0 | 0 | 3600 | 0 | 0 |
| select_6v6_screened_small | default | 217 | 4080 | 18×18 | simplex | 324 | 0 | 0 | 324 | 0 | 1 |
| select_6v6_tl3 | full | 52132 | 4024 | 60×60 | simplex | 875600 | 127600 | 9570 | 866030 | 0 | 0 |
| select_6v6_screened_prod | full | >180000（打ち切り） | — | — | — | — | — | — | — | — | — |

`nash_degenerate_60` の exploitability は `4.7e-4`（tol 0.05 未満）。fictitious play で採用され、MWU には進んでいない。

`select_6v6_screened_small` の位相: screening 182 ms（84%）、nash-scoring 24.6 ms（11%、60×60 の simplex）、dp-refine 10.2 ms（5%）。

`select_6v6_screened_prod` は 180 秒で打ち切った。small の screening 182 ms を trials `1000/8` と MC turn `5/1` で伸ばすと Phase A だけでおおよそ 100 秒超になり、refine tl=5 がそれに乗る。位相内訳は取れていない。

RSS はどのケースも約 4 MB。876k ノードの tl=3 でも増えていない。このサイズではメモリは支配項ではない。

## 状態異常ケース

`select_status_heavy` は 4 体、2 技、turn_limit 2。先頭 4 枠で、いま payoff が付与できる `StatusKind` をすべて含む。

| 枠 | タイプ | 技 |
|---|---|---|
| 0 | ノーマル | 10まんボルト（まひ 30%）、ねむりごな（命中 75%、ねむり） |
| 1 | みず | かえんほうしゃ（やけど 30%）、どくどく（命中 90%、もうどく） |
| 2 | かくとう | どくづき（どく 40%）、あくび（命中 85%、あくび） |
| 3 | エスパー | れいとうビーム（ねむり 30%）、おにび（命中 85%、やけど） |

タイプは でんき / ほのお / はがね / どく を避けてある。まひ・やけど・どくがタイプ免疫で消えない。こんらん・こおり・メロメロは未実装。

ペア `select_4v4_tl2` は同じ種族値・威力・命中で `status_effect` だけ外している。

| | plain | status | 比 |
|---|---:|---:|---:|
| wall | 305 ms | 526 ms | 1.72× |
| dp_nodes | 3744 | 5328 | 1.42× |
| dp_lp | 16 | 672 | 42× |
| 鞍点の割合 | 99.6% | 87.4% | |

追加の 221 ms は、ノード +1584 と LP +656 の両方に乗っている。LP 回数は大きく増えるが、行動行列が小さいので壁時計はノード展開の方がまだ大きい。こんらん・こおり・メロメロが入ると、同じ形で確率分岐と「鞍点でないノード」が増える。比較は `select_status_heavy` を固定 seed で取り直す。

## ボトルネック

1. **turn_limit ≥ 3 の DP ノード展開。** 6v6 tl=3 は 52.1 秒、875,600 ノード。うち鞍点 98.9%（866,030）、LP 1.1%（9,570）、枝刈り 0。ヒット率 `127600 / (875600+127600) = 12.7%`。時間のほとんどは遷移とハッシュマップで、simplex ではない。選出レベルの Nash は 0.005 ms（ミラーで鞍点）。
2. **auto-upgrade の MC screening。** `pkdx select` の既定 `switching_game`（tl=5）と tl≥4 は screening に入る。production 形は 180 秒で終わらなかった。small 形では壁時計の 84% が Phase A。
3. **状態異常で鞍点率が落ち、ノード内 LP が増える。** 上の 42×。tl=2 の 4v4 ではまだ壁時計の主因ではない。分岐が増えると 1 と重なる。
4. **選出レベルの simplex 失敗。** 60×60 の成功例は 30 ms。ピンした退化行列は 271 ms で fictitious play。52 秒の DP や 180 秒超の screening の横では小さい。
5. **ノード αβ は既定の窓では動いていない。** 計測した全ケースで `dp_pruned = 0`。子は常に `(-1, +1)` で呼ばれる。β 打ち切りは `lower >= 1` のときだけ。

## 改善候補

優先度は、この暫定計測で壁時計に効く順。効果は同じフィクスチャを同じ release で取り直したときのオーダー。回帰は勝率（`value`）と選出分布（`row_strategy` / 残る選出）が変わるか。

1. **screening の Phase A を短くする、または既定で `--parallel=auto` を使う。** 既定の `pkdx select`（tl≥4）が 180 秒を超えている。parallel は既存で bit-exact のテストがある。コア数にほぼ比例して Phase A と Phase C が縮む見込み（4 vCPU なら数分の一）。アルゴリズムは不変なので選出の回帰は低い。RSS はシャード数だけ増える。trials を 1000 から 200 に減らすと Phase A は約 5 倍短いが、足切り順が変わり選出が変わり得る。回帰は中。
2. **DP の再訪を増やす（状態キーはそのまま）。** tl=3 のヒット率 13%。同じ状態の再計算をハッシュで避ける余地が、展開コストの大半。キーを変えないメモの改善なら `value` はビット一致のままにできる。回帰は低。キーをパックし損ねると別状態が衝突し、勝率が変わる。回帰は高。
3. **子へ αβ の窓を渡す。** いま枝刈り 0。窓を伝播できれば tl≥3 と状態異常ケースのノードが減る。現状のビット一致は「子が exact」に依存している。窓の誤りは勝率と選出の両方を変える。回帰は高。効果の上限は大きいが、この PR では入れていない。
4. **状態異常・将来のこんらん / こおり / メロメロの分岐を、キャッシュキーが同じなら畳む。** `select_status_heavy` は LP が 42 倍、壁時計は 1.7 倍。新しい独立な Bernoulli が同程度ずつ乗ると、tl=3 の 52 秒に対してノードと非鞍点 LP がさらに増える。確率を変える実装は勝率の回帰が高い。比較用にこのケースを残す。
5. **fictitious play を exploitability < tol で早期停止する。** 効くのは simplex が落ちた 60×60 だけで、271 ms が数十 ms になる程度。tol を変えないなら選出は tol 以内の別戦略になり得る。回帰は低〜中。DP / screening の後でよい。

鞍点 fast path は既に働いている。tl=1 の 3600 ノードはすべて鞍点で LP 0。ノード内 simplex の微最適化は tl=3 の 52 秒をほとんど動かさない。
