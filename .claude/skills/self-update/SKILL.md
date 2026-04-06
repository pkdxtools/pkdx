---
name: self-update
description: "upstreamの最新変更を安全に取り込む。box/内のユーザーデータを保護しながらスキル・CLIを更新する。"
allowed-tools: Bash, AskUserQuestion
---

# Self-Update

フォーク先でupstreamの最新変更を安全にマージするスキル。

## パス定義

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../..
```

## Phase 0: 前提確認

### 0-1: upstreamリモート確認

```bash
cd $REPO_ROOT && git remote -v
```

`upstream` リモートが存在しない場合:

**AskUserQuestion**（1問）:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | upstreamのリポジトリURLは？ | upstream URL | Other(desc: 例: https://github.com/ushironoko/pkdx.git) |

```bash
git remote add upstream "<URL>"
```

### 0-2: default branch 検出

```bash
UPSTREAM_BRANCH=$(git symbolic-ref refs/remotes/upstream/HEAD 2>/dev/null | sed 's|refs/remotes/upstream/||')
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
| 1 | 未コミットの変更があります。stashして続行しますか？ | 確認 | はい(desc: 変更をstashして続行), いいえ(desc: 中断) |

「いいえ」→ スキル終了。
「はい」→:

```bash
cd $REPO_ROOT && git branch backup/pre-update-$(date +%Y%m%d-%H%M%S)
cd $REPO_ROOT && git stash push -u -m "self-update: auto-stash $(date +%Y%m%d-%H%M%S)"
```

## Phase 1: Fetch & Merge

```bash
cd $REPO_ROOT && git fetch upstream
```

### 1-1: 差分確認

```bash
cd $REPO_ROOT && git log --oneline HEAD..upstream/$UPSTREAM_BRANCH | head -20
```

差分がない場合は「すでに最新です」と表示してPhase 3へスキップ。

### 1-2: マージ実行

```bash
cd $REPO_ROOT && git merge upstream/$UPSTREAM_BRANCH --no-edit
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

- `.claude/skills/` 内のコンフリクト → upstream側(theirs)を優先:
  ```bash
  git checkout --theirs .claude/skills/<path> && git add .claude/skills/<path>
  ```

- その他のコンフリクト → ユーザーに判断を求める:

**AskUserQuestion**（コンフリクトファイルごと）:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | \<ファイルパス\> のコンフリクトをどう解決しますか？ | コンフリクト解決 | ours(desc: 自分の変更を優先), theirs(desc: upstreamを優先) |

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
| 1 | pkdxバイナリの更新方法は？ | バイナリ更新 | build(desc: ローカルでビルド/推奨・sourceと一致), download(desc: GitHub Releasesからダウンロード/タグ更新後のみ推奨), skip(desc: スキップ) |

- **build** (推奨):
  ```bash
  cd $REPO_ROOT/pkdx && moon build --target native
  ```

- **download**:
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
=== Self-Update Complete ===
マージ元: upstream/$UPSTREAM_BRANCH
新規コミット数: <N>
コンフリクト解決: <あり/なし>
バイナリ: <更新済み/スキップ>
stash: <復元済み/なし>
```
