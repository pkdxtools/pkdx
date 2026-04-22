---
name: blog
description: "サイト記事・設定のメンテナンス。新規ブログ記事の作成、記事の公開/非公開切替、タイトルや説明文の編集、記事削除、サイト名などの設定変更を対話的に行う。最後にユーザー確認のうえ git push でサイトに反映させる。記事管理・ブログ管理・サイト名変更・公開切替などの際に使用。"
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

各 Phase の完了報告（例: A-5, B-5, C-5, D-5, E-5）直後の Phase G への遷移は**自動**で行う。間に確認の AskUserQuestion は挟まない。ユーザーは完了報告テキストを見て、Phase G の差分提示へと続けて移行する。

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
| 1 | どの操作？ | 操作 | 公開/非公開切替(desc: Phase B), フロントマター編集(desc: Phase C), 削除(desc: Phase D) | false |

「サイト設定 or 記事一覧」を選んだ場合、続く AskUserQuestion:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どちら？ | 操作 | サイト設定変更(desc: Phase E), 記事一覧表示(desc: Phase F) | false |

Other での直接キーワード判定は以下:
- 「新規」「作成」「書く」→ Phase A
- 「公開」「下書き」「非公開」→ Phase B
- 「編集」「タイトル変更」→ Phase C
- 「削除」「消す」→ Phase D
- 「設定」「サイト名」「author」→ Phase E（2段目 skip 可）
- 「一覧」「リスト」→ Phase F（2段目 skip 可）

選択結果に応じて該当 Phase へ遷移する。

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

続いて [Phase G: 反映確認](#phase-g-反映確認) に進む（`action = "create"`, `slug = <slug>`）。

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
[1] エンニュート-build-2026-04-21.md  published: true
[2] カバルドン-build-2026-04-21.md    published: true
[3] my-first-post.md                    published: false
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

Phase B-1 / B-2 と同じフローで対象記事を選ぶ。**B-1 の skip 判定ルール（ユーザー発話に対象パスが含まれる場合、コレクション選択 AskUserQuestion を skip）も同様に適用される**。ユーザーが「box/teams/カバルドン-...md を削除したい」のようにパスを明示した場合は、コレクション選択を飛ばして D-2 に進む。

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
  - box/teams/カバルドン-build-2026-04-21.md
  - box/teams/カバルドン-build-2026-04-21.meta.json
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
| ファイル           | タイトル             | 公開状態 |
| my-first-post.md  | はじめまして         | true     |

=== box/teams ===
| ファイル                           | 軸           | 公開状態 |
| カバルドン-build-2026-04-21.md    | カバルドン   | true     |
| エンニュート-build-2026-04-21.md  | エンニュート | true     |
```

表示後、**AskUserQuestion** で「この記事を編集/切替/削除しますか？」と促し、YES ならそれぞれ Phase B/C/D に遷移する。NO ならスキル終了（Phase G は呼ばない — 一覧表示のみでは差分が無いため）。

---

## Phase G: 反映確認（共通サブフロー）

Phase A-E の完了時に必ず呼び出す。**編集結果をサイトに反映するかをユーザーへ確認し、承諾された場合のみ git add + commit + push を行う。**

### G-1: 差分確認

```bash
cd "$REPO_ROOT"
git status --short -- box/
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
