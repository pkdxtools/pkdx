---
name: team-builder
description: "対戦用ポケモン構築支援（シングル/ダブル対応）。軸ポケモンからタイプ補完・メタ分析・選出パターンまでガイドする。構築したい・パーティを組みたい・チーム作成時に使用。"
allowed-tools: Bash, WebFetch, Read, Write, AskUserQuestion
---

# Pokemon Team Builder

6体構築のシングル（3体選出）/ダブル（4体選出）対戦構築支援スキル。

## パス定義

スキルファイルの位置からリポジトリルートを算出する。CLIツール `pkdx` を使用する。

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../../..  （.claude/skills/team-builder/ → repo root）
PKDX=$REPO_ROOT/bin/pkdx
```

## キャッシュファイル

各Phase完了時に、構築中のデータをJSONファイルとして `$REPO_ROOT/box/cache/team_cache_<axis_name>.json` に書き出す。

### 目的

- コンテキスト圧縮後の状態復元
- Phase 8 で `cat cache.json | pkdx write teams` に直接渡す（JSON→マークダウン変換はCLI側で行う）
- Team State Block テキストの代替

### ファイルパス

```
$REPO_ROOT/box/cache/team_cache_<axis_name>_<timestamp>.json
```

`<timestamp>` はスキル開始時（Phase 0）に `date +%s` で取得した UNIX タイムスタンプ。以降のフェーズでは `$CACHE_FILE` 変数でパスを参照する。

```bash
CACHE_FILE="$REPO_ROOT/box/cache/team_cache_<axis_name>_$(date +%s).json"
```

### キャッシュの初期化

スキーマ定義は `pkdx/src/writer/schema.mbt` の `team_schema()` がSSoT。初期JSONは以下のコマンドで生成する:

```bash
bin/pkdx init-cache team > "$CACHE_FILE"
```

生成されるJSONの特徴:
- nullableフィールド（battle_format, mechanics, version）は `null`
- 数値フィールド（phase）は `0`
- 配列（members, coverage, defense_matrix, matchup_plans）は `[]`、`concept` は空文字

Phase 0でユーザー選択値（battle_format, mechanics, version, regulation）をマージし、以降のPhaseで members を段階的に追加していく。

### 更新タイミング

各Phaseの「Team State 出力」の直後にキャッシュファイルを書き出す:

| Phase | 書き込む内容 |
|-------|-------------|
| 0 | battle_format + mechanics + version + regulation |
| 1 | + members[0]（軸ポケモン: name/types/base_stats、role は空文字でも可） |
| 2 | + members[0].ability + coverage初期値 + members[0].role（ポケモンメモ） + members[0] 育成データ（nature / stat_points / actual_stats） + damage_calcs |
| 3 | + members[1-2]（攻め補完メンバー） + coverage更新 + 各 role（ポケモンメモ） + 育成データ + damage_calcs |
| 4 | + members[3-4]（受け補完メンバー） + defense_matrix + 各 role（ポケモンメモ） + 育成データ + damage_calcs |
| 5 | + 全メンバーの moves 確定 + members[5]（素早さ枠等） + 各 role（ポケモンメモ） + 育成データ + damage_calcs |
| 6 | + matchup_plans（仮想敵分析結果） |
| 7 | + 全メンバーの item 確定 + 残スロットの role（ポケモンメモ） + 未確定メンバーの育成データ最終確定 + damage_calcs + concept (構築コンセプト) |

> **メモ**: `role` フィールドはスキーマ上は文字列だが、SKILL では役割（物理アタッカー / 受け / サポート 等）に限定せず、採用理由・型名・対面時の注意点などを自由に書ける**ポケモンメモ欄**として扱う（空文字可）。詳細は [メンバー確定共通: ポケモンメモ入力](#メンバー確定共通-ポケモンメモ入力) を参照。

> **育成データ**: `members[i].nature` / `members[i].stat_points` / `members[i].actual_stats` の 3 フィールド。`pkdx select` / `pkdx nash graph` がこれらを読んで damage 計算の実数値を確定させる。未設定のまま Phase 8 まで進むと `select` は「攻撃側 SP=32 +性格補正 / 防御側 SP=0 無補正」の固定デフォルトで計算してしまい、実戦値とずれる。詳細は [メンバー確定共通: 育成データ入力](#メンバー確定共通-育成データ入力) を参照。

> **ダメージ計算**: 各メンバー確定後に任意で代表技のダメージ計算を cache.damage_calcs に追記する（`pkdx damage --attach-team` 経由）。該当記事ページには damage_calcs 章として埋め込まれ、FE の DamageCalcTable で描画される。詳細は [メンバー確定共通: ダメージ計算入力](#メンバー確定共通-ダメージ計算入力) を参照。

### Phase 8での扱い

- `cat cache.json | pkdx write teams` で直接マークダウンに変換
- 保存完了後、またはユーザーが保存をスキップした場合、キャッシュファイルを**削除**する

---

## メンバー確定共通: ポケモンメモ入力

各メンバーの特性・持ち物確定後、または Phase 1-Team-Vision でのスクショ取り込み確認後に呼び出す共通サブフロー。`role` フィールド（スキーマ上は文字列）へ自由メモを記入する。

### 用途

- 役割表記（例: 「物理アタッカー」「特殊受け」「リダイレクト要員」）
- 採用理由・型名（例: 「スカーフ最速 S189 抜き」「HBD 振り耐久型」）
- 対面時の注意点（例: 「相手スカーフ警戒、初手まもる安定」）
- ダブルでの並びシナジー要点 など

役割と複数情報の併記も可。**空文字 `""` 許容**（無理に埋めない）。

### 入力フロー

1. ユーザーへ次のテキストを出力（AskUserQuestion ではなくフリー入力依頼）:

   ```
   {ポケモン名} のメモを入力してください（役割・採用理由・対面メモなど自由）。
   不要なら「なし」と返答してください。
   ```

2. ユーザーの次のメッセージ全文を `members[i].role` に格納する（改行は半角スペース 1 個に正規化、目安 200 文字以内）
3. 「なし」「skip」「省略」「-」等の場合は `""` を格納
4. キャッシュファイルへ書き戻し、Team State Block の対応行のメモ表示を更新

### 呼び出しタイミング

| 呼び出し元 | タイミング |
|-----------|-----------|
| Phase 2-5 後 | 軸ポケモンの特性・持ち物確定直後 |
| Phase 3-6 後 | 攻め補完メンバー（2-3 体）の確定直後 |
| Phase 4-5 後 | 受け補完メンバー（2 体）の確定直後 |
| Phase 5-5 後 | 素早さ枠の確定直後 |
| Phase 7-1 後 | 残未確定スロットの確定直後 |
| Phase 1-Team-Vision 確認後 | スクショから 6 体確定後、`members[0]` → `members[5]` の順に 1 体ずつ本サブフローを呼び出す |

---

## メンバー確定共通: 育成データ入力

メンバーの特性・持ち物確定後に呼び出す共通サブフロー。性格・SP（Champions）/ EV（deprecated）・実数値を `members[i].nature` / `members[i].stat_points` / `members[i].actual_stats` に格納する。Standard (= EV/IV) 系の version では追加で `members[i].ivs` も格納する。

### なぜ必要か

`pkdx select` / `pkdx nash graph` はこの 3 フィールドを読んで `DamageCalcInput.atk_nature` / `def_nature` / `atk_stat_override` / `def_stat_override` / `def_hp_override` を設定する。未設定のメンバーは「攻撃側 SP=32 +性格補正 / 防御側 SP=0 無補正」の engine legacy default で計算されるため、実構築の打点・耐久とずれる。**未設定のまま Phase 8 に進むと、Phase 6 のマッチアップ分析や `pkdx select` の選出最適化が実戦と乖離する。**

Standard 形式ではメガ進化後の実数値を再計算するときに個体値 (IV) が必要になる。`members[i].ivs` を設定しないと select は 31 揃い (完璧個体) を仮定するため、0 攻撃の特殊アタッカーや 0 素早さのトリックルーム要員など、非 31 IV を意図的に使った構築は post-mega 実数値がユーザー意図からずれる。Champions はゲーム仕様上 IV が廃止されているため、`ivs` を設定しても無視される (Standard 構築のみで有効)。

### 入力フロー

1. **性格**: AskUserQuestion で性格名を選択（ようき / ひかえめ / いじっぱり / ずぶとい など）。判断材料として `$SKILL_DIR/references/stat_thresholds.md` の "素早さティア" / "耐久ベンチマーク" を提示する。

2. **SP/EV**: 以下のいずれかで確定:
   - **攻撃型**: A or C を 32（max）、S を抜き先に応じて調整し、残りを HP/耐久に振る
   - **耐久型**: `$PKDX hbd "<name>" --nature "<性格>" --fixed-ev "_,0,_,0,_,<S_sp>"` で最適配分を取得し、上位候補を AskUserQuestion で提示
   - **スカーフ型**: S=32、A or C=32、残りを HP に
   - **ユーザー直接指定**: "H252 A252 S4 余り" のような自由文字列を SP/EV に解釈

   stat_points は `{h, a, b, c, d, s}` 形式で格納（Champions は各 ≤ 32 合計 ≤ 66、deprecated は各 4 刻み ≤ 252 合計 ≤ 510）。

   **Standard (EV/IV) 系 version 限定**: ユーザーが IV を指定したら `members[i].ivs = {h, a, b, c, d, s}` に格納する。特に指定がなければ `{h:31, a:31, b:31, c:31, d:31, s:31}` を既定とする。ただし 0 攻撃 (特殊アタッカーの混乱自傷ケア) や 0 素早さ (トリックルーム下位行動) のような非 31 IV 運用が明示されたときは、その値を必ず保存する (select のメガ進化後再計算がこの値を使う)。Champions では IV がゲーム仕様上存在しないので `ivs` は**格納しない**（`null` のまま）。

3. **実数値の算出**: SP/EV 確定後、`$PKDX stat-calc` で実数値を出す:

   ```bash
   $PKDX stat-calc "<ポケモン名>" \
     --ev "H,A,B,C,D,S" \
     --nature "<性格>" \
     --version "<version>" \
     --format json
   ```

   JSON の `stats` (または実数値フィールド) を取り出して `members[i].actual_stats = {h,a,b,c,d,s}` に格納。手計算に頼らず CLI 出力を SSoT とする。

4. **キャッシュ書き戻し + Team State Block 更新**: `members[i]` の 3 フィールドを埋めてキャッシュ JSON を再保存し、Team State Block の該当行に「性格: / SP: / 実数値:」を反映する。

### Champions Vision 取り込み時の扱い

Phase 1-Team-Vision で vision 抽出 + `pkdx stat-reverse` 検証済みの SP / 実数値 / 性格は、**本サブフローを経由せず直接 `members[i]` に書き込む**（既に値が揃っているため再質問は冗長）。vision 検証で矛盾が出た個体のみ、AskUserQuestion で修正を受け付ける。

### 呼び出しタイミング

| 呼び出し元 | タイミング |
|-----------|-----------|
| Phase 2-5 後 | 軸ポケモンの特性・持ち物確定直後（ポケモンメモ入力の後） |
| Phase 3-6 後 | 攻め補完メンバー（2-3 体）の確定直後 |
| Phase 4-5 後 | 受け補完メンバー（2 体）の確定直後 |
| Phase 5-5 後 | 素早さ枠の確定直後 |
| Phase 7-1 後 | 残未確定スロットの確定直後 |

ポケモンメモ入力と本サブフローは連続して呼び出す（メモ → 育成データ → ダメージ計算入力 → 次のメンバーへ）。

---

## メンバー確定共通: ダメージ計算入力

各メンバーの育成データ確定直後に呼び出す共通サブフロー。そのメンバーのデータを用いて仮想敵ダメージ計算を実行し、cache の `damage_calcs[]` に追記する。Phase 8 で `pkdx write teams` が cache → meta.json serialize するとき、そのまま meta.json の `damage_calcs[]` として FE に渡り記事に反映される。

### 入力フロー

1. **実行可否判定**: AskUserQuestion:

   | # | 質問 | header | オプション |
   |---|------|--------|-----------|
   | 1 | `{ポケモン名}` のダメージ計算を入力しますか? | ダメ計 | はい(desc: 次メッセージで計算対象を複数行入力), いいえ(desc: スキップ) |

   「いいえ」なら即次のメンバーへ。

2. **対象入力**: 「はい」の場合、以下のテキストをユーザーへ出力（AskUserQuestion ではなくフリー入力依頼）:

   ```
   {ポケモン名} のダメージ計算対象を、以下のいずれかのフォーマットで 1 行 1 エントリで入力してください（複数可）。
   攻め (current member が攻撃): {技名}->{SP振り},{性格補正},{ポケモン名},{天候などの条件}
   受け (current member が防御): {SP振り},{性格補正},{ポケモン名},{技名},{天候などの条件}

   不要なら「なし」と返答してください。

   例:
     じしん->H32,無補正,ドドゲザン         # カバルドンのじしんで H32無補正のドドゲザンを攻撃
     逆鱗->H1,無補正,カイリュー
     アイアンヘッド->H32B32,補正あり,メガピクシー
     C32,補正あり,メガゲンガー,シャドーボール   # メガゲンガー(C32補正あり)のシャドーボールでカバルドンが受ける
     A32,無補正,ガブリアス,じしん
   ```

3. **フォーマット判定**:
   - 行に `->` が含まれる → 攻め (current member = attacker, listed pokemon = defender)
   - 行に `->` が含まれない → 受け (current member = defender, listed pokemon = attacker)
   - **どちらの format でも `{SP振り},{性格補正},{ポケモン名}` の 3 要素は常に "相手 (= opponent)" のもの**。current member の SP/性格/実数値は `members[i]` から暗黙取得し、入力で渡さない (重複入力で計算が食い違うのを防ぐため)。

4. **各フィールドの解釈ルール**:
   - **技名**: 攻めなら `members[i].moves[].name` に含まれること。受けなら `pkdx moves "<opponent>" --version champions` で習得確認
   - **SP振り**: `{stat letter}{数値}` の連結（大文字 H/A/B/C/D/S）。未指定 stat は `0`（例: `H32` → `{h:32,a:0,b:0,c:0,d:0,s:0}`、`H32B32` → `{h:32,a:0,b:32,c:0,d:0,s:0}`）。Champions 制約: 各 ≤ 32、合計 ≤ 66
   - **性格補正**:
     - `無補正` → opponent の nature を **省略** (CLI default: 攻撃側=攻撃stat特化相当 +10% / 防御側=無補正)
     - `補正あり` → 技の category に応じて opponent の nature を決定:
       - **攻め format** (opponent = defender): 物理技なら `ずぶとい` (B↑), 特殊技なら `しんちょう` (D↑)
       - **受け format** (opponent = attacker): 物理技なら `いじっぱり` (A↑), 特殊技なら `ひかえめ` (C↑)
   - **ポケモン名**: `pkdx query "<name>" --version champions --format json` で存在確認。`メガX` は DB 上のメガフォーム名に正規化（`M-A` で `X メガ進化形` や `メガ<X>` の綴り揺れを吸収）

4. **ステージング meta.json**: `pkdx damage --attach-team` は `.meta.json` が `box/teams/` 配下に実在している必要があるため、Phase 1-Team-Vision step 6 終了直後 / Phase 7-1 完了直後 に最終出力パスと同じ名前でステージング meta.json を pre-create する:

   ```bash
   STAGING="box/teams/<axis>-build-<YYYY-MM-DD>.meta.json"
   [ ! -f "$STAGING" ] && echo '{"damage_calcs":[]}' > "$STAGING"
   ```

   既存ファイルがあれば上書きせずそのまま使う（冪等）。

5. **計算実行 + attach**: 重要 — `pkdx damage` には `--atk-ev` / `--def-ev` オプションは存在しない。実数値は `--atk-stat` / `--def-stat` / `--def-hp` で直接渡す（pre-rank の生stat値）。実数値は **`pkdx stat-calc` の出力を SSoT** とし、手計算しない。

   **rev2 フラグ (威力可変 / 壁 / 連続技 / 状態)**: 以下は該当する技 / 状況でのみ追加する。指定しなければ既定値 (威力素点・壁なし・状態なし・連続技=auto) でそのまま計算される。
   - `--wall reflect|light-screen|aurora-veil` (または `リフレクター`/`ひかりのかべ`/`オーロラベール`) … 守り側の壁が場にある想定
   - `--atk-status yakedo|mahi|doku|...` (または `やけど`/`まひ`/...) … からげんき の威力 2x 判定 (まひ/やけど/どく/もうどく で発動、ねむり/あくびは行動不能扱いで発動しない)
   - `--def-status ...` … たたりめ の威力 2x 判定
   - `--atk-rank-up-count N` … アシストパワー の威力 = 20 + 20N
   - `--def-rank-up-count N` … つけあがる の威力 = 20 + 20N
   - `--atk-hp 1/2` (または `50%`) … やけっぱち の HP 半分以下判定
   - `--def-item-removable` … はたきおとす の 1.5x 判定 (奪える持ち物のときのみ)
   - `--multi-hit 5` … Skill Link 技で 5 発固定 / `auto` は DB 参照 (ロックブラスト等 2-5 乱数は中央値 3)
   - `--disguise-active` … ミミッキュの初撃 (ダメージ 0 + `disguise_blocked=true`)

   damage_calcs ブログ埋め込みでは `hits_dealt` と `disguise_blocked` も meta.json に記録される。連続技は 1 発ぶんを element-wise で n 倍して 16 段テーブルに反映される。

   **共通: opponent の実数値計算** (両 format で必要):

   ```bash
   # opponent の SP振りと性格補正から HP/A/B/C/D/S を取得
   OPP_STATS=$($PKDX stat-calc "<opponent_name>" --ev "<H>,<A>,<B>,<C>,<D>,<S>" \
       ${OPP_NATURE:+--nature "$OPP_NATURE"} --version champions --format json)
   # → 必要 stat (HP / 物理技なら A or B / 特殊技なら C or D) を jq で抽出
   ```

   **攻め format** の damage call (current member が攻撃、opponent が defender):

   ```bash
   # 技 category に応じて current member の攻撃 stat を members[i].actual_stats から取得
   # 物理技 → members[i].actual_stats.a / 特殊技 → members[i].actual_stats.c
   ATK_STAT=$( jq -r --arg key "<a or c>" '.members[i].actual_stats[$key]' "$CACHE_FILE" )
   # opponent の防御 stat を OPP_STATS から取得 (物理技 → b / 特殊技 → d) と HP
   DEF_STAT=$( echo "$OPP_STATS" | jq -r '.def or .spd' )
   DEF_HP=$( echo "$OPP_STATS" | jq -r '.hp' )

   $PKDX damage "<members[i].name>" "<opponent_name>" "<move_name>" \
     --atk-ability "<members[i].ability>" \
     --atk-item "<members[i].item>" \
     --atk-nature "<members[i].nature>" \
     --atk-stat $ATK_STAT \
     --def-stat $DEF_STAT \
     --def-hp $DEF_HP \
     ${OPP_NATURE:+--def-nature "$OPP_NATURE"} \
     --version champions \
     --attach-team "$STAGING" \
     --attach-title "<auto-generated, 例: '{move_name} vs {opp_sp}{opp_nature}{opp_name}'>"
   ```

   **受け format** の damage call (opponent が攻撃、current member が defender):

   ```bash
   # opponent の攻撃 stat を OPP_STATS から取得 (物理技 → atk / 特殊技 → spa)
   ATK_STAT=$( echo "$OPP_STATS" | jq -r '.atk or .spa' )
   # current member の防御 stat を members[i].actual_stats から取得 と HP
   # 物理技 → members[i].actual_stats.b / 特殊技 → members[i].actual_stats.d
   DEF_STAT=$( jq -r --arg key "<b or d>" '.members[i].actual_stats[$key]' "$CACHE_FILE" )
   DEF_HP=$( jq -r '.members[i].actual_stats.h' "$CACHE_FILE" )

   $PKDX damage "<opponent_name>" "<members[i].name>" "<move_name>" \
     --atk-stat $ATK_STAT \
     ${OPP_NATURE:+--atk-nature "$OPP_NATURE"} \
     --def-ability "<members[i].ability>" \
     --def-item "<members[i].item>" \
     --def-nature "<members[i].nature>" \
     --def-stat $DEF_STAT \
     --def-hp $DEF_HP \
     --version champions \
     --attach-team "$STAGING" \
     --attach-title "<auto-generated, 例: '{opp_name} {move_name} ({opp_sp}{opp_nature}) → {member_name}'>"
   ```

   **フォーム揺れ注意**: ギルガルドのような「攻撃時はブレード形態 / 防御時はシールド形態」のフォーム切り替え系は pkdx DB に攻撃時 base が登録されていない場合がある (シールド base spa=50 / ブレード base spa=140 等)。受け format でこれらを攻撃側に指定する場合、ユーザーに「pkdx 上はシールド形態のみ登録のため、攻撃時 base spa=140 から SP振りを反映した実数値を override します」と一行警告を出した上で手動 base から計算した値を `--atk-stat` で渡す。

6. **cache への書き戻し**: バッチ終了後、ステージング meta.json を読み、その `damage_calcs` 配列全体を cache.damage_calcs に上書き（staging は Phase 1-7 を通じて累積、cache は常にその snapshot を保持する single source）。

7. **Phase 8 での扱い**: Phase 8-2 の `pkdx write teams` は cache をそのまま使うので、staging に溜まった damage_calcs はそのまま meta.json に serialize される。staging ファイルは Phase 8 の cache 削除タイミングで同時削除する。

### 呼び出しタイミング

| 呼び出し元 | タイミング |
|-----------|-----------|
| Phase 2-7 後 | 軸ポケモンの育成データ確定直後 |
| Phase 3-6 後 | 攻め補完メンバーの育成データ確定直後 |
| Phase 4-5 後 | 受け補完メンバーの育成データ確定直後 |
| Phase 5-5 後 | 素早さ枠の育成データ確定直後 |
| Phase 7-1 後 | 残未確定スロットの育成データ確定直後 |
| Phase 1-Team-Vision step 4-b 後 | 各メンバーのメモ入力直後（vision 経由で育成データは既に埋まっているためメモ → ダメ計 の順で連続呼び出し） |

---

## Phase 0: 初期化

### 0-1: DB存在確認

```bash
$PKDX query "ピカチュウ" --format json >/dev/null 2>&1 && echo "OK" || echo "NOT_FOUND"
```

NOT_FOUNDの場合、以下を案内して**スキルを終了**:
```
pkdx CLI または pokedex.db / champions.db が見つかりません。リポジトリルートで以下を実行してください:
  ./setup.sh
```

### 0-2: 参照データ読み込み

以下を**並列で**Readする:
- `$SKILL_DIR/references/stat_thresholds.md` → 種族値ベンチマーク
- `$SKILL_DIR/references/format_rules.md` → メカニクスルール
- `$SKILL_DIR/references/items_abilities.md` → 持ち物・特性リファレンス

**Note**: タイプ相性は `$PKDX type-chart` および `$PKDX coverage` で計算可能。type.json の直接読み込みは不要。

### 0-3: バトル形式選択

AskUserQuestionでバトル形式を質問:
- **singles**: シングルバトル（3体選出）
- **doubles**: ダブルバトル（4体選出）

選択結果を `battleFormat` として以降のフェーズで使用。

### 0-4: メカニクス選択

AskUserQuestionで有効メカニクスを質問（multiSelect: true）:
- **mega**: メガシンカ
- **gigantamax**: キョダイマックス
- **zmove**: Zワザ
- **terastal**: テラスタル

未選択の場合はバニラルール（メカニクスなし）として動作。

### 0-5: バージョン確認

AskUserQuestion でゲームバージョンを質問:
- `champions`（**デフォルト / 推奨**）
- `scarlet_violet`（deprecated: 旧 EV/IV 制。SP 制の champions が現行推奨）
- `legendsza`（deprecated: 同上）
- その他（ユーザー入力）

**推奨の理由**: Champions 以降は SP (Stat Points) 制に一本化されており、damage 計算・実数値算出・select のメガ進化後再計算ともに SP 前提で最適化されている。旧 EV/IV 制 (`scarlet_violet` / `legendsza` 等) は後方互換のために残しているが、新規構築は `champions` を選択すること。

`champions` 選択時は続けてレギュレーションを質問:
- `M-A`（current）

キャッシュに `version` と `regulation` を記録。`regulation` は champions 以外では空文字。

これ以降、スクリプトに渡す `--version` / `--regulation` 引数として使用。

---

## Phase 1: 軸ポケモン決定

### version=champions の場合: チーム入力方式分岐

Phase 0 で `version=champions` を選択した場合、Phase 1 の冒頭で入力方式を質問する。それ以外の version では、直接「Phase 1 対話モード」に進む。

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | チーム入力方式を選んでください | 入力方式 | 対話で 1 体ずつ構築(desc: 従来通り Phase 1-5), ゲームのスクショから一括取り込み(desc: チーム画面の「能力」+「ステータス」2 枚から 6 体を OCR) | false |

- `対話で 1 体ずつ構築` → 下記「Phase 1 対話モード」へ
- `ゲームのスクショから一括取り込み` → [Phase 1-Team-Vision](#phase-1-team-vision-champions-チーム一括取り込み) へ

### Phase 1 対話モード

AskUserQuestionで軸ポケモンを聞く:
```
軸とするポケモンを1匹教えてください。
（日本語名・英語名どちらでもOK）
```

取得したポケモン名で以下を実行:
```bash
$PKDX query "<ポケモン名>" --version "<version>" --format json
```

#### フォーム違いポケモンの扱い

**手順**:

1. ユーザー入力名をそのまま `pkdx query "<名前>" --version "<version>" --format json` に渡す。以下は直接引ける:
   - 原種名に form 名を接頭/接尾した一意名: `ウォッシュロトム` / `ヒートロトム` / `メガガブリアス` / `メガリザードンX` 等
   - 合成された一意名: `キュウコン（アローラ）` / `ランドロス（れいじゅう）` / `ガーディ（ヒスイ）` / `バクフーン（ヒスイ）` 等
   - 英語名: `Wash Rotom` / `Ninetales (Alolan)` 等
2. **見つからない場合** (`Error: Pokemon not found`) は原種名で再 query し、返り値の `forms[]` を確認:
   - `forms[]` はその version に実在するフォームの一意名配列。原種引き時のみ列挙され、フォーム直引き時や形態無しの場合は **JSON キーごと省略** される
   - 例: `pkdx query ロトム --version champions` → `"forms":["ヒートロトム","ウォッシュロトム","フロストロトム","スピンロトム","カットロトム"]`
   - 例: `pkdx query キュウコン --version scarlet_violet` → `"forms":["キュウコン（アローラ）"]`
3. ユーザー意図に合う一意名を選び、その名前で再度 query して該当フォームの `type1` / `type2` / `ability1` / `ability2` / `dream_ability` / 種族値を取得

**注意点**:
- 戦闘面で base と完全に同じフォーム (トリミアン毛型・ビビヨン模様・フラベベ花色・Unown 文字・マホイップ flavor 等) は `forms[]` に現れない。これらは原種として扱って問題ない
- 該当 version にそのフォームが実在しない場合は `forms[]` からも除外される (例: Champions にはランドロス（れいじゅう）未収録)
- メガシンカも form の一種として `forms[]` に含まれる (`メガガブリアス` 等)。メガ名で query するとメガ進化後の type/ability/stats が得られる

**結果が空の場合**:

- 名前の確認を再度AskUserQuestionで依頼
- **メガシンカポケモンの場合**: 以下のAskUserQuestionで案内:

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | メガシンカポケモンのデータが見つかりませんでした。最新のメガシンカデータをDBに取り込みますか？（⚠ 実験的機能: マスターデータの更新時に再実行が必要になる場合があります） | メガデータ | はい(desc: メガシンカ64体のデータを取り込む), いいえ(desc: 通常フォームで続ける) |

「はい」の場合:
```bash
"$REPO_ROOT/bin/pkdx" migrate --repo-root "$REPO_ROOT"
```

実行後、元のクエリを再実行してデータを取得する。取得できた場合はそのまま続行。
取得できなかった場合は「パッチ対象に含まれていないポケモンです」と案内する。

結果からglobalNoを取得し、以降のフェーズで使用。

---

## Phase 1-Team-Vision: Champions チーム一括取り込み

Champions のチーム画面スクショ **2 枚 (能力 + ステータス)** から 6 体分の team cache を冪等に構築する。1 枚に 6 体が並ぶ UI のため、12 枚や 1 体ずつのループは不要。

### 1. スクショ添付依頼

ユーザーへ以下のメッセージを出力し、**次のメッセージで 2 枚の画像を会話に添付してもらう** (AskUserQuestion ではファイル添付できないためテキスト指示):

```
Champions のチーム画面スクショ 2 枚を、次のメッセージにまとめて貼ってください:
 - 「能力」画面 (特性・持ち物・技 4 つ が 6 体分見えるもの)
 - 「ステータス」画面 (SP・実数値・性格 ↑↓ が 6 体分見えるもの)
```

ユーザーからの次のメッセージに添付された画像 path (会話履歴に残る一時パス、例: `/var/folders/.../Image.png` 等) を Read ツールで読み込んで vision 抽出に進む。画像が 1 枚しか無い / 関係ない画像の場合はもう一度添付を依頼する。

### 2. Vision 抽出 (6 体一括)

2 枚の画像から、6 体それぞれについて以下を**一度に** vision で抽出する:

- **ポケモン名** (日本語カタカナ)、性別マーク (♂/♀/無性別)
- **特性**、**持ち物** (能力画面)
- **技 4 つ** (能力画面、名前のみ)
- **SP 配分** (ステータス画面、各 ≤ 32、合計 ≤ 66)
- **実数値** (ステータス画面、検算用)
- **性格 ↑↓ マーカー** (ステータス画面、ステータス名右の↑/↓記号)

中間結果は 6 体分まとめて表示する (体ごとに分割表示しない)。

### 3. 各体ごとの DB 照合 / SP 逆算 / 性格確定 / 技補完

抽出した 6 体について、ポケモンごとに以下を順次実行する。ユーザー対話は発生させず一括で進める (性格が一意に決まらない個体だけ、後段の確認時にまとめて選ばせる):

1. **DB 照合**: `pkdx query "<name>" --version champions --format json` で種族値・タイプ・特性候補を取得。Champions 側で未登録なら `--version scarlet_violet` で fallback
   - 性別でステータス・タイプ・特性が異なる種 (イダイトウ / イエッサン / パフュートン / ニャオニクス) を引く際は性別を明示する: `イダイトウ（オス）` / `イダイトウ（メス）` / 英名なら `Basculegion (Male)` / `Basculegion (Female)`。性別未指定の `イダイトウ` は M base を返すため F 個体を扱う際は必ず `（メス）` 付きで照合する
   - vision 抽出の性別マーク (♂ / ♀) は DB 照合直前に `♂ → （オス）` / `♀ → （メス）` へ正規化して `pkdx query` に渡す。`イダイトウ♂` / `イダイトウ♀` のままでは "Pokemon not found" になる
2. **SP 逆算検証**: `pkdx stat-reverse "<name>" --stats "<HP>,<A>,<B>,<C>,<D>,<S>" --version champions --format json` の出力 SP と vision 抽出 SP を比較。複数解は「いずれかと一致」で OK
3. **性格確定**: ↑↓マーカーが読めていれば性格テーブルから直接特定。読めない場合は SP + 実数値の整合性で候補を絞る (`team-builder/references/champions_sp.md` 参照)。候補 1 つなら自動確定、複数候補は後段で AskUserQuestion
4. **技詳細補完**: `pkdx moves "<name>" --version champions --format json` で抽出した 4 つの技名を DB 照合し、`{name, type, category, power, accuracy}` の 5 フィールドを `members[i].moves[j]` に格納する (issue #68 以降 `accuracy` も許容されるため手動で剥がす必要はない)。`pkdx moves` 出力には `pp` / `learn_method` / `priority` / `stat_effects` も含まれるが、これらはスキーマで拒否されるため抜粋が必要
5. **育成データ格納**: 1-3 で検証済みの性格・SP・実数値を直接 `members[i]` に書き込む:
   - `members[i].nature = "<性格名 JP>"` (例: `"ようき"`)
   - `members[i].stat_points = {h, a, b, c, d, s}` (vision 抽出 SP、stat-reverse と一致するもの)
   - `members[i].actual_stats = {h, a, b, c, d, s}` (vision 抽出の Lv50 実数値)

   本サブフローは [メンバー確定共通: 育成データ入力](#メンバー確定共通-育成データ入力) を**経由しない**（既に 3 種すべてが vision から取得済みで、再質問は冗長）。vision 検証で矛盾が出た個体のみ、手順 4 の確認画面で AskUserQuestion により修正を受け付ける。

### 4. 6 体分まとめて表示 + 一括確認

```
=== Champions チーム抽出結果 (6/6 体) ===
[1] マンムー (ようき / こだわりスカーフ / あついしぼう)
    SP: H20 A32 B0 C0 D0 S14  技: じしん / つららおとし / つららばり / ばかぢから
[2] アシレーヌ (れいせい / しんぴのしずく / げきりゅう)
    SP: ...
...
[6] ヌメルゴン(ヒスイ) (ずぶとい / たべのこし / シェルアーマー)
    SP: ...
```

メガ石 (「〇〇ナイト」) を検出した体があれば末尾に警告:
```
⚠ 次のポケモンはメガ石を所持しています: ハッサム, キュウコン
   メガ進化の戦闘評価は task B 実装後に有効になります。
```

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | このチーム構成でよいですか? | 確認 | はい(desc: team cache 組み立てに進む), 修正する(desc: 特定のポケモンの項目を個別修正), やり直す(desc: スクショ添付から再実行) | false |

- `修正する` → どのポケモン (1-6) のどの項目 (技 / 持ち物 / 性格 / SP 等) を上書きするか AskUserQuestion で選び、個別に修正
- `やり直す` → 手順 1 (スクショ添付依頼) から全体リセット

### 4-b. ポケモンメモ + ダメージ計算入力（任意）

確認 OK の後、6 体それぞれについて `members[0]` から順に以下を直列に実行する:

1. [メンバー確定共通: ポケモンメモ入力](#メンバー確定共通-ポケモンメモ入力) — フリー入力で次メッセージ全文を `members[i].role` に格納
2. [メンバー確定共通: ダメージ計算入力](#メンバー確定共通-ダメージ計算入力) — AskUserQuestion で可否を聞き、「はい」の場合フォーマット入力を受け付けて cache.damage_calcs に追記

**必ず 1 体ずつ** のシーケンス（6 体分のメモを 1 メッセージにまとめて受け付ける bulk モードは廃止。理由: 共通サブフローの「次メッセージ全文 = 対象メンバーの入力」という契約を壊さないため）。

全員 `なし` 回答ならメモ・ダメ計は空のまま。

### 5. 取り込み後の動線を選択

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | この後どうしますか? | 動線 | メタ分析・選出方針も対話で構築(desc: Phase 6 (仮想敵分析) に進む), 保存のみ(desc: Phase 8 に直行。メタ分析は空欄) | false |

- `メタ分析・選出方針も対話で構築` → Phase 6 に進む。team cache の members[0..5] は埋まっているので Phase 2-5 (軸分析・補完・素早さ・耐久) は skip
- `保存のみ` → team cache の `matchup_plans` を空配列、`concept` を空文字のまま Phase 8 に直行。出力 md の冒頭に「⚠ メタ分析セクションは未記入。`/team-builder` で再開可能」と注記を入れる

### 6. team cache 組み立て + 冪等性判定

1. cache スケルトン生成:

```bash
$PKDX init-cache team > "$CACHE_FILE"
```

2. 抽出 6 体を members に詰め、`version: "champions"`, `regulation: "M-A"`, `battle_format: "singles"`, `mechanics: "メガシンカ"` (該当時) を明記

3. `pkdx import-check` で冪等性判定:

```bash
EXISTING_DIR="$REPO_ROOT/box/teams"
if [ -d "$EXISTING_DIR" ]; then
  EXISTING=$(for f in "$EXISTING_DIR"/*.meta.json; do
    [ -f "$f" ] && jq --arg p "$f" '{path: $p, content: .}' "$f"
  done | jq -s '.')
else
  EXISTING='[]'
fi

jq -n \
  --slurpfile cache "$CACHE_FILE" \
  --argjson existing "$EXISTING" \
  '{kind: "team", cache: $cache[0], existing: $existing}' | \
  $PKDX import-check
```

出力に応じて分岐:

- `{"status":"skip", "matched_file": "..."}` → 既に同一データあり。**AskUserQuestion**: `保存せず終了` / `別名で保存する` / `やり直す`
- `{"status":"diff", "matched_file": "...", "differing_fields": [...]}` → 差分を表示し、**AskUserQuestion**: `新規ファイルとして保存` / `既存を上書き` / `保存せず終了`
- `{"status":"new"}` → そのまま次のステップへ

4. ユーザー承認後、選んだ動線 (Phase 6 or Phase 8) に進む

---

## Phase 2: 軸ポケモン分析

### 2-1: 技一覧取得

```bash
$PKDX moves "<globalNo>" --version "<version>" --format json
```

### 2-2: 特性の説明取得

`$PKDX query` のJSON出力から ability1, ability2, dream_ability を取得済み。特性の詳細説明が必要な場合は DB を直接クエリする:
```bash
sqlite3 "$REPO_ROOT/pokedex/pokedex.db" \
  "SELECT name, description FROM ability_language WHERE ability IN ('<ability1>', '<ability2>', '<dream_ability>') AND version='<version>' AND language='jpn';"
```

### 2-3: 分析結果を提示

以下の形式で提示:

```
## 軸ポケモン分析: {名前}

**タイプ**: {type1}/{type2}
**種族値**: H{hp} A{atk} B{def} C{spa} D{spd} S{spe} (合計: {bst})
**役割分類**: {stat_thresholds.mdから判定}

### 特性
- {ability1}: {説明}
  → 戦闘効果: {items_abilities.mdから該当する効果を分類表示}
- {ability2}: {説明}（あれば）
  → 戦闘効果: {同上}
- {dream_ability}: {説明}（夢特性）
  → 戦闘効果: {同上}

特性効果の分類:
  - 耐性付与: 「ふゆう → じめん無効」
  - 耐性変化: 「あついしぼう → ほのお/こおり半減」
  - 火力補正: 「ちからもち → 物理火力2倍」
  - 防御補正: 「マルチスケイル → HP満タン時ダメージ半減」
  - フィールド/天候: 「ひひいろのこどう → 晴れ展開+攻撃強化」
  - わざわい系: 「わざわいのつるぎ → 相手防御0.75x」

### 実質タイプ耐性（特性考慮）
| 攻撃タイプ | タイプ相性 | ability1考慮 | ability2考慮 | dream考慮 |
（免疫特性で弱点が消える場合や耐性変化がある場合のみ差分を表示）

### 主要技
#### STAB技（タイプ一致）
| 技名 | タイプ | 分類 | 威力 | 命中 |
（type1/type2に一致する技を威力順で）

#### 補完技（タイプ不一致の攻撃技）
| 技名 | タイプ | 分類 | 威力 | 命中 |
（STAB以外の攻撃技を威力順で上位10個）

#### 変化技（主要なもの）
| 技名 | タイプ | 効果概要 |
（category=変化の技から対戦で有用なもの）

#### 【doubles時のみ】ダブルバトル向けサポート技
| 技名 | タイプ | 効果概要 | カテゴリ |
（items_abilities.md §8 のダブル向け技リストと照合し、習得可能なものを抽出）
カテゴリ: 味方支援 / リダイレクト / S操作 / 全体防御 / 妨害
```

### 2-4: 特性選択

AskUserQuestionで採用特性を確定（ability1/ability2/dream_abilityから1つ選択）。
各選択肢のdescriptionに戦闘効果を記載する。

### 2-5: 推奨持ち物の提案

確定した特性と役割分類に基づき、items_abilities.mdから推奨持ち物を2-3個提案:
- 物理アタッカー → こだわりハチマキ / いのちのたま / ちからのハチマキ
- 特殊アタッカー → こだわりメガネ / いのちのたま / ものしりメガネ
- 耐久型 → たべのこし / とつげきチョッキ / ゴツゴツメット
- 高速アタッカー → こだわりスカーフ / きあいのタスキ / いのちのたま

AskUserQuestionで持ち物を確定（「後で決める」も選択可）。

### 2-6: ポケモンメモ入力

[メンバー確定共通: ポケモンメモ入力](#メンバー確定共通-ポケモンメモ入力) の手順で軸ポケモンのメモを `members[0].role` に格納する。

### 2-7: 育成データ入力

[メンバー確定共通: 育成データ入力](#メンバー確定共通-育成データ入力) の手順で軸ポケモンの性格・SP (Champions) or EV (deprecated)・実数値を `members[0].nature` / `members[0].stat_points` / `members[0].actual_stats` に格納する。

### 2-8: ダメージ計算入力

[メンバー確定共通: ダメージ計算入力](#メンバー確定共通-ダメージ計算入力) の手順で軸ポケモンを攻撃側とした代表技のダメージ計算を cache.damage_calcs に追記する。「いいえ」ならスキップ。

---

## Phase 3: 攻めの相性補完

### 3-1: 攻撃カバー率計算

type.jsonを参照し、以下のアルゴリズムで計算:

1. 軸のSTABタイプ（type1, type2）を取得
2. 軸の覚える攻撃技のタイプ一覧（重複除去）を取得
3. 各攻撃技タイプについて、type.jsonからそのタイプで**抜群（倍率 >= 2.0）を取れる防御タイプ**を集合に追加
4. 集合に含まれないタイプ = **攻めの穴**

### 3-2: 結果を提示

```
## 攻めの相性補完

### STAB技で抜群を取れるタイプ
{type1で抜群: ...}, {type2で抜群: ...}

### 技範囲全体で抜群を取れるタイプ
{全攻撃技で抜群が取れるタイプ一覧}

### 攻めの穴（抜群を取れないタイプ）
{18タイプから攻撃範囲を引いた残り}

### 穴を埋めるタイプ提案
| 攻めの穴 | 抜群を取れるタイプ |
```

### 3-3: 特性による実質攻撃範囲の補正

軸の確定特性がスキン系・火力補正系の場合、実質的な攻撃範囲を補正:
- スキン系（フェアリースキン等）: ノーマル技が変換タイプのSTAB技として扱える
- テクニシャン: 低威力技でも実用的な火力が出る
- いろめがね: 半減タイプへの打点が実質等倍になるため、攻めの穴が縮小

### 3-4: 補完候補の検索

攻めの穴を埋めるタイプで候補を検索:
```bash
$PKDX search --type "<穴を埋めるタイプ>" --version "<version>" --format json
```

候補に対して `$PKDX query` で特性も取得し、特性込みで評価:
- 免疫特性持ち → 受け枠との兼用が可能（例: ふゆう持ちは地面無効）
- 火力特性持ち → 攻め枠としての評価を上げる

### 3-5:【doubles時のみ】横の並びシナジー評価

ダブルバトルでは軸との「横の並び」（同時に場に出るペア）を重視して評価する。items_abilities.md §8〜§10 を参照し、以下の観点で候補をスコアリング:

1. **味方支援技の有無**: てだすけ、このゆびとまれ、いかりのこな、おいかぜ、トリックルーム等を習得するか
2. **支援特性の有無**: いかく、フレンドガード、おもてなし、テイルアーマー等（§9参照）
3. **コンボ成立性**: 軸 + 候補で§10のコンボパターンに該当するか
   - 例: 軸が高火力低耐久 → このゆびとまれ/いかりのこなリダイレクト持ちが高評価
   - 例: 軸がトリルエース適性 → トリックルーム始動役が高評価
   - 例: 軸が天候/フィールド依存 → 天候/フィールド始動特性持ちが高評価
4. **全体技の考慮**: 軸が全体技（じしん、なみのり等）を主力にする場合、味方がふゆう/よびみず等で被弾しないか

### 3-6: メンバー確定・特性選択・持ち物提案

AskUserQuestionで:
- どの攻めの穴を優先するか
- 候補から選択

メンバー確定時:
1. `$PKDX query` で特性一覧を取得
2. AskUserQuestionで特性を選択
3. 役割に応じた推奨持ち物を提案（2-3候補）
4. **持ち物重複チェック**: 既に確定済みの持ち物と同じものを提案しない。重複する場合は代替を提示。
5. AskUserQuestionで持ち物を確定
6. [メンバー確定共通: ポケモンメモ入力](#メンバー確定共通-ポケモンメモ入力) で `members[i].role` を埋める
7. [メンバー確定共通: 育成データ入力](#メンバー確定共通-育成データ入力) で `members[i].nature` / `stat_points` / `actual_stats` を埋める
8. [メンバー確定共通: ダメージ計算入力](#メンバー確定共通-ダメージ計算入力) で cache.damage_calcs にダメ計を追記（任意）

---

## Phase 4: 受けの相性補完

### 4-1: 防御相性計算（特性考慮）

type.jsonおよびitems_abilities.mdを参照し、以下のアルゴリズムで計算:

1. 軸のタイプ（type1, type2）を取得
2. 18タイプそれぞれについて、攻撃タイプとして軸への倍率を計算:
   - `倍率 = type.json[攻撃タイプ][type1] × type.json[攻撃タイプ][type2]`
   - type2が空なら`type.json[攻撃タイプ][type1]`のみ
3. **特性による補正を適用**:
   - 免疫特性: 該当タイプの倍率を `0`（無効）に変更（例: ふゆう → じめん = 0）
   - 耐性変化特性: 倍率に特性倍率を乗算（例: あついしぼう → ほのお/こおり × 0.5）
4. 分類:
   - 4.0: 4倍弱点
   - 2.0: 2倍弱点
   - 1.0: 等倍
   - 0.5: 半減
   - 0.25: 1/4耐性
   - 0.0: 無効（タイプ無効 or 特性免疫）

### 4-2: 結果を提示

```
## 受けの相性補完

### 弱点
| 攻撃タイプ | 倍率 |
（弱点を倍率の高い順に）

### 耐性
| 攻撃タイプ | 倍率 |
（半減以下を）

### 無効
| 攻撃タイプ |

### 弱点を補完するタイプ提案
| 弱点 | 半減以下で受けられるタイプ |
```

### 4-3: 補完候補の検索と相性補完コア提案

弱点を受けられるタイプで候補を検索:
```bash
$PKDX search --type "<弱点を受けるタイプ>" --version "<version>" --format json
```

候補に対して `$PKDX query` で特性も取得し、特性による実質耐性で再評価:
- 免疫特性持ちは追加の弱点をカバーできる（例: ちょすい持ちはみず無効）
- 耐性変化特性持ちは実質的な受け範囲が広がる

**相性補完コアの提示**: 軸 + 補完で互いの弱点をカバーし合う組み合わせを提案（特性込み）。

### 4-4:【doubles時のみ】ダブル向け受けの並び評価

ダブルバトルでは隣のポケモンを守る手段も「受けの補完」に含まれる:

1. **リダイレクト技持ち**: このゆびとまれ / いかりのこな → 軸への単体攻撃を吸える
2. **いかく持ち**: 場に出るだけで相手2体の攻撃を下げる → 物理耐久を実質補強
3. **ワイドガード / ファストガード持ち**: 全体技 / 先制技から味方を守れる
4. **フレンドガード持ち**: 隣の被ダメを常時0.75xに軽減
5. **まもる採用率**: ダブルではほぼ全員がまもるを採用前提。受けの補完枠にも推奨

### 4-5: メンバー確定・特性選択・持ち物提案

AskUserQuestionで:
- 攻め重視か受け重視か
- 候補から選択

メンバー確定時:
1. `$PKDX query` で特性一覧を取得
2. AskUserQuestionで特性を選択
3. 役割に応じた推奨持ち物を提案（既使用持ち物を除外）
4. AskUserQuestionで持ち物を確定
5. [メンバー確定共通: ポケモンメモ入力](#メンバー確定共通-ポケモンメモ入力) で `members[i].role` を埋める
6. [メンバー確定共通: 育成データ入力](#メンバー確定共通-育成データ入力) で `members[i].nature` / `stat_points` / `actual_stats` を埋める
7. [メンバー確定共通: ダメージ計算入力](#メンバー確定共通-ダメージ計算入力) で cache.damage_calcs にダメ計を追記（任意）

---

## Phase 5: 素早さチェック

### 5-1: 現チームの素早さ評価

stat_thresholds.mdを参照し、確定メンバーの素早さティアを判定。

チーム全体にTier A以上（base 111+）のポケモンが**1体もいない場合**、以下を警告:
```
⚠ チームに高速ポケモンがいません。以下のいずれかが必要です:
- base S 111+の高速ポケモンを追加
- こだわりスカーフで中速ポケモンを高速化
- おいかぜ/トリックルームなどのS操作技
```

### 5-2: こだわりスカーフによる実質素早さの考慮

Tier B-C帯のポケモンでも、こだわりスカーフ持ちなら高速ポケモンを抜ける場合がある。
計算: `スカーフ最速 = (base S × 2 + 52) × 1.1 × 1.5`（小数点切り捨て）

既にチームにスカーフ持ちが確定していない場合、スカーフ枠の候補も提示。

### 5-3:【doubles時のみ】S操作手段の評価

ダブルバトルではS操作技がシングル以上に重要。チーム内のS操作手段を棚卸し:

| S操作手段 | 効果 | 持続 | 評価基準 |
|-----------|------|------|---------|
| おいかぜ | 味方全体S2倍 | 4ターン | 中速チーム向き。始動役の耐久が重要 |
| トリックルーム | S逆転 | 5ターン | 低速エース軸。始動役が倒されないよう保護が必要 |
| こごえるかぜ / エレキネット | 相手S1段階↓ | 永続 | 控えめだが全体技で両方に入る |
| ねこだまし | 相手1体ひるみ | 1ターン | S操作の始動ターンを確保する補助 |

チーム内にS操作手段が**0個**の場合は警告し、おいかぜ/トリックルーム始動役の追加を提案。

### 5-4: 高速候補の検索（必要な場合）

Phase 3-4で決めた補完タイプと両立する高速ポケモンを検索:
```bash
$PKDX search --type "<補完タイプ>" --min-speed 100 --version "<version>" --format json
```

### 5-5: メンバー確定・特性選択・持ち物提案

AskUserQuestionで素早さ枠の方針を確認。

メンバー確定時:
1. `$PKDX query` で特性一覧を取得
2. AskUserQuestionで特性を選択
3. 推奨持ち物を提案（既使用持ち物を除外。スカーフ枠ならこだわりスカーフを優先提案）
4. AskUserQuestionで持ち物を確定
5. [メンバー確定共通: ポケモンメモ入力](#メンバー確定共通-ポケモンメモ入力) で `members[i].role` を埋める
6. [メンバー確定共通: 育成データ入力](#メンバー確定共通-育成データ入力) で `members[i].nature` / `stat_points` / `actual_stats` を埋める
7. [メンバー確定共通: ダメージ計算入力](#メンバー確定共通-ダメージ計算入力) で cache.damage_calcs にダメ計を追記（任意）

### 5-6: 耐久重視ポケモンのSP/EV最適化

耐久寄りのポケモン（HP/防御型アタッカー、壁役、受けポケ等）にSPを振る際は、`pkdx hbd` で総合耐久指数 HBD/(B+D) を最大化する配分を自動算出できる。S振りを固定して残りを H/B/D に最適配分:

```bash
# デフォルト (Champions SP): 予算66、各上限32
$PKDX hbd "<name>" --nature "<nature>" --fixed-ev "_,0,_,0,_,<S_sp>"

# Deprecated版: --version scarlet_violet 指定時は EV として解釈（予算508、各上限252）
$PKDX hbd "<name>" --nature "<nature>" --fixed-ev "_,0,_,0,_,<S_ev>" --version scarlet_violet
```

- `--hp-snap leftovers`: たべのこし持ちは 16n+1（H ≡ 1 mod 16）
- `--hp-snap residual`: 定数ダメ耐性重視は 16n-1
- `--phys-weight P --spec-weight S`: 物理/特殊のメタを反映した非対称重み（例: 物理多なら `--phys-weight 2`）
- `--top N`: 上位 N 候補を比較（微差の配分を選択）

アルゴリズムの詳細・H=B+D の導出・11n調整との関係は `.claude/skills/team-builder/references/bulk_theory.md` を参照。SP システムの詳細は `.claude/skills/team-builder/references/champions_sp.md` を参照。

---

## Phase 6: 仮想敵分析

### 6-1: メタデータ取得

ユーザーに想定する仮想敵6体を直接指定してもらう（手動入力）。AskUserQuestionで以下を確認:
- 現環境で意識したい上位ポケモン
- 軸に不利がつく代表的なポケモン
- よく当たる / 苦手意識のあるポケモン

### 6-2: 仮想敵6体の選出

ユーザー提示のリストから6体を選出する基準:
1. **環境の中心と目されるポケモン**を優先
2. **軸に対して弱点を突けるポケモン**を優先（type.jsonで判定）
3. **残りは環境全体のカバー**を考慮

各仮想敵のデータ取得:
```bash
$PKDX query "<仮想敵名>" --version "<version>" --format json
```

### 6-3: ユーザー確認

AskUserQuestionで仮想敵リストを提示し、入れ替えを受付。

---

## Phase 7: 選出パターン決定

### 7-1: 6体構築の確定

ここまでのフェーズで集まった情報を統合し、6体の構築を確定する。

| Slot | 役割 | 決定元 |
|------|------|--------|
| 1 | 軸 | Phase 1 |
| 2 | 攻め補完 | Phase 3 |
| 3 | 受け補完 | Phase 4 |
| 4 | 素早さ枠 | Phase 5 |
| 5 | メタ対策枠 | Phase 6 |
| 6 | 汎用/糊枠 | 残りの弱点を埋める |

未確定のスロットがある場合、Phase 3-5の候補リストから提案し、AskUserQuestionで決定。
各未確定メンバーの確定時にも特性選択 + 持ち物提案 + ポケモンメモ入力 + 育成データ入力 + ダメージ計算入力 を行う（Phase 3-5と同様のフロー）。共通サブフロー: [ポケモンメモ入力](#メンバー確定共通-ポケモンメモ入力) / [育成データ入力](#メンバー確定共通-育成データ入力) / [ダメージ計算入力](#メンバー確定共通-ダメージ計算入力) を参照。

### 7-1b: 持ち物重複の最終検証

6体全員の持ち物を一覧し、重複がないことを確認。
重複がある場合はAskUserQuestionで代替を提案。

### 7-1c: 育成データ埋め検証（Phase 6 マッチアップ前提）

6 体の `nature` / `stat_points` / `actual_stats` が全員分揃っていることを確認する。未設定のメンバーがいれば [メンバー確定共通: 育成データ入力](#メンバー確定共通-育成データ入力) を個別に呼び、最終的に全員 3 フィールドが埋まった状態で Phase 7-2 以降（カバー率計算 / 選出パターン決定）に進む。

**理由**: Phase 7-3 の選出パターン決定は ダメージ計算 (pkdx damage) を前提としており、また Phase 8 で保存された `box/teams/*.meta.json` が `pkdx select` への入力になる。ここで未設定のまま進むと、後段の分析結果が実構築と乖離する。

埋まっていない場合の Team State Block の確定メンバー行例:

```
  2. ガブリアス (攻め補完) 特性:さめはだ 持ち物:こだわりハチマキ メモ: 性格:未設定 SP:未設定 実数値:未設定
```

このような「未設定」表記が 1 件でも残っている場合、本ステップで必ず埋めてから次に進む。

### 7-2: チーム全体のカバー率計算

type.jsonを参照し、チーム全体の攻撃・防御カバー率を計算:

**攻撃カバー率**:
1. 6体それぞれの攻撃技タイプの集合を統合
2. 各攻撃タイプで抜群を取れる防御タイプの集合を統合
3. カバー率 = 集合サイズ / 18

**防御カバー率**:
1. 18の攻撃タイプそれぞれについて、チーム内で最も有利な受け先を特定
2. 全タイプに半減以下で受けられるメンバーがいるか確認
3. 受け先がいないタイプ = **構築の弱点**

### 7-3: 選出パターン (表選出 / 裏選出)

仮想敵ごとの 6 枚カードではなく、**このチームの「基本選出」と「サブプラン」**の 2 つを決める。

- **表選出 (primary_selection)**: このチームの基本選出。メタ全体で最も広く対応できる組み合わせ
- **裏選出 (alternate_selection)**: 表選出の役割対象外の相手に出すサブプラン

それぞれ `{members: string[], note: string}` を cache の `primary_selection` / `alternate_selection` に格納する (両方 optional、片方だけ入力して Phase 8 に進んでもよい)。

> **重要**: AI が note を勝手に書かない。タイプ相性・特性・技の通り具合の推定で誤情報（特に **タイプ相性の読み違い**）が混入しやすい。note は**ユーザーからのフリー入力 or 空文字**のみ。

#### 入力フロー（表選出 → 裏選出 の順）

以下の 2 サイクルを実行する:

1. **members の確定**:
   - AskUserQuestion で 6 体のメンバー名を選択肢に出し、multiSelect=true で表選出の members を確定
   - singles なら 3 体、doubles なら 4 体を選ぶのが基本だが、スキーマ上は任意数を許容（ユーザーが 5 体選んでもエラーにしない）
   - 判断材料として以下を提示してよい (AI の記憶に頼らない):
     - `pkdx type-chart "<仮想敵の type1>[,<仮想敵の type2>]" --move-type <技タイプ>` で実倍率取得
     - `pkdx query` で特性・種族値取得
     - items_abilities.md の特性・持ち物 / doubles なら §10 コンボパターン
   - AI は候補の列挙と事実ベース (type-chart / query) のコメントに留め、意図そのものはユーザーに委ねる

2. **note のフリー入力**: 以下のテキストを出力してユーザーの次メッセージ全文を note に格納する (改行は半角スペース 1 つに正規化):

   ```
   {表選出 or 裏選出} の狙い・立ち回り・想定ターン・注意点などを入力してください。
   不要なら「なし」と返答してください。
   ```

   「なし」「skip」「省略」「-」→ 空文字格納。

3. 同じ手順で **裏選出** を確定。AskUserQuestion で「裏選出を設定しますか？」を 1 問入れて、「いいえ」なら裏選出を未設定のまま Phase 7-4 へ進む。

#### 保存形式

```json
{
  "primary_selection": {
    "members": ["エンニュート", "ギャラドス", "ピクシー"],
    "note": "表選出の狙い..."
  },
  "alternate_selection": {
    "members": ["ハッサム", "ピクシー", "ブリジュラス"],
    "note": "裏選出の狙い..."
  }
}
```

`members` / `note` 未入力なら空配列 / 空文字を格納。

旧 `matchup_plans[]` は **新規構築では作らない**（writer schema には互換目的で残っているが emit しない）。既存 meta.json に matchup_plans が残っている場合、FE は primary/alternate が未設定のときのみフォールバック描画する。

### 7-4: テラスタル配分（terastal有効時）

terastalメカニクスが有効な場合、AskUserQuestionで:
- どのポケモンにテラスタルを切るか
- 何テラスタイプにするか
- テラスタル後の防御面を再計算して提示

### 7-5: メガシンカ配分（mega有効時）

megaメカニクスが有効な場合:
- メガシンカ可能なメンバーを特定
- メガ後の種族値・タイプ・特性を取得して比較
- AskUserQuestionで確定

### 7-6: 構築コンセプト入力

**構築コンセプト**（構築の狙い・勝ち筋・想定した立ち回り）を team cache の `concept` フィールドに書き込む。記事冒頭のチャプター「構築コンセプト」として掲載される。

#### 要約ソース

要約の材料は **`members[].role`（各メンバーのポケモンメモ） のみ** を使う。Phase 7-3 の matchup_plans は typing 誤認の危険があるため要約材料にしない。Phase 7-4/5 (テラス / メガ枠) の **事実情報** (どのポケモンにメガ石が乗っているか等) は補足として含めてよいが、AI による戦術評価・タイプ相性判定は含めない。

#### フロー

1. **要約生成**: 6 体の `role` フィールドを材料に、200〜400 文字で「軸は何で、どうやって勝つか」を日本語で要約する。以下のガードレールを守る:
   - 各ポケモンの **採用意図・役割・勝ち筋の言語化** のみに限定
   - タイプ相性・特性効果などの事実主張は避ける（ユーザーがメモに書いている範囲のみ引用可）
   - 構築名・軸・メガ枠などの事実は `members[].item` / mechanics 設定から確認してから書く（記憶に頼らない）

2. **ユーザーへフィードバック**: 生成した要約を提示してから AskUserQuestion:

   | # | 質問 | header | オプション |
   |---|------|--------|-----------|
   | 1 | この要約を構築コンセプトとして採用しますか? | コンセプト確定 | このまま採用(desc: 要約をそのまま concept に格納), 追記したい(desc: 次メッセージで追記内容を受け付け), 書き直す(desc: 次メッセージでユーザー自身が全文を書き直す), 空のまま進む(desc: concept = 空文字。記事にコンセプト章は出ない) |

3. **追記/書き直し の場合**: 次メッセージのユーザー入力全文を採用（追記なら生成要約 + ユーザー追記、書き直しなら完全置換）
4. cache の `concept` に格納

#### ダメージ計算の扱い

ダメージ計算結果は Phase 2-8 / 3-6(8) / 4-5(7) / 5-5(7) / 7-1(damage) / Phase 1-Team-Vision step 4-b の [メンバー確定共通: ダメージ計算入力](#メンバー確定共通-ダメージ計算入力) で都度累積されている想定。追加の計算が必要なら calc スキル側で `pkdx damage --attach-team` を実行できる。`concept` はそれら計算を前提にした勝ち筋の言語化として使う。


---

## Phase 8: 構築レポート出力

### 8-1: 出力形式の確認

**AskUserQuestion**（3問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | ポケソル形式のテキストも出力しますか？ | ポケソル出力 | はい(desc: ダメージ計算SV等で読み込めるテキストも出力), いいえ(desc: mdレポートのみ) | false |
| 2 | この構築データをバージョン管理の対象にしますか？ | バージョン管理 | はい(desc: gitで変更履歴を残す。GitHubアカウントがあればクラウドにもバックアップ可能), いいえ(desc: 手元にのみ保存。gitには記録しない) | false |
| 3 | この構築を構築ブログで公開しますか？ | ブログ公開 | いいえ(default, desc: 下書き状態で保存。ブログには掲載されない), はい(desc: 公開状態で保存。fork で構築ブログを有効化済みなら push 時に掲載される) | false |

質問2の回答に基づきファイル名を決定:
- **はい** → `{軸ポケモン名}-build-{YYYY-MM-DD}` （通常のファイル名）
- **いいえ** → `__no_save.{軸ポケモン名}-build-{YYYY-MM-DD}` （gitignore対象）

質問3の回答は md の frontmatter `published:` を決める:
- **いいえ** (default) → `published: false` (ブログ非掲載)。後から公開したくなったら md の `published:` を `true` に書き換えるか、同じ引数で **--publish** を付けて `pkdx write teams` を再実行する
- **はい** → `published: true` (ブログ掲載)。既存 md の edit-lock はそのまま有効

### 8-1.5: ポケモン画像の一括添付（任意）

構築ブログのメンバーカードは `site/public/pokemons/<member.name>.{png,jpg}` を**自動的に**右上に表示する。Phase 8-2 で md を書き出す前に、6 体分の画像を**チャットへ添付**することで一括登録できる。手動で `site/public/pokemons/` にファイルを置く必要はない。

**外部 runtime 不要**: 画像配置は agent (Claude) が `file` で形式・寸法を判定し、`cp` で `site/public/pokemons/` へ直接保存する。Bun / Node 等の追加 runtime は不要。

**スキップ可**: 画像が要らない / 後で blog skill の Phase H から登録する場合は、この 8-1.5 を丸ごと skip して 8-2 に進む。

#### 8-1.5-1: 添付の希望確認

**AskUserQuestion** (1問):

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | このタイミングでメンバー画像を添付しますか？ | 画像添付 | 後で(default, desc: 8-2 へ進む。後から blog skill の Phase H で追加可能), 今添付する(desc: 6 体分の画像を順番に添付) | false |

「後で」なら 8-1.5 を終了し 8-2 に進む。

#### 8-1.5-2: 既存の画像配置確認

「今添付する」が選ばれた場合、cache の `members[].name` を全件列挙して、各メンバーの画像配置状況を表示する:

```bash
for name in $(キャッシュから member.name を順番に取得); do
  if [ -f "$REPO_ROOT/site/public/pokemons/${name}.png" ]; then
    echo "${name}  ✓ (png)"
  elif [ -f "$REPO_ROOT/site/public/pokemons/${name}.jpg" ]; then
    echo "${name}  ✓ (jpg)"
  else
    echo "${name}  ✗ (未配置)"
  fi
done
```

通常メッセージとして一覧を表示。

#### 8-1.5-3: 添付対象の選択

**AskUserQuestion** (multiSelect):

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どのメンバーの画像を添付しますか？ | 対象 | members[] 各エントリ (各 desc に 「未配置 / 既存あり (差し替え)」を表示) | true |

選択 0 件なら 8-1.5 を終了し 8-2 へ。

#### 8-1.5-4: 各メンバーの画像を添付・検証・保存

選択リストを順番に処理する。各メンバーごとに通常メッセージで以下を提示:

```
[1/3] カバルドン の画像を添付してください
  仕様: 340×340 以上の正方形、PNG または JPEG
  (skip する場合は「skip」と入力)
```

ユーザーが画像を添付すると agent にローカルファイルパスが渡される。以下を**この順序で**実行する (詳細は blog skill Phase H-4 と同一)。

##### 8-1.5-4-a: symlink を拒否

```bash
SRC="<添付ファイルの絶対パス>"
[ -L "$SRC" ] && echo "REJECT_SYMLINK"
```

`REJECT_SYMLINK` が出たら「symlink は受け付けません」を提示し再添付要求 (skip なら次へ)。

##### 8-1.5-4-b: 形式と寸法を `file` で取得 + 判定

```bash
file "$SRC"
```

agent が出力をパース (BSD/GNU 共通フォーマット `PNG image data, W x H` / `JPEG image data, …, WxH`):

- 形式が PNG / JPEG 以外 → reject
- 寸法を抽出 (失敗時は **添付画像を agent が直接見て**おおよその寸法を判断)
- W ≠ H → reject (「正方形にしてください: 480×320」)
- W < 340 → reject (「340×340 以上にしてください: 200×200」)

reject なら理由提示 + 再添付要求。skip なら次へ。

##### 8-1.5-4-c: 拡張子決定 + 既存衝突確認

形式から拡張子を決め (`PNG` → `.png`、`JPEG` → `.jpg`)、保存先パスを組み立て:

```bash
DEST="$REPO_ROOT/site/public/pokemons/<member.name>.<ext>"
```

既存ファイルがある場合のみ **AskUserQuestion** (1問):

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | `<member.name>` の画像 (`<DEST>`) が既に存在します。どうしますか？ | 上書き | 上書きする(desc: 既存を消して新しい画像で置き換え), skip(desc: 既存を残す), 中断(desc: 8-1.5 を抜けて 8-2 へ) | false |

- 「skip」→ 次のメンバーへ
- 「中断」→ 残メンバー処理せず 8-2 へ
- 「上書きする」→ 8-1.5-4-d へ

##### 8-1.5-4-d: cp で保存

```bash
mkdir -p "$REPO_ROOT/site/public/pokemons"
cp "$SRC" "$DEST"
```

成功なら通常メッセージで「✓ <member.name>.<ext> を保存しました (<W>×<H>)」と報告し次のメンバーへ。

#### 8-1.5-5: 完了報告

全メンバー処理後、まとめを通常メッセージで出力:

```
画像添付完了:
  ✓ カバルドン.png 保存
  ✓ マンムー.png 保存
  - アーマーガア skip

site/public/pokemons/ 配下に作成されています。
構築 md を出力します...
```

直後に**自動で 8-2 へ遷移**。site/public/pokemons/* への変更は team-builder からは commit しない (構築 md と一緒に blog skill の Phase G で反映確認するか、ユーザーが手動で commit する)。

### 8-2: mdレポート出力（キャッシュ JSON → pkdx write）

キャッシュ JSON はPhase 0-7で段階的に構築済み。CLIがJSON→マークダウンCST→serializeを行うため、**マークダウンを直接書く必要はない**。

**出力先**:
- バージョン管理あり: `box/teams/{軸ポケモン名}-build-{YYYY-MM-DD}.md`
- バージョン管理なし: `box/teams/__no_save.{軸ポケモン名}-build-{YYYY-MM-DD}.md`

8-1の回答に基づき `--axis` の値を決定:
- バージョン管理あり → `--axis "<軸ポケモン名>"`
- バージョン管理なし → `--axis "__no_save.<軸ポケモン名>"`

```bash
# 8-1 の質問3 が「いいえ」: 非公開で保存 (published: false)
cat $CACHE_FILE | $PKDX write teams --date "YYYY-MM-DD" --axis "<軸ポケモン名 or __no_save.軸ポケモン名>"

# 8-1 の質問3 が「はい」: 構築ブログに掲載 (published: true)
cat $CACHE_FILE | $PKDX write teams --date "YYYY-MM-DD" --axis "<軸ポケモン名 or __no_save.軸ポケモン名>" --publish
```

CLIはキャッシュ JSON のスキーマ（`members` + `coverage` + `defense_matrix` 等）をバリデーションする。
全メンバーの `moves` が4技埋まっていない場合はバリデーションエラーとなる。

**エラー時の再試行**: exit code が 0 以外の場合、stderrのエラーメッセージに基づいてキャッシュ JSON を修正し再試行する。最大3回まで。

**生成される md の frontmatter**: 構築ブログ (`site/` の Astro が読む) 用に、以下の YAML frontmatter が自動付与される:

```yaml
---
title: "<軸ポケモン名> 構築"
axis: "<軸ポケモン名>"
date: YYYY-MM-DD
battle_format: "singles" | "doubles"
mechanics: "..."
version: "..."
regulation: "..."      # nullable
members: ["...", ...]  # 名前フロー配列
tags: []
edited: false          # ユーザーが手編集した場合に true に書き換える
published: false       # `--publish` 指定時だけ true。構築ブログ掲載可否を決める (falsy = 非公開)
generated_by: "pkdx"
schema_version: 1
---
```

**edit-lock (`edited: true`)**: ブログ向けに手編集した md は `edited: true` に書き換えておくと、次回以降の `pkdx write teams` 実行時に **md を上書きしない** (`.meta.json` は毎回更新される)。強制上書きしたい場合は `--force` を付ける:

```bash
cat $CACHE_FILE | $PKDX write teams --date "YYYY-MM-DD" --axis "..." --force
```

skip 時は stderr に `Preserved hand-edited box/teams/<slug>.md` と出るので、ユーザーには「前回の手編集を保持した。上書きしたい場合は再実行時に『--force で上書き』と伝えて」と案内する。

レポート出力後、ファイルパスをユーザーに通知。キャッシュファイルを削除する。

### 8-3: ポケソルテキスト出力

8-1で「はい」の場合のみ、Writeツールで以下の形式のテキストファイルを書き出す。

**出力先**: mdレポートと同じ prefix ルールを適用（バージョン管理なしの場合は `__no_save.` 付与）
- バージョン管理あり: `box/teams/{軸ポケモン名}-build-{YYYY-MM-DD}.txt`
- バージョン管理なし: `box/teams/__no_save.{軸ポケモン名}-build-{YYYY-MM-DD}.txt`

各ポケモンのブロックを空行区切りで並べる:

```
{ポケモン名} / {特性} / {持ち物}
{技1} / {技2} / {技3} / {技4}
実数値: {HP}-{攻撃}-{防御}-{特攻}-{特防}-{素早さ}
SP: {HP}-{攻撃}-{防御}-{特攻}-{特防}-{素早さ}
性格: {性格名}
```

**注意事項**:
- Champions では「SP」、deprecated バージョンでは「努力値」と表記する
- 実数値・SP・性格は **Phase 7-1c で埋め済みの `members[i].actual_stats` / `members[i].stat_points` / `members[i].nature`** から読み取る。未設定のまま Phase 8 に到達することは 7-1c でブロックしているため通常は発生しないが、例外的に未設定があれば `実数値: 未設定` / `SP: 未設定` / `性格: 未設定` と記載してユーザーに警告する
- team-builder cache に育成データが欠けていて、かつ `box/pokemons/<name>/` 配下に breed 出力がある場合は breed 側 meta.json を fallback source として利用可能（同一ポケモン・同一性格の場合のみ）。新 schema では breed の `build` セクションの `nature` / `stat_points` / `actual_stats` / `moves` はそのまま `members[i]` に転写できる (キー互換)。
- 技はPhase 8のレポートで推奨した4技を使用

---

## Team State Block

各フェーズ終了時に以下を出力し、会話内の状態を管理する。contextが圧縮された場合も、最新のTeam Stateから状態を復元可能。また、キャッシュファイルからも読み出すことができる。

```
=== Team State (Phase N完了) ===
バトル形式: {singles or doubles}
メカニクス: {有効メカニクス}
バージョン: {version}
軸: {名前} ({type1}/{type2}) [{H}/{A}/{B}/{C}/{D}/{S}] globalNo:{globalNo}
攻めカバー: {タイプ一覧} → {X}/18タイプ
攻めの穴: {タイプ一覧}
弱点: {タイプ(倍率)}（特性補正込み）
耐性: {タイプ(倍率)}（特性補正込み）
素早さ: Tier {X} (base {S})
確定メンバー:
  1. {名前} (軸) 特性:{特性名} 持ち物:{持ち物名} メモ:{role or 未記入} 性格:{nature or 未設定} SP:{HABCDS or 未設定} 実数値:{HABCDS or 未設定}
  2. {名前 or 検討中} (攻め補完) 特性:{特性名} 持ち物:{持ち物名} メモ:{role or 未記入} 性格:{nature or 未設定} SP:{HABCDS or 未設定} 実数値:{HABCDS or 未設定}
  3. {名前 or 検討中} (受け補完) 特性:{特性名} 持ち物:{持ち物名} メモ:{role or 未記入} 性格:{nature or 未設定} SP:{HABCDS or 未設定} 実数値:{HABCDS or 未設定}
  4. {名前 or 検討中} (素早さ枠) 特性:{特性名} 持ち物:{持ち物名} メモ:{role or 未記入} 性格:{nature or 未設定} SP:{HABCDS or 未設定} 実数値:{HABCDS or 未設定}
  5. {名前 or 検討中} (メタ対策) 特性:{特性名} 持ち物:{持ち物名} メモ:{role or 未記入} 性格:{nature or 未設定} SP:{HABCDS or 未設定} 実数値:{HABCDS or 未設定}
  6. {名前 or 検討中} (汎用) 特性:{特性名} 持ち物:{持ち物名} メモ:{role or 未記入} 性格:{nature or 未設定} SP:{HABCDS or 未設定} 実数値:{HABCDS or 未設定}
使用済み持ち物: [{持ち物1}, {持ち物2}, ...]
【doubles時のみ】S操作手段: {おいかぜ/トリックルーム/ねこだまし等}
【doubles時のみ】横の並びペア: {主要な先発ペアとそのシナジー}
仮想敵: {6体のリスト or Phase 6で決定}
```

---

## エラーハンドリング

| 状況 | 対応 |
|------|------|
| pkdx / pokedex.db が見つからない | Phase 0でセットアップ手順を案内し終了 |
| pkdx query の結果が空 | ポケモン名の確認を再度依頼。リージョンフォームの可能性を案内。メガシンカの場合はパッチ実行を提案 |
| pkdx moves の結果が空 | version値の不一致の可能性を案内 |
| DB未収録のポケモン | AskUserQuestionでタイプ・種族値・主要技を手動入力してもらう |
| `pkdx write teams` が `legacy schema detected` エラー | 該当 meta.json は旧 schema (hp/atk/... 長キー等)。`bin/pkdx convert meta --in <path> --in-place` で新 schema に変換してから再実行する |
