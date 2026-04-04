---
name: training-sim
description: "ポケモン育成シミュレーション。性格・特性・持ち物・技・努力値を対話的に設定し、Lv50実数値を算出する。育成したい・実数値計算・努力値配分等の質問時に使用。"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Pokemon Training Simulator

ポケモン1体の育成データを対話的に構築するスキル。性格・特性・持ち物・技・努力値を順に決定し、Lv50での実数値を常にフィードバックする。完成した育成データはダメージ計算（calc skill）に連携可能。

**v1スコープ**: 通常フォーム限定。リージョンフォーム・メガシンカフォーム等は対象外。

## パス定義

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../../..  （.claude/skills/training-sim/ → repo root）
PKDX=$REPO_ROOT/bin/pkdx
```

## 実数値計算式

Lv50, IV=31固定で以下の式を使用する。スキル実行中、Claudeがこの式に従い計算を行う。

```
HP = floor((base*2 + 31 + floor(EV/4)) * 50 / 100) + 60
他 = floor((floor((base*2 + 31 + floor(EV/4)) * 50 / 100) + 5) * nature_mod)

nature_mod: 上昇=1.1, 無補正=1.0, 下降=0.9
```

EV=0時の近似: HP → base+75, 他 → base+20（無補正）
EV=252時の近似: HP → base+107, 他 → base+52（無補正）

## 性格テーブル

| 性格 | 上昇(×1.1) | 下降(×0.9) |
|------|-----------|-----------|
| いじっぱり | こうげき | とくこう |
| さみしがり | こうげき | ぼうぎょ |
| やんちゃ | こうげき | とくぼう |
| ゆうかん | こうげき | すばやさ |
| ずぶとい | ぼうぎょ | こうげき |
| わんぱく | ぼうぎょ | とくこう |
| のうてんき | ぼうぎょ | とくぼう |
| のんき | ぼうぎょ | すばやさ |
| ひかえめ | とくこう | こうげき |
| おっとり | とくこう | ぼうぎょ |
| うっかりや | とくこう | とくぼう |
| れいせい | とくこう | すばやさ |
| おだやか | とくぼう | こうげき |
| おとなしい | とくぼう | ぼうぎょ |
| しんちょう | とくぼう | とくこう |
| なまいき | とくぼう | すばやさ |
| おくびょう | すばやさ | こうげき |
| せっかち | すばやさ | ぼうぎょ |
| ようき | すばやさ | とくこう |
| むじゃき | すばやさ | とくぼう |
| てれや | -- | -- |
| がんばりや | -- | -- |
| すなお | -- | -- |
| きまぐれ | -- | -- |
| まじめ | -- | -- |

---

## Phase 0: 初期化

### 0-1: DB存在確認

```bash
$PKDX query "ピカチュウ" --format json >/dev/null 2>&1 && echo "OK" || echo "NOT_FOUND"
```

NOT_FOUNDの場合、以下を案内して**スキルを終了**:
```
pkdx CLIまたはpokedex DBが見つかりません。リポジトリルートで以下を実行してください:
  git submodule update --init
  cd pokedex && ruby tools/import_db.rb
  cd pkdx && moon build --target native
```

### 0-2: バージョン選択

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | ゲームバージョンは？ | バージョン | scarlet_violet(default), legendsza, Other(バージョン名を入力) | false |

---

## Phase 1: ポケモン選択

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 育成するポケモンは？ | ポケモン | "Otherで回答してください" (desc: ポケモン名を入力), "Otherで入力" (desc: 日英どちらも対応) | false |

テンプレートのポケモン名をオプションに含めてはならない。

取得したポケモン名で以下を実行:
```bash
$PKDX query "<ポケモン名>" --version "<version>" --format json
```

**結果が空の場合**: 名前の確認を再度AskUserQuestionで依頼。リージョンフォームやメガシンカフォームの場合は「v1では通常フォームのみ対応しています」と案内。

JSONから `hp`, `atk`, `def_`, `spa`, `spd`, `spe`, `type1`, `type2`, `ability1`, `ability2`, `dream_ability` を抽出。

### 初期 Stat Card 表示

EV=0, 無補正で実数値を計算し表示する:

```
=== Stat Card (初期状態: EV=0, 無補正) ===
<name> (<type1>/<type2>)

         種族値  個体値  努力値  実数値
HP        <hp>    31      0     <calc>
こうげき   <atk>   31      0     <calc>
ぼうぎょ   <def>   31      0     <calc>
とくこう   <spa>   31      0     <calc>
とくぼう   <spd>   31      0     <calc>
すばやさ   <spe>   31      0     <calc>

特性: {ability1} / {ability2} / {dream_ability}
```

### Training State 出力

```
=== Training State (Phase 1完了) ===
ポケモン: <name> (<type1>/<type2>)
種族値: H<hp> A<atk> B<def> C<spa> D<spd> S<spe>
性格: 未選択
特性: 未選択
持ち物: 未選択
技: 未選択 / 未選択 / 未選択 / 未選択
EV: H0 A0 B0 C0 D0 S0 (残り: 510/510)
実数値: H<hp> A<atk> B<def> C<spa> D<spd> S<spe>
```

---

## Phase 2: 性格選択

**AskUserQuestion**（1問）:

上昇ステータス別にグループ化して提示する。

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 性格を選んでください | 性格 | こうげき↑: いじっぱり/さみしがり/やんちゃ/ゆうかん, ぼうぎょ↑: ずぶとい/わんぱく/のうてんき/のんき, とくこう↑: ひかえめ/おっとり/うっかりや/れいせい, とくぼう↑: おだやか/おとなしい/しんちょう/なまいき, すばやさ↑: おくびょう/せっかち/ようき/むじゃき, 無補正: てれや/がんばりや/すなお/きまぐれ/まじめ | false |

各オプションには desc として「<上昇ステータス>↑ <下降ステータス>↓」を付与する（無補正は「補正なし」）。

### 性格補正を反映した Stat Card を再表示

性格テーブルを参照し、上昇ステータスに×1.1、下降ステータスに×0.9を適用して全実数値を再計算。

```
=== Stat Card (性格: <nature> — <stat>↑ <stat>↓) ===
<name> (<type1>/<type2>)

         種族値  個体値  努力値  実数値  補正
HP        <hp>    31      0     <calc>  --
こうげき   <atk>   31      0     <calc>  ↑/↓/--
ぼうぎょ   <def>   31      0     <calc>  ↑/↓/--
とくこう   <spa>   31      0     <calc>  ↑/↓/--
とくぼう   <spd>   31      0     <calc>  ↑/↓/--
すばやさ   <spe>   31      0     <calc>  ↑/↓/--
```

### Training State 出力

---

## Phase 3: 特性選択

Phase 1で取得した `ability1`, `ability2`, `dream_ability` から空でないものを選択肢とする。

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 特性を選んでください | 特性 | {ability1}, {ability2}(空でなければ), {dream_ability}(空でなければ, desc: 夢特性) | false |

Stat Card を更新（実数値は変わらないが特性を表示に追加）。

### Training State 出力

---

## Phase 4: 持ち物選択

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 持ち物を選んでください | 持ち物 | なし, こだわりハチマキ(desc: A×1.5/技固定), こだわりメガネ(desc: C×1.5/技固定), こだわりスカーフ(desc: S×1.5/技固定), いのちのたま(desc: 威力×1.3/HP1/10消費), きあいのタスキ(desc: HP満タンで一撃耐え), たべのこし(desc: 毎ターンHP1/16回復), とつげきチョッキ(desc: D×1.5/変化技使用不可), しんかのきせき(desc: BD×1.5/進化前限定), ゴツゴツメット(desc: 接触技にHP1/6反動), オボンのみ(desc: HP1/2以下でHP1/4回復), ラムのみ(desc: 状態異常回復), Other(desc: アイテム名を入力) | false |

Stat Card を更新（持ち物を表示に追加）。

### Training State 出力

---

## Phase 5: 技選択

```bash
$PKDX moves "<ポケモン名>" --version "<version>" --format json
```

取得した技一覧を以下のカテゴリに分類して提示:

1. **タイプ一致技**: ポケモンのtype1/type2と一致するタイプの攻撃技（威力順）
2. **補完技**: タイプ不一致の攻撃技（威力上位10件）
3. **変化技**: 分類が「変化」の技（主要なもの）

**AskUserQuestion**（4問を一括）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 技1を選んでください | 技1 | {上位技のリスト}, Other(desc: 技名を入力) | false |
| 2 | 技2を選んでください | 技2 | {上位技のリスト}, Other(desc: 技名を入力) | false |
| 3 | 技3を選んでください | 技3 | {上位技のリスト}, Other(desc: 技名を入力) | false |
| 4 | 技4を選んでください | 技4 | {上位技のリスト}, Other(desc: 技名を入力) | false |

各オプションには desc として「<タイプ>/<分類>/威力<power>」を付与する。
変化技には desc に「**ダメ計対象外**」を明記する。

Stat Card を更新（技構成を表示に追加）。

### Training State 出力

---

## Phase 6: 努力値配分

### 6-1: 推奨配分提案

種族値と性格を分析し、典型的な配分パターンを3つ提案する。

**物理アタッカー型**（Atk種族値 > SpA種族値の場合）:
- ASぶっぱ: H4 A252 S252
- HAベース: H252 A252 B4
- 耐久調整: H252 A4 B252

**特殊アタッカー型**（SpA種族値 > Atk種族値の場合）:
- CSぶっぱ: H4 C252 S252
- HCベース: H252 C252 D4
- 耐久調整: H252 C4 D252

**耐久型**（Def+SpD種族値が高い場合）:
- HBベース: H252 B252 D4
- HDベース: H252 B4 D252

各提案に対して実数値を計算して併記する。

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 努力値配分を選んでください | EV配分 | {提案1}(desc: 実数値サマリ), {提案2}(desc: 実数値サマリ), {提案3}(desc: 実数値サマリ), カスタム(desc: 自由に配分) | false |

### 6-2: カスタム配分（カスタム選択時のみ）

AskUserQuestionで6ステータスの努力値を質問する。

**AskUserQuestion**（6問を一括）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | HP努力値は？ | HP EV | 0(default), 4, 252, Other(desc: 0-252の値) | false |
| 2 | こうげき努力値は？ | A EV | 0(default), 4, 252, Other(desc: 0-252の値) | false |
| 3 | ぼうぎょ努力値は？ | B EV | 0(default), 4, 252, Other(desc: 0-252の値) | false |
| 4 | とくこう努力値は？ | C EV | 0(default), 4, 252, Other(desc: 0-252の値) | false |
| 5 | とくぼう努力値は？ | D EV | 0(default), 4, 252, Other(desc: 0-252の値) | false |
| 6 | すばやさ努力値は？ | S EV | 0(default), 4, 252, Other(desc: 0-252の値) | false |

### バリデーション

以下を検証する:
- 各ステータスの努力値が0〜252の範囲内
- 努力値の合計が510以下
- **警告**（エラーではない）: 4の倍数でない努力値がある場合「Lv50では努力値4ごとに実数値1上昇するため、端数は無駄になります」と案内

バリデーションエラーがある場合はAskUserQuestionで再入力を依頼する。

### 6-3: 最終確認

全実数値を計算し、最終 Stat Card を表示:

```
=== 最終 Stat Card ===
<name> (<type1>/<type2>)
性格: <nature> (<stat>↑ <stat>↓)  特性: <ability>  持ち物: <item>

         種族値  個体値  努力値  実数値  補正
HP        <hp>    31    <ev>    <calc>  --
こうげき   <atk>   31    <ev>    <calc>  ↑/↓/--
ぼうぎょ   <def>   31    <ev>    <calc>  ↑/↓/--
とくこう   <spa>   31    <ev>    <calc>  ↑/↓/--
とくぼう   <spd>   31    <ev>    <calc>  ↑/↓/--
すばやさ   <spe>   31    <ev>    <calc>  ↑/↓/--

技: <move1> / <move2> / <move3> / <move4>
EV合計: <total>/510 (残り: <remaining>)
```

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | この配分でよろしいですか？ | 確認 | はい(default), 努力値を調整する, 性格を変更する | false |

- 「努力値を調整する」→ Phase 6-1 に戻る
- 「性格を変更する」→ Phase 2 に戻る

### Training State 出力

---

## Phase 7: 完成サマリー & ダメ計連携

### 育成データ一覧表示

```
=== 育成完了: <name> ===
タイプ: <type1>/<type2>
性格: <nature> (<stat>↑ <stat>↓)
特性: <ability>
持ち物: <item>

Lv50 実数値:
HP: <hp>  A: <atk>  B: <def>  C: <spa>  D: <spd>  S: <spe>
EV: H<ev> A<ev> B<ev> C<ev> D<ev> S<ev>

技構成:
1. <move1> (<type>/<category>/威力<power>)
2. <move2> (<type>/<category>/威力<power>)
3. <move3> (<type>/<category>/威力<power>)
4. <move4> (<type>/<category>/威力<power>)
```

### ダメ計連携

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | ダメージ計算を行いますか？ | ダメ計 | はい(desc: 育成した実数値でダメージ計算), いいえ(desc: 保存に進む) | false |

「はい」の場合:

**AskUserQuestion**（2問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 相手のポケモンは？ | 相手 | "Otherで回答してください" (desc: ポケモン名を入力) | false |
| 2 | 使用する技は？ | 技 | {move1}(攻撃技のみ), {move2}, {move3}, {move4} | false |

**変化技を選択された場合**: 「この技はダメージを与えません。攻撃技を選んでください」と案内し、再度質問する。

ダメージ計算を実行:
```bash
$PKDX damage "<name>" "<相手名>" "<技名>" \
  --atk-stat <計算済み実数値> \
  --atk-ability "<ability>" \
  --atk-item "<item>" \
  --version "<version>" \
  --format json
```

- 物理技 → `--atk-stat` にこうげき実数値を使用
- 特殊技 → `--atk-stat` にとくこう実数値を使用

### 免疫ケース

pkdx が `--format json` で免疫時にプレーンテキスト(`Immune (0 damage)`)を返す場合がある。JSONパース失敗時は「タイプ相性または特性により無効（ダメージ0）です」と案内する。

### 結果出力

calcスキルと同じ形式でダメージテーブルを表示:

```markdown
### ダメージ計算結果

**<name>** → **<相手名>** / <技名>

| 項目 | 値 |
|------|-----|
| 攻撃実数値 | <stat_name> <actual> |
| 技 | <move> (<type>/<category>, 威力<power>) |

| | 85 | 86 | 87 | 88 | 89 | 90 | 91 | 92 | 93 | 94 | 95 | 96 | 97 | 98 | 99 | 100 |
|---|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|-----|
| ダメージ | ... |
| 割合 | ... |

**確定数**: {ko_text}
```

ダメ計後、追加計算するか質問:

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 続けますか？ | 追加計算 | 別の技で計算, 別の相手で計算, 保存に進む | false |

---

## Phase 8: 保存

**AskUserQuestion**（2問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 育成データを保存しますか？ | 保存 | はい(desc: ./pokemons/<name>/配下に保存), いいえ(desc: 保存せず終了) | false |
| 2 | ファイル名を入力してください（拡張子不要） | ファイル名 | Other(desc: 例: スカーフ型, HBゴツメ等。空欄の場合はYYYYMMDD) | false |

「いいえ」の場合はスキルを終了。

「はい」の場合:

ファイル名の決定:
- ユーザーが入力した場合 → `./pokemons/<pokemon-name>/<入力値>.md`
- 入力が空または未指定の場合 → `./pokemons/<pokemon-name>/YYYYMMDD.md`（当日の日付）

1. `./pokemons/<pokemon-name>/` ディレクトリが存在しなければ作成
2. 同名ファイルが存在する場合はAskUserQuestionで上書き確認
3. 以下の形式でMarkdownファイルを出力

### 出力形式

```markdown
# <Name> 育成データ

## 基本情報

| 項目 | 値 |
|------|-----|
| ポケモン | <name> |
| タイプ | <type1>/<type2> |
| 性格 | <nature> (<stat>↑ <stat>↓) |
| 特性 | <ability> |
| 持ち物 | <item> |

## 実数値 (Lv50, 6V)

| ステータス | 種族値 | 努力値 | 実数値 |
|-----------|--------|--------|--------|
| HP | <base> | <ev> | <actual> |
| こうげき | <base> | <ev> | <actual> |
| ぼうぎょ | <base> | <ev> | <actual> |
| とくこう | <base> | <ev> | <actual> |
| とくぼう | <base> | <ev> | <actual> |
| すばやさ | <base> | <ev> | <actual> |

## 技構成

| 技名 | タイプ | 分類 | 威力 | 命中 |
|------|--------|------|------|------|
| <move1> | <type> | <category> | <power> | <accuracy> |
| <move2> | <type> | <category> | <power> | <accuracy> |
| <move3> | <type> | <category> | <power> | <accuracy> |
| <move4> | <type> | <category> | <power> | <accuracy> |

## ダメージ計算用コマンド

攻撃側として:
\`\`\`bash
bin/pkdx damage "<name>" "<相手>" "<技>" --atk-stat <A or C実数値> --atk-ability "<ability>" --atk-item "<item>"
\`\`\`

防御側として:
\`\`\`bash
bin/pkdx damage "<相手>" "<name>" "<技>" --def-stat <B or D実数値> --def-hp <HP実数値>
\`\`\`
```

保存完了後:
```
✓ ./pokemons/<name>/<filename>.md に保存しました。
```

---

## エラーハンドリング

| 状況 | 対応 |
|------|------|
| pkdx / DB が見つからない | セットアップ手順を案内しスキル終了 |
| ポケモンが見つからない | 名前の再入力を依頼。リージョンフォームの可能性を案内 |
| 技一覧が空 | バージョンの確認を案内（技はバージョンで異なる） |
| EV合計 > 510 | 再入力を依頼 |
| EV > 252（単体） | 再入力を依頼 |
| EVが4の倍数でない | 警告を表示（エラーではない） |
| ダメ計で免疫 | 「タイプ相性または特性により無効です」と案内 |
| 変化技でダメ計 | 「この技はダメージを与えません」と案内し攻撃技を再選択 |
| 同名ファイル存在 | 上書き確認をAskUserQuestionで行う |
| ファイル名に使用不可文字 | 「ファイル名に使用できない文字が含まれています」と案内し再入力 |
