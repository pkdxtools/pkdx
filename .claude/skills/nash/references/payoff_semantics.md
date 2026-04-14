# PayoffModel 仕様と選択基準

`pkdx select` や `pkdx nash solve` (characters 形式以外) で利得を damage 計算から作る際の選択肢。実装は `src/payoff/from_damage.mbt` (`winrate`, `best1v1_winrate`, `nash_responses_winrate`)。

## 共通仕様

- 返り値は `[0, 1]` の winrate。最終行列 `A[i, j] = 2·winrate(i, j) − 1 ∈ [-1, +1]`
- 決定論的モデル (`Best1v1` / `NashResponses`) では `A[i, j] + A[j, i] = 0` が厳密に成立 (定義から自動保証)
- 確率的モデル (`MonteCarloSim`) では `from_combatants` 内で**上三角推定 + 対称補完** (`A[j, i] = -A[i, j]`) を強制し、有限試行ノイズで反対称性が崩れるのを防ぐ
- 対角は常に 0 (同一の自己対戦 → 速度タイ → 0.5 → payoff 0)

## Best1v1 (既定)

### 計算アルゴリズム

```
ta = min over a.moves of (defender_hp / avg_damage(a → b using move))
tb = min over b.moves of (attacker_hp / avg_damage(b → a using move))

if ta < tb:       winrate = 1.0
elif ta > tb:     winrate = 0.0
elif ta = ∞:      winrate = 0.5   # 両者とも通らない
elif a.spe > b.spe: winrate = 1.0
elif a.spe < b.spe: winrate = 0.0
else:             winrate = 0.5
```

- `avg_damage`: 16-roll の算術平均 (immune は 0)
- `turns_to_ko`: `defender_hp / avg_damage`、ダメージ 0 なら `+∞`

### 意図と限界

**意図**: 速くて分かりやすく、多くの対面で「結局これで勝つか負けるか」の近似として機能する。

**限界**:
- 交代・状態異常・フィールド等を無視
- 耐久技・回復技を考慮しない (ダメージ 0 なら勝てない扱い)
- 混合戦略 (技選択のランダム化) を許容しない

**使いどころ**: 使用率ベースのメタ分析、選出最適化の高速計算 (6v6 → 20×20 行列が数ミリ秒)。

## NashResponses

### 計算アルゴリズム

各対面 (i, j) について、a の技 × b の技の内部 |moves_a| × |moves_b| 行列を作り、ゼロ和 Nash を解いた値を `A[i, j]` とする:

```
inner[k, l] = encode(turns_to_ko(a, b, a.moves[k]), turns_to_ko(b, a, b.moves[l]), speed)
            ∈ {-1, 0, +1}
A[i, j] = (Nash_value(inner) + 1) / 2 - 0.5   # rescaled
```

### 意図と限界

**意図**: 技選択の commitment problem を明示的にモデル化。「A は強い技だが B のカウンターに弱い」といった循環が内部に含まれる場合、単純な最良応答選択 (Best1v1) では得られない戦略的価値を計算できる。

**限界**:
- 計算量: 6v6 で 36 小 Nash × 20 選出対 = 非自明に重い
- 技の外にある動作 (交代、持ち物発動、テラスタル) は依然考慮しない
- 内部 Nash の判定も ±1/0 の離散化 → 中間 (ダメージ量の僅差) は粗い

**使いどころ**: 行列内に循環が明らかな構成 (例: みず vs くさ vs ほのお 型の 3 タイプ技)、技選択が勝敗を決する特殊な構築。

## MonteCarloSim (Phase 12)

### enum

```moonbit
MonteCarloSim(trials: Int, seed: UInt64)
```

### 計算アルゴリズム

`@moonbitlang/core/random` の `Rand::chacha8` で seeded RNG を作成。N trials × turn loop:

1. 各側が `rollout_pick_move` (ε-greedy) で技を選択。ε=`default_rollout_epsilon = 0.1` の確率で全 move から一様、残りの確率で `pick_best_move` (power > 0 の中で平均ダメージ最大)。変化技も ε で非ゼロ確率で標本化される
2. 先攻決定: `turn_order_sign(a, 優先度_a, Spe_a, b, 優先度_b, Spe_b)`。優先度は `move_meta.move_priority` で解決、素早さ同値は RNG coin flip
3. 優先度順逐次解決:
   - 先攻 → 選ばれた技が power > 0 なら 16-roll table から `rng.int(limit=16)` でサンプル → defender HP 減算。power = 0 (status) の場合は damage なし
   - defender HP > 0 なら後攻も同様に行動
4. HP=0 で勝者確定 (1.0 / 0.0)、200 turn 上限で 0.5 (draw)
5. trials 回累積 → `winrate = total / trials ∈ [0, 1]`

### Seed 仕様

`Rand::chacha8(seed: Bytes)` は **32-byte seed 固定** (MoonBit core の既知仕様、それ以外で abort)。`seed_to_bytes` は UInt64 を下位 8 byte little-endian + 0 padding 24 byte で 32 byte に詰める。

### 意図と限界

**意図**: ダメージ乱数を陽に取り込んだ確率モデル。Best1v1 の三値 (0/0.5/1) より細かい連続値で、近接対面の優劣を粒度高く表現。

**限界**:
- 変化技 (power=0) はサンプルされても効果は未反映 (ランクアップ / 状態異常等の damage 外効果は無視される)。ただし ε-greedy により「変化技ターン = 相手のみ進行」として winrate に影響する
- ランク補正・状態異常・天候・特性発動・テラスタル等は計算しない
- turn_limit=200 を超える長期戦は draw 扱い
- 各 trial 独立サンプルなので有限試行ノイズあり (zero-sum 補完で対称性のみは保証)
- ε が大きすぎると変化技の偶発選択が winrate を潰すリスクあり。デフォルト 0.1 は実戦的バランスで、必要に応じて simulate_battle の `epsilon` 引数で調整可能

**使いどころ**: Best1v1 / NashResponses が三値で潰れる対面 (火力拮抗・ダメージ範囲が広い) の優劣判定。trials を増やすほど誤差は減るが、6v6 で C(6,3)² = 400 セルの上三角だと cell あたり trials 回 → 慎重に。

### CLI 文字列

`"monte_carlo:<trials>:<seed>"`。例: `"monte_carlo:1000:42"`。`trials > 0` 必須、`seed` は UInt64 (10 進文字列)。

## SwitchingGame (Phase 13, TeamPayoffModel)

### enum (新軸)

```moonbit
TeamPayoffModel {
  Pairwise(PayoffModel)    // Phase 0-12 互換
  SwitchingGame(Int)       // turn_limit
}
```

`PayoffModel` 拡張ではなく**別軸の enum**。pairwise 対面ごとに winrate を計算する既存ロジックは `Pairwise(...)` でラップ、SwitchingGame は team-level の extensive-form ゲーム木として独立に評価する。

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
  - 優先度は `move_meta.move_priority` で判定 (例: しんそく=+2, バレットパンチ=+1)
  - 実効素早さは Spe ランク (`effective_speed(base, rank)`) を反映
  - 先攻 attack → defender HP 減算 → 先攻の積み技効果を反映 → KO 判定 → 後攻 alive なら attack / 積み効果
  - 先制 KO の場合、後攻の action は実行されない (リアル戦闘準拠)
  - 優先度・実効素早さが完全一致 (`turn_order_sign = 0`) のときは両者同時に damage を適用

### 積み技 (ランク補正)

`move_meta.stat_boost_effect` が `Some([(stat_idx, delta), ...])` を返す技は、使用者のランクベクトルを `clamp_rank` (`[-2, +2]`) しながら更新する。サポート対象の主要な積み技は `つるぎのまい` (A+2), `りゅうのまい` (A+1/S+1), `めいそう` (C+1/D+1), `わるだくみ` (C+2), `てっぺき` (B+2), `ちょうのまい` (C+1/D+1/S+1), `からをやぶる` (A+2/C+2/S+2/B-1/D-1), `ロックカット` / `こうそくいどう` (S+2)。未登録名はデフォルトで効果なし（将来拡張時に `move_meta.mbt` の表を更新）。

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

実到達 state は damage が整数刻みで離散化されるため有限。ランク (`my_ranks` / `opp_ranks`) は `[-2, +2]` に丸めて状態空間を抑える。N=3 の実測では turn_limit=2〜5 まで無理なく完走する（各ノードの Nash LP は最大 6×6 で数μs、到達 state は memoization でカバー）。turn_limit を上げるほど積み技→全抜きのような多ターン脅威を評価できるようになるため、要件に応じて 5 程度まで設定してよい。`switching_game_winrate_stats` で `ValueStats.hits/misses` を取れるので、実行前に局所的に turn_limit を試して予算感を把握するのが推奨。

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

JSON 入力に `team_payoff_model` フィールドを追加:

- `"pairwise:<model_string>"` 例: `"pairwise:best1v1"` / `"pairwise:nash_responses"` / `"pairwise:monte_carlo:1000:42"`
- `"switching_game:<turn_limit>"` 例: `"switching_game:3"`

JSON 互換ルール:
1. `team_payoff_model` のみ → そのまま使用
2. `payoff_model` のみ → `Pairwise(parse_model(...))` に自動ラップ
3. 両方指定 → `team_payoff_model` 優先
4. 両方とも parse fail → `InvalidJson` raise

## 比較表

| 観点 | Best1v1 | NashResponses | MonteCarloSim | SwitchingGame |
|---|---|---|---|---|
| 種別 | pairwise (PayoffModel) | pairwise | pairwise | team-level (TeamPayoffModel) |
| 計算量 (6v6 single) | 6×6 ≈ 36 damage calc | 36 + 400 small Nash | 上三角 15 cells × N trials × N turns | C(6,3)² × state数 × Nash solve |
| 技選択 | 最大ダメージ固定 | 同時行動の Nash | greedy max-damage | 行動選択の Nash (技 + 交代) |
| 交代 | 無視 | 無視 | 無視 | **モデル化** |
| 確率性 | 決定的 | 決定的 | seeded RNG | 決定的 (期待ダメージ) |
| 連続値 | {0, 0.5, 1} 三値 | 同上 (内部 Nash で粒度) | [0, 1] 連続 | [-1, +1] 連続 |
| 推奨場面 | 通常の選出最適 | 技循環中心 | 火力拮抗 / 範囲広いダメージ | 交代戦が決定的 / 積み技や先制技が重要 |

## CLI / JSON フィールド

`pkdx select` は stdin の JSON で受ける:

```jsonc
// pairwise model (legacy field, Phase 0-12)
{ "team": [...], "opponent": [...], "format": "single", "payoff_model": "best1v1" }
{ "team": [...], "opponent": [...], "format": "single", "payoff_model": "nash_responses" }
{ "team": [...], "opponent": [...], "format": "single", "payoff_model": "monte_carlo:1000:42" }

// team-level model (new field, Phase 13)
{ "team": [...], "opponent": [...], "format": "single", "team_payoff_model": "pairwise:best1v1" }
{ "team": [...], "opponent": [...], "format": "single", "team_payoff_model": "switching_game:3" }
```

`team_payoff_model` が指定されたらそれを優先。なければ `payoff_model` を `Pairwise(...)` に自動ラップ。両方 malformed なら `InvalidJson` raise。

## 実装の検証

- `src/payoff/from_damage_test.mbt` に両モデルの単体テスト
- `nash_responses_matches_inner_game_value`: 1 手 vs 1 手の退化ケースで Best1v1 と一致することを確認 (内部 1×1 の Nash 値 = 単一セル値 = Best1v1 結果)

## 将来拡張

- `ChampionsSP(stat_system: StatSystem)` — SP 合計 66 制約下の最適化 (pairwise variant)
- `SwitchingGame` の Double format 対応 (現在 Single 専用)
- 状態異常 / 天候 / フィールドのモデル化 (MonteCarloSim と SwitchingGame の双方)
- ランク補正技の拡充 (現状 `move_meta.stat_boost_effect` の表を拡張するだけで対応可能)
- MonteCarloSim の ε-greedy から局所 Nash LP への切替 (rollout の変化技評価を精緻化)
- αβ pruning / iterative deepening — `SwitchingGameState` は不変・ハッシャブルで αβ 前提を満たすため、`value` に `alpha` / `beta` 引数を足してノード順序を勾配ヒューリスティックで並べれば実装可能 (状態表現の変更不要)

新 pairwise variant は `from_damage.mbt` の `winrate` match に分岐を足し、`payoff_model_enum_exhaustive` test を更新する。team-level variant は `TeamPayoffModel` enum と `team_payoff_matrix_with_team_model` ディスパッチに分岐を足す。
