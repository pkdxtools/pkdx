---
name: nash
description: "ナッシュ均衡ソルバー。零和対戦 (ポケモン選出、構築マッチアップ、じゃんけん型メタ) の最適混合戦略、選出最適化 (pkdx select)、メタ乖離分析 (pkdx meta-divergence) を提供。「最適選出」「選出分布」「構築メタ」「対面ジャンケン」「使用率 vs 最適」等の質問時に使用。"
allowed-tools: Bash, Read, AskUserQuestion
---

# Nash Equilibrium Skill

零和 2 人ゲームの混合戦略ナッシュ均衡ソルバーと、その上に構築された選出最適化・メタ乖離分析。

## パス定義

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../../..
PKDX=$REPO_ROOT/bin/pkdx
```

## 用語

| 用語 | 意味 |
|---|---|
| value | 行プレイヤーから見たゲーム値 (期待利得) |
| exploitability | 現在の戦略 σ に対する最良応答で得られる追加利得。零和で 0 なら σ は Nash 均衡 |
| support | 確率 > 0 の純戦略 index 集合 |
| PayoffModel | 利得の作り方 (`best1v1` = 最大ダメージ技+素早さで勝率 / `nash_responses` = 技×技内部 Nash) |
| BattleFormat | `single` = 3 体選出 (20x20) / `double` = 4 体選出 (15x15) |

詳細はまず `references/` を参照:
- `references/theory.md` — 零和 LP / Simplex / Fictitious play / MWU の数式と根拠
- `references/exploitability.md` — exploitability / NashConv / KL / L1 の定義と使い分け
- `references/payoff_semantics.md` — Best1v1 / NashResponses の仕様と選択基準

## Phase 0: 初期化

### 0-1: pkdx 存在確認

```bash
$PKDX nash --help >/dev/null 2>&1 && echo "OK" || echo "NOT_FOUND"
```

NOT_FOUND の場合は以下を案内してスキルを終了:
```
pkdx CLI が見つかりません。リポジトリルートで以下を実行:
  ./setup.sh
  cd pkdx && moon build --target native src/main
```

## Phase 1: タスク選択 (AskUserQuestion)

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 何を計算しますか？ | 計算種別 | 既知の行列を解く (nash solve), 選出最適 (select), メタ乖離分析 (meta-divergence), 構築マッチアップ DOT グラフ (nash graph) |

選択に応じて Phase 2 以降に分岐。

## Phase 2a: `pkdx nash solve` — 行列 / monocycle characters を解く

### 入力形式の決定

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 入力の種類は？ | 入力形式 | 行列を直接入力 (matrix), monocycle character (p, v) リスト (characters) |

**matrix 形式**: n×n の実数行列。対称・反対称を問わない。零和にしたい場合は `A[j,i] = -A[i,j]` を自前で設定するか、monocycle 形式を使う。

**characters 形式**: 各キャラに `label` (名前)、`power` (スカラー p)、`v` (2D ベクトル {x, y})。利得は `A[i,j] = (pᵢ − pⱼ) + vᵢ × vⱼ` で自動生成。

### 実行

```bash
cat <<'JSON' | $PKDX nash solve
{
  "matrix": [[0, 1, -1], [-1, 0, 1], [1, -1, 0]],
  "labels": ["R", "P", "S"]
}
JSON
```

または:

```bash
cat <<'JSON' | $PKDX nash solve
{
  "characters": [
    {"label": "A", "power": 0, "v": {"x": 2, "y": 0}},
    {"label": "B", "power": 0, "v": {"x": -1, "y": 1.7}},
    {"label": "C", "power": 0, "v": {"x": -1, "y": -1.7}}
  ]
}
JSON
```

出力 JSON:
```json
{
  "value": 0,
  "row_strategy": [0.333, 0.333, 0.333],
  "col_strategy": [0.333, 0.333, 0.333],
  "exploitability": 0,
  "support": {"row": [0, 1, 2], "col": [0, 1, 2]},
  "labels": ["R", "P", "S"]
}
```

### 結果整形

```markdown
## Nash 均衡結果

- **ゲーム値**: {value}
- **exploitability**: {exploitability} (< 1e-6 なら厳密解とみなしてよい)

### 行プレイヤーの混合戦略
| index | label | 確率 |
|---|---|---|
| 0 | {labels[0]} | {row_strategy[0]:.3f} |
...

### 列プレイヤーの混合戦略
(同上)

### support
- 行: {labels of support.row}
- 列: {labels of support.col}
```

## Phase 2b: `pkdx select` — 選出最適化

### 入力の収集

team (6 体), opponent (6 体), format (single/double), payoff_model (pairwise) または team_payoff_model (team-level) を取得する。team は `box/teams/` のキャッシュまたはユーザー直接入力。

#### モデル選択肢

**pairwise (`payoff_model` フィールド)**:
- `"best1v1"` (デフォルト) — 速くて分かりやすい、技選択は固定
- `"nash_responses"` — 内部 move-vs-move Nash、技循環をモデル化
- `"monte_carlo:<trials>:<seed>"` — seeded RNG でダメージ乱数込み (例: `"monte_carlo:1000:42"`)

**team-level (`team_payoff_model` フィールド、Phase 13)**:
- `"pairwise:<model_string>"` — 上記 pairwise のラッパー (`"pairwise:best1v1"` 等)
- `"switching_game:<turn_limit>"` — 交代込み extensive-form ゲーム木 (先制技 / ランク補正技に対応)

両方指定された場合は `team_payoff_model` 優先。詳細は `references/payoff_semantics.md`。

### 実行

```bash
cat <<'JSON' | $PKDX select
{
  "team": [
    {"name":"P0","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":80,"spa":80,"spd":80,"spe":100,
     "ability":"","item":"","tera":"",
     "moves":[{"name":"のしかかり","type":"ノーマル","category":"physical","power":85}]},
    ...
  ],
  "opponent": [...],
  "format": "single",
  "payoff_model": "best1v1"
}
JSON
```

出力:
```json
{
  "format": "single",
  "value": 0.0,
  "exploitability": 0.0,
  "selections": [[0,1,2], [0,1,3], ...],
  "selection_names": [["P0","P1","P2"], ...],
  "opp_selections": [...],
  "opp_selection_names": [...],
  "row_strategy": [...],
  "col_strategy": [...]
}
```

### 結果整形

確率 > 1% の選出のみ表示:

```markdown
## 選出分布 ({format})

- **期待勝率 (value)**: {value:.3f}
- **exploitability**: {exploitability:.6f}

### 採用すべき選出
| 確率 | 選出メンバー |
|---|---|
| {p:.1%} | {names} |
...

### 相手の最適選出
(同上)
```

## Phase 2c: `pkdx meta-divergence` — メタ乖離分析

### 入力の収集

- `usage`: 各ポケモン/構築の使用率 (合計 1)
- `matrix`: 対応するマッチアップ行列
- `labels`: 名前

### 実行

```bash
cat <<'JSON' | $PKDX meta-divergence
{
  "usage": [0.4, 0.3, 0.3],
  "matrix": [[0, 1, -1], [-1, 0, 1], [1, -1, 0]],
  "labels": ["R", "P", "S"]
}
JSON
```

出力:
```json
{
  "exploitability": 0.0,
  "expected_value": 0.0,
  "regrets": [0.0, 0.0, 0.0],
  "over_used": [],
  "under_used": [],
  "labels": ["R", "P", "S"]
}
```

### 結果整形

```markdown
## メタ乖離レポート

- **期待利得 σᵀAσ**: {expected_value:.3f}
- **exploitability**: {exploitability:.3f}

### 各要素の regret
| label | 使用率 | regret |
|---|---|---|
| {labels[i]} | {usage[i]:.1%} | {regrets[i]:+.3f} |

### 過剰使用 (over_used)
{names — 使用率 > 0 だが負の regret = 本来避けるべき}

### 過少使用 (under_used)
{names — 負の regret だが使用率 < ε = 本来選ぶべき}
```

## Phase 2d: `pkdx nash graph` — DOT 可視化

同じ入力 (matrix / characters) で Graphviz DOT を出力。

```bash
cat <<'JSON' | $PKDX nash graph --threshold 0.5
{"matrix": [[0, 1, -1], [-1, 0, 1], [1, -1, 0]], "labels": ["R", "P", "S"]}
JSON
```

`threshold` で |A[i,j]| がその値以下のエッジを削除。大きな行列の可視化で有効。

## エラーハンドリング

| 状況 | 対応 |
|------|------|
| `invalid JSON: ...` | 入力 JSON の構文エラー。再入力を依頼 |
| `missing field: ...` | 必須フィールド不足。仕様を再提示して再入力 |
| `both matrix and characters provided; pick one` | どちらか一方を削除 |
| `matrix is not square: NxM` | 正方行列に修正 |
| `usage does not sum to 1 (got X)` | 使用率を正規化し直す |
| `game is infeasible` / `unbounded` | 入力が退化 (LP が解けない)。対角/反対称性を確認 |

## 計算条件の注意

- **stat_system**: `pkdx select` は Standard (EV252/IV31) 既定。Champions SP を使いたい場合は damage 計算前にステータスを `--atk-stat` 等で override する必要がある (現バージョンでは未サポート)。
- **天候・フィールド・ランク**: 現バージョンは 0 固定。動的状態を含む選出最適化は将来対応。
- **tera_type**: `combatant.tera` フィールドで指定可能。攻撃側 STAB のみに作用し、防御側タイプ書換は未実装。
