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
| TeamPayoffModel | 利得の作り方 (`switching_game` / `screened_switching_game:<trials>:<seed>:<keep_top>`)。turn_limit 既定は MC=5 / DP=5 (`switching_game:<N>` で個別上書き可) |
| BattleFormat | `single` = 3 体選出 (20x20) のみ対応 (`double` は現状未サポート) |

詳細はまず `references/` を参照:
- `references/theory.md` — 零和 LP / Simplex / Fictitious play / MWU の数式と根拠
- `references/exploitability.md` — exploitability / NashConv / KL / L1 の定義と使い分け
- `references/payoff_semantics.md` — SwitchingGame / ScreenedSwitchingGame の仕様と選択基準

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

team (6 体), opponent (6 体), format (single のみ対応), `team_payoff_model` を取得する。

#### データソース

1. **`box/teams/*.meta.json`** (推奨) — team-builder Phase 8 または Champions スクショ取り込みで生成される。`.meta.json` の `members` 配列がそのまま combatant として使える (`types[]` + `base_stats{}` 形式を `pkdx select` が直接受け付ける)。
2. **ユーザー直接入力** — 上記がない場合、ポケモン名・ステータス・技を対話で収集する。

#### `.meta.json` からの読み込み手順

```bash
# 1. 自チームの .meta.json を特定
ls box/teams/*.meta.json

# 2. members を team / opponent に詰め替えて select に渡す
# skill は .meta.json の "members" を "team" キーに、
# 相手の .meta.json の "members" を "opponent" キーに設定する。
# battle_format は "singles" → "single" に変換。
```

**重要**: `.meta.json` の `members` にはステータスが種族値 (`base_stats`) の場合と実数値 (`hp`/`atk`/...) の場合がある。Champions スクショ取り込み経由なら実数値が揃っているが、skill 手順で作成した場合は種族値のみの可能性がある。足りないデータ (実数値、priority、stat_effects 等) がある場合はユーザーに補完を促す。

#### モデル選択肢 (`team_payoff_model` フィールド)

- `"switching_game"` (既定) — 交代込み extensive-form ゲーム木。DP turn_limit=5 既定 (先制技 / ランク補正技に対応)。長期戦評価が必要なら `"switching_game:<N>"` で turn_limit を上書き可
- `"screened_switching_game:<trials>:<seed>:<keep_top>"` — MC で選出行列を screening (rollout turn_limit=5)、下位を quantile cutoff で枝刈り、残存 sub-matrix だけ SwitchingGame DP (refine turn_limit=5 既定)。例: `"screened_switching_game:1000:42:0.3"`。refine turn_limit を上書きしたいときは `"screened_switching_game:<trials>:<seed>:<keep_top>:<turn_limit>"`

**チューニングガイド (ScreenedSwitchingGame)**:

パラメータは 3 つ: `trials`, `seed`, `keep_top`。C(6,3)² = 400 セルの screening 空間を前提に設計。

| パラメータ | 推奨範囲 | 既定推奨 | 根拠 |
|---|---|---|---|
| `trials` | 500–2000 | 1000 | √1000 ≈ 32 → MC 標準誤差 ≈ 1/32 ≈ 3%。400 セル × 1000 trials = 400K rollout で Phase A 2–5 秒 |
| `keep_top` | 0.25–0.5 | 0.3 | 20 selections × 0.3 = 6 retained。Phase C コスト ∝ 6² = 36 セル (元の 9%)。Nash support サイズが通常 3–6 なので 0.3 で十分カバー |
| `seed` | 任意 UInt64 | 42 | 再現性が必要なら固定。同一 seed で同一結果を保証 |

**入力サイズ別ガイド**:
- **C(4,3)=4 selections**: keep_top ≥ 0.5 推奨 (4 × 0.3 = 1.2 → ceil = 2 は少なすぎる)
- **C(5,3)=10 selections**: keep_top=0.3–0.5 (3–5 retained)
- **C(6,3)=20 selections**: keep_top=0.25–0.3 (5–6 retained)。典型的なシングル 6v6 ケース

**Phase B 枝刈りの安全性**: screening 行列に Nash を解いてから、相手の Nash 均衡戦略下での期待値で各選出をスコアリングする。Nash support の選出はすべてゲーム値で同率首位になるため、`keep_top × n ≥ |Nash support|` であれば support が枝刈りされることはない。

**重要な trade-off**: screening は MC 40000-80000 rollout のオーバヘッドを伴う。`switching_game` が単独で 10 秒以内に完走する場合、screening を挟むと逆に遅くなる。先に `time bin/pkdx select` で素の `switching_game` を計測し、30 秒以上かかるとき初めて `screened_switching_game` を使う。Nash value は両モデル間で一致することを合成データで確認済み。

詳細は `references/payoff_semantics.md`。

#### 読みターン数の決定 (AskUserQuestion)

`team_payoff_model` 文字列を構築する直前に、ユーザーに「何ターン先まで読むか」を AskUserQuestion で必ず確認する。選択結果を `switching_game:<N>` / `screened_switching_game:<trials>:<seed>:<keep_top>:<N>` の `<N>` に埋め込む。

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 何ターン先まで読みますか？ | 読みの深さ | おまかせ（5ターン先まで・通常対戦向け）, じっくり読む（10ターン先まで・積み展開も評価／時間長め）, サクッと（3ターン先まで・パーティ調整中の素早い確認） |

ユーザー視点の言い換え（質問・選択肢に出す表現はこちら、内部で扱う turn_limit 値は次の対応表）:

| ラベル | turn_limit | こう案内する |
|---|---|---|
| おまかせ（5ターン先まで） | 5 | 通常の対戦想定。ほとんどの構築・選出で十分な精度 |
| じっくり読む（10ターン先まで） | 10 | 積み技や全抜き展開、長期戦の見極めに。計算は数倍〜10 倍ほど時間がかかります |
| サクッと（3ターン先まで） | 3 | パーティを調整しながら大まかな選出傾向だけ早く確認したいとき |

ユーザーが「Other」で任意の正整数を入力した場合はそれを `<N>` に埋め込む。負値・0 は弾く。「ターン」を「先読み」「深さ」と言い換えても OK だが、`turn_limit` / `DP` などの内部用語はユーザー向け文面に出さないこと。

**model 別のエンコード**:

- `switching_game` 選択時 → `"switching_game:<N>"`
- `screened_switching_game` 選択時 → `"screened_switching_game:<trials>:<seed>:<keep_top>:<N>"` (4 番目のフィールドとして付与)

### 実行

```bash
# 技の priority / stat_effects は `pkdx moves` の出力にそのまま乗ってくる
# ので、stdin JSON にはそのままコピペすれば DB 由来の情報が伝わる。
# 省略した場合はデフォルト (priority=0 / stat_effects=[]) で扱われる。
cat <<'JSON' | $PKDX select
{
  "team": [
    {"name":"P0","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":80,"spa":80,"spd":80,"spe":100,
     "ability":"","item":"","tera":"",
     "moves":[{"name":"のしかかり","type":"ノーマル","category":"物理","power":85,"priority":0,"stat_effects":[]}]},
    ...
  ],
  "opponent": [...],
  "format": "single",
  "stat_system": "champions",
  "team_payoff_model": "switching_game:<N>"
}
JSON
```

`<N>` は直前の AskUserQuestion で得た値を埋める (おまかせ=5 / じっくり読む=10 / サクッと=3、Other 入力時はその正整数)。`screened_switching_game` を選んだ場合は `"screened_switching_game:1000:42:0.3:<N>"` のように 4 番目のフィールドとして同じ値を付ける。

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

- **stat_system**: `pkdx select` は Champions SP 既定 (`"stat_system": "champions"`)。トップレベル JSON の `"stat_system"` フィールドで `"champions"` (既定) / `"standard"` を切り替え可能。旧バージョン (SV 等) のデータを使う場合は `"stat_system": "standard"` を明示する。
- **天候・フィールド・ランク**: 現バージョンは 0 固定。動的状態を含む選出最適化は将来対応。
- **tera_type**: `combatant.tera` フィールドで指定可能。攻撃側 STAB のみに作用し、防御側タイプ書換は未実装。
