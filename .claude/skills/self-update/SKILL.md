---
name: self-update
description: "pkdxを最新版に更新する。構築・育成データを保護しながらスキルやCLIツールを安全にアップデートする。更新したい・アップデート・最新にしたい時に使用。"
allowed-tools: Bash, AskUserQuestion
---

# Self-Update

最新変更を安全に取り込むスキル。フォーク運用・clone運用どちらにも対応する。ユーザーは非技術者を想定し、git関連の技術用語はコミュニケーションではできる限り使わない。

## パス定義

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../..
```

## Phase 0: 前提確認

### 0-1: 運用モデル判定

```bash
cd $REPO_ROOT && git remote -v
```

以下のパターンで判定:

**A. フォーク運用** — `origin` がユーザーのフォーク、`upstream` が本家
- `upstream` が存在する → そのまま続行
- `origin` が canonical `pkdxtools/pkdx` でない + `upstream` がない → `setup.sh` を実行して自動設定:
  ```bash
  cd $REPO_ROOT && ./setup.sh
  ```
  （`setup.sh` が upstream remote を自動追加する）

**B. clone運用** — `origin` が canonical `pkdxtools/pkdx` 本体で、`upstream` が存在しない
- `origin` から直接 pull する（`upstream` の代わりに `origin` を使う）
- 以降のフェーズで `upstream` と記載された箇所を `origin` に読み替える

判定後、使用するリモート名を `$UPDATE_REMOTE` に設定:
```bash
# フォーク運用
UPDATE_REMOTE="upstream"
# clone運用
UPDATE_REMOTE="origin"
```

判定ロジックの参考スニペット (`origin` URL → 運用モデル):
```bash
ORIGIN_URL="$(git -C $REPO_ROOT remote get-url origin 2>/dev/null || true)"
if echo "$ORIGIN_URL" | grep -qE "[:/]pkdxtools/pkdx(\.git)?/?$"; then
  MODE="clone"   # canonical upstream を直接 clone している
else
  MODE="fork"    # ユーザーの fork
fi
```

clone運用の場合、以下のメッセージを表示:

```
ℹ GitHubアカウントを作成してフォークに移行すると、構築・育成データの
  バージョン管理（変更履歴の保存・復元・クラウドバックアップ）が利用できます。
  詳しくは README.md の「セットアップ方法」を参照してください。
```

### 0-2: default branch 検出

```bash
UPSTREAM_BRANCH=$(git symbolic-ref refs/remotes/$UPDATE_REMOTE/HEAD 2>/dev/null | sed "s|refs/remotes/${UPDATE_REMOTE}/||")
if [ -z "$UPSTREAM_BRANCH" ]; then
  UPSTREAM_BRANCH="main"
fi
```

### 0-3: ワーキングツリーの状態確認

```bash
cd $REPO_ROOT && git status --porcelain
```

未コミットの変更がある場合（tracked + untracked）:

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 未保存の変更があります。バックアップして続行しますか？ | 確認 | はい(desc: 変更をバックアップして続行), いいえ(desc: 中断) |

「いいえ」→ スキル終了。
「はい」→:

```bash
cd $REPO_ROOT && git branch backup/pre-update-$(date +%Y%m%d-%H%M%S)
cd $REPO_ROOT && git stash push -u -m "self-update: auto-stash $(date +%Y%m%d-%H%M%S)"
```

> **メモ**: Phase 1 はソース更新とバイナリ更新の双方を含む。差分の有無に関係なく Phase 1-4（バイナリ更新）まで必ず到達する設計。

## Phase 1: Fetch & Merge

```bash
cd $REPO_ROOT && git fetch $UPDATE_REMOTE
```

`git fetch` が**失敗**した場合、以下のフォールバック判定を行う:

### 1-F: Web環境フォールバック（フォーク運用 + fetch失敗時）

**条件**（いずれか満たせば発火）:

1. `$UPDATE_REMOTE` が `upstream` （フォーク運用）かつ `git fetch upstream` が失敗（exit code ≠ 0）
2. フォーク運用判定だが `upstream` remote 自体が存在せず、`./setup.sh` を流しても
   web 環境では `git remote add upstream` 直後の fetch が proxy にブロックされる
3. Clone 判定として `git fetch origin` を試したが、`origin` 側がすでに最新まで
   進んでいるはずなのに Phase 1-5 で `version_drift=true` が残る場合（origin
   が canonical `pkdxtools/pkdx` でなく legacy fork に向いている疑いがあるため、
   Sync fork 経由で取り込むほうが確実）

この状況は主に Claude Code on the web 環境で発生する。web環境では git proxy がセッション対象リポジトリ（origin）のみにアクセスを制限するため、upstream への fetch がブロックされる。

**手順**:

1. ユーザーに状況を説明し、GitHub Web UIでの操作を案内する:

```
⚠ この環境では upstream リポジトリへの直接アクセスが制限されています。
  GitHub の Web UI から最新版を取り込む必要があります。
```

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | GitHub Web UIでフォークを同期してください。\n\n手順:\n1. ブラウザで自分のフォークリポジトリページを開く\n2. 「Sync fork」ボタンをクリック\n3. 「Update branch」をクリック\n4. 完了したら「完了」を選択してください | フォーク同期 | 完了(desc: Sync forkを実行しました), 中断(desc: 更新を中断します) |

「中断」→ Phase 2（Stash復元）へスキップしてスキル終了。

「完了」→ origin から pull して最新を取り込む:

```bash
cd $REPO_ROOT && git pull origin $UPSTREAM_BRANCH
```

pull 成功後、Phase 1-1（差分確認）をスキップし **Phase 1-4（バイナリ更新）** へ進む。
pull 失敗時は通常のコンフリクト処理（Phase 1-3）と同様に処理する。

---

`git fetch` が**成功**した場合、以下の通常フローを続行する:

### 1-1: 差分確認

```bash
cd $REPO_ROOT && git log --oneline HEAD..$UPDATE_REMOTE/$UPSTREAM_BRANCH | head -20
```

差分がない場合は「すでに最新です」と表示し、**Phase 1-4（バイナリ更新）** へ進む。バイナリ更新はソース差分の有無に関係なく必ず実行する（GitHub Releases のアセット差し替え、ローカルバイナリ欠損、version drift 残留などをカバーするため）。

### 1-2: マージ実行

```bash
cd $REPO_ROOT && git merge $UPDATE_REMOTE/$UPSTREAM_BRANCH --no-edit
```

### 1-3: コンフリクト処理

マージが失敗した場合:

```bash
cd $REPO_ROOT && git diff --name-only --diff-filter=U
```

コンフリクトファイルを一覧表示し:

- `box/` 内のコンフリクト → ユーザー側(ours)を優先 (構築・育成・ブログ記事・サイト設定はユーザー所有):
  ```bash
  git checkout --ours box/<path> && git add box/<path>
  ```
  対象例: `box/teams/**`, `box/pokemons/**`, `box/blog/**`, `box/site.config.json`

- `.claude/skills/` 内のコンフリクト → 更新元(theirs)を優先:
  ```bash
  git checkout --theirs .claude/skills/<path> && git add .claude/skills/<path>
  ```

- `site/**` のコンフリクト → 更新元(theirs)を優先 (Astro サイト本体は upstream 管理):
  ```bash
  git checkout --theirs site/<path> && git add site/<path>
  ```
  例外: `site/public/CNAME` はユーザーがカスタムドメイン用に追加する想定なので、存在すれば ours を保持する。

- `.github/workflows/**` のコンフリクト → 更新元(theirs)を優先 (CI/CD は upstream 管理):
  ```bash
  git checkout --theirs .github/workflows/<path> && git add .github/workflows/<path>
  ```

- `box/blog/TEMPLATE.md.example` のコンフリクト → 更新元(theirs)を優先 (ひな形は upstream が更新):
  ```bash
  git checkout --theirs box/blog/TEMPLATE.md.example && git add box/blog/TEMPLATE.md.example
  ```

- その他のコンフリクト → ユーザーに判断を求める:

**AskUserQuestion**（コンフリクトファイルごと）:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | \<ファイルパス\> の変更が衝突しています。どちらを残しますか？ | 衝突解決 | ours(desc: 自分の変更を残す), theirs(desc: 更新元の変更を採用) |

全コンフリクト解決後:
```bash
cd $REPO_ROOT && git commit --no-edit
```

### 1-4: バイナリ更新（GitHub Releases ダウンロード固定）

**ソース差分の有無に関係なく必ず実行する**。GitHub Releases のアセット差し替え、ローカルバイナリ欠損、`moon.mod.json` との version drift 残留などをまとめてカバーするため、ユーザーへの選択肢提示は行わない。`./setup.sh` が以下を一括で行う:

- 古いバイナリキャッシュのクリア
- GitHub Releases から最新 pkdx バイナリをダウンロード
- pokedex / champout submodule の同期
- `pkdx_patch/{009..012}/data.json` 再生成 → `champions.db` 再構築 → `pkdx migrate` 実行
- `box/**/*.meta.json` の schema マイグレーション（`<path>.bak` を 1 回だけ作成、既存 `.bak` は上書きしない）

```bash
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pkdx"
rm -f "$CACHE_DIR"/pkdx-*
cd $REPO_ROOT && ./setup.sh
```

`pkdx migrate` は bookkeeping を持たない seed-script モデルで、全マイグレーションが冪等（UPDATE / INSERT OR REPLACE / existence-check / 自己所有テーブルの DELETE→再投入）として実装されているため、再適用しても DB は data.json の状態へ収束する。

ローカル開発でビルド済みバイナリを使いたい場合は、`./setup.sh` を流した後に手動で `moon build --target native --release src/main` を打つ。

### 1-5: 動作確認

```bash
$REPO_ROOT/bin/pkdx version
$REPO_ROOT/bin/pkdx context --json | grep -o '"version_drift":[^,]*'
```

`"version_drift":false` が出ればバイナリと repo の version が一致している。

`true` の場合は、バイナリ側だけが新しい version を持ち、repo の `moon.mod.json` が
古い状態で取り残されている。これを放置すると SessionStart hook が毎セッション
`version_drift_message` を注入し続けるため、以下の **drift 復旧フロー** を順に試す。

#### 1-5-R: drift 復旧フロー

1. **upstream 不在ならまず追加** — `setup.sh` が再分類して `upstream` を追加
   する。すでに追加済みでも冪等:
   ```bash
   cd $REPO_ROOT && ./setup.sh
   ```
   ※ `setup.sh` の Step 0 が `origin` を判定し、canonical `pkdxtools/pkdx` 以外なら
   `upstream` を `pkdxtools/pkdx` に向けて自動追加する。

2. **未取り込みコミットを fetch + merge** — `moon.mod.json` の version bump
   コミットが upstream/origin に存在するのに HEAD に取り込まれていないケース:
   ```bash
   # $UPDATE_REMOTE は Phase 0-1 で設定済み (fork=upstream, clone=origin)
   cd $REPO_ROOT && git fetch $UPDATE_REMOTE
   cd $REPO_ROOT && git log --oneline HEAD..$UPDATE_REMOTE/$UPSTREAM_BRANCH -- moon.mod.json | head -5
   cd $REPO_ROOT && git merge $UPDATE_REMOTE/$UPSTREAM_BRANCH --no-edit
   ```
   コンフリクトが出たら **Phase 1-3** の手順に従って解決する。
   `git fetch` が失敗する web 環境では **Phase 1-F** に戻り、GitHub Web UI の
   Sync fork → `git pull origin $UPSTREAM_BRANCH` の経路で取り込む。

3. **再度 drift を確認** — 取り込みに成功したら再判定:
   ```bash
   $REPO_ROOT/bin/pkdx context --json | grep -o '"version_drift":[^,]*'
   ```
   `false` になれば復旧完了。

4. **まだ `true` のとき** — 以下の可能性をユーザーに報告し、状況に応じた
   選択肢を提示する:
   - GitHub Releases にまだ最新版が反映されていない（upstream `moon.mod.json` の
     値より古いバイナリしか配布されていない）→ 数分待って `./setup.sh` を再実行
   - `./setup.sh` の DL が失敗した（CDN/network 不調）→ `./setup.sh` を再実行
   - ローカルにビルド済みバイナリがあり、それが古い → `moon build --target native --release src/main`
     でリビルド、または `_build/native/{release,debug}/build/src/main/main.exe` を削除して
     `./setup.sh` を再実行（リリースバイナリへフォールバックされる）

SessionStart hook が同じ判定を毎回エージェントに注入するので、復旧できないまま
スキルを終了するときは、Phase 3 の完了レポートで `version_drift: true (要対処)`
と明示し、上記のどのケースに該当しそうかを併記する。

## Phase 2: Stash復元

Phase 0でstashした場合:

```bash
cd $REPO_ROOT && git stash pop
```

stash popでコンフリクトが発生した場合:
- `box/` 内 → stash側を優先（ユーザーの作業中データ）
- その他 → AskUserQuestionでユーザーに判断を求める

## Phase 3: 完了レポート

```
=== pkdxバージョンアップ完了 ===
マージ元: $UPDATE_REMOTE/$UPSTREAM_BRANCH
取り込み方法: <fetch & merge / fetch (差分なし) / Sync fork経由>
新規コミット数: <N>
コンフリクト解決: <あり/なし>
pkdx tools: 更新済み (GitHub Releases)
version_drift: <false / true (要対処)>
バックアップ: <復元済み/なし>
```

「取り込み方法」のラベル選択指針:
- `fetch & merge`: ソース差分があり `git merge` を実行したケース
- `fetch (差分なし)`: 差分ゼロでバイナリ更新のみを行ったケース
- `Sync fork経由`: Phase 1-F で GitHub Web UI の Sync fork → `git pull` を踏んだケース
