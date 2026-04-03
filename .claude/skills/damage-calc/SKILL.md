---
name: calc
description: "ダメージ計算。攻撃側・防御側・技名を指定し、特性・持ち物・天候込みのダメージ乱数表を出力する。ダメージ計算・ダメ計・何発で落ちる等の質問時に使用。"
allowed-tools: Bash, Read, AskUserQuestion
---

# Damage Calculator

Lv50ダメージ計算スキル。特性・持ち物・天候・フィールド・テラスタル・急所に対応。16段階の乱数テーブルと確定数を出力する。

## パス定義

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../../..  （.claude/skills/damage-calc/ → repo root）
POKEDEX_DIR=$REPO_ROOT/pokedex
DB_PATH=$POKEDEX_DIR/pokedex.db
```

## Phase 0: 初期化

### 0-1: DB存在確認

```bash
SKILL_PATH="$(dirname "$(readlink -f ~/.claude/skills/damage-calc/SKILL.md 2>/dev/null || echo .claude/skills/damage-calc/SKILL.md)")"
REPO_ROOT="$(cd "$SKILL_PATH/../../../.." 2>/dev/null && pwd || pwd)"
test -f "$REPO_ROOT/pokedex/pokedex.db" && echo "OK" || echo "NOT_FOUND"
```

NOT_FOUNDの場合、以下を案内して**スキルを終了**:
```
pokedex DBが見つかりません。リポジトリルートで以下を実行してください:
  git submodule update --init
  cd pokedex && ruby tools/import_db.rb
```

---

## Phase 1: 入力取得（ステップ式）

ユーザーの発言から情報を抽出する。既に指定されている項目はスキップし、不足分のみ質問する。

### Phase 1-1: ポケモン・技名（テキスト入力）

未指定の場合、1つずつテキストで質問する:

1. 「攻撃ポケモンは？」→ ユーザーがテキストで回答
2. 「防御ポケモンは？」→ ユーザーがテキストで回答
3. 「技は？（日本語名）」→ ユーザーがテキストで回答

**テンプレートの選択肢は出さない。** ユーザーの自由入力を受け付ける。

### Phase 1-2: 修飾子選択（AskUserQuestion一括）

ポケモン名確定後、DBから特性一覧を取得:
```bash
sqlite3 "$REPO_ROOT/pokedex/pokedex.db" \
  "SELECT ability1, ability2, dream_ability FROM local_pokedex_ability
   WHERE globalNo='<globalNo>' AND version='<version>'
   AND COALESCE(form,'')='' AND COALESCE(region,'')=''
   AND COALESCE(mega_evolution,'')='' AND COALESCE(gigantamax,'')=''
   LIMIT 1;"
```

**AskUserQuestion 1**（4問、左右キー選択）:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 攻撃側特性は？ | 攻撃特性 | なし(default), {ability1}, {ability2}, {dream_ability} |
| 2 | 防御側特性は？ | 防御特性 | なし(default), {ability1}, {ability2}, {dream_ability} |
| 3 | 攻撃側持ち物は？ | 攻撃持物 | なし(default), こだわりハチマキ/メガネ, いのちのたま |
| 4 | 防御側持ち物は？ | 防御持物 | なし(default), しんかのきせき, とつげきチョッキ |

特性オプションはDBから取得した実際の特性を表示する。空の特性は除外。

**AskUserQuestion 2**（3問）:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 攻撃側の実数値は？ | 攻撃数値 | 特化(default), Other(数値入力) |
| 2 | 防御側の実数値は？ | 防御数値 | 特化(default), Other(数値入力) |
| 3 | 天候は？ | 天候 | なし(default), はれ, あめ, すなあらし |

---

## Phase 2: 計算実行

```bash
bash $SKILL_DIR/scripts/calc_damage.sh "<攻撃側名>" "<防御側名>" "<技名>" \
  [--version <ver>] \
  [--atk-ability <name>] [--def-ability <name>] \
  [--atk-item <name>] [--def-item <name>] \
  [--weather <type>] [--field <type>] \
  [--tera-type <type>] [--critical] \
  [--atk-stat <value>] [--def-stat <value>] [--def-hp <value>]
```

「なし」が選択された修飾子はオプションを省略する。

### 計算条件（デフォルト）

- **レベル**: 50
- **攻撃側**: 該当攻撃ステータス 252振り + 性格補正↑（物理技→A特化、特殊技→C特化）
- **防御側**: HP 252振り + 該当防御ステータス 252振り + 性格補正↑（物理技→HB特化、特殊技→HD特化）
- **個体値**: 全て31
- **カスタム数値指定時**: `--atk-stat`, `--def-stat`, `--def-hp` で実数値を直接上書き

### スクリプト出力形式

```
=== DAMAGE CALC RESULT ===
attacker|{name}|{types}|{stat_name}:{base}→{actual}
defender|{name}|{types}|HP:{base}→{actual}|{stat_name}:{base}→{actual}
move|{name}|{type}|{category}|{power}
modifiers|atk_ability:{name}|def_ability:{name}|...  (修飾子がある場合のみ)
stab|{yes/no}|{mult}x
type_effectiveness|{multiplier}x
label|85|86|...|100
damage|{d1}|{d2}|...|{d16}
percent|{p1}%|{p2}%|...|{p16}%
summary|{min}~{max}|{min_pct}%~{max_pct}%
ko|{確定数テキスト}
```

---

## Phase 3: 結果出力

スクリプト出力を以下のMarkdownテーブルに整形して提示する。

```markdown
## ダメージ計算結果

**{攻撃側名}** → **{防御側名}** / {技名}

### 条件
| 項目 | 値 |
|------|-----|
| 攻撃側 | {name} ({types}) |
| 攻撃特性 | {ability or なし} |
| 攻撃持ち物 | {item or なし} |
| 攻撃実数値 | {stat_name} {actual} ({detail}) |
| 防御側 | {name} ({types}) |
| 防御特性 | {ability or なし} |
| 防御持ち物 | {item or なし} |
| HP実数値 | {hp_actual} ({detail}) |
| 防御実数値 | {stat_name} {actual} ({detail}) |
| 天候 | {weather or なし} |
| 技 | {move_name} ({type}/{category}, 威力{power}) |
| タイプ一致 | {あり/なし} ({mult}x) |
| タイプ相性 | {eff}x |

### ダメージ乱数表
| | 85 | 86 | 87 | 88 | 89 | 90 | 91 | 92 | 93 | 94 | 95 | 96 | 97 | 98 | 99 | 100 |
|---|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|-----|
| ダメージ | {d} | {d} | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | {d} |
| 割合 | {%} | {%} | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | {%} |

### 確定数
**{min_dmg} ~ {max_dmg} ({min_pct}% ~ {max_pct}%)**
→ {確定1発 / 乱数1発(X/16) / 確定2発 / ... / 5発以上}
```

修飾子がない項目は条件テーブルから省略してよい。

---

## Phase 4: 追加計算（オプション）

AskUserQuestionで追加計算を提案:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 続けて計算しますか？ | 追加計算 | 別の技で計算, 別の相手で計算, 攻防入替, 終了 |

選択に応じてPhase 1に戻る（既知の情報は保持）。終了を選んだ場合はスキルを終了。

---

## エラーハンドリング

スクリプトが `error|` で始まる出力を返した場合、以下に従って対処する。

| エラーコード | 対応 |
|-------------|------|
| `db_not_found` | セットアップ手順を案内しスキル終了 |
| `attacker_not_found` | 「攻撃側ポケモンが見つかりません」→ 名前の再入力を依頼。リージョンフォームの可能性を案内 |
| `defender_not_found` | 「防御側ポケモンが見つかりません」→ 名前の再入力を依頼 |
| `move_not_found` | 「技が見つかりません。日本語名で入力してください」→ 再入力を依頼 |
| `status_move` | 「{技名}は変化技のためダメージを与えません」と案内 |
| `variable_power` | 「{技名}は威力が可変のため自動計算できません」と案内 |
| `immune` | 「タイプ相性または特性により無効（ダメージ0）です」と案内 |

## 対応している修飾子

### 攻撃側特性
ちからもち, ヨガパワー, はりきり, サンパワー, テクニシャン, てつのこぶし, がんじょうあご, メガランチャー, すてみ, すなのちから, すいほう, もらいび, てきおうりょく, フェアリースキン, スカイスキン, フリーズスキン, エレキスキン, こだいかっせい, クォークチャージ, トランジスタ, りゅうのあぎと, はがねのせいしん, ちからずく, アナライズ, いろめがね

### 防御側特性
ちょすい, よびみず, もらいび, ひらいしん, でんきエンジン, ふゆう, そうしょく, かんそうはだ, ファーコート, マルチスケイル, フィルター, ハードロック, こおりのりんぷん, あついしぼう, たいねつ, もふもふ, すいほう

### 攻撃側持ち物
こだわりハチマキ, こだわりメガネ, いのちのたま, たつじんのおび, ちからのハチマキ, ものしりメガネ, ふといホネ, でんきだま, 各タイプ強化アイテム（プレート・おこう系）

### 防御側持ち物
しんかのきせき, とつげきチョッキ, 各半減きのみ（オッカ・ヤチェ等全18種）

### 天候・フィールド
はれ, あめ, すなあらし, ゆき, エレキフィールド, グラスフィールド, サイコフィールド, ミストフィールド

### その他
テラスタル（`--tera-type`）, 急所（`--critical`）
