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

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | どの操作を行いますか？ | 操作 | 新規ブログ記事作成(desc: box/blog/ に新しい記事ファイルを作る), 記事の公開/非公開切替(desc: published フラグを反転する), 記事のフロントマター編集(desc: タイトル/説明文/タグを変更), 記事削除(desc: 記事ファイルを削除する) | false |

上記で選ばれなかった操作が必要な場合は次の AskUserQuestion で:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 追加の操作 | 操作 | サイト設定変更(desc: site_name / author / enabled), 記事一覧を表示(desc: 全記事の公開状態を一覧) | false |

Other で直接「新規」「編集」「一覧」「設定」等のキーワードでも判定可。

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

Write tool で `$DEST` を以下の形式で生成する:

```markdown
---
title: "<ユーザー入力タイトル>"
date: <TODAY>
description: "<description または空>"
tags: [<tags または 空配列>]
published: <true | false>
---

# <ユーザー入力タイトル>

ここから本文を書いてください。
```

description / tags が空の場合はそのキー自体を省略してよい（schema で optional）。

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

**AskUserQuestion**（1問）:

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

Phase B-1 / B-2 と同じフローで対象記事を選ぶ。

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

Phase B-1 / B-2 と同じフローで対象記事を選ぶ。

### D-2: 関連 meta.json の検出

team-builder 由来の記事には `<slug>.meta.json` が併置されている:

```bash
SLUG=$(basename "$FILE" .md)
META="$(dirname "$FILE")/$SLUG.meta.json"
[ -f "$META" ] && echo "meta file exists"
```

### D-3: 最終確認

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 本当に削除しますか？ <削除対象ファイル一覧> | 削除確認 | キャンセル(desc: 削除しない), 削除する(desc: ファイルを削除。復元は git から可能) | false |

削除対象には `.md` と（存在すれば）`.meta.json` の両方を含める。

**user が「削除する」を選択した場合のみ削除を実行する。** `キャンセル` がデフォルト表示になるよう最初に配置する。

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

### E-3: 新しい値の入力

- `site_name`: 文字列（空禁止）
- `author`: 文字列 or null（「省略」で null に）
- `enabled`: `true` / `false` の2択 AskUserQuestion

### E-4: JSON 書き換え

Edit tool で `$SITE_CONFIG` の対象行を書き換える。Write tool で全体を書き直してもよいが、Edit の方が他キーを温存できるため優先する。

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

変更が無ければ（たとえば B で同じ値に切り替えた等）Phase G を即終了する。

差分ありの場合はユーザーへ変更ファイル一覧を提示する。

### G-2: 反映可否の確認

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション | multiSelect |
|---|------|--------|-----------|-------------|
| 1 | 変更をサイトへ反映しますか？ push するとリモートへ送信され、GitHub Actions がサイトを再ビルドします。 | 反映 | 反映しない(desc: ローカルに変更を残して終了。あとで手動 push 可能), 反映する(desc: git commit + push を実行してサイトに反映) | false |

「反映しない」を選ばれた場合はここで終了する。以下の案内を出す:

```
ローカルに変更を残しました。あとで手動で反映する場合は:
  git add -- <files>
  git commit -m "<任意のメッセージ>"
  git push
```

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
