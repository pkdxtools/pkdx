# TeamPayoffModel 仕様と選択基準

`pkdx select` が受け取る `team_payoff_model` の選択肢と設計根拠。旧 pairwise 系 (`Best1v1` / `NashResponses` / `MonteCarloSim(pairwise)`) は 2026-04 に全廃し、team-level の 2 択に統一した。

## 共通仕様

- すべて team-level (選出 3v3 を直接評価するモデルのみ)
- 戻り値は `[-1, +1]` (own 視点の Nash value)
- Single 専用 (3 体選出)。Double は現時点で未対応
- `damage_utils.mbt` は公開 API を持たず、`avg_damage` / `build_input_with_ranks` の内部ヘルパーのみ残存

## SwitchingGame (TeamPayoffModel)

### enum

```moonbit
TeamPayoffModel {
  SwitchingGame(Int)                                  // DP turn_limit (既定 DP_TURN_LIMIT = 5、`switching_game:<N>` で上書き可)
  ScreenedSwitchingGame(Int, UInt64, Double, Int)     // trials, seed, keep_top, refine_turn_limit (MC turn_limit = MC_TURN_LIMIT (5)、refine 既定 5)
}
```

DP turn_limit 既定は 5 (3 体選出の最短決着 3 ターン以上を十分カバーしつつ、素の `switching_game` が多技構成でも実用時間で完走するライン)。長期戦評価が必要なら `switching_game:<N>` で個別上書きする。MC screening rollout は定数 `MC_TURN_LIMIT` = 5 (足切り用の粗い評価)。team-level の extensive-form ゲーム木として評価する。

### 状態空間

```moonbit
SwitchingGameState {
  my_active : Int            // 0..N
  opp_active : Int
  my_hps : Array[Int]        // 長さ N
  opp_hps : Array[Int]
  my_ranks : Array[Int]      // 長さ 5: [A, B, C, D, S]、active のランクのみ追跡
  opp_ranks : Array[Int]     // 長さ 5、交代でリセット
  turn : Int                 // 0..DP_TURN_LIMIT
} derive(Show, Eq, Hash)
```

`HashMap[SwitchingGameState, Double]` (`StateCache`) に値を memoize。ランクは `[-2, +2]` にクランプして状態爆発を抑える（通常攻略で支配的な範囲を保ちつつ、±2 の飽和で `からをやぶる` 等の混合ランクアップを表現可能）。例外: まけんき / かちき の所持者のランクだけは実機どおり `[-6, +6]` で追跡する（`clamp_rank_for`、下記「まけんき / かちき」節）。ランクはダメージ計算（`atk_rank` / `def_rank` 経由で `(2+|r|)/2` / `2/(2+|r|)` の乗数）と先制順序（実効素早さ）に反映される。

### Action space

action は `ActionKind { UseMove(Int) | Switch(Int) }`:

- `UseMove(i)`: active pokemon の i 番目 move を使う (power=0 を含む全 move、ただし active が KO されている場合は除外)
- `Switch(i)`: alive かつ active 以外の i 番目 pokemon に交代

active 自身が HP=0 の場合は forced switch のみ。

### Transition

- **交代 vs 交代**: 両者 active 更新、ランクを `[0, 0, 0, 0, 0]` にリセット、damage なし、turn+1
- **交代 vs 技**: 交代側 active 更新 / ランクリセット、技側は新しい active に damage (新しいランク=0 で計算)。技側の自己積み効果も適用
- **技 vs 技**: 優先度→実効素早さ (`turn_order_sign`) で先攻決定して逐次解決
  - 優先度は `move.priority` を直接参照 (例: しんそく=+2, バレットパンチ=+1)
  - 実効素早さは Spe ランク (`effective_speed(base, rank)`) を反映
  - 先攻 attack → defender HP 減算 → 先攻の積み技効果を反映 → KO 判定 → 後攻 alive なら attack / 積み効果
  - 先制 KO の場合、後攻の action は実行されない (リアル戦闘準拠)
  - 優先度・実効素早さが完全一致 (`turn_order_sign = 0`) のときは両者同時に damage を適用

### 積み技 (ランク補正)

`move.stat_effects` が `[(stat_idx, delta), ...]` の形で載っている技 (DB の `move_meta` テーブルから populate) は、使用者のランクベクトルを `clamp_rank_for` (`[-2, +2]`。所持者がまけんき / かちき なら `[-6, +6]`) しながら更新する。`pkdx_patch/002_move_meta/data.json` に収録済みの主要な積み技: `つるぎのまい` (A+2), `りゅうのまい` (A+1/S+1), `めいそう` (C+1/D+1), `わるだくみ` (C+2), `てっぺき` (B+2), `ちょうのまい` (C+1/D+1/S+1), `からをやぶる` (A+2/C+2/S+2/B-1/D-1), `ロックカット` / `こうそくいどう` (S+2)。未登録名はデフォルトで効果なし — 追加は `data.json` に行を 1 つ足して `./setup.sh` を走らせれば反映される。

### Terminal value

`turn_limit` 到達時、または片側全滅:

- my 全滅 → `-1.0`
- opp 全滅 → `+1.0`
- 両側生存 + turn ≥ turn_limit → `(my_ratio - opp_ratio) / 2 ∈ [-1, +1]` (clamp)
  - `hp_ratio = Σ (hp_i / max_hp_i) / N`

### 再帰式

```
value(state, ..., cache, stats):
  match terminal_value(state, ..., turn_limit) {
    Some(v) => return v
  }
  if cache.has(state): stats.hits++; return cache[state]
  stats.misses++
  A = alive_actions(my_active, my_hps, my_team)
  B = alive_actions(opp_active, opp_hps, opp_team)
  M[i][j] = value(transition(state, A[i], B[j], ...), ...)  // 再帰
  v = solve_zero_sum(M).value
  cache[state] = v
  return v
```

### 計算量・推奨値

実到達 state は damage が整数刻みで離散化されるため有限。ランク (`my_ranks` / `opp_ranks`) は `[-2, +2]` に丸めて状態空間を抑える（まけんき / かちき の所持者のみ `[-6, +6]`）。`ValueStats.cached_states` で memoize 済みの固有状態数を取得可能。

**状態空間実測** (合成データ、各ポケモン 1 技):

| 構成 | turn_limit | cached_states | hits/misses | 推定メモリ |
|---|---|---|---|---|
| 2v2 ノーマル統一 HP200 | 20 | 113,295 | 2.0:1 | ~23 MB |
| 3v3 多型 HP150 | 5 | 2,664 | 0.66:1 | ~0.5 MB |

メモリ推定: `cached_states × ~200 bytes/state` (SwitchingGameState struct + HashMap overhead + Double value)。2v2 turn_limit=20 で ~23 MB に収まり、6v6 の選出 1 セル (3v3) でメモリ爆発は発生しない。ただし 3v3 turn_limit=20 は状態数が指数的に増加するため、実データでの計測が必要 (bit issue #a9de372d task B)。6v6 実データでの実測: turn_limit=1 は 1 秒未満、turn_limit=2 は 2 秒前後、turn_limit=3 は 40 秒前後で完走する (bit issue #38912f7b task C で pure-saddle fast path + node-level αβ-pruning 投入後)。turn_limit=4 以上は 5 分タイムアウトに収まらず、さらなる高速化は別タスクで検討。turn_limit を上げるほど積み技→全抜きのような多ターン脅威を評価できるようになるため、要件に応じて設定してよい (実用上限は現状 turn_limit=3)。`switching_game_winrate_stats` で `ValueStats.hits/misses` を取れるので、実行前に局所的に turn_limit を試して予算感を把握するのが推奨。

### LP 退化時の扱い (pure-saddle fast path)

選出レベル 60×60 行列 (`combinations_with_lead(6, 3)` の lead-aware 列挙) と `value` 再帰内部で解く per-state Nash の双方で、payoff matrix が **pure saddle** (`max_i min_j A[i,j] == min_j max_i A[i,j]` が `SADDLE_TOL = 1e-10` 内で成立) となる退化ケースを検出した時点で LP ソルバを skip し、純戦略と saddle value を直接返す。`@nash.solve_zero_sum` と `payoff.value` の双方に実装。

**動機**: turn_limit=3 以上の実データで状態空間が HP 離散 × 限定的な行動空間で多数の near-identical cell を生み、二相シンプレックスが数値的に不安定な pivot を繰り返し `InconsistentGame("col strategy has negative component ...")` を返していた (実データの 6v6 構成 tl=3 で ~70 秒後に失敗)。pure-saddle 検出はこの class の入力を simplex に渡さず直接解決するため、bug 回避と速度向上を同時に達成する。

**影響**: 既存の単体テスト (RPS, matching pennies, 2×2 mixed 等) は `maxmin < minmax` が strict に成立するため fast path を通らず、従来どおり shift-and-normalise LP 経由で解かれる。退化していない mixed Nash ケースへの影響なし。

### αβ-pruning (node-level, conservative)

`value` 関数が `alpha`, `beta` の labeled args (デフォルト `-1.0`, `+1.0`) を受け取り、以下の node-level 枝刈りを行う:

1. Matrix を 1 行ずつ埋めながら `row_min[i] = min_j A[i,j]` を計算し、`lower = max over filled rows of row_min[i]` を更新 (pure-maximin 下限)。
2. `lower >= beta - 1e-12` が成立したら残りの行をスキップして `lower` を返す (β-cutoff)。Nash(A) ≥ lower ≥ β より呼び出し側の関心範囲を超える。
3. 全 cell 埋めた後に `upper - lower ≤ SADDLE_TOL` なら saddle と判定し LP skip。
4. 子再帰は常に `(-1.0, +1.0)` で呼ぶため子の返り値は exact → top-level 値は non-pruning reference とビット一致する (bit-exact regression 保証)。

実測で turn_limit=3 の dominant team 比較で visited state 数が 15 → 3 (80% 削減)。top-level value は変わらないが中間 LP 回避で wall-clock が短縮する。

### 技メタ (`priority` / `stat_effects`)

技の `priority` と自己ランク補正 (`stat_effects`) は `@model.Move` 構造体に載っていて、`pkdx moves` / `pkdx damage` のクエリ時に `local_waza` と `pkdx_patch/002_move_meta` の `move_meta` テーブルを LEFT JOIN して自動的に populate される (未登録技はデフォルト `priority=0` / `stat_effects=[]`)。

```moonbit
// @model.Move (抜粋)
pub(all) struct Move {
  ..., priority : Int, stat_effects : Array[(Int, Int)]
}
```

payoff 層 (`SwitchingGame` / `MonteCarloSim`) は再帰 / rollout 内で `move.priority` / `move.stat_effects` を直接参照するだけ。別キャッシュや lookup 関数は不要。

スキル側は `pkdx moves` 出力 (priority / stat_effects 込み) をそのまま `pkdx select` の stdin JSON に流し込めば DB 由来のメタが正しく伝わる。新技を追加するときは `pkdx_patch/002_move_meta/data.json` に行を追加するだけ — コード変更は不要。

### `ValueStats` / `DamageCache` (memoization 観測)

```moonbit
ValueStats { mut hits : Int, mut misses : Int }
DamageCache { data : HashMap[DamageKey, Int], mut hits : Int, mut misses : Int }

DamageKey { my_attacker : Bool, atk_idx, def_idx, mv_idx, atk_rank, def_rank : Int }
```

2 段のキャッシュを持つ:

- **ValueStats** — state-value memo。`HashMap[SwitchingGameState, Double]` が保持する「state → Nash 値」の hit/miss を記録。
- **DamageCache** — damage-table memo。`(side, atk_idx, def_idx, mv_idx, atk_rank, def_rank)` をキーに 16-roll 平均ダメージをキャッシュ。1 turn 内の `transition` からも、異なる state からの遷移からも再利用される。

`switching_game_winrate` は両キャッシュを内部で作って捨てる。`switching_game_winrate_stats` は `(Double, ValueStats, DamageCache)` を返し、テスト / 診断でキャッシュ動作を black-box 観測可能。production で `DamageCache` のキー空間は `2 × N_atk × N_def × N_mv × 5 × 5` で上限されるため (ランクは `[-2, +2]` クランプ。まけんき / かちき の所持者のみ `[-6, +6]` で、その分キー空間はわずかに広がる)、state 数より圧倒的に小さく hit 比率は `misses ≪ hits` になる。

### CLI 文字列

JSON 入力の `team_payoff_model` フィールドで指定:

- `"switching_game"` (既定)
- `"screened_switching_game:<trials>:<seed>:<keep_top>"` 例: `"screened_switching_game:1000:42:0.3"`

既定 turn_limit: MC screening rollout = `MC_TURN_LIMIT` (5)、DP = `DP_TURN_LIMIT` (5)。`switching_game:<N>` / `screened_switching_game:<trials>:<seed>:<keep_top>:<turn_limit>` で個別に上書き可能 (MC rollout は定数で上書き不可)。

## ScreenedSwitchingGame (TeamPayoffModel)

### enum

```moonbit
TeamPayoffModel::ScreenedSwitchingGame(mc_trials: Int, mc_seed: UInt64,
                                       keep_top_quantile: Double)
```

Team-level の 2 段階パイプライン。SwitchingGame DP (refine turn_limit を 6 以上に上書きしたケース) が 6v6 の lead-aware 列挙 60² = 3,600 セル評価で重くなるケースで、team-level MC で「明らかに弱い選出」を事前に落としてから SwitchingGame DP を残存セルにだけ適用する。

### パイプライン

1. **Phase A — Screening**: `team_monte_carlo_value(selection_i, selection_j, mc_trials, mc_seed ^ cell_idx)` で全 3,600 セル (size_a × size_b = 60 × 60) を埋める。cell_idx = `i * size_b + j` でセル独立な RNG 状態を派生
2. **Phase B — Nash-weighted pruning**: screening 行列に Nash 均衡を解き、相手の Nash 戦略下での期待値で各行/列をスコアリング。top-`ceil(n * keep_top_quantile)` 行/列だけ残す (昇順ソート)
   - `row_score[i] = Σ_j col_nash[j] × A[i,j]` (row 視点)
   - `col_score[j] = -Σ_i row_nash[i] × A[i,j]` (column 視点、符号反転)
   - Nash support の選出はすべてゲーム値で同率首位になるため、`ceil(n * q) ≥ |Nash support|` であれば support が枝刈りされることは数学的に保証される
   - 旧方式 (mean-based) は「平均的に弱いが Nash support に入る specialist 選出」を落とすリスクがあったため廃止
3. **Phase C — Refine**: 残存 sub-matrix `R[i', j'] = switching_game_winrate(..., DP_TURN_LIMIT)` で精密評価

### Short-circuit

`keep_top_quantile >= 1.0` は screening を**完全に skip** して既存 `team_payoff_matrix_switching` に直接フォールスルーする。MC + refine の二重計算を避け、`keep_top=1.0` oracle test の bit-exact 保証 (`FiniteMatrix.at(i,j)` 全セル一致) にも必須。

### team-level MC rollout (`team_rollout`)

- 値域は **[-1, +1] (own 視点の value)**。winrate 名の関数は用意しない
- 各ターン両者が独立に action を選ぶ:
  - active KO → forced switch (相手 active への avg best-damage / hp 比最大の alive スロット)
  - active alive → ε-greedy。ε 確率で全 alive action (UseMove + Switch) から uniform、1-ε で greedy
  - greedy 基準: `stay_value = best_expected_damage(active, opp_active) / opp_hp`、`switch_value = max over alive others s of best_expected_damage(s, opp_active) / opp_hp`。`switch_value > stay_value + SWITCH_HYSTERESIS` (0.05) のとき Switch、それ以外は best move を UseMove
- 行動解決: switch-switch は damage なし、switch-move は switch 側が fresh active で受ける、move-move は `turn_order_sign` 逐次解決
- 終了: 全滅 ±1、turn_limit 到達 → `hp_ratio_own - hp_ratio_opp` を [-1, +1] clamp
- mega 進化は screening では無視 (精度は refine で担保)

### 計算量

- Phase A: size_a × size_b × mc_trials × avg_turn × damage_calc ≈ (60 × 60 × 1000 × 10 × 数μs) ≈ 18-45 秒
- Phase C: retained_rows × retained_cols × SwitchingGame 評価時間 ≈ (retained率)² × (60×60 換算 SwitchingGame 全評価時間)
- keep_top=0.3 なら 18-45 秒 + (0.3)² × full_DP ≈ 旧 20×20 換算で 9 倍程度の絶対値だが、相対的な高速化率 (≈10x speedup at high turn_limit) は維持

### パラメータチューニング指針

`combinations_with_lead(6, 3)` = 60 selections → 60² = 3,600 セルの screening 空間を前提とした推奨値:

| パラメータ | 推奨範囲 | 既定推奨 | 根拠 |
|---|---|---|---|
| `trials` | 500–2000 | 1000 | MC 標準誤差 ∝ 1/√trials。√1000 ≈ 32 → 誤差 ≈ 3%。3,600 cells × 1000 trials = 3.6M rollout で Phase A 18–45 秒 |
| `keep_top` | 0.2–0.4 | 0.3 | 60 selections × 0.3 = 18 retained → Phase C 18² = 324 cells (元の 9%)。Nash support は同一メンバー集合の 3 lead 違いが同率首位になりがちなので、support size は旧 20-row 時代より大きい (典型 6–18) |
| `seed` | 任意 UInt64 | 42 | 再現性が必要な場合に固定。同一 seed → 同一結果 |

**入力サイズ別ガイド** (lead-aware enumeration `n × C(n−1, k−1)` ベース):
- n=4, k=3 → 12 selections: keep_top ≥ 0.4 推奨 (12 × 0.3 = 3.6 → ceil = 4)
- n=5, k=3 → 30 selections: keep_top=0.25–0.4 (8–12 retained)
- n=6, k=3 → 60 selections: keep_top=0.2–0.3 (12–18 retained)

**Phase B の Nash-weighted 安全性**: screening 行列に Nash を解き、opponent Nash 下の期待値でスコアリングする。Nash support は全てゲーム値で同率首位 → `ceil(n × q) ≥ |support|` なら support は枝刈りされない (数学的保証)。旧 mean-based は「平均的に弱いが最適応答にだけ刺さる specialist」を落とすリスクがあった。

### 使いどころ (実測ベースの指針)

**多様型 6v6 (各ポケモン 2 技、6タイプ分散) で実測** (macOS M-series, 旧 20×20 列挙):

| モデル | 時間 | Nash value | selections |
|---|---|---|---|
| `switching_game:2` | 0.4 秒 | 0.030 | 20 |
| `switching_game:3` | 5.0 秒 | 0.055 | 20 |
| `switching_game:4` | 77 秒 | 0.066 | 20 |
| `switching_game:5` | >2 分 (未完走) | — | — |
| `switching_game` (tl=20) | >2 分 (未完走) | — | — |
| `screened:500:42:0.3:3` | 29 秒 | 0.042 | 6 |
| `screened:500:42:0.3:4` | 43 秒 | 0.054 | 6 |

> **注意**: 上の表は lead-aware 列挙 (60×60) 導入前の計測。新しい列挙ではセル数が **20² → 60² = 9 倍**になるため、`switching_game` の絶対時間は概ね 9 倍前後を見込む必要がある (cell ごとの DP は不変だが cell 数が増える)。screening の break-even 点は `tl=3` 付近に下がる。実測の再取得は別タスク。

**ベンチマーク構成**: team=ガブリアス/サーフゴー/カイリュー/ウォッシュロトム/ハッサム/ランドロス vs opponent=ミミッキュ/ドラパルト/キノガッサ/ヒードラン/ウーラオス/カプ・レヒレ。各ポケモン 2 技 (先制技・積み技含む)。

**分析** (旧 20×20 列挙下の傾向、定性的には新列挙でも同方向):
- tl=3→4 で 15 倍増 (5s→77s)。tl=5 以上は多技構成で実用外
- screened は **tl=4 で break-even** (旧列挙下、新列挙では tl=3 寄りに前倒し)
- tl=3 では screened が逆に遅い (旧列挙下、MC overhead 支配的)
- tl=20 は switching_game / screened 両方 infeasible (3v3×2技の action space が指数的に膨張)

screening は **MC phase に 3,600 cells × N trials の rollout オーバヘッド**があり、素の `switching_game` が短時間で完走する場合は screening のほうが遅い。**使うべきは switching_game が 30 秒以上かかる場合のみ**。

- 先に `time bin/pkdx select` で素の `switching_game:<N>` を計測し、遅いことを確認してから使う
- 技数 1 (action space 小) なら tl=20 でも実用的 (2v2: 113K states, 数秒)
- 技数 2+ では tl=3–4 が実用上限

### CLI 文字列

`"screened_switching_game:<trials>:<seed>:<keep_top>"`
例: `"screened_switching_game:1000:42:0.3"`

**バリデーション**: `trials > 0`, `0 < keep_top <= 1`。`keep_top=0.0` は parser で即 reject。`keep_top > 1.0` も InvalidJson (short-circuit 経路は `>= 1.0` のみで、`1.5` のような不正値は parser で弾く)。

### Double format 制約

`SwitchingGame` と同じく **Single 限定**。`Double + ScreenedSwitchingGame` は `run_select` で `InvalidJson("screened_switching_game does not support double format ...")` を raise。

### 実装の検証

- `team_monte_carlo_test.mbt`: team-specific behavior (全滅 ±1 / HP 比 draw / 同 seed 決定性)
- `screened_switching_game_test.mbt`: keep_top=1.0 での `FiniteMatrix.at(i,j)` 全セル bit-exact 一致、quantile → 残存数 `ceil(n*q)`、残存 index の昇順ソート、monotonicity (`0.3 < 0.8` で残存数増加)
- `cli_select_test.mbt`: `run_select` 経由で retained selections の shape / Double 拒否

## 比較表

| 観点 | SwitchingGame | ScreenedSwitchingGame |
|---|---|---|
| 種別 | team-level | team-level |
| 計算量 (6v6 single) | 60² × state数 × Nash (lead-aware) | Phase A 18-45s + Phase C (keep²) × SG |
| 技選択 | 行動 Nash (技 + 交代) | Phase C で行動 Nash |
| 交代 | **モデル化** | **モデル化** (screen は簡易 / refine は精密) |
| 確率性 | 決定的 | 決定的 (screen の seed 固定) |
| 連続値 | [-1, +1] 連続 | [-1, +1] 連続 |
| 推奨場面 | 通常の選出最適 | SG が 30 秒以上かかる大規模検証 |

## CLI / JSON フィールド

`pkdx select` は stdin の JSON で受ける:

```jsonc
{ "team": [...], "opponent": [...], "format": "single", "team_payoff_model": "switching_game" }
{ "team": [...], "opponent": [...], "format": "single", "team_payoff_model": "screened_switching_game:1000:42:0.3" }
```

`team_payoff_model` が未指定の場合は既定で `SwitchingGame` (DP turn_limit=`DP_TURN_LIMIT`=5)。ただし 5 は自動昇格閾値 4 以上のため、実行時は下記 Auto-screening により `ScreenedSwitchingGame` に置き換わる。`payoff_model` / `pairwise:*` / `best1v1` / `nash_responses` / `monte_carlo:*` は全て**廃止済み**で、渡すと `InvalidJson` となる。DP turn_limit は `switching_game:<N>` および `screened_switching_game:<trials>:<seed>:<keep_top>:<turn_limit>` で上書き可能。MC screening rollout の turn_limit は定数 (`MC_TURN_LIMIT` = 5)。

### Auto-screening (CLI 内部処理)

`run_select` は parse 結果を `auto_upgrade_team_model` に通してから DP に渡す。`SwitchingGame(N)` で `N >= AUTO_SCREEN_TURN_LIMIT` (= 4) のケースは自動で `ScreenedSwitchingGame(AUTO_SCREEN_TRIALS=1000, AUTO_SCREEN_SEED=42, AUTO_SCREEN_KEEP_TOP=0.3, refine_turn_limit=N)` に置き換わる。

- skill 側は turn_limit だけを考えて `switching_game:<N>` を組み立てればよく、screening を使うかどうかの判断は CLI が担う
- `screened_switching_game:...` を明示したケースは `auto_upgrade_team_model` の match が外れてパススルーするため、ユーザー指定の `trials` / `seed` / `keep_top` / `refine_turn_limit` がそのまま使われる
- 閾値未満 (N ≤ 3) の turn_limit、例えば `switching_game:3` は従来どおり pure SwitchingGame で動く
- 既定パラメータ (1000/42/0.3) は `src/payoff/semantics.mbt` の定数で集約管理。調整したい場合はここを書き換える

## Post-hit side effects (Phase 2-4)

`move_meta` に後付けされた post-hit 副次効果は 4 カラム:

- `recoil_num` / `recoil_den` — 反動ダメージ割合。`(0, 1)` なら反動なし。`dmg > 0` のとき `max(1, dmg * num / den)` HP を攻撃者から減算 (ゴースト無効化等で `dmg = 0` の場合は反動ゼロ)
- `self_ko` — `true` なら使用後に攻撃者 HP を 0 にする。**`dmg` によらず必ず発動** (ゴースト相手のじばくでも自爆する canonical 仕様)
- `recharge` — `true` なら次ターン行動不可。`SwitchingGameState.{my,opp}_must_recharge: Array[Bool]` に独立して保持 (`StatusCondition` とは別系統)。やけど+はかいこうせん等が共存可能

`stat_effects_json` のスキーマは `[[stat, delta, target]]` の 3 要素 (legacy 2 要素 `[stat, delta]` は target=0 として解釈されるので 006 既存エントリとの後方互換あり)。`target`:

- `0` — 自分 (攻撃者) のランク
- `1` — 相手 (防御側) のランク。ターゲットが `hp <= 0` のときは適用しない

post-hit 処理順 (`resolve_post_hit_effects` / team_monte_carlo の `team_apply_post_hit`):
1. damage は呼び出し元で既に適用済み
2. opp-target `stat_effects` を `defender_hp > 0` のときのみ適用
3. self-target `stat_effects` を常に適用
4. recoil (`dmg > 0` かつ `recoil_num > 0`) を適用、HP は `clamp_zero`
5. `self_ko` を常に適用 (`dmg` 無視)
6. `recharge` は `mv.recharge && attacker 生存` のときのみ `must_recharge[active]=true` を立てる

`must_recharge` の消費規則:
- ターン開始時に flag が true だった active は、そのターン `UseMove`/`Mega` を `per_side_attempt` で強制 skip。Switch は許可 (switch 時に flag クリア)
- ターン終了時、**ターン開始時に flag=true だったスロットのみ** flag を false に戻す。ターン途中で新しく立った flag は次ターンに持ち越す

### 相手ダウンの防御特性 (技由来、Showdown `onTryBoost`)

`apply_stat_effects` (`target = 1` かつ `delta < 0`、あまのじゃく反転後) で、所持者の特性が `ability_blocks_opp_stat_drop` を満たすとそのダウンは不発になる。DP (`with_post_hit_effects`) と MC (`team_apply_post_hit`) は同じ関数を通る。

- **クリアボディ / しろいけむり / メタルプロテクト**: 全能力の相手由来ダウンを不発 (Showdown は同一の `onTryBoost` body)
- **かいりきバサミ**: 攻撃 (index 0) のダウンのみ不発。防御・特攻・特防・素早さのダウンは通る
- **不発のダウンは rank も反応も変えない**。`landed` が立たないので、まけんき / かちき の反応は起きない (Showdown は `AfterEachBoost` が不発のダウンに対して走らない)
- **自己ダウン (`target = 0`) は不発にならない**。Showdown は `target === source` で免除する (インファイト の自己 B-1 / D-1 は クリアボディ でも通る)
- **通す特性**: いかく 専用の防御特性 (どんかん / マイペース / せいしんりょく / きもったま) は Showdown で `effect.name === 'Intimidate'` に限定されるため技由来のダウンは防がない。ばんけん (Guard Dog) も いかく 専用で、技由来のダウンは通る
- **未対応**: ミラーアーマー (技由来のダウンを使用者へ反射する) は別経路で未モデル (下記「MVP 対象外」)
- **判定に使う特性**: DP は mega 後の実効特性 (`effective_combatant`)。メタグロス (クリアボディ) はメガ進化で かたいツメ になり、ブロックしなくなる。MC は mega 未モデル (`megaed` 常に false) なので raw の特性で判定する (MC の mega 未モデル化と同じ境界)。いかく の登場時判定も DP は mega 後実効特性

### そうしょく (Sap Sipper) の吸収 — DP / MC

Showdown の `onTryHit` (null を返す): 相手のくさタイプの技 (攻撃・変化) が所持者を狙うと、技は当たらず、所持者の A が +1 される (+6 で頭打ち。吸収自体は起きる)。`ability_absorb_boost` が `(A, +1)`、`ability_absorbs_move` が吸収判定を返す。DP は `apply_damage_variants_fanout` 冒頭で `with_absorb_effects` の単一 leaf を返し、`attempt_accuracy` が命中率を 100 にする。MC は `team_apply_post_hit` (A +1 だけ行って return)、`mc_try_apply_status` (状態付与をしない)、`mc_attempt_accuracy` (命中 100) で同じ判定を行う。

- **吸収される技**: 防御側の特性 (DP は mega 後の実効特性) が そうしょく、技の解決タイプ (`resolve_effective_move_type`、engine と同じ前段) がくさ、かつ技が相手を狙う。ダメージ技と変化技の両方が対象 (Showdown の `onTryHit` は両方で走る)。
- **吸収されない技** (`is_grass_non_foe_target_move`、`src/damage/move_flags.mbt`): 自分・自分側・フィールド・味方に作用するくさ技。ねをはる / こうごうせい / せいちょう / コットンガード / ニードルガード (自分)、グラスフィールド (フィールド)、アロマセラピー (てもち)、ジャングルヒール (自分と味方)。出典は champions `move.target` の 7 (自分) / 10 (フィールド全体) と、説明文の味方・てもちへの作用。`pokedex.db` には target 列がないため、同じ名前表で判定する。
- **吸収時に起きないこと**: HP 変化、状態異常、寄生、回復、ねがいごと、反動、自爆、recharge、相手ダウン、使用者の自己ダウン、接触 proc、道具 proc。Showdown は吸収で `targets` が空になり、`selfDrops` (`spreadMoveHit` の段) まで進まないため、リーフストーム の自己とくこう -2 も起きない。
- **Protean / Libero**: 吸収された技でもタイプ固定は記録する。Showdown は `PrepareHit` を `trySpreadMoveHit` の moveSteps (TryHit を含む) より前に実行する。
- **命中**: 吸収は命中判定より前に起きる (Gen 9 の moveSteps は Invulnerability → TryHit → TypeImmunity → TryImmunity → Accuracy)。そのため命中率が低い状態技 (ねむりごな 75 等) でも外れ枝は無く、単一 leaf (確率 1.0) になる。
- **ランク範囲**: そうしょく の所持者は ±6 で追跡する (`ability_tracks_full_stages` → `clamp_rank_for`)。通常特性の ±2 で丸めると、+1 の頭打ちが +2 になってしまう。
- **あまのじゃく**: 所持者は特性を 1 つしか持たないため、所持者側の反転は起きない。使用者があまのじゃくでも吸収された技は自己効果を出さないので、反転対象がない (`switching_game_sap_sipper_wbtest.mbt` で確認)。
- **かたやぶり**: 未対応 (下記「MVP 対象外」)。そうしょく は破壊可能 (breakable) 特性だが、かたやぶり は pkdx でモデルしていない。
- **瀕死の保持者**: 保持者が瀕死 (HP 0) なら A は上がらない (Showdown は瀕死の対象に技が通らない)。DP (`with_absorb_effects`) と MC (`team_apply_post_hit`) の両方で、生存時のみ A +1 を適用する。
- **MC**: mega 未モデルなので raw の特性で判定する (DP は mega 後実効特性)。

### 崩れ技 (Crash damage) — DP / MC

Showdown の `hasCrashDamage` + `onMoveFail` (`data/moves.ts`): **技が命中しなかった leg で使用者が最大 HP の 1/2 を失う**。対象は `is_crash_move` (`src/damage/move_flags.mbt`) の名前表で、とびひざげり / かかとおとし / サンダーダイブ / とびげり (Past 専用、Champions の技プールには無い)。Mind Blown / Steel Beam は丸め (`Math.round`) と multihit の扱いが違い、pokedex.db にも champions.db にも無いので含めない。DB に crash 列は無い (`move_meta` は `recoil_*` / `self_ko` のみ)。

- **消費量**: `max(1, floor(maxHP / 2))`。Showdown は `this.damage(source.baseMaxhp / 2, …)` を `spreadDamage` の `clampIntRange(_, 1)` に通す (`sim/battle.ts:2130`)。`clampIntRange` は `Math.floor` の後に下限 1 を掛ける (`lib/utils.ts:320-326`)。pkdx は `effective_hp` (実効最大 HP) を使う。Mind Blown / Steel Beam の `Math.round(maxhp / 2)` とは丸めが違う (対象外)。
- **発生する leg**: (a) 外れ (命中判定の失敗)、(b) タイプ / 特性で無効な leg (免疫 leg、`hits_count = 0`)。どちらも Showdown では対象が空になり `trySpreadMoveHit` が false を返すので、`useMove` の `!moveResult` 分岐 (`battle-actions.ts:589-596`) で `MoveFail` (崩れ) が走る。ゴーストへの とびひざげり、じめんへの サンダーダイブ、ひらいしん / でんきエンジン への サンダーダイブ (`check_def_immunity`) が該当する。
- **発生しない leg**: 命中 (ダメージを与えた leg)、眠り / まひ / 反動による行動不能 (`per_side_attempt` の skip は `SideAttempt.miss = false`)、再使用 (`must_recharge`)。Protect (未モデル) は含まない。
- **マジックガード**: 消費 0。Showdown `magicguard.onDamage` は `effect.effectType !== 'Move'` で `false` を返す (`data/abilities.ts:2466-2477`)。崩れのエフェクトは `dex.conditions.get('High Jump Kick')` で作られる `Condition` (`effectType` 既定 `'Condition'`、`sim/dex-data.ts:126`) なので対象になる。`ability_blocks_crash_damage` が唯一の判定。ほかの `onDamage` は崩れを防がない: Sturdy / Disguise / Ice Face は `effectType === 'Move'` 限定、Rock Head は `recoil` 限定 (`abilities.ts:3908`)。
- **ひんし**: 現 HP ≤ 消費量なら HP 0。反動 (recoil) と同じく HP 0 で表現し、交代は既存の瀕死処理に任せる。HP は `clamp_zero`。
- **行動順**: 崩れは使用者の行動枠で起きる (`MoveFail` は技の最後)。行動の速い側の崩れは相手の行動より前、遅い側は後。DP は `crash_miss_outcomes` で `move_turn_sign` を使い、同速は両順序の平均 (0.5 / 0.5)。切り替え (Switch) は常に先に解決するので、切り替えの相手がいる外れは崩れが後。MC は Step 3 の `own_first` の順に、各 leg の直後で適用する。
- **眠りで行動不能になった使用者**: 先に行動した相手の眠り技で眠った場合、崩れは起きない (Showdown は行動そのものが起きない)。DP は `action_blocked_by_fresh_status`、MC は `*_blocked_mid_turn` で判定する。
- **相手 HP への影響**: 崩れは使用者の HP だけを減らす。相手の HP / 状態 / ランクは変えない。
- **DP の実装位置**: 外れ = `attempt_turn_with_cache` の `(_, _, true)` arm → `crash_miss_outcomes` (`SideAttempt.miss` は accuracy miss だけ立つ)。免疫 = `apply_damage_variants_fanout` の `hits_count = 0` leg → `with_crash_damage`。非崩れ技の経路は変えない (`attempt_has_crash_miss` が false なら従来の arm を通る)。
- **MC の実装位置**: 外れ = `mc_resolve_attempt` の 3 番目 (`missed`) → 各 leg 直後の `mc_apply_crash`。免疫 = `team_perform_attack` の 4 番目 (`immune`) → leg 内の `mc_apply_crash`。`team_perform_attack` の戻り値は 4 要素。
- **既知の差 (DP / MC 共通の既存差分)**: 先の leg で使用者が ひんし になった後、残りの leg の扱いが DP と MC で違う。MC は後の leg を target 生存でゲートする (`own_hps > 0 && opp_hps > 0`)。DP は actor の生存だけを見る (`resolve_moves` の `second_attacker_hps`)。崩れで先行の使用者が ひんし になるケースも、反動による ひんし と同じくこの差分に含まれる。parity テストは相手が行動しない (眠り / 交代) か、後行の使用者が崩れる構成に限っている。
- **テスト**: `switching_game_crash_wbtest.mbt` (DP: 免疫 / 外れ / マジックガード / 両者外れ / 行動順 / 眠り / 同速の確率質量 など) と `team_monte_carlo_crash_parity_wbtest.mbt` (MC の leg 単位 + DP / MC parity の感度ガード)。
- **未対応 (open)**:
  - むこうみず (Reckless) の崩れ技 ×1.2: Showdown `reckless.onBasePower` は `move.recoil || move.hasCrashDamage`。pkdx の `abilities.mbt` は `is_recoil_move` のみ。ダメージ計算側の別 PR。
  - ちくでん (Volt Absorb) の電気無効: `check_def_immunity` に未収録 (ひらいしん / でんきエンジン は収録済み)。Showdown の `voltabsorb.onTryHit` は null を返すので サンダーダイブ は崩れる。
  - Mind Blown / Steel Beam (DB に無い)、Protect、みがわり、Substitute。

### MVP 非対応 (将来拡張で検討)

- 確率副次効果 (アイアンテール 10% B-1 等) ― `stat_effects` は常に 100% 発動前提
- みがわり越しの opp-target stat drop 無効化
- 特性免疫 (ぼうじん 等)。技由来の能力ダウンを防ぐ特性は上記「相手ダウンの防御特性」で対応
- ふきとばし / ほえる / どくどくのトゲ等の相手操作系

## Multi-hit chance-node integration (Phase 2-D/2-E、#91)

連続技 (`Random2to5` / `TripleVariant` / `PopulationBomb` / `ParentalBond`) と Skill Link で生まれる **per-hit hits_count 確率分布**を switching game の chance-node leaf 展開に統合する。

### 中核 API

```moonbit
@model.DamageOutcome {
  probability : Double           // この hits_count が realize される確率
  mean_damage : Int              // 当該 hits_count での mean damage (16-roll の平均、burn 等の effect 折込済み)
  hits_count : Int               // この outcome での実 hit 数
  hit_steps : Array[HitStep]     // 各 hit のメタ (def_stage_after / contact 等)
} derive(Show, Eq)

compute_damage_variants(atk, dfn, mv, atk_rank, def_rank, ...)
  -> Array[@model.DamageOutcome]                              // 純関数 (cache miss 時)

damage_variants_cached(cache, my_attacker, atk_idx, atk_ranks, def_idx, def_ranks, mv_idx, ...)
  -> Array[@model.DamageOutcome]                              // L1 (HashMap) + L2 (disk) 経由

apply_damage_variants_fanout(state, outcomes, attacker_is_me~, attacker_active~, defender_active~, ...)
  -> Array[(Double, SwitchingGameState)]                      // chance-node leaf 展開
```

### 5 つの attack site への統合

`switching_game.mbt` 内で「単一 mean damage を defender HP から減らす」という旧経路を持っていた 5 箇所をすべて `damage_variants_cached → apply_damage_variants_fanout` に置換:

1. `resolve_attacker_leg` (`UseMove vs UseMove` の attacker leg)
2. `(Switch, UseMove)` arm (defender が交代 → 攻撃側のみ damage)
3. `(UseMove, Switch)` arm (attacker が交代 → 防御側のみ damage)
4. `partial_act_outcomes` の `(true/false, UseMove)` 部分実行 arm
5. `Some(..)` 後段の post-hit fanout 共通 dispatch

`SwitchingGameState` の cache key shape (HP / status / ranks / megaed / item_consumed / must_recharge / turn) は variants 統合後も不変。`hits_count` や `landed` は **leaf state に焼き込まれず**、各 leaf は通常の `SwitchingGameState` として memoize される。

### `attack_event` payload の 4-tuple 化

旧: `(Bool, Int, @model.Move)?`  → 新: `(Bool, Int, @model.Move, Int)?`

4 番目に **`mv_idx`** を追加。`damage_variants_cached` が L1 cache key に `mv_idx` を必要とするため、`Some(..)` 後段の post-hit fanout 共通 dispatch で attack site から運ばれてくる。

### per_side_attempt と variants の責務分担

「accuracy / paralyze full / sleep / recharge / freeze 解除」 系の **行動が起きるか否か** の Bernoulli 試行は `per_side_attempt` が単独で担う。`apply_damage_variants_fanout` は「行動が起きた前提で hits_count がどう分岐するか」だけを扱う。

| 副次効果 | 担当 fanout |
|---|---|
| accuracy (move-level miss) | `per_side_attempt` |
| paralyze full / sleep / freeze 解除 / drowsy | `per_side_attempt` |
| recharge (はかいこうせん 等) | `per_side_attempt` |
| hits_count 分布 (Triple Axel / PopulationBomb / Random2to5) | `apply_damage_variants_fanout` |
| contact-proc (ほのおのからだ 等、per-hit Bernoulli) | `apply_contact_proc_fanout` (variants に rank-up された後) |
| secondary status (技 `status_effect` 30% paralyze 等、per-hit Bernoulli) | post-hit fanout の secondary 段 (variants の hits_count を引数化) |
| post-hit side effects (recoil / self_ko / stat_effects) | `with_post_hit_effects` (per-variant immutable) |

contact-proc と secondary status は **hits_count を渡されて per-hit Bernoulli compounding を行う** (例: ほのおのからだ × みだれづき hits=5 → P(burn) = 1 - 0.7^5 ≈ 0.832)。

### L2 disk cache の注意点

`damage_variants_cached` は cache miss 時に副作用として `mean_damage_via_disk` を呼んで scalar mean を温める。`@model.DamageOutcome` の variants payload 自体はまだ disk schema に永続化していない (将来 work)。同一プロセス内では L1 (HashMap) ヒットでフル variants を返せるが、プロセスを跨いだ復元では再計算が走る。Monte Carlo / select / nash CLI の cross-session L2 ヒット率は scalar mean のおかげで従来どおり保たれる。

### 検証範囲

- `damage_variants_cached_wbtest.mbt` — `compute_damage_variants` 単体 (variants 数 / 確率 / mean_damage)
- `apply_damage_variants_fanout_wbtest.mbt` — fanout 単体 (HP per variant / per-hit Bernoulli)
- `attack_site_variants_wbtest.mbt` — 5 attack site の `transition_with_cache` 出口
- `switching_game_variants_wbtest.mbt` — 8 ケース parameterized matrix (じしん / ハイドロポンプ / Skill Link ロックブラスト / トリプルアクセル / ネズミざん / みだれづき / つららばり / ParentalBond)
- `switching_game_variants_test.mbt` — black-box e2e (mirror match の anti-symmetry / 多重 fanout の per-hit compounding)
- `branch_count_test.mbt` — 決定論的 cached_states 上限 (Triple Axel ≤ 800 / PopulationBomb ≤ 4500 / 多重 fanout ≤ 1000)

## Protean / Libero (へんげんじざい / リベロ)

へんげんじざい / リベロ は「場に出てから最初に撃った技のタイプ」に使用者を単タイプ化する特性。SwitchingGame (DP) と team-level MC の両方で再現する。engine (`@damage`) は非改変で、payoff 層が per-slot のロックタイプを保持し `effective_combatant` で type を override する。

### 状態 (per-slot ロックタイプ)

`SwitchingGameState` / `TurnWorkspace` に `my_protean_locked : Array[String]` / `opp_protean_locked : Array[String]` を持つ (長さ = チーム数)。`"" = 未発動`、型名 (`"ほのお"` 等) = ロック中。HP / ランク等と同じく状態の一部なので DP の cache key に含まれ、ロック有無で別 state として memoize される。team MC 側は `team_rollout` 内のローカル `own_protean_locked` / 相手側配列で同じ per-slot 表現を持つ。

### 発動 (ロックの記録)

`with_post_hit_effects` (DP) / `record_protean_lock` (MC) が攻撃解決の直後に attacker スロットへ `mv.type_` を書き込む。発動条件:

- 実効特性 (`atk_eff.ability`) が `へんげんじざい` または `リベロ`
- `atk_eff.tera_type == ""` — テラスタル中は型固定で Protean 非発動
- 当該スロットが未ロック (`== ""`) — **once per switch-in**。ロック済みなら以降何度撃っても最初のタイプのまま (再変化しない)
- カテゴリゲートなし — Status 技でも発動する

特性判定は base ではなく **mega 後の実効特性** (`effective_combatant(_, atk_is_mega)`) を見る。base げきりゅう → mega へんげんじざい のように mega で初めて Protean を得る個体でも正しく記録するため。発動技自身のダメージはこのフックより前に計算済みなので、記録されたロックは「次手以降」の damage / type-chart に効く。`mv.type_` は variant 非依存なので、`apply_damage_variants_fanout` から variant ごとに呼ばれても全 leaf が同一ロック値へ収束する。

### ダメージへの反映 (`effective_combatant` override)

`effective_combatant(c, is_mega, protean_locked?)` の適用順 (precedence):

1. **mega form 解決** — `is_mega && mega_form` のとき type/ability/stats を override
2. **tera ゲート** — `tera_type != ""` のとき Protean override を無効化 (テラスがタイプを支配し、engine の `tera_type` 経路に委ねる)
3. **Protean lock** — `protean_locked != "" && tera_type == ""` のとき返す Pokemon を `type1=protean_locked, type2=""` に上書き

override を末尾に置くことで mega 解決結果にも一律でかぶせられる (mega と Protean は同ターン両立しないが、順序非依存にするため末尾)。

ロック中は attacker の type1 が override 済みなので、`build_input_with_ranks` / cache key の `protean_consumed = (atk_protean_locked != "")` を立てて engine 側の Protean STAB gate (二重 push) を止める。通常 STAB 経路が「ロックタイプ一致技に STAB」「ロックタイプで被弾」を担う。これにより:

- **offense**: ロック後はロックタイプ技にのみ STAB。未ロックの発動技には engine が STAB を push する (出てきて最初の攻撃挙動 = CLI 既定)
- **defense**: ロック後は被弾時の防御相性が変化後タイプで計算される

### リセット

ロックは以下で `""` へ戻り、再登場時に新しいタイプで再発動できる:

- **switch-out** — `transition_with_cache` / `partial_act_outcomes` の Switch arm で出ていくスロットを解除 (leech_seeded と同じ境界ガード・同じ index)
- **mega** — mega 発動はロックを解除し再発動可能にする (`megaed` と対)。mega 発動技は `protean_consumed=false` で STAB を得て、その後 `with_post_hit_effects` が新タイプで再ロックする

テラスタルはロックを記録しない (発動ゲートで弾く)。

### L2 cache key (v6)

`DamageKey` / `CacheKeyInput` に `atk_protean_locked` / `def_protean_locked` を追加。同一種族・同一技でも未ロック / ほのおロック / みずロック でダメージが変わる (type override) 一方 name_ja は不変なため、これらを key に含めないとロック前にキャッシュされた matchup が以降のロック後 lookup を shadow する (異なるロックタイプ同士も alias する)。`SCHEMA_VERSION` を v5→v6 に bump し、既存 `damage_cache.sqlite` は自動 invalidate される。

### MC parity

team-level MC (`team_monte_carlo.mbt`) も同一セマンティクスを実装。greedy 選択 (`pick_best_move` / `best_expected_damage` / `greedy_team_action`) と実ダメージ解決 (`team_perform_attack`) が **同一の** Protean override を共有し、ロック中の Protean 個体はロックタイプ技を選ぶ greedy が実ダメージと一致する。MC は mega 未モデルなので `is_mega=false` 固定で DP 側 `effective_combatant` を再利用 (SSoT)。

### 検証範囲

- `switching_game_protean_wbtest.mbt` — DP の発動条件 (初手ロック / Status 技 / テラス非発動 / 2手目再ロックなし / 非Protean no-op / opp 側記録 / fanout 全 leaf 同一値)、offense STAB / defense type-chart、`effective_combatant` precedence (tera 優先 / 単タイプ override / `""` no-op)、switch / mega リセット、mega-acquired Protean、mega + Status
- `team_monte_carlo_protean_parity_wbtest.mbt` — MC/DP value parity を `|dp - mc| < 0.15` で pin (offense STAB + defense type-chart、自分側 / 相手側)、非Protean の決定性 (no-op)、テラス中の bit-exact (ロックゲート off)、greedy/damage coherence (ロック個体が STAB 技を選ぶ)

## いかく / あまのじゃく / ばけのかわ (Intimidate / Contrary / Disguise)

登場時ランク干渉 (いかく)・技のランク変化反転 (あまのじゃく)・初撃ダメージ無効 (ばけのかわ) の 3 特性を SwitchingGame (DP) と team-level MC の双方で再現する。engine (`@damage`) は既存経路を極力非改変で使い、payoff 層が「ランク配列への entry-time 適用」「`apply_stat_effects` チョークポイントでの符号反転」「per-slot busted フラグと damage transform」で挙動を足す。Protean と同じく DP / MC を同一セマンティクスで揃え、各特性を `|dp - mc| < 0.15` の parity test で pin する。

### いかく (Intimidate) — DP

真理値表は `entry_abilities.mbt` の `apply_intimidate_on_entry(entrant_ability, target_ability, target_ranks, entrant_ranks)` に集約。DP 配線ラッパ `apply_intimidate_entry` (`switching_game_turn.mbt`) が entrant / target 双方を **mega 後の実効特性** (`effective_combatant(_, megaed)`) で解決してから呼ぶ (base げきりゅう → mega いかく のような個体も正しく発動)。

- **発動タイミング (entry)**: 「場に出る」全イベント。
  - 初期 lead — top-level entry で `apply_intimidate_entry` を両サイドに 1 回ずつ (2 コール)
  - 交代 (voluntary switch) — `transition_with_cache` の Switch arm (switch-vs-switch は両 entrant、switch-vs-move は交代側)
  - 部分実行 (`partial_act` arm) の交代
  - 死に出し (瀕死後の forced switch) も entry として同じ arm を通る
- **mega では再発動しない** — mega 進化は form 切替のみで entry ではないため `apply_intimidate_entry` を呼ばない。
- **相互作用テーブル** (target は 1 特性のみ保持するため排他):

  | target_ability | 効果 |
  |---|---|
  | ばんけん (Guard Dog) | 下降が上昇に反転 → target A **+1** |
  | ミラーアーマー (Mirror Armor) | 反射 → **entrant** A -1、target 無変化 (再反射なし: いかく持ちは同時にブロック特性を持てないため素の -1 で exact) |
  | びびり (Rattled) | target A **-1** かつ S **+1** (Gen8+ でいかくが Rattled を誘発) |
  | あまのじゃく (Contrary) | 反転 → target A **+1** (`ability_reverses_stat_changes` 判定) |
  | `ability_blocks_intimidate` の 8 種 (どんかん / マイペース / せいしんりょく / きもったま / クリアボディ / かいりきバサミ / しろいけむり / メタルプロテクト) | no-op |
  | まけんき / かちき | target A **-1** (`apply_opp_stat_drop`)。1 回の能力ダウンイベント (いかく 1 回) で実際に下がったときだけ 1 回反応 (`apply_opp_drop_reaction`): まけんき = 攻撃 **+2** / かちき = 特攻 **+2** (上限 +6) |
  | その他 | target A **-1** |

- 全 write は `clamp_rank_for` を通る（所持者が まけんき / かちき なら `[-6, +6]`、それ以外は `[-2, +2]` に飽和）。相互いかく (両 lead / 相互交代) は entrant を入れ替えた 2 独立コールで解決する。

### あまのじゃく (Contrary) — DP

技の `stat_effects` (自己積み・相手ダウン双方) のランク変化を**単一チョークポイント** `apply_stat_effects(self_ranks, opp_ranks, opp_alive, mv, attacker_ability~, defender_ability~)` で反転する。

- 各 effect の `target` で holder を選ぶ: `target == 0` → attacker (自己積み) の ranks と `attacker_ability`、`target == 1 && opp_alive` → defender (相手ダウン) の ranks と `defender_ability`。それ以外の target 値は forward-compat のため無視。
- holder が `ability_reverses_stat_changes(holder_ability)` を満たすとき `delta` を符号反転してから `clamp_rank`。非 Contrary 入力は反転前と **bit-identical** (両 ability 引数は default なしの必須引数にして、全 call site が解決済み特性を明示する契約)。
- 効く技: からをやぶる / オーバーヒート / インファイト 等の自己ダウン、あまえる 等の被弾ダウン。いかく反転も同じ `ability_reverses_stat_changes` 判定を entry テーブル側で共有する。

### まけんき / かちき (Defiant / Competitive) — DP

相手由来の能力ダウンに反応する特性。反応は 2 経路 (いかく の登場時ダウン / 技 `stat_effects` の相手ダウン) で同じ helper を共有する。ダウン適用は `apply_opp_stat_drop` (実際に下がったかを Bool で返す)、反応は `apply_opp_drop_reaction` (実際に下がった能力ごとに 1 回)。

- **発動条件**: 相手由来のダウン (いかく 1 回 / 1 つの技の相手ダウン群) のうち、**実際に適用された**ダウンの能力ごとに 1 回発動する。ランクが変化しなかったダウン (既に下限・ブロック・反射) は反応しない。同じ能力への重複エントリは 1 回に数える。自分の技の自己ダウン (`target = 0`) では発動しない。
- **反応**: まけんき = 攻撃 (index 0) +2、かちき = 特攻 (index 2) +2。反応の上限は +6 (`clamp_stat_stage`)。
- **同時に複数能力を下げる技** (くすぐる / なみだめ) は、その技の全ダウンを適用してから、下がった能力ごとに 1 回ずつ反応する (`apply_stat_effects` 1 呼び出しで、両方下がれば 2 回)。ダウンの判定は技の開始時点のランクで行う。Showdown の `boost()` は技の能力変化表を開始時点で上限・下限に切り詰めてから適用するため、開始時点で -6 の能力は、先に別能力の反応で持ち上がっても下がらない (例: 特攻 -6 のかちきへのなみだめ → 攻撃 -1 のみ適用・反応 1 回 → 特攻 -4)。反応を全ダウンの後にまとめても、各ダウン直後に反応する Showdown と結果が一致する (±1 のダウン 2 件・反応 +2 の全ランク組を総当たりで確認)。
- **ランク範囲**: 所持者のランクは実機どおり `[-6, +6]` で追跡する (`clamp_rank_for`)。下限 -6 で止まるため「既に下限なら不発」が実機どおりになる。他特性は従来の `[-2, +2]` (既存挙動は不変)。
- **対象の相手ダウン技**: `pkdx_patch/005_move_meta_posthit` 収録の `target = 1` 技 (あまえる / いやなおと / こわいかお / しっぽをふる / にらみつける / なきごえ / くすぐる / なみだめ)。表に無い技と、確率付きの追加効果による相手ダウンは未対応。
- **交代**: 所持者が交代で退場するとランクは 0 に戻る (switch-out リセット)。
- **MC**: 同じ `apply_intimidate_on_entry` / `apply_stat_effects` を呼ぶため、parity は構造的に一致する。
- **未モデル**: みがわり・しろいきり等による阻止 (payoff 層に身代わり / 場の効果による阻止は無い)。

### しろいハーブ (White Herb, 持ち物) — DP / MC

所持者の能力ランクに負のものが 1 つでもあれば、負のランクを全て 0 に戻し、持ち物を消費する (Showdown `whiteherb`、1 戦闘 1 回)。helper は `held_item_stat_reset.mbt` の `apply_held_item_stat_reset` (1 側) / `apply_held_item_stat_reset_pair` (両側)。

- **判定点**: Showdown の `onStart` / `onAnySwitchIn` (登場)、`onAnyAfterMove` (技の後)、`onAnyAfterMega` (メガ)、`onResidual` (残り HP 処理) に対応する。DP は (1) 登場時いかく (lead・交代・死に出し) の直後、(2) 技の効果 (`with_post_hit_effects`、両 active) の直後、(3) メガ直後、(4) `apply_eot` の直後に両 active を判定する。負のランクを生むのは「登場時いかく」と「技の効果」だけで、どちらの直後にも判定があるので、(3) と (4) は実到達では no-op (対応を残すために呼ぶ)。
- **まけんき / かちき との順序**: 相手ダウンを適用し、反応 (まけんき = 攻撃 +2 / かちき = 特攻 +2) の後に判定する。Showdown の `AfterEachBoost` (反応) が先、`onAnyAfterMove` (しろいハーブ) が後。反応で負でなくなった能力は解除されず、負のまま残った能力だけが 0 に戻る。例: まけんき の所持者が くすぐる (A-1 / B-1) を受けると、下がった能力ごとに 1 回ずつ反応するので A は -1 +2 +2 = +3 となり、負のまま残った B だけが 0 に戻って消費される。なきごえ (A-1) だけなら A は +1 となり、負が無いので消費されない。
- **不発は判定を起こさない**: クリアボディ 等で不発になったダウンは rank が変わらないので、負のランクは生じず消費もされない。かいりきバサミ で A のダウンだけ不発なら、同じ技の B のダウンは通って解除される。
- **自己ダウン**: 技の使用者の自己ダウン (インファイト の B-1 / D-1、からをやぶる の反対 等) も、その技の直後に解除される。自己ダウンは まけんき / かちき の反応を起こさない (既存どおり)。
- **消費状態**: 既存の `my_item_consumed` / `opp_item_consumed` (P5 の per-slot 持ち物消費フラグ) を流用する。しろいハーブ の所持者が消費したときだけ値が変わるので、他の matchup では状態キーも状態数も変わらない。消費後は交代を跨いで持続し、2 回目以降の負のランクは解除されない (1 戦闘 1 回)。
- **ダメージ計算への影響**: 消費済みの持ち物は DP では `damage_cache_layer` が itemless として扱い、MC では `consumed_item_view` が同じ swap を行う。しろいハーブ自体はダメージ補正を持たないので威力は変わらないが、はたきおとす (相手が持ち物を持つと威力 ×1.5) は消費後は効かなくなる (Showdown と一致)。
- **ひんし**: hp が 0 の所持者は判定しない (Showdown の `getAllActive` は ひんし を除外する)。技の効果で自分が ひんし になる場合 (自爆 / 自己 KO) は判定されず、消費もされない。
- **MC**: 同じ helper を技の効果 (6 leg)・登場 (lead / switch)・EOT の後に呼ぶ。MC は mega 未モデルなので (3) のメガ判定は持たない。MC の単一 rollout と DP の値は、parity テストで感度ガード付きに確認する。
- **未モデル**: なげつける で しろいハーブ を投げたときの効果 (使用者の負のランク解除と持ち物の消失、Showdown の `fling.effect`)。持ち物の移動 (トリック / ついばむ 等) による所持者の変化。

### ばけのかわ (Disguise, ミミッキュ専用) — DP

- **状態**: `SwitchingGameState` に per-slot `my_disguise_busted : Array[Bool]` / `opp_disguise_busted : Array[Bool]` を追加 (`false` = 未消費 intact、`true` = 剥がれ済み busted)。HP / ランク等と同じく state の一部なので DP cache key に含まれ、intact / busted で別 state として memoize される。書き込みは `with_disguise_busted` が copy-on-write で行い、**交代でリセットしない** (1 戦闘 1 回)。
- **cache key**: `DamageKey.def_disguise_intact : Bool` を追加。intact は初段ブロック + chip、busted はフルダメージで同一 matchup のダメージが変わるため、含めないと intact でキャッシュした reduced 値が busted lookup を shadow / alias する。**intact のときは L2 disk cache をバイパス** (disk には常に disguise 非考慮の素値のみを載せる契約。wire format が hit_steps を持たず busted 相手に誤読されるため)。
- **damage transform**: engine は `disguise_active = false` 固定で呼ばれ (`build_input_with_ranks`)、`r.variants` の `total_damages` は素の全ヒット合算。初段減算 + chip 付与は payoff 層の `outcomes_from_calc_result` → `disguise_reduced_mean` (`damage_utils.mbt`) で行う。
  - `chip = r.defender_hp / 8` (= `effective_hp(defender) / 8` 床)。`r.defender_hp` は engine が `def_hp_override` 込みで解いた防御側最大 HP なので chip の SSoT。
  - `disguise_reduced_mean` は初段の `damage_per_roll` 合算 `s0` を全合算 `s` から引き (`reduced = max(s - s0, 0)`)、`/16` → burn fold → `+ chip`。単発技は `s0 = s` なので `reduced = 0`、mean = chip。連続技は**初段のみブロック**し 2 発目以降は通す。
  - reflect (反射) 経路も intact のとき同様に `effective_hp(defender) / 8` の chip 化 (engine の `def_hp_override` と整合)。
- **反動/ドレイン精度 (`dmg_for_effects` 分離)**: 反動・ドレイン回復は「実際に与えたダメージ」基準で計算する必要があるため、`dmg_for_effects = actual_dmg - disguise_chip` を別に持つ。ブロック時は mean = chip なので `dmg_for_effects = 0` → 反動なし・ドレイン回復なし。接触判定・追加効果 (状態異常 proc 等) は chip ヒットでも通常どおり発生する。
- **bust フラグ書き込み条件**: intact かつ `power > 0` かつ `hits_count > 0` (実際に着弾したダメージ技ヒット) のときのみ被弾側 slot の busted を立てる。変化技・タイプ無効 (`is_immune`) では剥がれず chip も出さない。

### MC parity

`team_monte_carlo.mbt` が 3 特性とも DP と同一セマンティクスを実装。MC は mega 未モデルなので **raw ability** (`is_mega = false`) を使い、screening 用に **単一ロール近似** (variant 加重平均 = `avg_damage` 相当) で評価する。

- **いかく**: `apply_intimidate_on_entry` を初期 lead 2 コール (`own`/`opp`) と交代 (voluntary / forced) の各 entry で呼ぶ (DP と同じ truth table を共有)。
- **あまのじゃく**: `apply_stat_effects` を DP と共有 (SSoT)。
- **まけんき / かちき**: いかく経路 (`apply_intimidate_on_entry`) と相手ダウン技 (`apply_stat_effects`) を DP と共有 (SSoT)。反応は両経路とも `apply_opp_drop_reaction` を、実際に下がった能力ごとに 1 回呼ぶ (いかく は 1 能力なので 1 回)。
- **ばけのかわ**: `disguise_intact_mc(team, active, busted)` が「ばけのかわ持ち かつ `busted[slot] == false`」で intact 判定。`own_disguise_busted` / `opp_disguise_busted : Array[Bool]` を `team_rollout` ローカルに持ち (slot-bound・戦闘持続、交代非リセット)、damage は同じ `disguise_reduced_mean` を再利用。busted は `res_bust` を返して被弾側配列へ書き戻す。
- 各特性を `|dp - mc| < 0.15` の value-tol で pin し、非該当チームでの決定性 (no-op) と greedy/damage coherence を感度ガードで確認する。

### 検証範囲

- `entry_abilities_test.mbt` — `apply_intimidate_on_entry` の分岐網羅 (無 / ばんけん / ミラーアーマー / びびり / あまのじゃく / 無効化 8 種 / 非いかく entrant no-op / 相互いかくの 2 独立コール)
- `ability_immunity_test.mbt` — `ability_blocks_intimidate` / `ability_reverses_stat_changes` の特性集合定義
- `switching_game_intimidate_wbtest.mbt` — DP 配線 (初期 lead / Switch arm / partial_act / 死に出し、mega 後実効特性判定、clamp)
- `team_monte_carlo_intimidate_parity_wbtest.mbt` — MC/DP value parity + 各分岐 (ばんけん / ミラーアーマー / びびり / あまのじゃく / 無効化) + 非いかくチーム no-op
- `switching_game_contrary_wbtest.mbt` — `apply_stat_effects` の反転 (からをやぶる 等の自己積み反転、あまえる 等の被弾反転、いかく反転、target 0/1)
- `team_monte_carlo_contrary_parity_wbtest.mbt` — Contrary の MC/DP parity
- `switching_game_disguise_wbtest.mbt` — 初撃ブロック + chip、連続技初段のみ、変化技/タイプ無効で非剥がれ、交代非リセット、`dmg_for_effects` 分離 (反動/ドレイン)、`def_disguise_intact` cache key
- `team_monte_carlo_disguise_parity_wbtest.mbt` — Disguise の MC/DP parity + busted 配列の戦闘持続
- `switching_game_defiant_competitive_wbtest.mbt` — まけんき / かちき の反応 (いかく / 相手ダウン技 / 複数ダウン技は下がった能力ごとに反応 / 開始時点で下限の能力は不変 / 重複エントリは 1 回 / 自傷不発 / 上限 +6 / 下限不発 / 防がれたダウン)、持ち主別 clamp (`clamp_rank_for`)、DP 配線 (交代いかく・連続交代の累積・交代退場リセット・くすぐるで攻撃のみ下限)
- `team_monte_carlo_defiant_competitive_parity_wbtest.mbt` — まけんき / かちき の MC/DP parity (lead いかく・相手ダウン技・複数ダウン技 (くすぐる) は下がった能力ごとに反応・MC no-op)
- `held_item_stat_reset_wbtest.mbt` — しろいハーブ の判定 helper (負のランクを全て 0・正は残す / 消費済み・他の持ち物・ひんし・範囲外は no-op / 両側独立 / 消費済み所持者の itemless view)
- `switching_game_white_herb_wbtest.mbt` — しろいハーブ の DP 判定点 (なきごえ・自己ダウン・まけんき / かちき の反応後・クリアボディ 不発・いかく (lead / 交代 / partial-act)・ミラーアーマー反射・消費の持続・技の後に後攻が解除後の B で受ける・EOT・メガ直後)
- `team_monte_carlo_white_herb_parity_wbtest.mbt` — しろいハーブ の MC/DP parity (自己ダウン後の被弾 / 登場時いかく の lead)
- `switching_game_stat_drop_block_wbtest.mbt` — 相手ダウンの防御特性 (クリアボディ / しろいけむり / メタルプロテクト の全能力ブロック、かいりきバサミ の攻撃のみ、自己ダウン免除、不発のダウンは反応しない、いかく 専用特性 / ばんけん は通る、あまのじゃく は反転が先、DP 配線 `with_post_hit_effects`)
- `team_monte_carlo_stat_drop_block_parity_wbtest.mbt` — クリアボディ による相手ダウン技 (なきごえ) ブロックの MC/DP parity
- `switching_game_sap_sipper_wbtest.mbt` — そうしょく の吸収 (くさ攻撃 / 状態 / やどりぎのタネ / 相手素早さダウン / リーフストーム の自己ダウン不発 / 自分狙いのくさ技は非吸収 / グラスフィールド / くさ以外は通常 / A +6 頭打ち / ±6 積み上がり / Protean 固定 / 持ち主の技は非吸収 / 命中 100 の固定 / 1 ターン解決で単一 leaf)
- `team_monte_carlo_sap_sipper_parity_wbtest.mbt` — そうしょく の MC 経路 (post-hit / 状態付与 / 命中) と、乱数の入らない matchup での DP/MC parity (horizon 2 / 3)

### MVP 対象外 (将来拡張)

- ミラーアーマーによる技由来 (非いかく) の能力ダウンの反射 — 反射された能力ダウンで まけんき / かちき の使用者が反応する経路を含めて未対応 (いかく の反射は `apply_intimidate_on_entry` で対応済み)
- かたやぶり (Mold Breaker) による ばけのかわ / あまのじゃく の貫通
- あまのじゃく × はらだいこ — はらだいこ は `move_meta` 未収録のため現状 edge case は発生しない

## 将来拡張

- `SwitchingGame` / `ScreenedSwitchingGame` の Double format 対応 (現在 Single 専用)
- 状態異常 / 天候 / フィールドのモデル化
- 変化技の効果拡充 — 上記 Post-hit 節 参照。`pkdx_patch/005_move_meta_posthit/data.json` に行を足すだけで追加可能。確率副次効果・特性免疫を扱う場合は `move_meta` テーブルのスキーマと `@model.Move` 側のフィールド追加が必要
- `team_rollout` の ε-greedy から局所 Nash LP への切替 (rollout の変化技評価を精緻化)
- Aggressive αβ-pruning (child alpha/beta propagation) — 現状の node-level 保守的実装は子を常に `(-1, +1)` で呼ぶため bit-exact だが、速度は saddle skip に依存する
- Iterative deepening + transposition-table による action reordering — αβ の β-cutoff ヒット率を上げる

新 team-level variant は `TeamPayoffModel` enum と `team_payoff_matrix_with_team_model` ディスパッチに分岐を足す。pairwise 系は意図的に削除したため、再導入は非推奨。
