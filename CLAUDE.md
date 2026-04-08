# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ポケモン対戦構築支援リポジトリ。Claude Codeのスキル群として動作し、以下の機能を提供する。

- **team-builder** — 6体構築のシングル（3体選出）/ダブル（4体選出）対戦チームビルドを対話的にガイド
- **calc** — Lv50ダメージ計算（特性・持ち物・天候・フィールド・テラスタル・急所対応、16段階乱数テーブル出力）
- **breed** — ポケモン育成シミュレーション（性格・努力値・実数値の対話的計算、.mdファイル出力）
- **self-update** — フォーク先でupstreamの最新変更を安全にマージ

CLIツール `pkdx` (MoonBit native binary) が pokedex.db への全クエリ、ダメージ計算、実数値計算・逆算、および構築・育成データのマークダウン出力を担う。

**運用モデル**: fork-based。ユーザーはリポジトリをフォークし、`box/` 配下に構築・育成データを蓄積。`self-update` スキルでupstreamに追従する。

## Setup

```bash
./setup.sh    # remote設定 + submodule初期化 + pokedex.db生成 + pkdxバイナリDL + box/ディレクトリ作成 を一括実行
```

`setup.sh` はフォーク/クローンを自動判定し、フォークの場合は upstream remote を自動設定する。

### セットアップ方法

#### A. GitHubアカウントがある場合（推奨）

1. GitHub で `ushironoko/pkdx` をフォーク
2. `git clone https://github.com/<user>/pkdx.git && cd pkdx && ./setup.sh`
3. upstream remote は `setup.sh` が自動設定（手動不要）
4. 出力は `box/` 配下に保存。`self-update` スキルでupstreamに追従

クラウドバックアップ・PC間共有・変更履歴の保存と復元が利用可能。

#### B. GitHubアカウントがない場合

1. `git clone https://github.com/ushironoko/pkdx.git && cd pkdx && ./setup.sh`
2. 全機能が利用可能。データは手元のPCにのみ保存される
3. あとからGitHubアカウントを作成してフォークに移行可能

`pokedex.db` と `pkdx` バイナリが存在しないとスキルは動作しない。

## Architecture

```
pkdx/                     # MoonBit CLI ツール (native binary)
  moon.mod.json            # モジュール定義 (deps: moonbitlang/x, mizchi/markdown)
  src/
    main/                  # エントリポイント + SQLite C-FFI + File I/O FFI
      main.mbt, cwrap.c, sqlite3.c, io_ffi.mbt
    db/                    # DB接続 + クエリ関数
    damage/                # Gen9ダメージ計算エンジン (4096丸め, 16段階乱数)
    types/                 # 18x18タイプ相性テーブル (ハードコード)
    model/                 # Pokemon, Move, DamageCalcInput/Result 型
    cli/                   # サブコマンドパーサー + JSON/テーブルフォーマッタ
    writer/                # JSON→マークダウンCST変換 (mizchi/markdown使用)
      validate.mbt          # JSONスキーマ検証
      teams.mbt             # TeamReport JSON→CST
      pokemon.mbt           # PokemonBuild JSON→CST

bin/
  pkdx                    # Unix用ラッパースクリプト (ローカルビルド優先)
  pkdx.cmd                # Windows用ラッパー

box/                      # ユーザーデータ出力先（フォーク先でgit管理）
  teams/                   # team-builder出力 (.md)
  pokemons/                # breed出力 (.md)
  cache/                   # skill キャッシュ (.json, gitignored / team-builder・breed が使用)

.claude/skills/
  team-builder/
    SKILL.md              # 構築スキル本体（Phase 0-8 の対話フロー定義）
    references/
      format_rules.md     # メカニクス定義（メガ/ダイマ/Z/テラスタル）
      stat_thresholds.md  # 種族値ベンチマーク・素早さティア
  calc/
    SKILL.md              # ダメージ計算スキル本体
  breed/
    SKILL.md              # 育成シミュレーションスキル本体（Phase 0-8 の対話フロー定義）
  self-update/
    SKILL.md              # upstream追従スキル

pokedex/                  # git submodule (towakey/pokedex)
  pokedex.db              # SQLiteデータベース（生成が必要）
  er.md                   # DB ER図
```

## Database Notes

- `pokedex.db` のテーブル群は `globalNo` + フォーム識別カラム（`form`, `region`, `mega_evolution`, `gigantamax`）で結合する
- 通常フォームの取得には `COALESCE(form, '') = ''` 等の条件が必要（NULL/空文字が混在）
- `local_pokedex_*` テーブルの `version` は小文字スネーク（`scarlet_violet`）
- `local_waza*` / `local_pokedex_waza*` テーブルの `version` は Mixed Case（`Scarlet_Violet`）— pkdx 内部で自動変換
- タイプ名は日本語（`ほのお`, `みず` 等）
- `globalNo` はゼロ埋め4桁（`0445`）— pkdx は入力を自動正規化

## CLI Usage (pkdx)

`POKEDEX_DB` 環境変数またはリポジトリルートからの自動解決で DB パスを決定する。

```bash
# ポケモン検索（日本語名 or 英語名）
bin/pkdx query "ガブリアス" --version scarlet_violet --format json

# 技一覧取得（ポケモン名 or globalNo）
bin/pkdx moves "ガブリアス" --version scarlet_violet --format json

# タイプ検索（タイプ名は日本語、最低素早さ指定可）
bin/pkdx search --type "ドラゴン" --min-speed 100 --version scarlet_violet

# ダメージ計算（特性・持ち物・天候等はオプション）
bin/pkdx damage "ガブリアス" "サーフゴー" "じしん" \
  --atk-ability "すながくれ" --weather "すなあらし" --format json

# タイプ相性
bin/pkdx type-chart "ほのお" "くさ"

# 攻撃範囲カバー率
bin/pkdx coverage "ほのお,みず,くさ"

# 実数値計算（種族値+努力値+性格→Lv50実数値）
bin/pkdx stat-calc "ガブリアス" --ev "0,252,0,0,4,252" --nature "ようき" --format json
bin/pkdx stat-calc "ガブリアス" --ev "0,252,0,0,4,252" --nature-up S --nature-down C

# 逆算: 実数値→必要な種族値を逆引き（単一値モード）
bin/pkdx stat-reverse 130 --iv 31 --ev 252 --nature up
# 逆算: ポケモン名+実数値6種→努力値を逆引き（ポケモンモード）
bin/pkdx stat-reverse "ガブリアス" --stats "183,200,115,90,106,169" --iv 31

# キャッシュ雛形生成（skillがPhase 0で呼び出す。JSONスキーマ由来のプレースホルダを出力）
bin/pkdx init-cache team     > box/cache/team_cache_xxx.json
bin/pkdx init-cache pokemon  > box/cache/breed_cache_xxx.json

# チーム構築レポート保存（skillキャッシュJSON→box/teams/にmd出力）
cat box/cache/team_cache_ガブリアス_*.json | bin/pkdx write teams --date 2026-04-06 --axis "ガブリアス"

# 育成データ保存（skillキャッシュJSON→box/pokemons/にmd出力）
cat box/cache/breed_cache_ガブリアス_*.json | bin/pkdx write pokemon --name "ガブリアス" --file "スカーフ型"

# 耐久指数最適化（H/B/D の EV を最適化、HP条件・火力比重・top-N 対応）
bin/pkdx hbd "ガブリアス" --nature ようき
bin/pkdx hbd "ガブリアス" --nature ようき --fixed-ev "_,0,_,0,_,252" --hp-snap leftovers
bin/pkdx hbd "カビゴン" --nature ずぶとい --phys-weight 2 --spec-weight 1 --top 5
```

## Reference documents

ドメイン理論・設計背景・数式導出など、コードからは読み取れない知識は `.claude/skills/*/references/` に置き、エージェントが質問に自力で回答できるようにする。

- **`.claude/skills/team-builder/references/bulk_theory.md`** — 耐久指数 HBD/(B+D) の導出、H=B+D 則、greedy 勾配法アルゴリズム、11n調整との関係、HP条件の根拠。`hbd` サブコマンドや努力値配分に関する質問はここを第一参照。
- **`.claude/skills/team-builder/references/format_rules.md`** — メガ/ダイマ/Z/テラスタル等のメカニクス定義
- **`.claude/skills/team-builder/references/stat_thresholds.md`** — 種族値ベンチマーク・素早さティア
- **`.claude/skills/team-builder/references/items_abilities.md`** — 道具・特性の考察用データ

## Skill Flow

### team-builder

Phase 0（初期化）→ Phase 8（レポート出力）の順に進行。各フェーズ終了時に `=== Team State ===` ブロックを出力し、コンテキスト圧縮後も状態を復元可能にする。Phase 8で構造化JSONを `pkdx write teams` に渡し、決定的なマークダウンを `box/teams/{軸ポケモン名}-build-{YYYY-MM-DD}.md` として出力。

### calc

攻撃側・防御側・技名を受け取り、`pkdx damage` で計算を実行。16段階の乱数テーブル・確定数・割合をJSON出力する。オプションで特性・持ち物・天候・フィールド・テラスタル・急所を指定可能。

### breed

ポケモン1体の育成データを対話的に構築。Phase 0（初期化）→ Phase 8（保存）の順に進行し、各フェーズで実数値をフィードバック。Phase 8で構造化JSONを `pkdx write pokemon` に渡し、決定的なマークダウンを `box/pokemons/<name>/<filename>.md` に保存。`--atk-stat`/`--def-stat`/`--def-hp` を通じてcalcスキルと連携。

### self-update

upstreamの最新変更をフォーク先に安全にマージする。`box/` 内のユーザーデータを保護しつつ、スキルファイルとCLIバイナリを更新する。
