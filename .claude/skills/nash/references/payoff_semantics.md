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
  SwitchingGame(Int)                                  // turn_limit
  ScreenedSwitchingGame(Int, UInt64, Double, Int)     // trials, seed, keep_top, refine_turn_limit
}
```

team-level の extensive-form ゲーム木として評価する。

### 状態空間

```moonbit
SwitchingGameState {
  my_active : Int            // 0..N
  opp_active : Int
  my_hps : Array[Int]        // 長さ N
  opp_hps : Array[Int]
  my_ranks : Array[Int]      // 長さ 5: [A, B, C, D, S]、active のランクのみ追跡
  opp_ranks : Array[Int]     // 長さ 5、交代でリセット
  turn : Int                 // 0..turn_limit
} derive(Show, Eq, Hash)
```

`HashMap[SwitchingGameState, Double]` (`StateCache`) に値を memoize。ランクは `[-2, +2]` にクランプして状態爆発を抑える（通常攻略で支配的な範囲を保ちつつ、±2 の飽和で `からをやぶる` 等の混合ランクアップを表現可能）。ランクはダメージ計算（`atk_rank` / `def_rank` 経由で `(2+|r|)/2` / `2/(2+|r|)` の乗数）と先制順序（実効素早さ）に反映される。

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

`move.stat_effects` が `[(stat_idx, delta), ...]` の形で載っている技 (DB の `move_meta` テーブルから populate) は、使用者のランクベクトルを `clamp_rank` (`[-2, +2]`) しながら更新する。`pkdx_patch/006_move_meta/data.json` に収録済みの主要な積み技: `つるぎのまい` (A+2), `りゅうのまい` (A+1/S+1), `めいそう` (C+1/D+1), `わるだくみ` (C+2), `てっぺき` (B+2), `ちょうのまい` (C+1/D+1/S+1), `からをやぶる` (A+2/C+2/S+2/B-1/D-1), `ロックカット` / `こうそくいどう` (S+2)。未登録名はデフォルトで効果なし — 追加は `data.json` に行を 1 つ足して `./setup.sh` を走らせれば反映される。

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

実到達 state は damage が整数刻みで離散化されるため有限。ランク (`my_ranks` / `opp_ranks`) は `[-2, +2]` に丸めて状態空間を抑える。6v6 実データ (Nosada vs カマカマキリ) での実測: turn_limit=1 は 1 秒未満、turn_limit=2 は 2 秒前後、turn_limit=3 は 40 秒前後で完走する (bit issue #38912f7b task C で pure-saddle fast path + node-level αβ-pruning 投入後)。turn_limit=4 以上は 5 分タイムアウトに収まらず、さらなる高速化は別タスクで検討。turn_limit を上げるほど積み技→全抜きのような多ターン脅威を評価できるようになるため、要件に応じて設定してよい (実用上限は現状 turn_limit=3)。`switching_game_winrate_stats` で `ValueStats.hits/misses` を取れるので、実行前に局所的に turn_limit を試して予算感を把握するのが推奨。

### LP 退化時の扱い (pure-saddle fast path)

選出レベル 20×20 行列と `value` 再帰内部で解く per-state Nash の双方で、payoff matrix が **pure saddle** (`max_i min_j A[i,j] == min_j max_i A[i,j]` が `SADDLE_TOL = 1e-10` 内で成立) となる退化ケースを検出した時点で LP ソルバを skip し、純戦略と saddle value を直接返す。`@nash.solve_zero_sum` と `payoff.value` の双方に実装。

**動機**: turn_limit=3 以上の実データで状態空間が HP 離散 × 限定的な行動空間で多数の near-identical cell を生み、二相シンプレックスが数値的に不安定な pivot を繰り返し `InconsistentGame("col strategy has negative component ...")` を返していた (Nosada vs カマカマキリ tl=3 で ~70 秒後に失敗)。pure-saddle 検出はこの class の入力を simplex に渡さず直接解決するため、bug 回避と速度向上を同時に達成する。

**影響**: 既存の単体テスト (RPS, matching pennies, 2×2 mixed 等) は `maxmin < minmax` が strict に成立するため fast path を通らず、従来どおり shift-and-normalise LP 経由で解かれる。退化していない mixed Nash ケースへの影響なし。

### αβ-pruning (node-level, conservative)

`value` 関数が `alpha`, `beta` の labeled args (デフォルト `-1.0`, `+1.0`) を受け取り、以下の node-level 枝刈りを行う:

1. Matrix を 1 行ずつ埋めながら `row_min[i] = min_j A[i,j]` を計算し、`lower = max over filled rows of row_min[i]` を更新 (pure-maximin 下限)。
2. `lower >= beta - 1e-12` が成立したら残りの行をスキップして `lower` を返す (β-cutoff)。Nash(A) ≥ lower ≥ β より呼び出し側の関心範囲を超える。
3. 全 cell 埋めた後に `upper - lower ≤ SADDLE_TOL` なら saddle と判定し LP skip。
4. 子再帰は常に `(-1.0, +1.0)` で呼ぶため子の返り値は exact → top-level 値は non-pruning reference とビット一致する (bit-exact regression 保証)。

実測で turn_limit=3 の dominant team 比較で visited state 数が 15 → 3 (80% 削減)。top-level value は変わらないが中間 LP 回避で wall-clock が短縮する。

### 技メタ (`priority` / `stat_effects`)

技の `priority` と自己ランク補正 (`stat_effects`) は `@model.Move` 構造体に載っていて、`pkdx moves` / `pkdx damage` のクエリ時に `local_waza` と `pkdx_patch/006_move_meta` の `move_meta` テーブルを LEFT JOIN して自動的に populate される (未登録技はデフォルト `priority=0` / `stat_effects=[]`)。

```moonbit
// @model.Move (抜粋)
pub(all) struct Move {
  ..., priority : Int, stat_effects : Array[(Int, Int)]
}
```

payoff 層 (`SwitchingGame` / `MonteCarloSim`) は再帰 / rollout 内で `move.priority` / `move.stat_effects` を直接参照するだけ。別キャッシュや lookup 関数は不要。

スキル側は `pkdx moves` 出力 (priority / stat_effects 込み) をそのまま `pkdx select` の stdin JSON に流し込めば DB 由来のメタが正しく伝わる。新技を追加するときは `pkdx_patch/006_move_meta/data.json` に行を追加するだけ — コード変更は不要。

### `ValueStats` / `DamageCache` (memoization 観測)

```moonbit
ValueStats { mut hits : Int, mut misses : Int }
DamageCache { data : HashMap[DamageKey, Int], mut hits : Int, mut misses : Int }

DamageKey { my_attacker : Bool, atk_idx, def_idx, mv_idx, atk_rank, def_rank : Int }
```

2 段のキャッシュを持つ:

- **ValueStats** — state-value memo。`HashMap[SwitchingGameState, Double]` が保持する「state → Nash 値」の hit/miss を記録。
- **DamageCache** — damage-table memo。`(side, atk_idx, def_idx, mv_idx, atk_rank, def_rank)` をキーに 16-roll 平均ダメージをキャッシュ。1 turn 内の `transition` からも、異なる state からの遷移からも再利用される。

`switching_game_winrate` は両キャッシュを内部で作って捨てる。`switching_game_winrate_stats` は `(Double, ValueStats, DamageCache)` を返し、テスト / 診断でキャッシュ動作を black-box 観測可能。production で `DamageCache` のキー空間は `2 × N_atk × N_def × N_mv × 5 × 5` で上限されるため (ランクは `[-2, +2]` クランプ)、state 数より圧倒的に小さく hit 比率は `misses ≪ hits` になる。

### CLI 文字列

JSON 入力の `team_payoff_model` フィールドで指定:

- `"switching_game:<turn_limit>"` 例: `"switching_game:3"`
- `"screened_switching_game:<trials>:<seed>:<keep_top>:<turn_limit>"` 例: `"screened_switching_game:1000:42:0.3:3"`

指定がなければ既定で `SwitchingGame(2)` が用いられる。

## ScreenedSwitchingGame (TeamPayoffModel)

### enum

```moonbit
TeamPayoffModel::ScreenedSwitchingGame(mc_trials: Int, mc_seed: UInt64,
                                       keep_top_quantile: Double,
                                       refine_turn_limit: Int)
```

Team-level の 2 段階パイプライン。既存 `SwitchingGame(3)` が 6v6 の C(6,3)² = 400 セル評価で 40 秒前後かかるため、team-level MC で「明らかに弱い選出」を事前に落としてから SwitchingGame DP を残存セルにだけ適用する。

### パイプライン

1. **Phase A — Screening**: `team_monte_carlo_value(selection_i, selection_j, mc_trials, mc_seed ^ cell_idx)` で全 400 セル (size_a × size_b) を埋める。cell_idx = `i * size_b + j` でセル独立な RNG 状態を派生
2. **Phase B — Pruning**: mean-based row/col score で top-`ceil(n * keep_top_quantile)` 行/列だけ残す (昇順ソート)
   - `row_score[i] = mean_j A[i,j]` (row 視点で高いほど良い)
   - `col_score[j] = -mean_i A[i,j]` (column 視点で高いほど良い、符号反転)
   - `min/max` は MC 有限試行ノイズに弱いため不採用。`mean` は統計的にロバスト
3. **Phase C — Refine**: 残存 sub-matrix `R[i', j'] = switching_game_winrate(...,  refine_turn_limit)` で精密評価

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

- Phase A: size_a × size_b × mc_trials × avg_turn × damage_calc ≈ (20 × 20 × 1000 × 10 × 数μs) ≈ 2-5 秒
- Phase C: retained_rows × retained_cols × SwitchingGame 評価時間 ≈ (retained率)² × 40 秒
- keep_top=0.3 なら 2-5 秒 + (0.3)² × 40 秒 ≈ 6 秒台の目安 (10 倍近い高速化)

### 使いどころ (実測ベースの指針)

**合成 6v6 (単純な 1 技ずつのチーム) で実測**:

| モデル | 時間 | Nash value | selections 数 |
|---|---|---|---|
| `switching_game:3` | 0.8 秒 | 0.3333 | 20 |
| `screened_switching_game:500:42:0.3:3` | 16.2 秒 | 0.3333 | 6 |

screening は **MC phase に 400 cells × N trials の rollout オーバヘッド**があり、素の `switching_game:N` が 10 秒以内に完走する場合は screening のほうが遅い。**使うべきは `switching_game:N` が 30 秒以上かかる場合のみ**。Nash value は両モデル間で一致 (合成データで確認済み、value agreement は強い sanity check)。

- `switching_game:3+` が 6v6 実データでタイムアウトに近い (40 秒前後) ケースのみ推奨
- turn_limit ≥ 4 を含む長期戦評価を screening 込みで行いたい場合の実用解
- 先に `time bin/pkdx select` で素の `switching_game:N` を計測し、遅いことを確認してから使う

### CLI 文字列

`"screened_switching_game:<trials>:<seed>:<keep_top>:<turn_limit>"`
例: `"screened_switching_game:1000:42:0.3:3"`

**バリデーション**: `trials > 0`, `turn_limit > 0`, `0 < keep_top <= 1`。`keep_top=0.0` は parser で即 reject。`keep_top > 1.0` も InvalidJson (short-circuit 経路は `>= 1.0` のみで、`1.5` のような不正値は parser で弾く)。

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
| 計算量 (6v6 single) | C(6,3)² × state数 × Nash | Phase A 2-5s + Phase C (keep²) × SG |
| 技選択 | 行動 Nash (技 + 交代) | Phase C で行動 Nash |
| 交代 | **モデル化** | **モデル化** (screen は簡易 / refine は精密) |
| 確率性 | 決定的 | 決定的 (screen の seed 固定) |
| 連続値 | [-1, +1] 連続 | [-1, +1] 連続 |
| 推奨場面 | 通常の選出最適 (turn_limit 1-3) | SG(3+) が 30 秒以上かかる大規模検証 |

## CLI / JSON フィールド

`pkdx select` は stdin の JSON で受ける:

```jsonc
{ "team": [...], "opponent": [...], "format": "single", "team_payoff_model": "switching_game:3" }
{ "team": [...], "opponent": [...], "format": "single", "team_payoff_model": "screened_switching_game:1000:42:0.3:3" }
```

`team_payoff_model` が未指定の場合は既定で `switching_game:2`。`payoff_model` / `pairwise:*` / `best1v1` / `nash_responses` / `monte_carlo:*` は全て**廃止済み**で、渡すと `InvalidJson` となる。

## 将来拡張

- `SwitchingGame` / `ScreenedSwitchingGame` の Double format 対応 (現在 Single 専用)
- 状態異常 / 天候 / フィールドのモデル化
- 変化技の効果拡充 — 現状は `move.stat_effects` 経由の自己ランク補正のみ。`pkdx_patch/006_move_meta/data.json` に行を足すだけで追加可能。状態異常・交代・ひるみ系に拡張する場合は `move_meta` テーブルのスキーマ (`stat_effects_json` 以外の effect kind 列) 追加と `@model.Move` 側のフィールド追加を検討
- `team_rollout` の ε-greedy から局所 Nash LP への切替 (rollout の変化技評価を精緻化)
- Aggressive αβ-pruning (child alpha/beta propagation) — 現状の node-level 保守的実装は子を常に `(-1, +1)` で呼ぶため bit-exact だが、速度は saddle skip に依存する
- Iterative deepening + transposition-table による action reordering — αβ の β-cutoff ヒット率を上げる

新 team-level variant は `TeamPayoffModel` enum と `team_payoff_matrix_with_team_model` ディスパッチに分岐を足す。pairwise 系は意図的に削除したため、再導入は非推奨。
