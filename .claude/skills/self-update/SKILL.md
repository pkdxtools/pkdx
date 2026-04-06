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
- `origin` が `ushironoko/pkdx` でない + `upstream` がない → `setup.sh` を実行して自動設定:
  ```bash
  cd $REPO_ROOT && ./setup.sh
  ```
  （`setup.sh` が upstream remote を自動追加する）

**B. clone運用** — `origin` が `ushironoko/pkdx` で、`upstream` が存在しない
- `origin` から直接 pull する（`upstream` の代わりに `origin` を使う）
- 以降のフェーズで `upstream` と記載された箇所を `origin` に読み替える

判定後、使用するリモート名を `$UPDATE_REMOTE` に設定:
```bash
# フォーク運用
UPDATE_REMOTE="upstream"
# clone運用
UPDATE_REMOTE="origin"
```

clone運用の場合、以下のメッセージを表示:

```
ℹ GitHubアカウントを作成してフォークに移行すると、構築・育成データの
  バージョン管理（変更履歴の保存・復元・クラウドバックアップ）が利用できます。
  詳しくは README.md の「セットアップ方法」を参照してください。
```

### 0-2: default branch 検出

```bash
UPSTREAM_BRANCH=$(git symbolic-ref refs/remotes/$UPDATE_REMOTE/HEAD 2>/dev/null | sed 's|refs/remotes/$UPDATE_REMOTE/||')
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

## Phase 1: Fetch & Merge

```bash
cd $REPO_ROOT && git fetch $UPDATE_REMOTE
```

### 1-1: 差分確認

```bash
cd $REPO_ROOT && git log --oneline HEAD..$UPDATE_REMOTE/$UPSTREAM_BRANCH | head -20
```

差分がない場合は「すでに最新です」と表示してPhase 3へスキップ。

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

- `box/` 内のコンフリクト → ユーザー側(ours)を優先:
  ```bash
  git checkout --ours box/<path> && git add box/<path>
  ```

- `.claude/skills/` 内のコンフリクト → 更新元(theirs)を優先:
  ```bash
  git checkout --theirs .claude/skills/<path> && git add .claude/skills/<path>
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

## Phase 2: バイナリ更新

### 2-1: キャッシュクリア

```bash
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pkdx"
rm -f "$CACHE_DIR"/pkdx-*
```

### 2-2: リビルドまたはダウンロード

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | pkdx cliの更新方法は？ | pkdxアップデート | download(desc: GitHub Releasesから最新版ダウンロード/推奨), build(desc: ローカルでビルド), skip(desc: スキップ) |

- **build** :
  ```bash
  cd $REPO_ROOT/pkdx && moon build --target native
  ```

- **download** (推奨) :
  ```bash
  cd $REPO_ROOT && ./setup.sh
  ```

- **skip**: 何もしない

### 2-3: 動作確認

```bash
$REPO_ROOT/bin/pkdx version
```

## Phase 3: Stash復元

Phase 0でstashした場合:

```bash
cd $REPO_ROOT && git stash pop
```

stash popでコンフリクトが発生した場合:
- `box/` 内 → stash側を優先（ユーザーの作業中データ）
- その他 → AskUserQuestionでユーザーに判断を求める

## Phase 4: 完了レポート

```
=== pkdxバージョンアップ完了 ===
マージ元: $UPDATE_REMOTE/$UPSTREAM_BRANCH
新規コミット数: <N>
コンフリクト解決: <あり/なし>
pkdx tools: <更新済み/スキップ>
バックアップ: <復元済み/なし>
```
