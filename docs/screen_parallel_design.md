# 設計メモ: MC screening の並列化

コードはまだ変えない。数値は `docs/select_nash_bench.md` の公式ベースライン（`moonc v0.10.18+6c83a7f62`、4 vCPU、in-process）に合わせる。production 形は中央値 17.1 分で完走している。

## 何を並列にするか

`team_payoff_matrix_screened`（`src/payoff/screened_switching_game.mbt`）の壁時計は、6v6 シングルではほぼ Phase A と Phase C である。

- Phase A: 60×60 = 3600 セル × `team_monte_carlo_value`（`src/payoff/team_monte_carlo.mbt`）。
- Phase B: 親プロセスで `screen_nash_scores` を 1 回。60×60 の simplex は数十 ms。並列化しない。
- Phase C: 残った部分行列（keep_top=0.3 なら約 18×18 = 324 セル）の `switching_game_winrate`。

small 形（trials=8、MC tl=1）では Phase A が 84% だった。production 形は trials が 125 倍、ターン上限が 5 倍なので、Phase A の線形外挿は small の 182 ms × 625 ≈ **110 秒**。完走した 17.1 分との差は Phase C（refine tl=5）で、ノード数は 6v6 tl=3 全探索の 15 倍ある。並列化の主対象は Phase A と Phase C のセルループで、時間の大半は Phase C である。

## 使える手段

### プロセス分割（native、現状の実装）

`team_payoff_matrix_screened_parallel` が既にある。`shard_row_ranges` で行区間を切り、子プロセス `pkdx __select-shard`（`src/payoff/cli_select.mbt` の worker）が `screen_one_cell` / `refine_one_cell` を呼ぶ。`src/process/process.mbt` が spawn / wait を担う。

制約:

- native 専用。wasm には再 exec も temp ファイルも無い。
- Windows は `MAXIMUM_WAIT_OBJECTS = 64`（`max_parallel_shards`）。POSIX は事実上 `nproc`。
- 子は入力 JSON を読み直す。SQLite の damage cache はシャードでは使わない（`pkdx select` の `--parallel` と同じ）。
- `silent_dp_fallback_count` も DP のプロファイルカウンタもプロセス内グローバルで、スレッドセーフではない（`switching_game_turn.mbt` の注記）。プロセス境界ならカウンタは子ごとに独立で、親の値は増えない。
- 起動コストは 1 プロセスあたり JSON パースとチーム構築。3600 セル × 1000 trial の計算に対しては、シャード数がコア数程度なら無視できる。シャードをセル単位（3600 プロセス）にすると起動が支配する。

`pkdx select --parallel=auto` はこの経路を既にある。`select-bench` の 17.1 分は `--parallel` を付けない in-process である。実装の第一歩は新しいランタイムではなく、production 形を `--parallel=auto` で測ること。

### OS スレッド（native）

MoonBit のこのツリーは共有メモリのスレッドプールを持たない。CPU 束縛の rollout を 1 プロセスの複数コアで走らせるには、言語側のスレッドと、次の共有状態の隔離が要る。

- ChaCha8 の `Rand` はセルごとに別インスタンスにする（下のシード節）。
- `silent_dp_fallback_count` と `dp_profile_*` は `AtomicInt` かスレッドローカルに変える。現状の `Ref` を共有するとカウントが壊れるだけでなく、データ競合になる。
- damage のディスクキャッシュは接続をスレッド間で共有しない。screening はもともと `disk = None` でも成立する。DP refine をスレッド化するときだけ L2 をシャードごとに分けるか、親だけが書く。

プロセス分割より RSS は小さく、起動も無い。ただし wasm には輸出できず、正しさの証明は「データ競合が無い」ことを別途要る。プロセス版は既に bit-exact のテストがある（`parallel_select_test.mbt`）。

### async（native / wasm）

`moonbitlang/async` は協調的な並行で、ロールアウト中に await しない純計算を複数コアには載せない。Phase A はダメージ計算と RNG だけで I/O が無い。async にしても壁時計はほぼ 1 スレッドのままである。wasm で「並列に見せる」ためだけに async を使わない。

### wasm

wasm-gc はこの CLI の配布形態ではない。制約だけ固定する。

- プロセス spawn は使えない。`__select-shard` は native 限定のまま。
- 共有メモリのスレッド（SharedArrayBuffer）は pkdx の対象にしない。ブラウザ側のワーカー数が環境依存で、決定性とテストが崩れる。
- wasm で screening を速くするなら、試行回数を減らす（別メモの信頼区間）か、ネイティブで計算して結果だけ渡す。wasm 内の CPU 並列は設計に入れない。

## 決定性とシード

今日の契約は次のとおり。

1. セル `(i, j)` のシードは `mc_seed XOR (i * size_b + j)`（`screen_one_cell`）。
2. セルの中では `seeded_rng` が ChaCha8 を 1 本作る（`seed_to_bytes` は先頭 8 バイトだけがシード）。
3. `team_monte_carlo_value` はそのストリームを trial 0 から順に `team_rollout` へ渡す。1 ロールアウトが消費する乱数の個数は、交代や命中で変わる。trial `t` の開始位置は trial `0 .. t-1` の消費量に依存する。

この契約をビット一致のまま並列にするなら、**分割単位はセル（またはセルの行区間）まで**とする。同じセルの trial を複数ワーカーに分けない。行シャードは今の `shard_row_ranges` のままでよく、セルの計算順がシャード内でシリアルなら、シャード間の結合は連結だけで元の行列と一致する。`parallel_select_test.mbt` が既にこれを見ている。

trial 単位まで割るなら、ストリームを続けるのではなく trial ごとに独立シードにする。

```
trial_seed(cell_seed, t) = splitmix64(cell_seed) を t に依存させて混ぜた UInt64
mean = (1/T) * Σ_t rollout(RNG(trial_seed))
```

同じ `(cell_seed, t)` はどのワーカーが計算しても同じ値になる。平均の足し順は整数 trial を double で足すので、`t` の昇順に足せばワーカー間でもビット一致にできる（各 trial の値を配列に置き、最後にシリアルに還元する）。これは**今日の「1 本の ChaCha8 を trial 間で継続する」結果とは一致しない**。ビット一致が要るモード（既定の `team_monte_carlo_value`）では使わない。信頼区間メモの適応試行と組み合わせるときだけ、trial インデックスシードを新しいモードの定義にする。

やってはいけないこと:

- ワーカー番号をシードに入れる（割当が変わると結果が変わる）。
- `rng` を mutex で共有して trial を奪い合う（消費順がスケジューラ依存）。
- 行のハッシュをセル番号の代わりに使う（列挙順が契約）。

## 粒度

| 粒度 | 個数（6v6） | 向き |
|---|---|---|
| 行区間 | 60 行を `nproc` 個に分割。4 コアなら 15 行 × 60 列 = 900 セル/プロセス | 今の実装。起動が少なく、負荷は行あたりの trial 数が同じなら均等 |
| セル | 3600 | 仕事は均等だがプロセス 3600 は起動で負ける。スレッドプールのタスクサイズとしては可。1 タスクが軽すぎるなら 8〜32 セルをバッチ |
| trial | セルあたり 1000 | ビット一致モードでは不可。独立シードモードでは、1 セルが重いときにだけ使う |

Phase C も同じ行区間でよい。残行が 18 でコアが 4 なら、端数は `shard_row_ranges` の既存の余り分配（先頭シャードが 1 行多い）で足りる。Phase B は親が全行揃ってから 1 回だけ実行する。シャードが Nash を各自で解かない。

## 期待効果

#174 後の公式ベースラインでは、同じ production 形（`select_6v6_screened_prod`）が 3 回完走し、壁時計の中央値は 1024 秒（17.1 分、最小 1009 秒、最大 1034 秒）だった。ノード 13,260,281 のうち鞍点 98.7%、LP 1.29%。6v6 tl=3 全探索（中央値 54.8 秒、875,600 ノード）の 15.1 倍のノードに対し時間は 18.7 倍なので、17 分の本体は Phase A ではなく refine tl=5 の DP である。以前の「180 秒超」は打ち切りで、遅くなったわけではない。

条件: 6v6、trials=1000、MC tl=5、keep=0.3、refine tl=5、4 vCPU、in-process。

- Phase A の線形外挿は約 110 秒（上記）。4 プロセスなら計算部分は約 30 秒。起動と JSON 再パースを足して **Phase A はおおよそ 30〜40 秒**。
- Phase B は 1 秒未満の見込み（60×60 simplex の実測は 30 ms 前後。MC 行列でも同オーダー）。
- Phase C が 17.1 分のほとんどを占める。ノード単価を tl=3（54.8 秒 / 875,600 ノード）に合わせると 13,260,281 ノードは約 14 分で、実測 17.1 分と近い。4 プロセスでセルを割れば Phase C はおおよそ 4 分前後。Phase A の 30〜40 秒と足して、**1 プロセス 17.1 分に対して 4 プロセスでおおよそ 4〜5 分**。Phase B の 1 回の Nash は残る。位相タイマーは production 形ではまだ取っていないので、この内訳はノード数からの見積もりである。
- 8 コア以上でも、60 行しか無いので行シャードは 60 で飽和する。それ以上はセルバッチか、独立シードの trial 分割が必要で、後者は結果の定義が変わる。

速度以外: production 形の RSS 中央値は 60.8 MB（tl=3 までは約 4 MB）。4 プロセスならその数倍。damage cache をシャードが共有し始めると、ロックかファイル競合でこの見積もりは壊れる。screening シャードはディスクキャッシュ無しのままにする。
