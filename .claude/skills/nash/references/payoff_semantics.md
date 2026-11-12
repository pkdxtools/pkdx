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

スキル側は `pkdx moves` 出力 (priority / stat_effects / status_effect / flinch_chance / recoil_num・recoil_den / self_ko / recharge / heal_* / weather_set / field_set 込み) をそのまま `pkdx select` の stdin JSON に流し込めば DB 由来のメタが正しく伝わる。効果のキーは既定値 (状態異常なし / flinch 0 / 反動なし / false / 回復・天候・フィールド設定なし) のときは省略される。新技を追加するときは `pkdx_patch/002_move_meta/data.json` に行を追加するだけ — コード変更は不要 (状態異常・ひるみは m017–m019 の投入先に行を足す)。

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

上の 3 種 (recoil / self_ko / recharge) は move_meta (m005) 由来で、`pkdx moves` の JSON も同じ名前 (`recoil_num` / `recoil_den` / `self_ko` / `recharge`) で出し、`pkdx select` の `parse_move_json` が読む (既定値は省略)。JSON 入力では DB を引かない。一方、崩れ技 (`is_crash_move`) の自傷とてっていこうせんの最大 HP 反動 (`is_max_hp_recoil_move`) は技名の判定 (`src/damage/move_flags.mbt`) なので、JSON の `name` だけで決まりキーは不要。回復 (`heal_*`、`HealingEffect` の 7 種) / 天候設定 (`weather_set`) / フィールド設定 (`field_set`) は m014 / m015 由来で、同じく JSON のキー (`heal_kind` 等) で届く。

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

免疫 leg (タイプ / 特性で無効な技) は 2〜4 と 6 を行わず、5 (`self_ko`) と Protean 記録だけを行う。詳細は下記「タイプ / 特性で無効な技 (immune leg)」。

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
- **発生する leg**: (a) 外れ (命中判定の失敗。眠りの目覚め枝で技を使って外れた場合も含む: DP は `wake_outs` の `miss = true`、MC は `mc_resolve_attempt` の `missed`)、(b) タイプ / 特性で無効な leg (免疫 leg、`hits_count = 0`)。どちらも Showdown では対象が空になり `trySpreadMoveHit` が false を返すので、`useMove` の `!moveResult` 分岐 (`battle-actions.ts:589-596`) で `MoveFail` (崩れ) が走る。ゴーストへの とびひざげり、じめんへの サンダーダイブ、ひらいしん / でんきエンジン への サンダーダイブ (`check_def_immunity`) が該当する。
- **発生しない leg**: 命中 (ダメージを与えた leg)、眠り / まひ / 反動による行動不能 (`per_side_attempt` の skip は `SideAttempt.miss = false`)、再使用 (`must_recharge`)。Protect (未モデル) は含まない。
- **マジックガード**: 消費 0。Showdown `magicguard.onDamage` は `effect.effectType !== 'Move'` で `false` を返す (`data/abilities.ts:2466-2477`)。崩れのエフェクトは `dex.conditions.get('High Jump Kick')` で作られる `Condition` (`effectType` 既定 `'Condition'`、`sim/dex-data.ts:126`) なので対象になる。`ability_blocks_crash_damage` が唯一の判定。ほかの `onDamage` は崩れを防がない: Sturdy / Disguise / Ice Face は `effectType === 'Move'` 限定、Rock Head は `recoil` 限定 (`abilities.ts:3908`)。
- **ひんし**: 現 HP ≤ 消費量なら HP 0。反動 (recoil) と同じく HP 0 で表現し、交代は既存の瀕死処理に任せる。HP は `clamp_zero`。
- **行動順**: 崩れは使用者の行動枠で起きる (`MoveFail` は技の最後)。行動の速い側の崩れは相手の行動より前、遅い側は後。DP は `crash_miss_outcomes` で `move_turn_sign` を使い、同速は両順序の平均 (0.5 / 0.5)。切り替え (Switch) は常に先に解決するので、切り替えの相手がいる外れは崩れが後。MC は Step 3 の `own_first` の順に、各 leg の直後で適用する。
- **眠りで行動不能になった使用者**: 先に行動した相手の眠り技で眠った場合、崩れは起きない (Showdown は行動そのものが起きない)。DP は `action_blocked_by_fresh_status` (`crash_second` の blocked 枝、`with_landing_sleep_consumed`)、MC は `*_blocked_mid_turn` で判定する。どちらも着弾ターンの眠りの 1 回目を `consume_sleep_attempt_on_block` で消費する (崩れは起きなくても消費は起きる。`resolve_moves` と同じ規則)。
- **相手 HP への影響**: 崩れは使用者の HP だけを減らす。相手の HP / 状態 / ランクは変えない。
- **DP の実装位置**: 外れ = `attempt_turn_with_cache` の `(_, _, true)` arm → `miss_self_loss_outcomes` (`SideAttempt.miss` は accuracy miss だけ立つ。てっていこうせん の外れも同じ経路、下記「てっていこうせん」節)。免疫 = `apply_damage_variants_fanout` の `hits_count = 0` leg → `with_crash_damage` (てっていこうせん は `with_max_hp_recoil` を併用、どちらも他方の技では恒等)。崩れ技 / てっていこうせん の外れが無い attempt は従来の arm を通る (`attempt_has_miss_self_loss` が false)。
- **MC の実装位置**: 外れ = `mc_resolve_attempt` の 3 番目 (`missed`) → 各 leg 直後の `mc_apply_crash`。免疫 = `team_perform_attack` の 4 番目 (`immune`) → leg 内の `mc_apply_crash`。`team_perform_attack` の戻り値は 4 要素。
- **既知の差 (DP / MC 共通の既存差分)**: 先の leg で使用者が ひんし になった後、残りの leg の扱いが DP と MC で違う。MC は後の leg を target 生存でゲートする (`own_hps > 0 && opp_hps > 0`)。DP は actor の生存だけを見る (`resolve_moves` の `second_attacker_hps`)。崩れで先行の使用者が ひんし になるケースも、反動による ひんし と同じくこの差分に含まれる。parity テストは相手が行動しない (眠り / 交代) か、後行の使用者が崩れる構成に限っている。
- **テスト**: `switching_game_crash_wbtest.mbt` (DP: 免疫 / 外れ / マジックガード / 両者外れ / 行動順 / 眠り / 同速の確率質量 など) と `team_monte_carlo_crash_parity_wbtest.mbt` (MC の leg 単位 + DP / MC parity の感度ガード)。
- **未対応 (open)**:
  - ちくでん (Volt Absorb) の電気無効: `check_def_immunity` に未収録 (ひらいしん / でんきエンジン は収録済み)。Showdown の `voltabsorb.onTryHit` は null を返すので サンダーダイブ は崩れる。
  - Mind Blown / Steel Beam (DB に無い)、Protect、みがわり、Substitute。

### タイプ / 特性で無効な技 (immune leg) — DP / MC

タイプ相性 0 (例: インファイト → ゴースト) と特性による無効 (`check_def_immunity`: ちょすい / よびみず / もらいび / ひらいしん / でんきエンジン / ふゆう / そうしょく / かんそうはだ) は、DP では `compute_damage_variants` が返す `hits_count = 0` の sentinel、MC では `team_perform_attack` の 4 番目の戻り値 `immune` で判定する。この leg は技が当たらないので、DP は `with_immune_effects`、MC は `team_apply_post_hit(immune=true)` と `mc_try_apply_status(immune=true)` で次の 2 つだけを行う。

- **残るもの**
  - 自爆 (`self_ko`): じばく / だいばくはつ は `selfdestruct: 'always'`。Showdown の `useMove` は対象判定より前に使用者を ひんし にするので、免疫でも倒れる (`battle-actions.ts:564-566`)。
  - Protean / Libero の記録: `PrepareHit` は `TryHit` より前に走る (`battle-actions.ts:652-654`)。`data/abilities.ts` の `protean.onPrepareHit` が記録する。
- **止まるもの**
  - 自己・相手のランク変化 (`stat_effects` の全件)、反動、回復・ドレイン、自己 `recharge` (はかいこうせん 等)、自己交代、状態異常、接触 proc、道具 proc。Showdown は対象が外れ、`trySpreadMoveHit` が `targets` 空で `moveResult = false` を返すため、`spreadMoveHit` (`runMoveEffects` / `selfDrops` / `secondaries`) に届かない (`battle-actions.ts:676-681`, `:1080-1192`)。反動は `hitStepMoveHitLoop` の中でしか適用されない (`:1040-1042`)。
  - しろいハーブ の判定: DP は通らず、MC は通る。理由は「しろいハーブ」節の「吸収 / 免疫 leg」。
- **ifHit の自爆は発動しない**: Memento (おきみやげ) / Final Gambit / Healing Wish (いやしのねがい) / Lunar Dance (みかづきのまい) は `selfdestruct: 'ifHit'` で、`runMoveEffects` の `damage[i] !== false` でしか倒れない (`battle-actions.ts:1342-1344`)。pkdx の `self_ko` は DB (`move_meta`) 上 じばく / だいばくはつ だけなので、この区別を持つ必要はない。
- **未対応: 先の leg で対象が ひんし になった場合**: 2 本目の leg は攻撃側の HP だけを見て解決される (`switching_game_turn.mbt:469`)。Showdown は `getMoveTargets` が空を返して技を失敗させる (`pokemon.ts:841-862`) ので、Protean 記録も崩れ技も起きない。本変更の対象外。
- **参照テスト**: `src/payoff/switching_game_immune_wbtest.mbt` (DP、対照・Protean・そうしょく+しろいハーブ を含む)、`src/payoff/team_monte_carlo_immune_parity_wbtest.mbt` (MC と DP/MC parity)。

### てっていこうせん (最大 HP 1/2 反動) — DP / MC

- **根拠**: Champions `champout/rom-txt/usa/wazainfo_syn.json:13644` "After attacking, the user takes damage equal to 1/2 of its max HP."。Showdown `data/moves.ts` steelbeam は `mindBlownRecoil: true` と `onMoveFail` (`this.damage(Math.round(source.maxhp / 2), ...)`)。能力変化は無い (旧 `pkdx_patch/005` の自己 Def/SpD -2 は m016 で除去)。
- **量**: `Math.round(maxhp / 2)`。非負整数では ceil(maxhp / 2) (奇数 151 → 76)。`battle-actions.ts:1438` (`applyRecoilDamage`)。
- **発動条件** (Showdown の `moveResult` / `totalDamage` に対応):
  - 命中: 実ダメージ (`dmg_for_effects`) > 0 のとき。`applyRecoilDamage` は `move.totalDamage` が真のときだけ呼ばれる (`battle-actions.ts:1040-1041`、量は `:1438`)。ばけのかわ の初撃ブロックは 0 ダメージなので反動なし。
  - 免疫 / 外れ (`MoveFail`): 対象が生存しているとき。対象不在 (`!target` は `battle-actions.ts:525`、`!targets.length` は `:574`) は `MoveFail` (`:591`) に届かず反動なし。外れは `per_side_attempt` の `SideAttempt.miss` (命中判定の外れだけ true。麻痺・睡眠の不発は false。崩れ技と同じフラグを使う)。
  - 行動しない (麻痺・睡眠・反動硬直・ひんし): 技が使われないので反動なし。着弾ターンに眠らされた使用者 (`action_blocked_by_fresh_status`) の外れも同じく反動なしで、眠りの 1 回目が消費される (崩れ技と同じ規則。DP は `miss_self_loss_outcomes` の後攻枝、MC は `*_blocked_mid_turn`)。
- **マジックガード**: 反動を無効化する。Showdown では `magicguard.onDamage` が `effect.effectType !== 'Move'` で弾き、steelbeam の condition は `effectType: 'Condition'` (`dex-conditions.ts`)。Champions `tokuseiinfo_syn.json:3442` "The Pokémon takes damage only from attacks." と一致。DP は mega 後の実効特性、MC は raw 特性 (MC は mega 未モデル)。
- **対象外**: Protect / Detect 系 (payoff 層に無い)。Showdown では Protect で `moveResult = false` になり反動は発動する (`moves.ts` の protect `onTryHit` が `NOT_FAIL` (= `''`) を返し、`hitStepTryHitEvent` (`battle-actions.ts:705-713`) で対象が落ちる)。Champions 側の文言は沈黙 (SILENT) のため、Protect を実装するときに同じ扱いにする。
- **順序**: 反動は使用者の leg の位置 (行動順) で適用する。DP は崩れ技と同じ `miss_self_loss_outcomes` (`switching_game_crash.mbt`) が外れ leg を行動順に挿入し、同速は両順序を 0.5 ずつ平均する。両者とも外した場合、崩れ技同士は順序に依らないが、反動は対象の生死を見るため両 leg を行動順に解決する (先に倒れた側には反動が入らない)。MC は `team_rollout` Step 3 の各 leg (`own_missed` / `opp_missed` → `mc_apply_miss_self_loss`)。
- **自己 KO**: HP は 0 床でクランプ。反動は実ダメージ適用の後 (対象の KO が先) に入る。MC は all-KO で即 return する既存 leg と同じ扱い。
- **参照テスト**: `src/payoff/switching_game_max_hp_recoil_wbtest.mbt` (DP: 命中・奇数丸め・感度・マジックガード・自己 KO・対象不在・免疫・外れの順序・外れ確率・`miss` フラグ)、`src/payoff/switching_game_miss_self_loss_wbtest.mbt` (DP: 崩れ技とてっていこうせんの同時外し・両者外しの行動順・同速の平均・着弾ターンの眠り)、`src/payoff/team_monte_carlo_max_hp_recoil_parity_wbtest.mbt` (MC leg 単位・ばけのかわ・`mc_resolve_attempt` の `missed`・DP/MC 値の parity・着弾ターンの眠り parity)、`src/damage/steelbeam_flags_test.mbt` (メガランチャー対象外・フラグ)、`src/migrate/m016_steelbeam_test.mbt` (データ)。

### ねむり (Champions 規則) — DP / MC

本家テキスト (Champions。`champout/rom-txt/usa/help_syn.json:26333`):

> After a Pokémon is put to sleep, it will remain asleep on its first turn, it will have a 1-in-3 chance of being cured on its second turn, and it will be cured on its third turn. A Pokémon that used the move Rest has no chance of being cured until its third turn.

JP (`champout/rom-txt/jpn/help_syn.json:23848`): 「ねむり状態になってから　１度目は技が使えない。２度目は　１／３の確率で回復する。３度目は　回復する。技ねむるでは　３度目まで回復しない。」 ねむる は `wazainfo_syn.json:2130` "The user falls asleep for 2 turns."、あくび は `wazainfo_syn.json:5264` "Makes the target drowsy."。

**状態表現** (`src/model/status_condition.mbt`):

- `Sleep(n)` — 通常ねむり (ねむり技、あくび経由)。眠ったまま技を出そうとするたびに `n` を 1 減らす。`n >= 2`: 確定で眠ったまま。`n == 1`: 1/3 で目覚めて行動 (命中判定あり)、2/3 で `Sleep(0)`。`n == 0`: 確定で目覚めて行動 (命中判定あり)。
- `RestSleep(n)` — ねむる 由来。`n >= 1`: 確定で眠ったまま、`n == 0`: 目覚めて行動。2 回目の抽選が無いのが `Sleep` との違い。`apply_healing` (`switching_game_effects.mbt`) が `RestSleep(2)` を直接書く。満タン失敗 / ふみん・やるき・スイートベール / エレキ・ミストの gate は従来どおり。
- `Drowsy(1)` (あくび) → EOT で `Drowsy(0)` → 次の EOT で `Sleep(2)`。Yawn 由来も通常ねむりの規則に従う。

**試行の数え方** (`per_side_attempt` / `mc_resolve_attempt`):

- 「眠らされてから技を出そうとした回数」を数える。先攻が眠らされる場合 (行動後に着弾) は翌ターンが 1 回目。
- 後攻が同ターンに眠らされる場合は、着弾ターンの行動 (眠ったまま) が 1 回目になる。`action_blocked_by_fresh_status` の枝で `consume_sleep_attempt_on_block` が `Sleep(2)` を `Sleep(1)` に進める (DP `transition_with_cache` と崩れ外れ時の `crash_second`、MC の mid-turn block 2 箇所)。Showdown `slp.onBeforeMove` が後攻の着弾ターンにも走るのと同じ。
- 交代: 眠りのカウンタは据え置き (交代は試行ではない。`per_side_attempt` は `Switch` で `Sleep` を進めない)。Champions 本文は交代を扱わないため Showdown に合わせた (`dl-pokemon/pokemon.ts:1530` の `clearVolatile` は boosts / volatiles を消すが status / statusState は残す)。
- 確率の枝: `Sleep(1)` の目覚め枝は `SLEEP_SECOND_TURN_WAKE_RATE` (= 1/3) × 命中。skip 回数は 1 (確率 1/3) か 2 (確率 2/3)。`RestSleep(2)` は skip 回数 2 固定。

**Showdown との比較** (`dl-conditions/conditions.ts` の `slp`: `startTime = random(2,5)`、`onBeforeMove` で減算、0 で目覚め。Rest は `time = 3` (`dl-moves/moves.ts:14959` 付近) なので 2 skip 後に目覚め、`RestSleep(2)` と一致): Showdown の通常ねむりは skip 回数が 1〜3 の一様分布。Champions 規則では 3 回目が確定目覚めのため skip は最大 2。Yawn は Showdown の volatile が 2 残留で `slp` を付与する (`moves.ts:21133` 付近) ので、付与から 2 ターン目の終わりに眠り、その次の試行が 1 回目 — pkdx の `Drowsy` 経路と一致。

**未対応 / 既知の近似**:

- ねごと / いびき (眠り中に使える技、JP help_syn.json:23848 "いびき　ねごと以外の技が使えない") は未モデル。眠りの行動制限は全技共通。
- はやおき (Early Bird、`tokuseiinfo_syn.json:1554` "awakens from sleep twice as fast") は未モデル。
- エレキ / ミストフィールドは眠りの付与のみ阻止 (`help_syn.json:28394` "they cannot fall asleep")。目覚めには影響しない。
- **同ターン再眠りの順序近似 (既存、DP / MC 共通)**: 目覚め抽選は `attempt_turn_with_cache` (DP) / 行動試行 (MC) で行動前に pre-turn 適用される。後攻が 2 回目 (1/3) で目覚めた直後に、同ターン先攻の眠らせ技が再び眠らせると、その標的は行動前にブロックされる。本家では先攻の技は眠ったままの標的に失敗し、標的は目覚めて行動する。Sleep(0) の既存挙動と同じ。例: 速い Spore 使いが遅い標的を毎ターン眠らせる fixture は DP / MC ともに標的が 0 回行動する。parity は取れるが期待値は本家とずれる。follow-up として「目覚めを後攻の leg 直前に適用する」順序修正が必要 (DP `transition_with_cache` と MC の mid-turn 2 箇所を同時に変える)。
- **参照テスト**: `src/payoff/switching_game_sleep_wbtest.mbt` (DP 分布・Rest・あくび・交代・着弾消費)、`src/payoff/team_monte_carlo_sleep_parity_wbtest.mbt` (MC 分布、DP/MC parity、感度ガード)、`src/payoff/team_monte_carlo_test.mbt` (着弾ブロックの MC 回帰)。

### こおり (Champions 規則) — DP / MC

本家テキスト (Champions。`champout/rom-txt/usa/help_syn.json:26184`):

> The Pokémon can't use almost any moves but has a 25% chance of being cured each time it tries to do so. The Pokémon will be cured on its third turn after becoming frozen or if it takes damage from a Fire-type move or certain other moves. Ice-type Pokémon are unaffected.

こおりタイプは凍らない (`help_syn.json:23193` "Ice Types ・ Cannot be frozen")。麻痺の 12.5% は同じ節の `help_syn.json:26071` (「12.5% chance of being unable to use moves」) で、`PARALYZE_SKIP_RATE` の根拠。

**状態表現** (`src/model/status_condition.mbt`):

- `Freeze(n)` — こおり。凍ったまま技を出そうとするたびに試行として数える。`n >= 1`: 25% (`FREEZE_THAW_RATE`) で解凍して行動 (命中判定あり)、75% で `Freeze(n-1)`。`n == 0`: 確定で解凍して行動 (命中判定あり)。付与時は `Freeze(2)`。
- 3 回の試行で必ず解凍する: 1 回目 1/4、2 回目 3/16、3 回目 9/16 (`switching_game_freeze_wbtest.mbt` の分布テスト)。
- 解凍技 (defrost) を使う凍った使用者は、乱数なしで行動前に解凍する (命中判定あり、外れても解凍)。対象は本文で「使用者を解凍」と書く フレアドライブ (`wazainfo_syn.json:7480`) / かえんボール (`:13396`) / もえつきる (`:12460`、炎タイプ使用者のみ) / ねっとう (`:9816`) / ねっさのだいち (`:14386`)、本文が黙る シャカシャカほう (`:15924`) は Showdown `flags.defrost` で補う。

**解凍 (こおり → None)**:

- 与ダメージのある 炎タイプ の攻撃技 (変化技は除く) が命中すると、二次効果より前に解凍する。本文 "takes damage from a Fire-type move" / Showdown `frz.onDamagingHit`。ダメージ 0 (ばけのかわ / 無効) では解凍しない。
- thawsTarget 技 (ねっとう / ねっさのだいち。本文 "Cures the user and target of being frozen"、`:9816` / `:14386`。シャカシャカほう は Showdown 補完) は命中後、二次効果の後に相手を解凍する (Showdown `onAfterMoveSecondary`)。凍っている間は やけど の二次効果が付かない。

**付与**:

- 技の追加効果 `status_effect` (FreezeKind、確率 %)。DB: `pkdx_patch/017_move_meta_freeze/data.json` (m017) が れいとうビーム / ふぶき / れいとうパンチ / こおりのキバ / フリーズドライ を 10% で投入 (本文 `wazainfo_syn.json:636` / `:658` / `:38` / `:8136`。フリーズドライ の `:11178` は凍結に触れないので Showdown の 10% で補う)。
- **トライアタック は未対応**: 本文 `:2208` "20% chance of leaving the target burned, frozen, or paralyzed" は 3 種を 1/3 ずつ振るが、`status_effect` は単一の種類と整数確率しか持てない (6.67% は表せない)。やけど / まひ の 3 分岐も同様に未モデル。
- 付与をブロックする条件 (`maybe_apply_status_fanout` / `mc_try_apply_status`): こおりタイプ、ミストフィールド (grounded、既存の `field_blocks_status`)、はれ (`Weather::Sun`)、マグマのよろい (`tokuseiinfo_syn.json:1348` "The Pokémon cannot be frozen.")、りんぷん (`:606` "immune to additional effects from attacks"、`power > 0` の技の追加効果のみ。やけど / まひ / どく / もうどく にも同じ規則で、下の節)。エレキフィールドは凍結を止めない (`field_blocks_status`)。既存の状態異常がある相手には付与しない (状態異常は同時に 1 つ)。
- はれ (Harsh Sunlight、`help_syn.json:27747`) の本文は凍結に触れない。Showdown `sunnyday.onImmunity` (`frz` → false) を採用 (判断事項)。
- リーフガード (`tokuseiinfo_syn.json:3566`、はれで状態異常を防ぐ)、ぜったいねむり、フラワーベール (ダブル専用) は未モデル。pkdx は他の状態異常にも同じ特性を適用していないため (「特性免疫」は眠りの Rest 経路のみ)。

**試行の数え方と行動時点の解決** (`per_side_attempt` / `mc_resolve_attempt`):

- 凍結の試行は「凍ってから技を出そうとした回数」。先攻が凍らされる場合 (行動後に着弾) は翌ターンが 1 回目。後攻が同ターンに凍らされる場合は、着弾ターンの行動試行が 1 回目 (#203 の眠りと同じ数え方)。この試行の 25% は本文どおり有効。
- 交代: 凍結カウンタは据え置き (交代は試行ではない)。`Switch` は `Freeze` を進めない。
- **行動時点の解決** (`freeze_roll_deferred` / `resolve_pending_freeze_attempt`、MC は Step 3): 両者が技を出す場合、相手の技が解凍 (炎の命中 / thawsTarget) か凍結 (こおりの追加効果) をしうるとき、その側の解凍抽選と命中は自分の行動時点で振る。先攻の技の結果 (解凍 / 凍結) が後攻の試行に反映される。遅らせない枝は事前抽選のままで、分布は同一。Showdown `frz.onBeforeMove` が行動時点で走るのと同じ順序。
- 後攻が凍らされた着弾ターンの試行は 25% の抽選を受ける。眠りの `consume_sleep_attempt_on_block` のように確定で行動を止めない (本文が「試行のたびに 25%」と書くため)。

**Showdown との比較** (`crash-scratch/freeze-showdown/conditions.ts` = `data/conditions.ts` の `frz`):

- 解凍確率: Showdown `frz.onBeforeMove` は `randomChance(1, 5)` = 20%。Champions 本文は 25% なので本文を採る。凍結の 3 ターン目の確定解凍は Showdown に無く本文由来 (Showdown の凍結は解凍されるまで続く)。
- 解凍技: `onModifyMove` で defrost 技は解凍後に技を出す (Showdown と同じ)。Burn Up は使用者が炎タイプでないと defrost されず、通常の試行になる (下記の未対応)。
- 炎の命中: `onDamagingHit` (`move.type === 'Fire' && move.category !== 'Status'`) と同じ。Polar Flare の例外 (`polarflare`) は Champions プールに無いので実装していない。

**未対応 / 既知の近似**:

- トライアタック (上記)。フレアドライブ 等の反動は既存の反動モデルのまま。
- もえつきる を炎タイプでない使用者が使った場合の「失敗」は未モデル (通常の試行として扱い、解凍しない。使用者の技は通常どおり解決)。
- 凍結の付与源は技の追加効果だけ (m017 は こおり 行のみ)。やけど / まひ / どく / もうどく の追加効果は m018 で投入 (下の節)。ひるみは未モデル。
- れいとうビーム 等の ふぶき「雪で必中」は未モデル (命中は 70 のまま)。こおりのキバ のひるみ 10% は未モデル。
- 「行動時点の解決」は凍っている側と凍らせる技の組み合わせだけに適用する。他の経路 (交代 / 行動しない相手) は事前抽選 (分布は同一)。
- **参照テスト**: `src/payoff/switching_game_freeze_wbtest.mbt` (試行の枝・分布・付与ブロック・解凍・着弾抽選・交代)、`src/payoff/team_monte_carlo_freeze_parity_wbtest.mbt` (MC の枝と真理値表、DP/MC parity と感度ガード)、`src/migrate/m017_freeze_test.mbt` (move_meta 投入の冪等性)。

### 攻撃技の二次状態異常 (やけど / まひ / どく / もうどく) — DP / MC

本家テキストの例 (`champout/rom-txt/usa/wazainfo_syn.json`、ラベル行の番号):

- やけど: ほのおのパンチ `:16` "Has a 10% chance of burning the target." / ねっとう `:9816` "Has a 30% chance of burning the target. Cures the user and target of being frozen."
- まひ: かみなりパンチ `:60` "Has a 10% chance of paralyzing the target." / でんじほう `:2936` "Paralyzes the target." (確率の記述なし = 100%)
- どく: ヘドロばくだん `:2848` "Has a 30% chance of poisoning the target." / キラースピン `:15152` "Poisons targets." (確率の記述なし = 100%)
- もうどく: どくどくのキバ `:5612` "Has a 50% chance of badly poisoning the target."

免疫・ブロック・既存の効果 (本文。判定は `secondary` 側の SSoT に従う):

- 免疫: ほのお は やけど (`help_syn.json:22637` "Fire Types ・ Cannot be burned")、でんき は まひ (`:22714` "Cannot be paralyzed")、どく / はがね は どく・もうどく (`:23003` / `:23500` "Cannot be poisoned or badly poisoned")。
- 特性: りんぷん (`tokuseiinfo_syn.json:606` "immune to additional effects from attacks") はダメージ技の追加効果を全 kind で止める。ちからずく (`:4170` "moves lose their additional effects, but ... boosted by 30%") は使用者の追加効果を失う。
- 効果 (既存): やけど は 1/16 EOT と物理半減 (`help_syn.json:25934`)、どく 1/8 EOT (`:25672`)、もうどく n/16 (`:25785`)、まひ は 12.5% 行動不能と素早さ半減 (`:26069`)。

**投入 (m018)**: `pkdx_patch/018_move_meta_status/data.json` (33 行、`src/migrate/m018_move_meta_status.mbt`)。各行の確率と行番号は m018 の doc コメントに列挙。内訳は やけど 14 (ほのおのパンチ 10 / かえんほうしゃ 10 / だいもんじ 10 / ねっぷう 10 全体 / ブレイズキック 10 / フレアドライブ 10 / ほのおのキバ 10 / ふんえん 30 全体 / ねっとう 30 / れんごく 100 / かえんボール 10 / ねっさのだいち 30 / ひゃっきやこう 30 / シャカシャカほう 20 全体)、まひ 10 (かみなりパンチ 10 / のしかかり 30 / １０まんボルト 10 / かみなり 30 / でんじほう 100 / とびはねる 30 / ボルテッカー 10 / かみなりのキバ 10 / ほうでん 30 全体 / ほっぺすりすり 100)、どく 8 (ヘドロばくだん 30 / どくづき 30 / クロスポイズン 10 / ダストシュート 30 / ヘドロウェーブ 10 全体 / シェルアームズ 20 / どくばりセンボン 50 / キラースピン 100 全体)、もうどく 1 (どくどくのキバ 50)。既存行 (フレアドライブ / ボルテッカー) は ailment 列だけ上書きし recoil を残す。m017 の こおり 行は触らない。

**投入しない技**: トライアタック `:2208` (やけど / こおり / まひ を 1/3 ずつ = 6.67%。単一の `status_effect` と整数確率で表せない)、フェイタルクロー `:14448` (どく / まひ / ねむり の 3 種。ねむりは本 PR の対象外)、しっとのほのお `:14120` (同ターンに相手の能力が上がった時だけ。能力上昇の追跡が必要)、くちばしキャノン `:12588` (接触技を受けた後に攻撃者をやけどにする別の仕組み)。

**判定規則** (DP `maybe_apply_status_fanout` + `secondary_gated_move` / MC `mc_try_apply_status`):

1. 追加効果は命中ごとに独立に抽選する (連続技は hit ごと。既存の per-hit 規則)。
2. この命中で相手の HP が減ったときだけ付く (`secondary_gated_move` の `hp_lost`。DP は `actual_dmg`、MC は `before - res_hp`)。ばけのかわ が初撃を吸収した命中は chip (最大 HP / 8) で HP が減るので付く (Showdown fallback、判断事項 1)。タイプ免疫と 特性による吸収 (そうしょく) は HP を減らさず、呼び出し元で抜けるので付かない。瀕死の対象 (HP 減少なし) にも付かない。命中で倒れた対象は HP 0 なので `maybe_apply_status_fanout` が付与しない。
3. 対象が既に状態異常なら付かない (こおり の凍結中も含む)。タイプ免疫。ミストフィールド (grounded) で止まる。エレキフィールドは止めない (既存の `field_blocks_status`)。
4. りんぷん (ダメージ技のみ) と ちからずく (攻撃側) で止める。マグマのよろい と はれ は こおり だけ止める。
5. 変化技 (power 0) の状態異常は追加効果ではなく命中後の直接効果で、りんぷん・ちからずく の影響を受けない。
6. 凍結解除: 炎のダメージ技の命中で凍結が解けた後は、同じ技の追加効果が付く (解凍は二次効果より前)。ねっとう / ねっさのだいち の解凍は二次効果の後 (既存の thawsTarget 規則)。
7. 後攻が先攻の技で やけど になった場合、後攻の物理攻撃は行動時点の状態で半減する (`resolve_moves` の `second_burn` / MC の `opp_burn_now`)。まひ の 12.5% 行動不能は行動時点では振らない (下記の既知の近似)。

**DB 経路の正規化 (二重抽選の防止)**: `move_meta.ailment_chance` は変化技では命中率と同値 (おにび 85 / 命中 85、でんじは 90 / 命中 90、ねむりごな 75 / 命中 75 など。champions.db の `move.accuracy` と一致を確認済み)。命中は `move.accuracy` で既に抽選されるので、DB 経路の変化技の `status_effect` は確率 100 に正規化する (`normalize_status_effect_chance`、`src/db/query_moves.mbt`)。正規化しないと 命中 × 確率 の二重抽選になる。ダメージ技の二次効果は ailment_chance が追加効果の確率なのでそのまま残す。JSON 入力 (`pkdx select`) の `status_effect` は従来どおりで、変化技の確率は命中後の確率として扱う (命中率は `accuracy` に書き、JSON の `accuracy` を 100 のままにする既存の入力はそのまま有効)。

**payoff への接続**: `pkdx moves` の JSON (`src/cli/format_moves.mbt` `moves_to_json`) は `status_effect` を `{"kind":和名,"chance":N}` で出す。`pkdx select` の `parse_move_json` は同じ形を読むので、DB の行は nash スキル経由の select まで届く。キーは既定値 (None) のとき省略する (キー無し = None と同じ結果)。変化技の確率は上記「DB 経路の正規化」で 100 に揃っているので、JSON 経由でも 命中 × 確率 の二重抽選は起きない。手書きの JSON 入力では、変化技は `accuracy` に命中率を書き `chance` は 100 にする (`chance` にも命中率を入れると二重抽選になる)。回帰テスト: `src/payoff/cli_select_moves_roundtrip_wbtest.mbt` (DB 実値の往復)、`src/cli/format_moves_wbtest.mbt` (出力形式)。

**Showdown との比較** (本文が沈黙する点だけ補う。今回の 33 行は全て本文の確率で足り、Showdown の確率は使っていない。以下は規則の照合のみ、`crash-scratch/freeze-showdown/abilities.ts` と `crash-scratch/mega-showdown/battle-actions.ts`):

- ちからずく: Showdown `sheerforce.onModifyMove` は `move.secondaries` を削除して追加効果を失わせ、`onBasePower` の 1.3 倍 (`[5325, 4096]`) も `hasSheerForce` の技 (= 追加効果のある技) だけに掛ける。本 PR は追加効果の削除を採用。威力の条件は pkdx で未対応 (上記 4)。
- りんぷん: Showdown `shielddust.onModifySecondaries` は `effect.self` でない追加効果を全て落とす。本 PR の規則 (ダメージ技の追加効果を全 kind で止める) と一致。

**判断事項 (Judgment calls)**:

1. **HP が減った命中だけ追加効果 (ばけのかわ の chip を含む)。Showdown fallback。** Champions 本文 (`tokuseiinfo_syn.json:6600`、LabelName 行、本文は OriginalText の "loses 1/8 of its max HP instead of taking the damage") は chip だけを述べ、追加効果には触れない。字面の Showdown では、`disguise.onDamage` が 0 を返し (`crash-scratch/dl-abilities/abilities.ts:970-976`)、`battle-actions.ts:1146` / `:1164` の `if (!damage[i] && damage[i] !== 0) targets[i] = false` は 0 ダメージの対象を残すので、追加効果は走る。本 PR はこれを採る: ばけのかわ の初撃でも 100% まひの ほっぺすりすり は まひ を入れる。コードを読んだ限り、b102445 (#208) も ばけのかわ の chip で こおり を付けていた (gate なし)。本 PR の gate 追加で一度落ちたため、同じ規則に戻した (こおり も同じ gate)。タイプ免疫・吸収 (そうしょく)・瀕死は HP を減らさないので付かない。
2. **二ターン技 (とびはねる `:6368`) は 1 ターンの近似で扱う**。pkdx は溜ターンを持たず、二ターン技も 1 ターンの技として解決する (既存)。まひ の追加効果はその命中ターンに付く。
3. **確率の記述がない技 (でんじほう / ほっぺすりすり / れんごく / キラースピン) は 100%**。本文 "Paralyzes the target." / "Burns the target." / "Poisons targets." を確定と読む (Showdown も chance 100 で一致)。
4. **ちからずく の威力 1.3 倍は既存の実装のまま全技に掛かる** (`damage/abilities.mbt` `get_atk_ability_final`)。本文は追加効果のある技だけ。本 PR では直さない (既存の入力の出力が変わるため)。
5. **りんぷん は こおり 以外の kind にも効かせる**。m017 の時点では こおり だけだったが、本 PR で ダメージ技の追加効果 (やけど / まひ / どく) へ広げた (本文 `:606` は種類を限定しない)。

**未モデル (既知の近似・未対応)**:

- フリンチ (ひるみ): こおりのキバ / ほのおのキバ / かみなりのキバ / 等。ひるみは本 PR の範囲外 (別 PR)。フリンチを足す時は、行動前の「ひるみ」判定を後攻の行動前に入れる (`action_blocked_by_fresh_status` と同じ位置) 必要がある。
- 複数状態異常の技: トライアタック (3 種 6.67% ずつ)、フェイタルクロー (どく / まひ / ねむり 各 10%)。単一の `status_effect` では表せない。
- 威力が条件で 2 倍になる技: ひゃっきやこう (状態異常の相手に 2 倍)、どくばりセンボン (毒の相手に 2 倍)、のしかかり (ミニマイズの相手に 2 倍)。確率の部分だけ入れ、威力は既存どおり (未モデル)。
- 特性 (状態異常の免疫・反射・EOT): じゅうなん `:256` (まひ免疫)、めんえき `:544` (どく免疫)、ねつこうかん `:7654` / すいほう `:6396` (やけど免疫)、きよめのしお `:7712` (全状態異常免疫)、リーフガード `:3566` (はれで免疫)、シンクロ `:926` (反射)、ふしょく `:6658` (毒・鋼 相手にも毒)、こんじょう `:2126` (状態異常中の攻撃 1.5 倍、やけどの物理半減無効)、ポイズンヒール `:3144` (毒中の回復)。どれも pure status 技と同様に未モデル (指示どおり、既存の免疫 helper を流用しない)。
- マジックガード: 状態異常の EOT (やけど / どく / もうどく) のダメージを防がない (既存の `eot_slip_active` が見ない)。
- ちからずく の威力 1.3 倍が全技に掛かる (上記 4)。
- 天候による命中 (かみなり の雨 / 晴れ の命中 50%)、ミニマイズ、フィールド効果の追加効果 (たつまき 等) は未モデル。
- 技由来でない状態異常 (ほのおのからだ 等の接触特性) は既存どおり (`apply_contact_proc_fanout`)。
- 変化技 (`power = 0`) の状態異常の命中・確率は既存のまま。JSON 入力で `accuracy` と `status_effect.chance` の両方に値を入れると二重抽選になる (既存の入力契約。DB 経路は正規化済み)。
- Champions に無い (参考): Serene Grace (てんのめぐみ 0 体)、Covert Cloak (かくれみの: items に無し)。

**既知の DP / MC 差 (本 PR の前から存在し、b102445 と数値が同一であることを確認済み)**: 確率つきの やけど / どく の追加効果で、DP と MC の値が状態によって乖離する。例 (1v1、特殊 威力 70 の技の追加効果を 特殊 威力 70 の相手に、4 ターン。タイプは非 STAB): やけど 30%: DP -0.400 / MC -0.198、どく 30%: DP 0.020 / MC 0.142、まひ 30%: DP -0.839 / MC -0.835。この 1 組の fixture では、終端の EOT ダメージを持つ やけど / どく で差が出て、EOT のないまひでは差が出なかった。物理の相手を使った 他の fixture では、やけど 30% の差が 0.001〜0.074 の範囲だった (威力・相手の攻撃種別で変化)。原因は未特定 (`apply_eot` の位置と終端の HP 比の読み方は両者で同じに見えた)。本 PR の parity テストは DP と MC が一致する形 (物理 威力 50 の相手、特殊 威力 50 の やけど 30%: DP 0.088 / MC 0.087、対照 -0.140 / -0.143) だけを使い、感度ガード (やけど の経路の差 0.23 > 0.005) を置く。

**参照テスト**: `src/payoff/switching_game_secstatus_wbtest.mbt` (付与の確率・免疫・ブロック・ちからずく / ばけのかわ の chip 経路 (まひ 100% / こおり 100%)・タイプ免疫と そうしょく の不発・解凍後の やけど・後攻の半減・りんぷん の e2e)、`src/payoff/team_monte_carlo_secstatus_parity_wbtest.mbt` (MC の分布・真理値表・ばけのかわ の chip・DP/MC parity と感度ガード)、`src/payoff/team_monte_carlo_freeze_parity_wbtest.mbt` (MC の ばけのかわ chip の こおり)、`src/migrate/m018_status_test.mbt` (投入の内容・既存行・冪等)、`src/db/status_effect_normalize_test.mbt` (DB 経路の正規化)。

### ひるみ (flinch, Champions 規則) — DP / MC

- 本文: `champout/rom-txt/usa/wazainfo_syn.json` の「N% chance of making the target flinch」(命中ごと)。特性: せいしんりょく は受けない (tokuseiinfo_syn.json:039)。ふくつのこころ はひるみで素早さ +1 (tokuseiinfo_syn.json:080)。りんぷん はダメージ技の追加効果を止め、ちからずく の使用者は追加効果を失う (既存のゲートを流用)。
- データ: `move_meta.flinch_chance` (m019、19 行 = 18 技 + 表記違い 1 件)。champions 経路は champout の全角 `３ぼんのや`、pokedex 経路は `3ぼんのや` (ASCII) で引くので両方を入れる。ねこだまし は m019 では行を作らない (初回行動ゲートは m020、下の節)。はやてがえし (相手の先制技が条件) は行を作らない (見送り)。DB → payoff 接続済み: `pkdx moves` の JSON (`moves_to_json`) は `flinch_chance` を出し (0 の技は省略)、`pkdx select` の `parse_move_json` が同じキーを読む。
- 規則 (DP / MC 共通): 先攻の技が命中して相手の HP が減り、相手が生存すると、命中数ぶんの独立抽選 (`1 - (1 - p)^n`) で `flinch_chance`% 成立する。成立した相手は同ターンの後攻の行動を失う (持ち越さない)。後攻が先に行動している場合は効かない。
- 行動時点の解決: 相手の技がひるみを付与しうる (`flinch_chance > 0`) ときは、こちらの試行 (眠り / 凍結 / まひ / 命中) を後攻の行動時点で振る (DP `flinch_roll_deferred`、MC `mc_flinch_deferred`、こおり の `freeze_roll_deferred` と同じ仕組み)。ひるみ成立枝は `flinched_outcomes` (DP / MC の SSoT) の分布を使い、命中判定を行わない。
- 優先度 (Showdown `data/conditions.ts`、Champions 本文は未記載): flinch 8 / slp・frz 10 (先に止まる) / par 1 (ひるみが先、まひ判定はしない) / mustrecharge 11 (リチャージは止まってひるみに到達しない)。defrost 技の使用者はひるみで止まっても凍ったまま (解凍は技の実行時)。ふくつのこころ は行動前にひるみが効いた枝だけ発火 (Showdown `Flinch` event)。せいしんりょく は付与自体を拒否 (`onTryAddVolatile`)。
- 状態: `SwitchingGameState.my_flinched` / `opp_flinched` (ターン内フラグ、`attempt_turn_with_cache` の出口で必ず false に戻す)。
- 判断事項: (1) ひるみ率は本文の % だけを使う (Showdown の確率は使わない)。2 ターン技 (ゴッドバード) は命中ターンに付ける 1 ターン近似 (とびはねる と同じ扱い)。(2) 多段技の命中数は DP が `1 - (1 - p)^n`、MC は 1 回として扱う (現データのひるみ技は全て単発)。おやこあい (`multi_hit.mbt` の 2 命中化) の 2 命中目も DP だけ抽選に入り、MC は 1 回 (状態異常の既存の近似と同じ)。(3) ばけのかわ の chip は HP 減少として数える (状態異常と同じ判定)。
- 未モデル: いびき の「ねむっている間だけ使える」(使用可否は未ゲート。ひるみ率だけ投入)、ドラゴンダイブ のミニマイズ時の威力 2 倍、はやてがえし (条件付き)、におい (TOKUSEIINFO_SYN_001: 特性由来の 10% ひるみ、本 PR の仕様外)、てんのめぐみ (追加効果の確率 2 倍、pkdx 全体で未モデル)、3ぼんのや の防御ダウン (既存の `stat_effects` 側の扱い)。ねこだまし は次の節。
- 既知の DP / MC 差 (本 PR で確認、ひるみ以前から存在): DP はダメージを平均値 1 点で扱い、MC は 16 乱数を抽選する。KO の閾値付近では終端値 (全滅 ±1) がずれる。例 (HP 200、たいあたり 60、ひるみなし、4 ターン): DP -1.000 / MC -0.937。parity テストは HP 1000 にして閾値を跨がせない (凍結 parity と同じ方針)。HP 1000、50% ひるみ: DP 0.000 / MC 0.001、対照 (ひるみなし) -0.068 / -0.068。
- 参照テスト: `src/payoff/switching_game_flinch_wbtest.mbt` (確率・ゲート・ふくつのこころ・眠り / まひ / 凍結 / defrost / リチャージ・持ち越し・SSoT 表・多段確率)、`src/payoff/team_monte_carlo_flinch_parity_wbtest.mbt` (MC の真理値表・分布・DP/MC parity と感度ガード)、`src/migrate/m019_flinch_test.mbt` (投入・既存行・冪等)、`src/db/query_moves_flinch_test.mbt` / `query_moves_flinch_wbtest.mbt` (DB 経路)、`src/payoff/cli_select_flinch_wbtest.mbt` (JSON 入力)。

### ねこだまし (Fake Out, WAZAINFO_SYN_252) — DP / MC

- 本文: `champout/rom-txt/usa/wazainfo_syn.json` 行 4432 (`WAZAINFO_SYN_252`)。"Makes the target flinch. This move fails unless it is the first move used by the user after it enters a battle." `help_syn.json` には該当文が無い。ひるみは「Makes the target flinch」なので確率抽選ではなく、命中すれば既存のひるみ経路で必ず付く (m020 の `flinch_chance` 100)。
- 状態: `SwitchingGameState.my_fresh` / `opp_fresh` (`Bool?`、サイドごと)。
  - `None` — select 入力で `my_fresh` / `opp_fresh` を省略した既定。失敗ゲートもひるみも掛けない。技は従来どおりの先制ダメージ技として解決し、`flinch_chance` が 100 でもひるまない。交代しても `None` のまま。既存の select 入力はここへ落ち、行列は変わらない。select は DB から `flinch_chance` も fresh も埋めない (入力 JSON が正)。
  - `Some(true)` — 登場後の初行動。バトル開始のリードで撃たせるときは呼び出し側が渡す。select は「毎選択がターン 1」とは仮定しない。
  - `Some(false)` — 登場後に技の行動を使った。ねこだまし は失敗する (ダメージもひるみも無い)。命中した扱いにはしない。
- 更新: ターン開始値から決める。`None` は何をしても `None`。`Some` は交代で `Some(true)` (そのターンは動かず、次のターンが初行動)、`UseMove` / `Mega` で `Some(false)`。技がひるみ・眠り・まひ・反動・外れで止まっても消費する。本文は "used" としか書かない。この消費位置は Showdown `sim/battle-actions.ts` の `runMove` 先頭 (`activeMoveActions++` が `BeforeMove` より前) に合わせた。交代で 0 に戻すのも同ファイルの `switchIn`。
- 他のひるみ技は fresh を見ない。せいしんりょく / りんぷん / ちからずく / ふくつのこころ / ひんし / 先攻だけ、は #210 の経路のまま。
- 見送り: はやてがえし (`WAZAINFO_SYN_918`、相手が先制技を撃とうとしているときだけ成功)。であいがしら (`WAZAINFO_SYN_660`) は同じ "first move" 文を持つがひるみは無く、本変更ではゲートしない。
- 参照テスト: `src/payoff/switching_game_fake_out_wbtest.mbt`、`src/migrate/m020_fake_out_test.mbt`。

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
- **吸収 / 免疫 leg**: DP は `with_absorb_effects` / `with_immune_effects` の単一 leaf で判定 (2) を通らず、MC は通る。観測できない: この leg は負のランクを作らず、負のランクを作る経路 (登場時いかく・`apply_stat_effects`) は直後に判定されるので、消費前の保持者に解除対象が残らない。
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
