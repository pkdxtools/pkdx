---
name: battle
description: "対戦中の高速応答モード。calc skillを事前ロードし、ダメ計とメモのラベル付き入力のみを最短で処理する。対戦中・バトル中・実戦中・対戦が始まる等の発話時に使用。"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Battle Mode

対戦中にスムーズに応答するためのモード。**ダメ計の出力**と**メモの追記**のみを行い、それ以外のテキスト応答は一切返さない。

## 応答スタイル（最優先・絶対遵守）

このスキルが起動している間、エージェントは以下のみを返す:

1. ダメ計ラベル入力 → ダメ計結果のテーブル（calc skill Phase 3 と同形式）
2. メモラベル入力 → 追記行 1 行のみ（例: `memo[12:34:56] 追記しました`）
3. 終了ラベル入力 → 終了処理の最終 1 行（保存先パス or 破棄通知）
4. ラベル無し入力 → 1 行のリマインダ（`ラベル(ダメ計:/メモ:/終了)を付けてください`）

**禁止事項**:
- 「次の指示をください」「他に何かありますか」「了解しました」等の対話継続プロンプト
- 思考過程・進捗ナレーション・補足解説
- ダメ計結果以外のチーム分析・戦略提案
- AskUserQuestion を Phase 1 (バトル中) で発火させること（ポケモン名/技名がユーザー入力から読み取れず計算不可能な場合の最小 1 問のみ例外）

## パス定義

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../../..  （.claude/skills/battle/ → repo root）
PKDX=$REPO_ROOT/bin/pkdx
SESSION_TS=$(date +%s)
MEMO_FILE=/tmp/pkdx_battle_memo_${SESSION_TS}.md
TEAM_FILE=""           # チーム未選択時は空のまま
DMG_LOG=/tmp/pkdx_battle_dmg_${SESSION_TS}.md   # ダメ計結果のセッション内蓄積
```

`MEMO_FILE` のパスは Phase 0 完了時にユーザーへ 1 度だけ通知する。ユーザーが任意のエディタで開いて確認できるようにするため。

---

## Phase 0: 初期化（ユーザー応答なしで連続実行する部分）

### 0-1: calc skill の事前ロード

ダメ計ロジック（特殊技・特性・持ち物・壁・連続技などの全パターン）をコンテキストに展開しておく。**Skill ツールでは起動しない**（calc の Phase 1 対話フローへ突入してしまうため）。Read のみで知識をロードする。

```
Read $REPO_ROOT/.claude/skills/calc/SKILL.md
Read $REPO_ROOT/.claude/skills/calc/references/special_cases.md
```

### 0-2: pkdx 動作確認

```bash
$PKDX query "ピカチュウ" --format json >/dev/null 2>&1 && echo OK || echo NG
```

NG の場合は `./setup.sh を実行してください` と返してスキル終了。

### 0-3: メモ・ダメ計ログ初期化

```bash
SESSION_TS=$(date +%s)
MEMO_FILE=/tmp/pkdx_battle_memo_${SESSION_TS}.md
DMG_LOG=/tmp/pkdx_battle_dmg_${SESSION_TS}.md
: > "$MEMO_FILE"
: > "$DMG_LOG"
```

### 0-4: チーム選択（AskUserQuestion その 1）

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | バトルチームを選択しますか？ | チーム選択 | はい, いいえ |

- 「いいえ」→ Phase 0-6 へ（`TEAM_FILE` 空のまま）
- 「はい」→ Phase 0-5 へ

### 0-5: チームファイル選択（AskUserQuestion その 2、はい のときのみ）

```bash
ls "$REPO_ROOT/box/teams/"*.meta.json 2>/dev/null
```

得られたファイルパスをオプションに並べる（表示は basename）。最大 5 件、それ以上は「Other」で自由入力させる。

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | どのチームを使いますか？ | チームファイル | <basename1>, <basename2>, ..., Other |

選択結果からフルパスを `$TEAM_FILE` に保存し、内容を全文 Read する。`members[]` から各ポケモンの以下を抽出してエージェント側で保持する:

| 保持キー | 用途 |
|----------|------|
| `name` | ダメ計の `<attacker>` / `<defender>` 引数 |
| `types[]` | タイプ一致判定の事前確認 |
| `ability` | `--atk-ability` / `--def-ability` |
| `item` | `--atk-item` / `--def-item` |
| `nature` | `--atk-nature` / `--def-nature` |
| `actual_stats.{h,a,b,c,d,s}` | `--atk-stat` / `--def-stat` / `--def-hp` (override) |
| `moves[].name` | ダメ計時の技候補。ユーザーが略称で言及してもこのリストから補完 |

`base_stats` は override の整合確認のために控えるだけで、ダメ計コマンドへは渡さない（actual_stats が SSoT）。

### 0-6: 起動完了通知（1 ブロック）

以下のフォーマット 1 つだけを返してバトル中ループへ入る。

```
battle mode ready (memo=/tmp/pkdx_battle_memo_<ts>.md, team=<basename or none>)
```

これ以降、Phase 1 のラベル入力を待つだけで、こちらから追加の発話はしない。

---

## Phase 1: バトル中ループ（ラベル分岐）

ユーザー入力の冒頭にあるラベルで分岐する。ラベルは以下のどれかにマッチする:

| パターン | 分類 |
|----------|------|
| `ダメ計:` / `ダメ計：` / `ダメ計 ` 始まり | ダメ計 |
| `メモ:` / `メモ：` / `メモ ` 始まり | メモ |
| `終了` / `対戦終了` / `バトル終了` 単独行 or 始まり | 終了 |
| 上記以外 | ラベル無し |

### 1-A: ダメ計

ラベル後の本文をパースして `pkdx damage` を 1 発で叩く。**AskUserQuestion は使わない**（最小 1 問の例外を除く）。

#### 入力例の解釈

- `ダメ計: 自分カバルドン → 相手ガブリアス じしん` → カバルドンが攻撃側、ガブリアスが防御側
- `ダメ計: 受け側 マンムー こおりのつぶて` → 自分のマンムーが受ける？ それとも撃つ？ 文脈から判断、不明なら攻撃側として処理し、必要なら 1 行コメントで補足
- `ダメ計: メガリザY ソラビ → カバ` → 略称は `pkdx query` で正式名にせず、まずチームメンバー名・特殊計算パターン名（calc skill の references 参照）と照合して一意に解決

#### TEAM_FILE が設定されている場合

そのポケモンが `members[]` に含まれていれば、保持中の `ability` / `item` / `nature` / `actual_stats` を **黙って自動展開する**:

```bash
$PKDX damage "<atk>" "<def>" "<move>" \
  --atk-ability "<members[atk].ability>" \
  --atk-item    "<members[atk].item>" \
  --atk-nature  "<members[atk].nature>" \
  --atk-stat    "<members[atk].actual_stats.a or .c>" \
  --def-ability "<members[def].ability>" \
  --def-item    "<members[def].item>" \
  --def-nature  "<members[def].nature>" \
  --def-stat    "<members[def].actual_stats.b or .d>" \
  --def-hp      "<members[def].actual_stats.h>" \
  --version champions \
  --format json
```

物理/特殊判定は技の `category` から決定（チームの `members[i].moves[]` または `pkdx moves` から取得）。

#### TEAM_FILE が空、または相手側が外部ポケモン

`pkdx damage` は最低限の引数（attacker/defender/move）のみで叩き、デフォルト計算（A/C 特化、HP 最大投資、性格補正↑）に乗せる。ユーザーが `ダメ計:` 本文で `特性=ちからもち` や `持ち物=こだわりハチマキ` のように書いていればそれだけ反映する。

#### 出力フォーマット

calc skill Phase 3 のテーブルと同じ。**ただし「条件」ブロックは攻撃側名/防御側名/技名/min-max/確定数の 1 行サマリに圧縮し、修飾子の表は省略可**（バトル中の視認性優先）。例:

```
ガブリアス じしん → カバルドン (B176)
最低 38.6% 〜 最高 45.6% / 確定3発
[85] 38.6  [86] 39.5  [87] 40.0  [88] 40.9  ... [100] 45.6
```

ユーザーが詳細表を要求した場合（例: 本文に `詳細` を含む）のみフルテーブルを返す。

#### ダメ計結果の蓄積

毎回 `$DMG_LOG` に append する（Phase 2 の保存に使う）。

```bash
{
  echo ""
  echo "### [$(date +%H:%M:%S)] <atk> <move> → <def>"
  echo "<min%>〜<max%> / <確定数>"
  echo '```json'
  echo "<pkdx damage --format json の出力>"
  echo '```'
} >> "$DMG_LOG"
```

### 1-B: メモ

ラベル後の本文をそのまま `$MEMO_FILE` に追記する。

```bash
{
  echo ""
  echo "[$(date +%H:%M:%S)] <input本文>"
} >> "$MEMO_FILE"
```

応答は **1 行のみ**:

```
memo[HH:MM:SS] 追記しました
```

### 1-C: 終了

Phase 2 へ遷移する。

### 1-D: ラベル無し

以下 1 行のみ返す:

```
ラベル(ダメ計:/メモ:/終了)を付けてください
```

---

## Phase 2: 終了処理

### 2-1: TEAM_FILE が空の場合

```bash
rm -f "$MEMO_FILE" "$DMG_LOG"
```

返答 1 行:

```
battle ended (memo discarded)
```

→ スキル終了。

### 2-2: TEAM_FILE が設定されている場合

AskUserQuestion 1 問:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 対戦ログをチームへ紐付けて保存しますか？ | ログ保存 | はい, いいえ |

「いいえ」→

```bash
rm -f "$MEMO_FILE" "$DMG_LOG"
```

返答:

```
battle ended (memo discarded)
```

「はい」→ ログ書き出し:

```bash
SLUG=$(basename "$TEAM_FILE" .meta.json)
LOG_PATH="$REPO_ROOT/box/teams/${SLUG}-battle-log-$(date +%Y-%m-%d-%H%M%S).md"

{
  echo "# 対戦ログ - ${SLUG}"
  echo ""
  echo "- 日時: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "- チーム: ${SLUG}"
  echo ""
  echo "## メモ"
  cat "$MEMO_FILE"
  echo ""
  echo "## ダメ計記録"
  cat "$DMG_LOG"
} > "$LOG_PATH"

rm -f "$MEMO_FILE" "$DMG_LOG"
```

返答 1 行:

```
battle log saved: <LOG_PATH>
```

→ スキル終了。

---

## エラーハンドリング

| 状況 | 対応 |
|------|------|
| `pkdx damage` が `Error:` で始まる出力を返した | エラーメッセージを 1 行で返す。再質問はしない（ユーザーが入力を直して再投入する） |
| `box/teams/*.meta.json` が 0 件で「はい」が選ばれた | 1 行で `box/teams/ にメタデータ無し、チーム未選択モードで起動` と返して TEAM_FILE 空のまま続行 |
| メモ/ログのファイル書き込み失敗 | 1 行でエラー通知。スキルは終了せず Phase 1 ループを継続 |
