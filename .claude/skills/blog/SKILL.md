---
name: blog
description: "サイト記事・設定のメンテナンス。新規ブログ記事の作成、公開/非公開切替、frontmatter (タイトル・説明文・タグ) 編集、記事削除、記事一覧表示、メンバー画像追加・差し替え、構築記事の本文編集 (構築コンセプト / ダメージ計算 / ポケモンメモ / 選出やりなおし)、サイト設定 (サイト名 / author / enabled) 変更を対話的に行う。最後にユーザー確認のうえ git push でサイトに反映。記事管理・ブログ管理・本文編集・構築コンセプト編集・ダメ計追加削除・ポケモンメモ・選出変更・メンバー画像差し替え・サイト名変更・公開切替・記事削除・記事一覧などの際に使用。"
allowed-tools: Bash, Bash(git status:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git remote:*), Bash(git branch:*), Read, Edit, Write, Glob, AskUserQuestion
---

# Blog / Site Maintenance

`box/blog/`, `box/teams/`, `box/site.config.json` に対するメンテナンス操作を提供する。team-builder / breed がコンテンツを「生成」する側であるのに対し、このスキルはコンテンツを「管理」する側に特化する。

本スキルは以下を 1 セッションで扱う:

1. コンテンツ編集（Phase A-F）
2. 編集結果の確認と git push（Phase G、**ユーザー承認必須**）

**git push は Phase G で必ずユーザーの YES 確認を得てから実行する。** 無確認で push することはない。push を拒否された場合はローカルに変更を残したまま終了する。

## Skip 判定 共通ルール

全 Phase の AskUserQuestion に適用される共通ルール:

**skip してよい条件（いずれか該当）**:
- ユーザー発話に既に当該質問の回答が含まれている（例: 「カバルドン記事を削除したい」→ コレクション選択・記事選択 を skip）
- 直前の Phase / AskUserQuestion で既に確定した情報を再確認する質問
- ユーザーが操作対象パスを絶対 / 相対パスで明示している

**skip 時の扱い**:
- 想定される回答を skill 記載の手順通りに内部で決定
- skip した事実と選んだ想定応答をユーザーへ通常メッセージで開示（例: 「対象コレクションを `teams` と判定して続行します」）

**絶対に skip してはいけない質問**:
- 削除確認ダイアログ（Phase D-3）
- Phase G-2 の反映可否確認
- Phase G-3 の送信先最終確認（「反映する」経路）
- Phase G-4 の commit メッセージ確認

## Phase 間遷移の原則

各 Phase の完了報告（例: A-5, B-5, C-5, D-5, E-5, H-5, I-8）直後の Phase G への遷移は**自動**で行う。間に確認の AskUserQuestion は挟まない。ユーザーは完了報告テキストを見て、Phase G の差分提示へと続けて移行する。

## パス定義

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../..
BLOG_DIR=$REPO_ROOT/box/blog
TEAMS_DIR=$REPO_ROOT/box/teams
SITE_CONFIG=$REPO_ROOT/box/site.config.json
```

## Phase 0: 初期化

### 0-1: box 配下の存在確認

```bash
ls "$REPO_ROOT/box" >/dev/null 2>&1 || { echo "box/ が見つかりません。setup.sh を先に実行してください。"; exit 1; }
```

### 0-2: site.config.json 読み込み

`$SITE_CONFIG` が存在しない場合は作成する:

```bash
if [ ! -f "$SITE_CONFIG" ]; then
  cat > "$SITE_CONFIG" <<'JSON'
{
  "site_name": "pkdx site",
  "author": null,
  "enabled": true
}
JSON
fi
```

存在する場合は Read で現状を取得する。

### 0-3: 操作選択

最初の AskUserQuestion で編集系 4 操作（Phase A/B/C/D）のみ提示し、それら**すべてに該当しない**ときだけ 2 段目 AskUserQuestion を出す。ユーザー発話にすでに明確な意図がある場合（「サイト名を〇〇に変えたい」「一覧を見たい」等）は 1 段目を skip して該当 Phase に直接遷移してよい。

**AskUserQuestion**（1問、ユーザー意図が既に明確なら skip 可）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どの操作を行いますか？ | 操作 | 新規ブログ記事作成(desc: box/blog/ に新しい記事ファイルを作る), 記事の編集/削除/公開切替(desc: 既存記事の frontmatter 編集・削除・published フラグ反転), サイト設定 or 記事一覧(desc: site_name / author / enabled / 記事一覧表示), その他(desc: 上記以外を Other で入力) | false |

選択内容に応じて以下へ:
- 「新規ブログ記事作成」 → Phase A
- 「記事の編集/削除/公開切替」 → **続く AskUserQuestion**（下記）で B/C/D のどれかを確定
- 「サイト設定 or 記事一覧」 → **続く AskUserQuestion**（下記）で E/F のどちらかを確定
- 「その他」→ Other キーワードから判定

「記事の編集/削除/公開切替」を選んだ場合、続く AskUserQuestion:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どの操作？ | 操作 | 公開/非公開切替(desc: Phase B), フロントマター編集(desc: Phase C), 削除(desc: Phase D), メンバー画像メンテ(desc: Phase H — team 記事のメンバー画像追加・差し替え), 本文編集(desc: Phase I — 構築コンセプト / ダメージ計算 / ポケモンメモ / 選出 の編集 (team 記事のみ)) | false |

「サイト設定 or 記事一覧」を選んだ場合、続く AskUserQuestion:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どちら？ | 操作 | サイト設定変更(desc: Phase E), 記事一覧表示(desc: Phase F) | false |

Other での直接キーワード判定は以下:
- 「新規」「作成」「書く」→ Phase A
- 「公開」「下書き」「非公開」→ Phase B
- 「編集」「タイトル変更」→ Phase C
- 「削除」「消す」→ Phase D
- 「画像」「メンバー画像」「ポケモン画像」→ Phase H
- 「コンセプト」「構築コンセプト」「ダメ計」「ダメージ計算」「ポケモンメモ」「役割メモ」「role」「選出」「表選出」「裏選出」「本文」→ Phase I
- 「設定」「サイト名」「author」→ Phase E（2段目 skip 可）
- 「一覧」「リスト」→ Phase F（2段目 skip 可）

選択結果に応じて該当 Phase へ遷移する。

### 0-4: ローカル dev プレビューの起動（任意）

操作 Phase へ遷移する直前に、ユーザーへローカル dev プレビューを起動するか確認する。dev サーバーを立ち上げておくと、Edit / Write のたびに Astro が hot reload するので、ユーザーは編集結果をブラウザでリアルタイムに確認しながら作業できる。

**Phase F (一覧表示) を選んだ場合は本ステップを skip** (差分が出ない / プレビューする意味がないため)。それ以外は以下を実行。

#### 0-4-1: 起動希望の確認

**先に port 4321 の使用状況を確認**してから AskUserQuestion を出す:

```bash
ALREADY_RUNNING=$(lsof -nP -iTCP:4321 -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -1)
```

`$ALREADY_RUNNING` が空でない場合は通常メッセージで以下を出して**skip** (既起動の dev server をユーザーは別ターミナルで使っている想定):

```
http://localhost:4321 で既に何かがリッスンしています。
別ターミナルで起動済みの dev server を使うか、ご自分で確認してください。
```

`$ALREADY_RUNNING` が空の場合のみ **AskUserQuestion** (1問)。**質問には bun runtime が必要である旨の断りを必ず含める** (setup.sh は bun を入れないため、ユーザーが未導入の可能性がある):

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | ローカルで dev プレビューしながら作業しますか？ (Astro の hot reload で編集結果がリアルタイムに反映されます。**プレビュー起動には bun runtime が必要です。未導入の場合は scripts/install_bun.sh で自動インストールするか確認します**) | プレビュー | 起動しない(default, desc: 編集だけ進めて、ブラウザで確認しない), 起動する(desc: preview_start で site を起動。bun 未導入なら先にインストール確認。Phase G 終了時に停止確認) | false |

「起動しない」を選ばれた場合はそのまま該当 Phase へ。

#### 0-4-2: dev server を preview_start で起動

「起動する」を選ばれた場合、**`mcp__Claude_Preview__preview_start` ツール**を `name: "site"` で呼び出す。生 Bash で `bun run dev &` を回さない (プロセス管理が手動になり Phase G-7 の停止が不安定になるため、preview_start に一任する)。

前提として `.claude/launch.json` に `site` エントリが必要 (この repo では既に配置済み)。`preview_start` は launch.json の `runtimeExecutable` / `runtimeArgs` / `cwd` / `port` を読んで `bun run dev` を `site/` 配下で起動する。

**bun の存在確認**: `runtimeExecutable: "bun"` のため bun が PATH 上に無いと preview_start は失敗する。`setup.sh` は意図的に bun を入れないため、以下で検出し、未インストール時は `scripts/install_bun.sh` を案内する:

```bash
if ! command -v bun &>/dev/null; then
  echo "MISSING_BUN"
fi
```

`MISSING_BUN` が出力された場合、通常メッセージで以下を提示してから **AskUserQuestion** (1問) を出す:

```
dev server 起動には bun runtime が必要ですが、PATH 上に見つかりません。
scripts/install_bun.sh で bun 1.3.12 (site/ の pin バージョン) をインストールできます。
(~/.bun/bin/bun に入り、~/.zshrc / ~/.bashrc に PATH 追記されます)
```

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | bun を今インストールしますか？ | インストール | インストールする(default, desc: scripts/install_bun.sh を実行), スキップ(desc: dev プレビューを使わず編集だけ進める) | false |

「インストールする」を選ばれた場合:

```bash
bash "$REPO_ROOT/scripts/install_bun.sh"
# 新シェルではなく現行シェル向けに PATH を通す
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
command -v bun  # 再確認
```

インストールに失敗 (exit code != 0) または `command -v bun` が依然空なら、「起動しない」相当で該当 Phase へ遷移する (DEV_PREVIEW_ID は設定しない)。成功したら次の preview_start 呼び出しへ進む。

「スキップ」を選ばれた場合は「起動しない」相当で該当 Phase へ。

```
preview_start(name="site")
→ { serverId, port: 4321, name: "site", reused: <bool> }
```

`serverId` を**セッション内変数 `DEV_PREVIEW_ID` として記憶**する (Phase G-7 で停止する際に必要)。

起動後、最大 15 秒ほど待ってから http://localhost:4321/pkdx/ がリッスンし始めたかを以下で確認:

```bash
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if curl -fsS -o /dev/null http://localhost:4321/pkdx/; then
    echo "ready"
    break
  fi
  sleep 1
done
```

起動できたら通常メッセージで案内 (Astro は `astro.config.mjs` で `base: "/pkdx/"` を設定しているため、ルート `/` は 404 になる。プレビューを開くときは必ず `/pkdx/` 付きで案内する):

```
✓ dev server を起動しました
  URL: http://localhost:4321/pkdx/   ← base path /pkdx/ を必ず付けること (ルートは 404)
  編集するたびに自動でブラウザに反映されます (要リロード)

  【Claude Desktop でプレビューを開く】
  - Preview ペインを開く: Cmd+Shift+P (macOS) / Ctrl+Shift+P (Windows)
  - または セッションツールバーの「Preview」ドロップダウンから
  - Preview ペインが開いていれば上記 URL が自動でロードされます
  - Claude Desktop 以外で確認する場合はブラウザに URL を直接開いてください

  Phase G 完了時に停止確認します。
```

15 秒以内に起動しなかった場合は、preview_start の戻り値や `mcp__Claude_Preview__preview_logs` でエラーを確認し、`DEV_PREVIEW_ID` を破棄してから該当 Phase へ進む (プレビューなしで作業継続)。

---

## Phase A: 新規ブログ記事作成

### A-1: 基本情報の収集

**AskUserQuestion**（3問、全て Other で自由入力）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 記事のタイトルは？ | タイトル | Otherで入力(desc: 日本語可) | false |
| 2 | ファイル名（slug, 半角英数とハイフン）は？ | slug | Otherで入力(desc: 例 first-post, 2026-release-notes), 日付付きで自動生成(desc: post-YYYY-MM-DD) | false |
| 3 | description（検索結果やカードに出る短い紹介）は？ | description | Otherで入力(desc: 1-2文程度), 省略(desc: 空欄にする) | false |

slug バリデーション: `^[a-zA-Z0-9][a-zA-Z0-9\-]*$`。NG の場合は再入力を促す。

### A-2: タグ（任意）

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | タグを追加しますか？ | タグ | なし(desc: タグ空で作成), Otherで入力(desc: カンマ区切り 例: 対戦,考察) | false |

### A-3: 公開状態

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 公開状態は？ | 公開 | 下書き(published: false)(desc: まず非公開で作成。後から切り替え), 公開(published: true)(desc: いきなり公開) | false |

### A-4: ファイル生成

> **frontmatter 表記ルール（site/src/content.config.ts の blogSchema 準拠）**:
> - `title` / `description`: ダブルクォート囲み（例: `title: "記事タイトル"`）
> - `date`: クォート無し ISO 日付（`date: 2026-04-22`）
> - `tags`: inline flow 配列、各要素ダブルクォート囲み（例: `tags: ["astro", "dev"]`）
> - `published`: クォート無しの真偽値（`published: false`）
> - `description` / `tags` / `eyecatch` は schema 側で optional。値が空の場合はキーごと省略してよい（`tags: []` 空配列も OK だが省略が推奨）

重複チェック:

```bash
DEST="$BLOG_DIR/<slug>.md"
if [ -e "$DEST" ]; then
  echo "既に存在します: $DEST"
  # AskUserQuestion で上書き確認 or slug 再入力
fi
```

今日の日付を取得:

```bash
TODAY=$(date +%Y-%m-%d)
```

Write tool で `$DEST` を上述の表記ルールに**完全準拠**した形式で生成する。以下は具体例 (タイトル="Astro アップグレードメモ", slug=astro-upgrade-notes, tags=astro/dev, published=false, date は **必ず `date +%Y-%m-%d` の実行結果を使う**。skill 内の例日付をそのまま写すと、実行日と違う場合にバグる):

```markdown
---
title: "Astro アップグレードメモ"
date: 2026-04-22   # ← TODAY=$(date +%Y-%m-%d) の結果。例の値をそのまま使わない
description: "Astro 6 系への移行メモ"
tags: ["astro", "dev"]
published: false
---

# Astro アップグレードメモ

ここから本文を書いてください。
```

上記の各フィールドについて:
- `title`: ユーザー入力を**必ずダブルクォート**で囲む
- `date`: `TODAY=$(date +%Y-%m-%d)` の値をクォート無しで
- `description`: **ダブルクォート**で囲む。空なら行ごと省略
- `tags`: inline flow で**各要素ダブルクォート**。空なら行ごと省略（`tags: []` より推奨）
- `published`: `true` / `false` をクォート無しで

### A-5: 完了報告

```
新規記事を作成しました: box/blog/<slug>.md
  公開状態: <下書き | 公開>
  本文を編集するには box/blog/<slug>.md を直接エディタで開いてください。
```

続いて A-6 （dev server 再起動）を判定してから [Phase G: 反映確認](#phase-g-反映確認) に進む（`action = "create"`, `slug = <slug>`）。

### A-6: dev server 再起動（新規ファイル反映のため）

Astro の content collection (glob loader) は既存ファイルの Edit には hot reload で追従するが、**新規追加された md は dev server を再起動するまで `/pkdx/blog/<slug>/` ルートが生成されない**（`[...slug].astro` の getStaticPaths が dev 起動時のスナップショットで固定されるため）。従って Phase A で新規作成した直後は、プレビュー中の dev server を必ず再起動してから Phase G の反映確認へ進む。

**skip 条件**: `DEV_PREVIEW_ID` が未設定（Phase 0-4 で dev server を起動していない / 起動失敗した）場合は本ステップを skip。ユーザー確認も挟まず次へ進む。

`DEV_PREVIEW_ID` が設定されている場合のみ、以下を**無確認で自動実行**する（ユーザーは Phase 0-4 でプレビュー前提の作業に同意済みのため、再起動ごとに問い合わせると煩わしい）:

```
mcp__Claude_Preview__preview_stop(serverId: "<DEV_PREVIEW_ID>")
mcp__Claude_Preview__preview_start(name: "site")
→ 戻り値の serverId で DEV_PREVIEW_ID を上書き
```

`preview_start` 直後は Phase 0-4-2 と同様に最大 15 秒まで `curl -fsS http://localhost:4321/pkdx/` でリッスン確認する。起動できたら通常メッセージで以下を報告:

```
✓ dev server を再起動しました (新規記事ルート反映のため)
  URL: http://localhost:4321/pkdx/blog/<slug>/
  published: false の場合はビルド対象外となるため /pkdx/blog/ 一覧には出ませんが、
  URL 直打ちでプレビューできます。
```

再起動に失敗した場合（`preview_start` がエラー / 15 秒タイムアウト）は `DEV_PREVIEW_ID` をクリアし、通常メッセージで以下を出してから Phase G へ進む（Phase G-7 の停止確認は skip される）:

```
⚠ dev server の再起動に失敗しました。手動で再起動してください:
  mcp__Claude_Preview__preview_list → preview_stop → preview_start
```

---

## Phase B: 公開/非公開切替

### B-1: 対象コレクション選択

**skip 判定**: ユーザー発話に対象パスが含まれる場合（例: `box/teams/...md` や「team 記事」「blog 記事」の明示）、本ステップを skip して B-2 に直接進んでよい。skip した場合、対象コレクションは発話から判定する。

**AskUserQuestion**（1問、skip 条件未適用時のみ）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どのコレクションの記事を切り替えますか？ | 対象 | blog(desc: box/blog/ 配下), teams(desc: box/teams/ 配下) | false |

### B-2: 記事選択

対象ディレクトリから `*.md` をリスト化（`TEMPLATE.md.example` は除外）:

```bash
TARGET_DIR=$BLOG_DIR   # or $TEAMS_DIR
find "$TARGET_DIR" -maxdepth 1 -name '*.md' ! -name 'TEMPLATE*' | sort
```

各記事の現状 `published` フラグを Read して把握する:

```bash
for f in *.md; do
  grep -E '^published:' "$f" || echo "(未設定)"
done
```

表示例:

```
[1] SAMPLE-カバルドン-build-2026-04-21.md  published: true
```

**AskUserQuestion**（1問、最大4件ずつバッチ）:

- 記事数 ≤ 4: そのまま選択肢に並べる
- 記事数 > 4: 「ファイル名を直接指定」等で Other 入力を受ける

### B-3: published フラグ反転

Edit tool で対象ファイルの frontmatter 内 `published: ` を反転する:

- `published: true` → `published: false`
- `published: false` → `published: true`
- 未設定の場合: `date:` 行の直後に `published: false` を挿入（`published` のデフォルトは true だが、明示しておく）

### B-4: publishedAt リセット考慮

published: false → true へ切り替えた場合、`publishedAt` の扱い:

- `with-published-at.ts` loader が git log で自動補完するため、**特に何もしない**のが正解
- ただし「今から公開した」扱いで並び順を最新に寄せたい場合は `publishedAt:` 行を明示的に追加する提案をする

**AskUserQuestion**（false → true の場合のみ、1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 公開日時をどう扱いますか？ | 公開日時 | 自動(推奨)(desc: git log から自動補完される), 今の時刻を publishedAt に明記(desc: 一覧で最新として扱われる) | false |

「今の時刻」を選んだ場合:

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

Edit tool で frontmatter に `publishedAt: <NOW>` を追加（既存があれば上書き）。

### B-5: 完了報告

```
<ファイル名> の公開状態を <new_state> に変更しました。
```

続いて [Phase G: 反映確認](#phase-g-反映確認) に進む（`action = "toggle"`, `slug = <slug>`, `new_state = <new_state>`）。

---

## Phase C: 記事のフロントマター編集

### C-1: 対象選択

Phase B-1 / B-2 と同じフローで対象記事を選ぶ。**B-1 の skip 判定ルールも同様に適用される**。

### C-2: 編集項目選択

Read で現状の frontmatter を取得してユーザーに提示した上で:

**AskUserQuestion**（1問, multiSelect）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どの項目を編集しますか？ | 項目 | title, description, tags, eyecatch | true |

### C-3: 新しい値の入力

選ばれた項目ごとに AskUserQuestion で Other 入力を受ける。各項目:

- `title`: 文字列（空禁止）
- `description`: 文字列（空許可 → 行ごと削除）
- `tags`: カンマ区切り → `[tag1, tag2]` 形式に整形
- `eyecatch`: パス文字列（空許可 → 行ごと削除）

### C-4: Edit 適用

Edit tool で frontmatter 内の対象行を書き換える。値が空で削除対象の場合は `replace_all: false` で行そのものを消す。

### C-5: 完了報告

```
<ファイル名> のフロントマターを更新しました:
  - <field>: <before> → <after>
```

続いて [Phase G: 反映確認](#phase-g-反映確認) に進む（`action = "edit"`, `slug = <slug>`, `fields = <updated fields>`）。

---

## Phase D: 記事削除

### D-1: 対象選択

Phase B-1 / B-2 と同じフローで対象記事を選ぶ。**B-1 の skip 判定ルール（ユーザー発話に対象パスが含まれる場合、コレクション選択 AskUserQuestion を skip）も同様に適用される**。ユーザーが「box/teams/SAMPLE-カバルドン-...md を削除したい」のようにパスを明示した場合は、コレクション選択を飛ばして D-2 に進む。

### D-2: 関連 meta.json の検出

team-builder 由来の記事（`box/teams/` 配下のみ）には `<slug>.meta.json` が併置されている。**`box/blog/` 配下には `.meta.json` 併置無し**のため、対象が blog の場合は本ステップ自体を skip する:

```bash
SLUG=$(basename "$FILE" .md)
META="$(dirname "$FILE")/$SLUG.meta.json"
# box/teams/ 配下のみ検出対象
if [[ "$FILE" == *"/box/teams/"* ]] && [ -f "$META" ]; then
  echo "meta file exists: $META"
fi
```

### D-3: 最終確認

**削除対象一覧の提示方法**: AskUserQuestion の質問文本体には含めず、**質問直前の通常メッセージとして**別途提示する（質問文に長い一覧を詰めない）:

```
# 通常メッセージとして先に出力
削除対象:
  - box/teams/SAMPLE-カバルドン-build-2026-04-21.md
  - box/teams/SAMPLE-カバルドン-build-2026-04-21.meta.json
```

そのあと AskUserQuestion を出す。

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 上記ファイルを削除してよいですか？ | 削除確認 | キャンセル(desc: 削除しない), 削除する(desc: ファイルを削除。復元は git から可能) | false |

削除対象には `.md` と（存在すれば）`.meta.json` の両方を含める。

**user が「削除する」を選択した場合のみ削除を実行する。** `キャンセル` がデフォルト表示になるよう最初に配置する。**本ダイアログは「Skip 判定 共通ルール」で skip 禁止と定めた critical 質問に該当するため、絶対に skip しない**。

### D-4: 削除実行

```bash
rm -- "$FILE"
[ -f "$META" ] && rm -- "$META"
```

### D-5: 完了報告

```
削除しました: <files>
誤って削除してしまった場合、リポジトリルートで以下を実行すると復元できます:
  git checkout HEAD -- <file path>
```

続いて [Phase G: 反映確認](#phase-g-反映確認) に進む（`action = "delete"`, `slug = <slug>`）。

---

## Phase E: サイト設定変更

### E-1: 現状表示

`$SITE_CONFIG` を Read して現状を表示:

```
現在のサイト設定:
  site_name: <value>
  author: <value or null>
  enabled: <true | false>
```

### E-2: 変更項目選択

**AskUserQuestion**（1問, multiSelect）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どの項目を変更しますか？ | 項目 | site_name(desc: サイト名 ヘッダーや <title> に使用), author(desc: 著者名 フッターに表示), enabled(desc: false にするとデプロイが停止する) | true |

**multiSelect 挙動**: ユーザーが選んだ項目**のみ** E-3 で新値入力を求める。選ばれなかった項目は touch しない（Edit も発火しない）。選択が 0 件なら E-4 以降を skip し「変更項目がないため終了」でセッション終了。

### E-3: 新しい値の入力

E-2 で選ばれた項目それぞれについて新値を問う。選ばれなかった項目は本ステップを発火させない:

- `site_name`: 文字列（空禁止）
- `author`: 文字列 or null（「省略」で null に）
- `enabled`: `true` / `false` の2択 AskUserQuestion

### E-4: JSON 書き換え

Edit tool で `$SITE_CONFIG` のうち **E-2 で選ばれた行のみ**書き換える。Write tool で全体を書き直してもよいが、Edit の方が他キーを温存できるため優先する。

`author: null` の場合は `"author": null` と記述する（文字列 "null" ではなく JSON の null）。

### E-5: 完了報告

```
サイト設定を更新しました:
  - <field>: <before> → <after>

enabled: false にした場合は GitHub Actions のデプロイが skip されます。
```

続いて [Phase G: 反映確認](#phase-g-反映確認) に進む（`action = "site-config"`, `fields = <updated fields>`）。

---

## Phase F: 記事一覧表示

`$BLOG_DIR` と `$TEAMS_DIR` をスキャンし、各記事の `title` と `published` を Read で抽出してテーブル表示する。

```
=== box/blog ===
(記事なし)

=== box/teams ===
| ファイル                                | 軸           | 公開状態 |
| SAMPLE-カバルドン-build-2026-04-21.md   | カバルドン   | true     |
```

表示後、**AskUserQuestion** で「この記事を編集/切替/削除しますか？」と促し、YES ならそれぞれ Phase B/C/D に遷移する。NO ならスキル終了（Phase G は呼ばない — 一覧表示のみでは差分が無いため）。

---

## Phase H: メンバー画像メンテ

`box/teams/<slug>.md` の `members[]` に対応するポケモン画像 (`site/public/pokemons/<member.name>.{png,jpg}`) を**ユーザーがチャットに添付**する形で追加・差し替えする。MemberCard コンポーネントは `member.name` から自動的に画像を解決して右上に表示する。

ユーザーが手動で `site/public/pokemons/` にファイルを置く必要はない。**チャット添付されたファイルを agent (Claude) が `file` で検証して `cp` で保存する**。外部スクリプト・追加 runtime は不要。

### H-1: 対象 team 記事を選択

```bash
ls "$TEAMS_DIR"/*.md 2>/dev/null
```

複数ある場合は **AskUserQuestion** で 1 件を選ばせる (Phase B-2 と同様のパス選択)。発話に `box/teams/...md` が含まれていれば skip して直接対象記述を採用する。

### H-2: members 一覧の取得 + 画像有無の表示

選択された `<slug>.md` の frontmatter を Read で取得して `members:` 配列を抽出する。配列の各 `<name>` について以下を実行:

```bash
if [ -f "$REPO_ROOT/site/public/pokemons/${name}.png" ]; then
  echo "${name}  ✓ (png)"
elif [ -f "$REPO_ROOT/site/public/pokemons/${name}.jpg" ]; then
  echo "${name}  ✓ (jpg)"
else
  echo "${name}  ✗ (未配置)"
fi
```

通常メッセージとして一覧を表示する:

```
画像配置状況 (site/public/pokemons/):
  カバルドン  ✓ (png)
  マンムー    ✗ (未配置)
  アーマーガア ✗ (未配置)
  ...
```

### H-3: 添付対象を multiSelect で選択

**AskUserQuestion** (multiSelect):

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どのメンバーの画像を追加 / 差し替えますか？ | 対象 | members[] 各エントリ (各 desc に「未配置 / 既存あり (差し替え)」を表示) | true |

選択 0 件なら Phase H をここで終了し Phase G へ遷移する。

### H-4: 各メンバーの画像を添付・検証・保存

選択リストを順番に処理する。各メンバーごとに通常メッセージで以下を提示:

```
[1/3] カバルドン の画像を添付してください
  仕様: 340×340 以上の正方形、PNG または JPEG
  (skip する場合は「skip」と入力)
```

ユーザーが画像を添付すると、agent にローカルファイルパス (例: `/var/folders/.../tmp/Image-xxxxx.png`) が渡される。以下を**この順序で**実行する。

#### H-4-a: symlink を拒否

```bash
SRC="<添付ファイルの絶対パス>"
if [ -L "$SRC" ]; then
  echo "REJECT_SYMLINK"
fi
```

`REJECT_SYMLINK` が出力されたら通常メッセージで「symlink は受け付けません。実体ファイルを添付してください」と提示し再添付要求 (skip なら次のメンバー)。

#### H-4-b: 形式と寸法を `file` で取得

```bash
file "$SRC"
```

出力例:
- `…: PNG image data, 480 x 480, 8-bit/color RGB, non-interlaced`
- `…: JPEG image data, JFIF standard 1.01, … precision 8, 1024x768`
- `…: GIF image data, version 89a, …`

agent が出力をパースして以下を判定する (BSD/GNU 共通フォーマット):

| 項目 | 判定 |
|------|------|
| 形式 | `PNG image data` / `JPEG image data` 以外は reject (「対応形式は PNG / JPEG のみ」) |
| 寸法 | `<W> x <H>` または `<W>x<H>` を抽出。失敗したら **添付画像を agent が直接見て**おおよその寸法を判断 |
| 正方形 | `W !== H` なら reject (「正方形にしてください: 480×320 が添付されました」) |
| 最小サイズ | `W < 340` なら reject (「340×340 以上にしてください: 200×200 が添付されました」) |

reject の場合は理由を通常メッセージで提示し再添付要求。再添付なし (skip) なら次のメンバーへ。

#### H-4-c: 拡張子の決定 + 既存衝突確認

形式から拡張子を決める (`PNG` → `.png`、`JPEG` → `.jpg`)。保存先パスを組み立て:

```bash
DEST="$REPO_ROOT/site/public/pokemons/<member.name>.<ext>"
```

既存ファイルがある場合のみ **AskUserQuestion** (1問):

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | `<member.name>` の画像 (`<DEST>`) が既に存在します。どうしますか？ | 上書き | 上書きする(desc: 既存を消して新しい画像で置き換え), skip(desc: 既存を残す), 中断(desc: Phase H を中断して Phase G に遷移) | false |

- 「skip」→ 次のメンバーへ
- 「中断」→ 残メンバー処理せず Phase G へ
- 「上書きする」→ H-4-d へ進む

#### H-4-d: cp で保存

```bash
mkdir -p "$REPO_ROOT/site/public/pokemons"
cp "$SRC" "$DEST"
```

成功なら通常メッセージで「✓ <member.name>.<ext> を保存しました (<W>×<H>)」と報告し、次のメンバーへ。

### H-5: 完了報告

全メンバー処理後、まとめを通常メッセージで出力:

```
画像メンテ完了:
  ✓ カバルドン.png 保存
  ✓ マンムー.png 保存
  - アーマーガア skip (再添付なし)

差分は site/public/pokemons/ 配下に作成されています。
続けて Phase G (反映確認) に遷移します。
```

直後に**自動で Phase G へ遷移**する (確認 AskUserQuestion は挟まない)。Phase G-1 の `git status --short -- box/ site/public/pokemons/` で `?? site/public/pokemons/カバルドン.png` などが検出される。

---

## Phase I: 構築記事 本文編集

`box/teams/<slug>.md` と同名の `.meta.json` のペアに対する本文編集を提供する。4 種類のサブ操作 (**構築コンセプト** / **ダメージ計算 追加・削除** / **ポケモンメモ** / **選出やりなおし**) をサポート。

### 背景・設計原則

- team-builder が生成する構築記事は `.md` と `.meta.json` のペア構造。**site の team ページ (`site/src/pages/teams/[...slug].astro`) は `.md` 本文を描画せず、`.meta.json` の構造化データを Astro コンポーネント (MemberCard / DamageCalcTable / MatchupPlans 等) に流し込んで描画する**。つまり site ページの見た目を司るのは `.meta.json` 側 (title / description / tags など frontmatter は `.md` から読む)。
- 一方 `.md` 本文は GitHub などで raw 閲覧したときに人間が読む用に同じ内容が書き出されている。`.meta.json` と一致するように同期を保つのが望ましい。
- Phase I は **meta.json (SSoT) を更新しつつ、同期のため md 本文の対応箇所も Edit で書き換える**。両方を更新することで site 表示と raw 閲覧の整合を取る。
- **frontmatter (title / description / tags / published / edited など) は一切触らない**。これらは Phase C の守備範囲。
- `pkdx write teams --force` による md 再生成は **使わない**。再生成は frontmatter を既定値で上書きしてしまい、Phase C で付けた title / description / tags / `edited: true` を失うため。

対象は `box/teams/*.md` のみ。`box/blog/*.md` には meta.json が併置されないため Phase I では扱わない (blog 記事の本文編集はユーザー自身がエディタで直接編集する)。

### Phase I 共通 skip ルール

Phase I の AskUserQuestion は、上部「Skip 判定 共通ルール」(L22–30) に加えて次の Phase I 固有 skip 判定が適用される。全て「skip した事実と想定応答を通常メッセージで開示」必須。

1. **I-1 の対象ファイル選択**: 発話に以下のいずれかが含まれれば skip して採用ファイルを確定する:
   - 完全パス `box/teams/<slug>.md` または絶対パス相当
   - slug 文字列 (例: `SAMPLE-カバルドン-build-2026-04-21`)
   - **slug の部分文字列で `find "$TEAMS_DIR" -name "*<部分文字列>*.md"` が 1 件に収束する場合** (例: `SAMPLE-カバルドン`)
   
   2 件以上にヒットした場合は skip せず AskUserQuestion を出す。

2. **I-2 の編集項目選択 (multiSelect)**: 発話で明示された項目が 1 個以上ある場合は skip して発話項目のみを採用する。発話内容との対応付けキーワード:
   - 「コンセプト」「概念」「狙い」→ 構築コンセプト
   - 「ダメ計 追加」「damage_calcs 追加」「計算を足す」→ ダメージ計算 追加
   - 「ダメ計 削除」「ダメ計 消す」「ダメ計 整理」「重複削除」→ ダメージ計算 削除
   - 「メモ」「役割」「role」→ ポケモンメモ
   - 「選出」「表選出」「裏選出」「選出やりなおし」→ 選出やりなおし
   
   発話から項目が 1 つも推定できない場合のみ AskUserQuestion を発火。

3. **I-5-2 の削除対象 index 選択**: 発話に index 列 (「1, 3, 5」「index 0 と 4」など) が含まれていれば skip して該当 index を採用する。発話の index が **1-indexed** か **0-indexed** かはユーザーに確認 (AskUserQuestion Other)。ただし発話文脈から明らかな場合 (SKILL の出力一覧 `[0]..[N]` を参照していると読める) は 0-indexed で確定し通常メッセージで開示。

4. **I-6-2 / I-7-3 のメンバー・note 選択**: 発話にメンバー名列・note 本文が含まれていれば skip。

5. **I-7-2 の選出操作 (multiSelect)**: 発話から操作 (表書換 / 裏書換 / 表 null / 裏 null) が推定できる場合 skip。**「書き換える」と「未設定にする」が同一対象で同時に解釈可能な場合は「書き換える」を優先**する (未設定にしてから書き換えるのと最終状態が同じで、かつ意図推定として書き換えが自然)。

### meta.json の updated_at 更新規則

Phase I の jq 更新では、該当フィールド (concept / members[i].role / damage_calcs / primary_selection / alternate_selection) を書き換えると同時に `.updated_at` フィールドも **必ず** `$(date +%Y-%m-%d)` で更新する。writer 側の meta.json と挙動を揃えるため。

具体例 (I-3-3 の jq に統合):

```bash
NOW=$(date +%Y-%m-%d)
tmp=$(mktemp)
jq --arg v "$NEW_CONCEPT" --arg ts "$NOW" '.concept = $v | .updated_at = $ts' "$META" > "$tmp" && mv "$tmp" "$META"
```

I-5-3 / I-6-4 / I-7-4 の全 jq テンプレートにも同様に `.updated_at = $ts` を追加する。

### I-1: 対象 team 記事を選択

前述「Phase I 共通 skip ルール」1 の条件に合致すれば skip して発話のファイルを採用する。

合致しない場合は候補を列挙:

```bash
find "$TEAMS_DIR" -maxdepth 1 -name '*.md' ! -name 'TEMPLATE*' | sort
```

- 1 件のみ → 自動選択 (通常メッセージで「対象を <file> と判定して続行します」と開示)
- 複数件 → **AskUserQuestion** (1問) で 1 件選ばせる (Phase B-2 と同様のバッチ方式)

選択後 meta 併置を確認:

```bash
SLUG=$(basename "$FILE" .md)
META="$(dirname "$FILE")/$SLUG.meta.json"
if [ ! -f "$META" ]; then
  echo "NO_META"
fi
```

`NO_META` が出力された場合、通常メッセージで以下を提示して skill 終了 (Phase G に遷移しない):

```
<$FILE> は team-builder 由来ではありません (meta.json なし)。
Phase I は meta.json のある構築記事専用です。frontmatter だけ編集したい場合は Phase C をご利用ください。
```

### I-2: 編集項目を選択 (multiSelect)

**AskUserQuestion** (1問, multiSelect):

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どの項目を編集しますか？ (複数選択可) | 項目 | 構築コンセプト(desc: concept 本文), ダメージ計算 追加(desc: /calc / pkdx damage --attach-team への案内), ダメージ計算 削除(desc: 既存の damage_calcs を除去), ポケモンメモ(desc: members[i].role の役割・型名メモ), 選出やりなおし(desc: 表選出 / 裏選出 の再入力) | true |

選択 0 件 → Phase G へそのまま遷移 (通常メッセージで「編集項目なしで終了」)。
選択 1 件以上 → 選んだ順 (I-3 → I-4 → I-5 → I-6 → I-7) で処理。

### I-3: 構築コンセプト編集

#### I-3-1: 現状取得・提示

```bash
CUR_CONCEPT=$(jq -r '.concept // ""' "$META")
```

通常メッセージで提示:

```
現在の構築コンセプト:
  <CUR_CONCEPT if non-empty, else "(未設定)">
```

#### I-3-2: 新値入力

**AskUserQuestion** (1問):

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 新しい構築コンセプトは？ | コンセプト | Otherで入力(desc: 新しい本文を直接書く), 削除(desc: コンセプト章ごと消す), スキップ(desc: この項目は編集しない) |

(multiSelect=false)

- スキップ → 次項目へ
- 削除 → `NEW_CONCEPT=""`
- Other → ユーザー入力全文を `NEW_CONCEPT` に格納 (改行は半角スペース 1 個に正規化、目安 600 文字以内)

#### I-3-3: meta.json 更新

```bash
NOW=$(date +%Y-%m-%d)
tmp=$(mktemp)
jq --arg v "$NEW_CONCEPT" --arg ts "$NOW" '.concept = $v | .updated_at = $ts' "$META" > "$tmp" && mv "$tmp" "$META"
```

`.updated_at` は前掲「meta.json の updated_at 更新規則」節に従い必ず同時更新する。

#### I-3-4: md 本文の同期

現 md を Read し、以下 4 ケースで処理 (Edit tool を使用):

writer (`src/writer/teams.mbt` `build_team_document`) の空行保証:
- 各 `## <見出し>` の**前後**に空行が 1 本ずつ入る
- concept 本体は 1 段落 (Paragraph) で出力される (改行は writer 側で半角スペース化されている)
- よって md 内の concept セクションは必ず `## 構築コンセプト\n\n<OLD>\n\n## チーム` のパターンで出現する (次章は常に `## チーム`)

この保証を前提に、Edit の old_string / new_string は **`## 構築コンセプト\n\n<OLD>\n\n` までを含める** (末尾の空行 1 本を含む、次章 `## チーム` は含めない) 形で exact-match する。これで writer と手編集の間で空行数がブレても unique hit する。

| 旧 concept | 新 concept | old_string | new_string |
|-----------|-----------|-----------|-----------|
| 非空 | 非空 | `## 構築コンセプト\n\n<OLD>\n\n` | `## 構築コンセプト\n\n<NEW>\n\n` |
| 非空 | 空 | `## 構築コンセプト\n\n<OLD>\n\n` | `` (空文字に置換 = セクション削除) |
| 空 | 非空 | `## フォーマット\n\n<フォーマット箇条書き全体>\n\n` の末尾 (直後に挿入) | `## フォーマット\n\n<同じ箇条書き>\n\n## 構築コンセプト\n\n<NEW>\n\n` |
| 空 | 空 | no-op | no-op |

Edit tool は exact-match。旧 concept を meta.json から正しく取得しているので、`## 構築コンセプト\n\n<CUR_CONCEPT>\n\n` が md 内で一意にヒットするはず。ヒットしなかった場合は通常メッセージで以下を警告し md 更新を skip (meta.json のみ更新済み):

```
⚠ md 本文の "## 構築コンセプト" 節が想定形式と異なるため同期を skip しました。
  site 描画は meta.json から行われるため問題ありませんが、raw md と meta.json が
  ずれた状態になっています。必要に応じて手動で md を修正してください。
```

### I-4: ダメージ計算 追加

新規 damage_calcs の追加は `pkdx damage --attach-team` が一次インターフェース。blog skill 内で追加フォームを重複実装すると入力項目 (特性 / 持ち物 / 天候 / ランク / atk-stat / def-stat / def-hp / テラスタル 等) が calc スキル並みに膨らむため、**calc スキルへ委譲**する。

通常メッセージで以下の案内を表示:

```
ダメージ計算の追加は /calc または pkdx damage --attach-team で行えます。
/calc スキルなら対話的に特性・持ち物・天候・ランク補正まで指定できます。

手動コマンド例:
  ./bin/pkdx damage <攻撃側ポケモン> <防御側ポケモン> <技名> \
    --atk-stat <A or C 実数値> --def-stat <B or D 実数値> --def-hp <H 実数値> \
    --attach-team $META \
    --attach-title "<記事に出る表示タイトル>" \
    --attach-note "<任意の解説文>"

補足: damage_calcs は site 側で meta.json から DamageCalcTable コンポーネントが
自動描画するため、md 本文への追記は不要 (Phase I-4 の同期対象外)。
追記後に改めて blog skill を起動すれば Phase G で差分を確認して push できます。
```

通常メッセージ出力のみで、本項目では追加の AskUserQuestion は発火しない。次の選択項目へ進む。

### I-5: ダメージ計算 削除

#### I-5-1: 現状列挙

```bash
COUNT=$(jq -r '.damage_calcs // [] | length' "$META")
```

`COUNT == 0` なら通常メッセージで「damage_calcs が登録されていません」と通知し、次項目へ。

`COUNT >= 1` なら全エントリを通常メッセージで先に提示 (AskUserQuestion の質問文本体には含めない):

```bash
jq -r '.damage_calcs // [] | to_entries[] |
  "[\(.key)] \(.value.title // "(no title)")  \(.value.min_percent | floor)%-\(.value.max_percent | floor)%"' "$META"
```

出力例:

```
削除候補:
  [0] じしん vs H32無補正ドドゲザン  52%-61%
  [1] じしん vs H32無補正メガゲンガー  91%-107%
  [2] メガゲンガー シャドーボール (C32補正あり) → カバルドン  49%-58%
  ...
```

#### I-5-2: 選択

**前提 skip チェック**: 前述「Phase I 共通 skip ルール」3 に該当するか確認。発話に index 列が含まれていれば AskUserQuestion を skip して idxs を直接採用する。

AskUserQuestion を出す場合は **母集団件数による分岐** を守る:

- **`COUNT <= 12`**: 全エントリを選択肢に並べる multiSelect
- **`COUNT > 12`**: 選択肢は **「Other でカンマ区切り index 入力」1 個のみ** 並べる。I-5-1 の一覧は既に通常メッセージで提示されているので、ユーザーはそれを参照して Other に index 列を入力する

**AskUserQuestion** (1問, multiSelect):

| 条件 | 質問 | header | オプション | multiSelect |
|-----|------|--------|-----------|-------------|
| `COUNT <= 12` | どの計算を削除しますか？ | 削除対象 | 上記 index 付きラベルを全件展開 | true |
| `COUNT > 12` | 削除したい計算の index をカンマ区切りで入力してください (例: `0,3,5,9`) | 削除対象 | Otherで入力(desc: 上の一覧の `[N]` の N を参照) | false |

**index 解釈**: SKILL の一覧は `[0]..[N-1]` の 0-indexed で出力される。ユーザー入力の index も 0-indexed として解釈する (通常メッセージで「0-indexed (最初の要素は 0) として扱います」と明示してから受け取る)。

選択 0 件 / Other 空入力 → 次項目へ (削除なし)。

#### I-5-3: meta.json 更新

`idxs` をカンマ区切り index 文字列 (例: `0,3,5`) として組み立てた上で:

```bash
NOW=$(date +%Y-%m-%d)
tmp=$(mktemp)
jq --argjson idxs "[$idxs]" --arg ts "$NOW" '
  .damage_calcs =
    ([(.damage_calcs // []) | to_entries[] | select(.key as $k | $idxs | index($k) | not) | .value])
  | .updated_at = $ts
' "$META" > "$tmp" && mv "$tmp" "$META"
```

#### I-5-4: md 本文の同期

**不要**。`build_team_document` は damage_calcs セクションを md に出力しないため、md 側には元々該当章が存在しない。

### I-6: ポケモンメモ (members[i].role) 編集

#### I-6-1: 現状列挙

```bash
jq -r '.members // [] | to_entries[] | "[\(.key)] \(.value.name)  role: \((.value.role // "") | if . == "" then "(未設定)" else . end)"' "$META"
```

出力例を通常メッセージで提示:

```
メンバー一覧:
  [0] カバルドン    role: 先発要因。ステロを撒いて吠えるだけ...
  [1] マンムー      role: フルアタなのに耐久調整しているマンムー...
  [2] アーマーガア  role: (未設定)
  ...
```

#### I-6-2: 対象メンバー選択

**AskUserQuestion** (1問, multiSelect=false):

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | どのメンバーのメモを編集しますか？ | メンバー | 各 [i] ポケモン名 を選択肢に展開 (members は最大 6 体なので全件並べる) |

選ばれた index を `IDX`、ポケモン名を `NAME` とする。

#### I-6-3: 新値入力

現在の role を再提示してから **AskUserQuestion** (1問):

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 新しい <NAME> のメモは？ | メモ | Otherで入力(desc: 役割・型名・採用理由・対面時の注意点など 目安200字以内), 削除(desc: role を空にする), スキップ(desc: この項目は編集しない) |

- スキップ → I-6 終了、次項目へ
- 削除 → `NEW_ROLE=""`
- Other → 入力を `NEW_ROLE` に格納 (改行は半角スペース 1 個に正規化)

#### I-6-4: meta.json 更新

```bash
NOW=$(date +%Y-%m-%d)
tmp=$(mktemp)
jq --argjson i "$IDX" --arg v "$NEW_ROLE" --arg ts "$NOW" \
   '.members[$i].role = $v | .updated_at = $ts' "$META" > "$tmp" && mv "$tmp" "$META"
```

#### I-6-5: md 本文の同期

`## チーム` セクションの表の対象行を Edit で書き換える。

writer 仕様 (`src/writer/teams.mbt` `build_members_table`) では列は `# | ポケモン | タイプ | 種族値 | 特性 | 持ち物 | メモ` の 7 列。行は `| <IDX+1> | <NAME> | <types> | <bs> | <ability> | <item> | <OLD_ROLE> |` 形式。

アプローチ:

1. md 全体を Read
2. `| <IDX+1> | <NAME> |` で始まる行を探し、その行全体 (`\n` で区切られる 1 行) を取得
3. 末尾 ` <OLD_ROLE> |` を ` <NEW_ROLE> |` に書き換え
4. Edit tool で旧行を新行に置換 (行全体を old_string に入れると unique なので置換失敗しにくい)

注意事項:

- role に `|` や改行が含まれる場合、writer 側の出力もそのまま入れている可能性があるためパターン不一致になり得る。その場合は通常メッセージで同期 skip を警告 (I-3-4 と同じ文言)。
- `NEW_ROLE` に `|` を入れるとテーブル構造を壊す。入力時に検出したら「`|` は含められません。別の表現に書き換えてください」と再入力を促す。

### I-7: 選出やりなおし (primary_selection / alternate_selection)

#### I-7-1: 現状表示

```bash
jq -r '
  "現在の表選出:\n" +
  "  members: \((.primary_selection.members // []) | join(" + ") | if . == "" then "(未設定)" else . end)\n" +
  "  note: \(.primary_selection.note // "(なし)")\n" +
  "現在の裏選出:\n" +
  "  members: \((.alternate_selection.members // []) | join(" + ") | if . == "" then "(未設定)" else . end)\n" +
  "  note: \(.alternate_selection.note // "(なし)")"
' "$META"
```

通常メッセージで出力。

#### I-7-2: 編集操作選択

**AskUserQuestion** (1問, multiSelect):

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 選出をどう変更しますか？ | 選出操作 | 表選出を書き換える, 裏選出を書き換える, 表選出を未設定にする, 裏選出を未設定にする | true |

**排他性規則**: 「表選出を書き換える」と「表選出を未設定にする」が同時に選ばれた場合は**「書き換える」を優先**する (未設定の結果に対して値を書き込むのと最終状態が同じで、書き換え意図の方が発話として自然)。裏選出も同様。通常メッセージで「表選出: 『書き換える』と『未設定にする』が同時選択されたため、書き換え側を採用します」と開示する。

選択 0 件 → I-7 終了、次項目へ。

#### I-7-3: 「書き換える」が選ばれたスロットごとの入力

対象 (primary / alternate) について順に処理。

a. **メンバー選択** — 6 体を選択肢として並べる multiSelect:

   ```bash
   MEMBERS=$(jq -r '.members[].name' "$META")
   FORMAT=$(jq -r '.battle_format // "singles"' "$META")
   ```

   **AskUserQuestion** (1問, multiSelect):

   | # | 質問 | header | オプション |
   |---|------|--------|-----------|
   | 1 | <表選出 or 裏選出> に入れるメンバーを選んでください (<FORMAT> 推奨: singles=3体 / doubles=4体) | メンバー | 各 `<NAME>` を選択肢に展開 | 

   multiSelect=true。選択結果を配列 `SELECTED[]` に格納。

b. **note 入力** — **AskUserQuestion** (1問):

   | # | 質問 | header | オプション |
   |---|------|--------|-----------|
   | 1 | <表選出 or 裏選出> の立ち回り・狙いを記述してください | note | Otherで入力(desc: 想定ターン・出す条件・技選択の意図 目安300字以内), 空のまま(desc: note なしで登録) |

   multiSelect=false。空 or Other で入力を `NOTE` に格納。

#### I-7-4: meta.json 更新

「書き換える」対象:

```bash
NOW=$(date +%Y-%m-%d)
tmp=$(mktemp)
# key は primary_selection or alternate_selection
jq --arg key "$KEY" --argjson ms "$SELECTED_JSON" --arg note "$NOTE" --arg ts "$NOW" \
   '.[$key] = {members: $ms, note: $note} | .updated_at = $ts' "$META" > "$tmp" && mv "$tmp" "$META"
```

`SELECTED_JSON` は `SELECTED[]` を bash で以下のように JSON 配列に serialize する:

```bash
SELECTED_JSON=$(jq -cn --args '$ARGS.positional' -- "${SELECTED[@]}")
# 例: SELECTED=("カバルドン" "マンムー" "イダイトウ") → ["カバルドン","マンムー","イダイトウ"]
```

空配列 `SELECTED=()` の場合は「書き換える」対象の成立条件を満たさないので I-7-3 で警告し書き換えをスキップする。

「未設定にする」対象:

```bash
NOW=$(date +%Y-%m-%d)
tmp=$(mktemp)
jq --arg key "$KEY" --arg ts "$NOW" 'del(.[$key]) | .updated_at = $ts' "$META" > "$tmp" && mv "$tmp" "$META"
```

(`del` で削除することで、content.config 側の optional 扱いに戻す。null を入れても FE の `?? 0` フォールバックで動くが、既存構築の慣習 (Phase 8 で未設定なら emit しない) に合わせる。)

#### I-7-5: md 本文の同期

`## 選出パターン` セクション全体を再生成して置換する。

1. 現 md から `## 選出パターン` セクションを抽出: `\n## 選出パターン\n` から次の `\n## ` または EOF までの範囲。
2. meta.json の最新値 (primary_selection / alternate_selection) から writer 相当の markdown を組み立てる:

   ```
   
   ## 選出パターン
   
   ### 表選出
   
   * 選出: A + B + C
   
   <primary.note>
   
   ### 裏選出
   
   * 選出: D + E + F
   
   <alternate.note>
   ```

   - `primary_selection` が未設定 (削除 or members 空) → `### 表選出` ブロックを出さない
   - `alternate_selection` が未設定 → `### 裏選出` ブロックを出さない
   - 両方未設定 → `## 選出パターン` セクション自体を削除 (旧範囲を空文字に)
   - note が空文字 → note 段落 (空行+note+空行) を出さない (writer 仕様と同じ。`build_selection_plan_block` は `note.length() > 0` のときだけ Paragraph を push)

3. Edit tool で旧範囲を新 markdown に置換。

#### I-7-6: エラーケース

md 本文に `## 選出パターン` 節が無く、新たに追加する場合は **ファイル末尾** (最後の非空行の後) に追記する (writer の構造上も選出パターンは末尾章)。

### I-8: 完了報告

編集項目それぞれの before → after を箇条書きで通常メッセージ出力する。**空値表記規則**:

- concept / role が空文字に変更されたとき → `"(削除)"`
- concept / role が空文字から非空に変更されたとき → `"(未設定)"` → `"<新値 40字>..."`
- primary_selection / alternate_selection が del されたとき → `(未設定)`
- damage_calcs 削除後の件数は常に `<before 件数> 件 → <after 件数> 件 (<削除数> 件削除)`

テンプレート:

```
<slug>.md / <slug>.meta.json を更新しました:
  - 構築コンセプト: "<before 40字>..." → "<after 40字>..."       # 両方非空の場合
  - 構築コンセプト: "(未設定)" → "<after 40字>..."                # 新規作成
  - 構築コンセプト: "<before 40字>..." → "(削除)"                 # 削除
  - ポケモンメモ (<member.name>): "<before 40字>..." → "<after 40字>..."
  - 選出やりなおし: 表選出 = A + B + C / 裏選出 = (未設定)        # del された側は "(未設定)"
  - ダメージ計算削除: 28 件 → 17 件 (11 件削除)                     # 削除数も併記
```

変更がなかった項目は箇条書きに含めない (編集操作がスキップされた場合など)。

直後に **自動で Phase G へ遷移** する (確認 AskUserQuestion は挟まない)。Phase G の `action = "edit-body"`, `slug = <slug>` として commit メッセージを生成する。

---

## Phase G: 反映確認（共通サブフロー）

Phase A-E / Phase H の完了時に必ず呼び出す。**編集結果をサイトに反映するかをユーザーへ確認し、承諾された場合のみ git add + commit + push を行う。**

### G-1: 差分確認

```bash
cd "$REPO_ROOT"
git status --short -- box/ site/public/pokemons/
```

**差分判定ルール**: 上記コマンドの stdout が 1 行以上返れば「差分あり」とする。以下の prefix すべてを差分として扱う:

- `??` 未追跡（新規作成 / Phase A）
- ` M` / `M ` 変更（編集 / Phase C / Phase E）
- ` D` / `D ` 削除（Phase D）
- ` A` 追加 stage 済（通常は未使用だが念のため）

変更が無ければ（stdout が空）以下を出力して Phase G を即終了する:

```
変更はありませんでした（編集前と同じ状態です）。
```

差分ありの場合、**次の G-2 AskUserQuestion を出す直前に、通常メッセージとして**変更ファイル一覧（`git status --short` の出力そのまま）を提示する。AskUserQuestion の質問文本体にはファイル一覧を埋め込まない（質問文が長くなると UI で読めない）。

```
# 通常メッセージとして先に出力
変更ファイル:
 ?? box/blog/astro-upgrade-notes.md
```

### G-2: 反映可否の確認

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 変更をサイトへ反映しますか？ push するとリモートへ送信され、GitHub Actions がサイトを再ビルドします。 | 反映 | 反映しない(desc: ローカルに変更を残して終了。あとで手動 push 可能), 反映する(desc: git commit + push を実行してサイトに反映) | false |

「反映しない」を選ばれた場合は以下の案内を出す（`<files>` は G-1 で列挙した実ファイルパスに展開する）:

```
ローカルに変更を残しました。あとで手動で反映する場合は:
  git add -- <files>
  git commit -m "<任意のメッセージ>"
  git push
```

**案内出力後、skill セッション自体を終了する**（Phase 0 に戻らない / 追加操作を促さない）。ユーザーが再度 blog skill を起動すれば新規セッションとして扱う。

### G-3: ブランチ・リモート確認

「反映する」を選択された場合:

```bash
BRANCH=$(git branch --show-current)
REMOTE_URL=$(git remote get-url origin)
```

ユーザーに以下を**必ず提示**し、最終承諾を得る（CLAUDE.md のPR安全規則に準拠）:

```
送信先の確認:
  remote: <REMOTE_URL>
  branch: <BRANCH>
```

`BRANCH == main` かつ `REMOTE_URL` が fork（`origin` が upstream でない）でない場合は**追加の確認**を行う:

**AskUserQuestion**（条件付き、1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | `<REMOTE_URL> (branch: <BRANCH>)` へ push します。よろしいですか？ | 送信先 | キャンセル(desc: push しない), 送信する(desc: この送信先で実行) | false |

「キャンセル」の場合はここで終了し、G-2 の「反映しない」と同じ案内を出す。

### G-4: commit メッセージ生成

Phase A-E の `action` に応じて既定の commit メッセージを組み立てる。CLAUDE.md の「プライベート情報を commit メッセージに含めない」ルールを守り、汎用的な技術用語のみを使う:

| action | commit メッセージ例 |
|--------|--------------------|
| create | `content(blog): add <slug>` |
| toggle | `content: set <slug> published=<new_state>`（teams の場合 `content(team):`） |
| edit   | `content: update frontmatter for <slug>` |
| edit-body | `content(team): update body for <slug>` |
| delete | `content: remove <slug>` |
| site-config | `chore(site): update <fields>` |

ユーザーにメッセージ案を提示し、変更不要か確認:

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | commit メッセージは `<generated>` で良いですか？ | メッセージ | このまま使う(desc: 生成されたメッセージで commit), Otherで入力(desc: カスタムメッセージを指定) | false |

### G-5: commit + push 実行

```bash
# 変更ファイルだけ stage（add -A を使わず安全に）
git add -- <変更ファイルパス一覧>

git commit -m "$(cat <<'EOF'
<generated or user-provided message>
EOF
)"

git push origin "$BRANCH"
```

**注意事項:**

- `git add -A` / `git add .` は**使わない**。CLAUDE.md の安全ルールに準拠し、対象ファイルを個別に指定する。
- `--no-verify` / `--force` / `--force-with-lease` は**使わない**。Hook エラーが起きたら内容を提示してユーザーに判断を仰ぐ。
- pre-commit hook に失敗した場合は amend せず、原因を修正して新規 commit を作る。

### G-6: 完了報告

push 成功後、以下を提示する:

```
push しました: <branch> → <remote>
1-2 分ほどで https://<owner>.github.io/<repo>/ に反映されます。
Actions の進行状況は次のコマンドで確認できます:
  gh run list --limit 3
```

`box/site.config.json` の `enabled: false` を設定している場合は追加で:

```
⚠ enabled: false のため GitHub Actions はサイトのデプロイを skip します。
  再開するには Phase E で enabled: true に戻してください。
```

### G-7: dev server の停止確認

Phase 0-4 で dev server を起動済み (`DEV_PREVIEW_ID` がある) 場合のみ実行する。未起動なら本ステップを skip。`DEV_PREVIEW_ID` を覚え忘れていた場合は `mcp__Claude_Preview__preview_list` で `name: "site"` の `serverId` を解決する。

**AskUserQuestion** (1問):

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | dev server を停止しますか？ (起動したまま残すと、別ターミナルから引き続き http://localhost:4321/pkdx/ で確認できます) | dev停止 | 停止する(default, desc: preview_start で起動した dev server を停止する), 残しておく(desc: 起動したまま skill を終了。手動で停止する場合は preview_list / preview_stop) | false |

「停止する」を選ばれた場合、`mcp__Claude_Preview__preview_stop` ツールを `serverId: "<DEV_PREVIEW_ID>"` で呼び出して停止する (preview_start で起動したサーバーは preview_stop で確実に止まる。`kill` での PID 取得は不安定なので使わない)。停止後に通常メッセージで「✓ dev server を停止しました」と報告。

「残しておく」を選ばれた場合は通常メッセージで案内:

```
dev server は起動したままです: http://localhost:4321/pkdx/
停止する場合は以下のいずれか:
  - mcp__Claude_Preview__preview_list で serverId を確認して preview_stop を呼ぶ
  - Claude Code の /bashes コマンドで該当 shell を kill
  - lsof -nP -iTCP:4321 -sTCP:LISTEN で PID を確認して kill <PID>
```

`DEV_PREVIEW_ID` をクリアして skill 終了。

---

## エラーハンドリング

| 状況 | 対応 |
|------|------|
| `$REPO_ROOT/box` が無い | 「`./setup.sh` を先に実行してください」と案内して終了 |
| `$SITE_CONFIG` が壊れた JSON | Read 後にパースエラーを伝え、ユーザーに手動修正を依頼 |
| 対象 `.md` が見つからない | ディレクトリ内の md を列挙して再選択を促す |
| frontmatter が YAML として不正 | 該当行を提示し、手動修正を依頼（自動修復はしない） |

## 注意事項

- **git push は Phase G でユーザー YES 承認を得たときだけ実行する**。無確認 push は禁止。
- `git add -A` / `git add .` は使わない（対象ファイル個別指定のみ）
- `--force` / `--force-with-lease` / `--no-verify` は使わない
- ファイル削除は取り返しがつきにくいため、確認ダイアログで `キャンセル` をデフォルトに置く
- `box/blog/TEMPLATE.md.example` は管理対象外（一覧からも除外）
- team-builder が生成した `.meta.json` は Astro の content collection からは読まれないが、関連ファイルとして削除時に対応する
- commit メッセージにプライベート情報（組織名・個人名・内部ツール名等）を含めない（CLAUDE.md 準拠）
