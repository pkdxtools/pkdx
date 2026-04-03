---
name: calc
description: "ダメージ計算。攻撃側・防御側・技名を指定し、特化同士のダメージ乱数表を出力する。ダメージ計算・ダメ計・何発で落ちる等の質問時に使用。"
allowed-tools: Bash, Read, AskUserQuestion
---

# Damage Calculator

特化同士（Lv50, 252振り+性格補正）のダメージ計算スキル。16段階の乱数テーブルと確定数を出力する。

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

## Phase 1: 入力取得

ユーザーの発言から以下を抽出する。不足があればAskUserQuestionで質問。

| 入力 | 必須 | 説明 |
|------|------|------|
| 攻撃側ポケモン名 | ○ | 日本語名 or 英語名 |
| 防御側ポケモン名 | ○ | 日本語名 or 英語名 |
| 技名 | ○ | **日本語名のみ対応** |
| バージョン | × | デフォルト: `scarlet_violet` |

AskUserQuestion例:
```
ダメージ計算に必要な情報を教えてください。
- 攻撃側ポケモン
- 防御側ポケモン
- 使用する技（日本語名）
```

---

## Phase 2: 計算実行

```bash
bash $SKILL_DIR/scripts/calc_damage.sh "<攻撃側名>" "<防御側名>" "<技名>" "<version>"
```

### 計算条件（固定）

- **レベル**: 50
- **攻撃側**: 該当攻撃ステータス 252振り + 性格補正↑（物理技→A特化、特殊技→C特化）
- **防御側**: HP 252振り + 該当防御ステータス 252振り + 性格補正↑（物理技→HB特化、特殊技→HD特化）
- **個体値**: 全て31
- **持ち物・特性・天候**: なし（素の計算）

### スクリプト出力形式

```
=== DAMAGE CALC RESULT ===
attacker|{name}|{types}|{stat_name}:{base}→{actual}
defender|{name}|{types}|HP:{base}→{actual}|{stat_name}:{base}→{actual}
move|{name}|{type}|{category}|{power}
stab|{yes/no}
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
| 攻撃実数値 | {stat_name} {actual} (種族値{base}, 252振り, 性格↑) |
| 防御側 | {name} ({types}) |
| HP実数値 | {hp_actual} (種族値{hp_base}, 252振り) |
| 防御実数値 | {stat_name} {actual} (種族値{base}, 252振り, 性格↑) |
| 技 | {move_name} ({type}/{category}, 威力{power}) |
| タイプ一致 | あり(1.5x) / なし |
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

---

## Phase 4: 追加計算（オプション）

AskUserQuestionで追加計算を提案:
```
別の技や相手で再計算しますか？
- 同じ攻撃側で別の技を計算
- 同じ攻撃側で別の防御側を計算
- 攻撃側と防御側を入れ替えて計算
- 終了
```

選択に応じてPhase 2に戻る。終了を選んだ場合はスキルを終了。

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
| `immune` | 「タイプ相性により無効（ダメージ0）です」と案内 |
