# pkdx select / Nash ベンチ

#174（toolchain と依存の更新）と #176（`pkdx nash solve` の fallback）が main に入ったあと、`origin/main`（`18d94d6`）へ rebase して取り直した公式ベースライン。各ケースは別プロセスで複数回実行し、壁時計は中央値を載せる。

その後 `origin/main`（`41f2996`、#189 の `pkdx select --parallel` を含む）を merge した。下の表は `18d94d6` での計測値のまま。merge 後の quick 再確認は「再確認（41f2996 取り込み後）」節。

## 計測環境

| 項目 | 値 |
|---|---|
| moon | `moon 0.1.20261028 (e1e1f15 2026-10-28)` |
| moonc | `v0.10.18+6c83a7f62`（2026-10-28）。配布ピンは今後この moonc 形式の URL に切り替わる |
| moonrun | `0.1.20261028 (e1e1f15 2026-10-28)` |
| feature flags | `rr_moon_mod,rr_moon_pkg` |
| uname | Linux 6.12.94+ x86_64 |
| CPU | Intel Xeon, 4 vCPU |
| MemTotal | 16,387,280 kB |
| バイナリ | `_build/native/release/build/src/main/main.exe`（`moon build --target native --release src/main`） |
| 依存 | `moon.mod`: `moonbitlang/x@0.5.6`, `mizchi/markdown@0.8.4`, `mizchi/jsonschema@0.8.1`, `mizchi/admiral@0.1.1`, `ushironoko/nash-mbt@0.1.1` |
| 並列 | なし。`select-bench` は in-process（`pkdx select --parallel=1` と同じ呼び出し）で、`--parallel` は付けない。`pkdx select --parallel` 自体は #189 で main に入った（bench の対象外）。4 vCPU は使っていない |
| 回数 | 最初のプロセスの壁時計が 1 秒未満のケースは 5 プロセス、それ以外は 3 プロセス。各プロセスは `--repeats 1`。表の壁時計はプロセス間の中央値、min / max もプロセス間。`scripts/bench_select.sh` の既定（`-p auto`、`-n 1`）がこの手順 |
| damage cache | なし（`disk = None`）。SQLite のヒットで時間が揺れない |
| RSS | GNU time 1.9 の `Maximum resident set size`（KB）。プロセス起動を含む。表は中央値。GNU time（`/usr/bin/time -v`）が無い環境では、スクリプトの RSS 列は `-` になる（壁時計と値は出る） |

この計測時の `moon version --all` 全文（パスは実行環境のホーム）:

```
moon 0.1.20261028 (e1e1f15 2026-10-28) ~/.moon/bin/moon
moonc v0.10.18+6c83a7f62 (2026-10-28) ~/.moon/bin/moonc
moonrun 0.1.20261028 (e1e1f15 2026-10-28) ~/.moon/bin/moonrun

Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

`scripts/bench_select.sh` は毎回 `moon version --all` を実行し、各行を `# ` 付きで結果の先頭に書く。TSV の `moonc` 列には 2 番目のフィールド（`v0.10.18+6c83a7f62`）だけを繰り返す。`pkdx select-bench` 自身の TSV は数値のままにして、1 行目がヘッダである前提を壊さない。

Toolchain は `scripts/install_moon.sh`（pin `scripts/moon-version` = `0.10.18+6c83a7f62`）。ビルドは `scripts/moon_build_native.sh --release`。mooncakes の旧 `moon.mod.json` はローカルキャッシュ上だけで `moon tool migrate-manifest` される。ソルバの戻り値を変える変更は、このベースライン取得では入っていない。`dp_nodes` / `dp_lp` / `dp_saddle` は全試行で一致した。

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
bash scripts/bench_select.sh -c select_status_heavy -p 1   # 1 プロセスだけ（確認用）
```

`-p` はケースあたりのプロセス数。既定 `auto` は最初のプロセスの壁時計が 1 秒未満なら 5、それ以外は 3。`-n` は 1 プロセス内の反復回数（既定 1）。どちらも数値を変えるのは回数だけで、solver の結果は変わらない。

スクリプトはケースごとにプロセスを分け、TSV の末尾に `wall_ms_max`（プロセス間の最大）、`procs`（プロセス数）、GNU time の max RSS（中央値）と `moonc` 版を足す。`wall_ms_median` / `wall_ms_min` はプロセス間の中央値と最小。`value` / `solver` / `dp_*` などの決定的な列は 1 つ目のプロセスの値で、2 つ目以降と違えば stderr に警告を出す。結果を残すときは標準出力をそのまま保存する。先頭の `# moon version --all:` ブロックが `moon version --all` の全文で、表の `moonc` 列がコンパイラ版（例: `v0.10.18+6c83a7f62`）である。

```bash
bash scripts/bench_select.sh -t default | tee /tmp/pkdx_select_bench.tsv
```

単体で `moon version --all` を見るとき:

```bash
moon version --all
```

seed はケース内で固定（行列は `42`、screening は `42`、退化フィクスチャは `tests/fixtures/nash_simplex_failure_60x60.json`）。同じバイナリなら `value` / `solver` / `dp_*` は繰り返して一致する。時間と RSS は一致しない。

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
      parallel > 1 かつ screened かつ input_path 非空   # #189
        → team_payoff_matrix_screened_parallel（子プロセス。bit-exact）
      screened
        → team_payoff_matrix_screened
      それ以外（SwitchingGame を含む。--parallel を付けても in-process）
        → team_payoff_matrix_switching
    build_select_result
      → solve_with_fallback   # 選出行列の 1 回だけ
```

`AUTO_SCREEN_TURN_LIMIT` は `src/payoff/semantics.mbt` で **4**。skill 文書（`.claude/skills/nash/SKILL.md`、`references/payoff_semantics.md`）の「N ≥ 5 で昇格」とは一致していない。コードが正。skill 側の修正はこの PR の範囲外。

### 選出行列の作り方

シングル 6 体、3 体選出、先頭付き。選出数は `6 × C(5, 2) = 60`。セル数は `60² = 3600`。

`SwitchingGame`（`team_payoff_matrix_switching`）は全セルを `switching_game_winrate` で埋める。位相名 `dp-full`。

`ScreenedSwitchingGame`（`team_payoff_matrix_screened`）:

1. `keep_top >= 1` なら screening をスキップし、上の full DP に落ちる。
2. Phase A `screening`。全セルを `team_monte_carlo_value`。seed は `mc_seed XOR cell_idx`。MC の turn_limit は既定 `MC_TURN_LIMIT = 5`。入力 JSON の `mc_turn_limit` で上書きできる（`pkdx select` に対応する CLI フラグは無い）。bench の small ケースだけ関数引数で 1 にしている。
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

## ベースライン

release、上の環境。時間はプロセス内の `wall_ms`。ばらつきは別プロセス間の最小・最大。`dp_*` は全試行で同一。RSS は GNU time の KB（中央値）。

| case | n | wall 中央値 ms | min | max | RSS | solver | dp_nodes | dp_lp | dp_saddle |
|---|---:|---:|---:|---:|---:|---|---:|---:|---:|
| nash_rps_3 | 5 | 0.0158 | 0.0099 | 0.0358 | 3708 | simplex | 0 | 0 | 0 |
| nash_skew_20 | 5 | 0.394 | 0.373 | 0.502 | 3716 | simplex | 0 | 0 | 0 |
| nash_near_copy_20 | 5 | 0.375 | 0.367 | 0.396 | 3720 | simplex | 0 | 0 | 0 |
| nash_skew_60 | 3 | 30.53 | 30.20 | 30.80 | 3844 | simplex | 0 | 0 | 0 |
| nash_degenerate_60 | 3 | 275.0 | 272.6 | 277.0 | 4100 | fictitious_play | 0 | 0 | 0 |
| select_4v4_tl2 | 3 | 318.9 | 318.4 | 319.0 | 3816 | simplex | 3744 | 16 | 3728 |
| select_status_heavy | 3 | 548.1 | 545.9 | 548.3 | 3952 | simplex | 5328 | 672 | 4656 |
| select_6v6_tl1 | 3 | 119.7 | 118.1 | 119.8 | 3888 | simplex | 3600 | 0 | 3600 |
| select_6v6_screened_small | 3 | 221.5 | 220.7 | 222.9 | 4080 | simplex | 324 | 0 | 324 |
| select_6v6_tl3 | 3 | 54799 | 54053 | 54865 | 4032 | simplex | 875600 | 9570 | 866030 |
| select_6v6_screened_prod | 3 | 1023886 | 1008863 | 1034452 | 60832 | simplex | 13260281 | 171298 | 13088983 |

`select_6v6_tl3` は鞍点 866030 / 875600 = 98.9%、LP 9570 / 875600 = 1.09%、枝刈り 0、ヒット 127600（ヒット率 12.7%）。`select_6v6_screened_prod` は鞍点 98.7%、LP 1.29%、枝刈り 0、ヒット 3,918,255（ヒット率 22.8%）、`screen_lp = 1`。`nash_degenerate_60` の value は `-0.04246`（以前と同じ）。fictitious play で採用され、MWU には進んでいない。

`select_6v6_screened_prod` の 13,260,281 ノードは tl=3 全探索 875,600 の 15.1 倍。時間も 54.8 秒の 18.7 倍（1024 秒）で、refine tl=5 のノード展開が壁時計の本体である。small 形で Phase A が 84% だった比率は、この production 形には当てはまらない。

RSS は tl=3 まで約 4 MB。production screening は中央値 60.8 MB。

### #174 前（1 回、同じ moonc、依存更新前）との差

以前の列は moon `0.1.20261028`、更新前の依存で 1 回だけ測った値。ノード数が一致するものはアルゴリズム出力が動いていない。

| case | before ms | after 中央値 ms | 差 | dp_nodes / lp / saddle |
|---|---:|---:|---:|---|
| nash_rps_3 | 0.0026 | 0.0158 | 相対差は大きいが絶対値は 0.01 ms 台。計測ノイズ | 0 / 0 / 0（一致） |
| nash_skew_20 | 0.42 | 0.394 | −6% | 一致 |
| nash_near_copy_20 | 0.36 | 0.375 | +4% | 一致 |
| nash_skew_60 | 30.2 | 30.53 | +1.1% | 一致 |
| nash_degenerate_60 | 271 | 275.0 | +1.5% | 一致。solver は fictitious_play |
| select_4v4_tl2 | 305 | 318.9 | +4.6% | 3744 / 16 / 3728（一致） |
| select_status_heavy | 526 | 548.1 | +4.2% | 5328 / 672 / 4656（一致）。鞍点 87.4%、LP 12.6% |
| select_6v6_tl1 | 114 | 119.7 | +5.0% | 3600 / 0 / 3600（一致） |
| select_6v6_screened_small | 217 | 221.5 | +2.1% | 324 / 0 / 324（一致） |
| select_6v6_tl3 | 52132（52.1 s） | 54799（54.8 s） | +5.1% | 875600 / 9570 / 866030（一致）。鞍点 98.9%、LP 1.09% |
| select_6v6_screened_prod | 180000 で打ち切り、未完 | 1023886（17.1 min） | 以前は完走していない | 今回初めてノードを記録。鞍点 98.7%、LP 1.29% |

見立て: payoff の DP / MC ソースは `19e5315` から `18d94d6` の間で `cli_nash` 以外変わっていない。moonc も同じ pin。依存は `moonbitlang/x` が 0.4.41 から 0.5.6 になった。差は −6%〜+5.1% の範囲にあり（`nash_rps_3` を除く）、ノード数はすべてビット単位で一致する。`nash_skew_20` の −6% と他の + 側の差は、1 回計測対 3 回中央値のばらつきの範囲で、アルゴリズムの退行ではないと見ている。`nash_rps_3` は相対差が大きいが、中央値 0.016 ms で、このタイマーの分解能の中に入る。

production screening が「遅くなった」わけではない。以前は 180 秒で殺していた。完走すると 17.1 分で、tl=3 と同じくノードの約 99% が鞍点、LP は約 1.3% である。長い理由は refine turn_limit=5 の展開ノード 1320 万である。

### 再確認（41f2996 取り込み後）

#189（`pkdx select --parallel`）を含む `origin/main`（`41f2996`）を merge したあとの quick 再確認。`scripts/bench_select.sh -t default` を 1 回実行した。`select_6v6_tl3` と `select_6v6_screened_prod` は時間が長いので今回は対象外。

| 項目 | 値 |
|---|---|
| moon / moonc / moonrun | 上と同じ（`moon version --all` の出力は一致） |
| バイナリ | `moon build --target native --release src/main`（merge コミット） |
| 環境 | Linux 6.12.113+ x86_64、8 vCPU（他のジョブと共用。load 1〜3）、GNU time なし（RSS 列は `-`） |
| 回数 | 各ケース 5 プロセス（最初のプロセスが 1 秒未満）。各プロセス `--repeats 1` |

壁時計は上の 4 vCPU の表と比べない。同じケースの壁時計は −9%〜+16% の範囲でずれた（`nash_rps_3` は 0.01 ms 台なので除く）。負荷・CPU 数・プロセス数のどれが効いたかは切り分けていない。見るべきはノード数・solver・value の一致で、表の 6 ケースはすべて一致した。

| case | 中央値 ms | min | max | solver | dp_nodes | dp_lp | dp_saddle | 18d94d6 の dp_nodes / lp / saddle |
|---|---:|---:|---:|---|---:|---:|---:|---|
| nash_rps_3 | 0.0121 | 0.0105 | 0.0162 | simplex | 0 | 0 | 0 | 一致（0 / 0 / 0） |
| nash_skew_8 | 0.0248 | 0.0228 | 0.0347 | simplex | 0 | 0 | 0 | 表なし |
| select_3v3_tl1 | 0.366 | 0.357 | 0.417 | simplex | 9 | 0 | 9 | 表なし |
| select_screened_3v3 | 0.339 | 0.329 | 0.550 | simplex | 4 | 0 | 4 | 表なし（screen_lp = 1） |
| nash_skew_20 | 0.410 | 0.365 | 0.487 | simplex | 0 | 0 | 0 | 一致（0 / 0 / 0） |
| nash_skew_60 | 33.2 | 32.3 | 42.0 | simplex | 0 | 0 | 0 | 一致（0 / 0 / 0） |
| nash_near_copy_20 | 0.411 | 0.398 | 0.439 | simplex | 0 | 0 | 0 | 一致（0 / 0 / 0） |
| nash_degenerate_60 | 250.3 | 244.6 | 268.6 | fictitious_play | 0 | 0 | 0 | 一致。value −0.0424579 |
| select_4v4_tl2 | 353.5 | 330.4 | 417.5 | simplex | 3744 | 16 | 3728 | 一致（3744 / 16 / 3728） |
| select_status_heavy | 577.8 | 558.3 | 604.4 | simplex | 5328 | 672 | 4656 | 一致（5328 / 672 / 4656） |
| select_6v6_tl1 | 127.2 | 126.5 | 127.9 | simplex | 3600 | 0 | 3600 | 一致（3600 / 0 / 3600） |
| select_6v6_screened_small | 257.3 | 251.5 | 275.8 | simplex | 324 | 0 | 324 | 一致（324 / 0 / 324、screen_lp = 1） |

`select_6v6_screened_small` の中央値は 221.5 ms（18d94d6）から 257.3 ms になった。ノード数は同じ。この差がコードの変化によるものか環境によるものかは、この再確認では分けられていない。

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
| wall 中央値 | 318.9 ms | 548.1 ms | 1.72× |
| dp_nodes | 3744 | 5328 | 1.42× |
| dp_lp | 16 | 672 | 42× |
| 鞍点の割合 | 99.6% | 87.4% | |

追加の 229 ms は、ノード +1584 と LP +656 の両方に乗っている。LP 回数は大きく増えるが、行動行列が小さいので壁時計はノード展開の方がまだ大きい。こんらん・こおり・メロメロが入ると、同じ形で確率分岐と「鞍点でないノード」が増える。比較はこの `select_status_heavy` を固定 seed で取り直す。

## ボトルネック

1. **turn_limit ≥ 3 の DP ノード展開。** 6v6 tl=3 は中央値 54.8 秒、875,600 ノード。うち鞍点 98.9%（866,030）、LP 1.09%（9,570）、枝刈り 0。ヒット率 `127600 / (875600+127600) = 12.7%`。時間のほとんどは遷移とハッシュマップで、simplex ではない。
2. **auto-upgrade の refine（tl=5）。** `pkdx select` の既定 `switching_game`（tl=5）と tl≥4 は screening に入る。production 形は中央値 17.1 分、13,260,281 ノード（鞍点 98.7%、LP 1.29%）。small 形（trials=8、MC tl=1）では Phase A が 84% だったが、production の時間比は tl=3 全探索とノード数にほぼ比例しており、refine の DP が本体である。
3. **状態異常で鞍点率が落ち、ノード内 LP が増える。** 上の 42×。tl=2 の 4v4 ではまだ壁時計の主因ではない。分岐が増えると 1 と重なる。
4. **選出レベルの simplex 失敗。** 60×60 の成功例は中央値 30.5 ms。ピンした退化行列は 275 ms で fictitious play。54.8 秒の DP や 17.1 分の screening の横では小さい。
5. **ノード αβ は既定の窓では動いていない。** 計測した全ケースで `dp_pruned = 0`。子は常に `(-1, +1)` で呼ばれる。β 打ち切りは `lower >= 1` のときだけ。

## 改善候補

優先度は、このベースラインで壁時計に効く順。効果は同じフィクスチャを同じ release で取り直したときのオーダー。回帰は勝率（`value`）と選出分布（`row_strategy` / 残る選出）が変わるか。

1. **（#189 で一部実装済み）refine（Phase C）と Phase A の並列。** `pkdx select --parallel=N` は Phase A と Phase C を行シャードに分けて子プロセスで計算する（bit-exact。テストは `parallel_select_test.mbt` ほか）。まだ残っているのは、production 形（`select_6v6_screened_prod`）を `--parallel=auto` で 1 回取ることと、位相タイマー（screening / nash-scoring / dp-refine）を production 形で取ることである。コア数にほぼ比例してセルループが縮む見込みは見積もりで、実測ではない（4 vCPU なら数分の一、Phase B の 1 回の Nash は残る）。行シャードの上限は行数（Phase A は 60、Phase C は残り行数）。アルゴリズムは不変なので選出の回帰は低い。RSS はシャード数だけ増える。trials を 1000 から 200 に減らすと Phase A は約 5 倍短いが、17 分の本体が Phase C なら全体は少ししか縮まない。足切り順が変わり選出が変わり得る。回帰は中。設計は `docs/screen_parallel_design.md`。
2. **DP の再訪を増やす（状態キーはそのまま）。** tl=3 のヒット率 13%。同じ状態の再計算をハッシュで避ける余地が、展開コストの大半。キーを変えないメモの改善なら `value` はビット一致のままにできる。回帰は低。キーをパックし損ねると別状態が衝突し、勝率が変わる。回帰は高。
3. **子へ αβ の窓を渡す。** いま枝刈り 0。窓を伝播できれば tl≥3 と状態異常ケースのノードが減る。現状のビット一致は「子が exact」に依存している。窓の誤りは勝率と選出の両方を変える。回帰は高。効果の上限は大きいが、この PR では入れていない。
4. **状態異常・将来のこんらん / こおり / メロメロの分岐を、キャッシュキーが同じなら畳む。** `select_status_heavy` は LP が 42 倍、壁時計は 1.72 倍。新しい独立な Bernoulli が同程度ずつ乗ると、tl=3 の 54.8 秒に対してノードと非鞍点 LP がさらに増える。確率を変える実装は勝率の回帰が高い。比較用にこのケースを残す。
5. **fictitious play を exploitability < tol で早期停止する。** 効くのは simplex が落ちた 60×60 だけで、275 ms が数十 ms になる程度。tol を変えないなら選出は tol 以内の別戦略になり得る。回帰は低〜中。DP / screening の後でよい。

鞍点 fast path は既に働いている。tl=1 の 3600 ノードはすべて鞍点で LP 0。ノード内 simplex の微最適化は tl=3 の 54.8 秒をほとんど動かさない。
