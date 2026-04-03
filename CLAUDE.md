# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ポケモン対戦構築支援リポジトリ。Claude Codeのスキル群として動作し、以下の2機能を提供する。

- **pokemon-builder** — 6体構築・3体選出のシングルバトル向けチームビルドを対話的にガイド
- **damage-calc** — Lv50ダメージ計算（特性・持ち物・天候・フィールド・テラスタル・急所対応、16段階乱数テーブル出力）

CLIツール `pkdx` (MoonBit native binary) が pokedex.db への全クエリとダメージ計算を担う。

## Setup

```bash
./setup.sh    # submodule初期化 + pokedex.db生成 + pkdxバイナリDL を一括実行
```

手動で行う場合:
```bash
git submodule update --init           # pokedex サブモジュール取得
cd pokedex && ruby tools/import_db.rb # pokedex.db 生成（Ruby必要）
# pkdx バイナリは bin/pkdx 経由で GitHub Releases から自動DL
```

`pokedex.db` と `pkdx` バイナリが存在しないとスキルは動作しない。

## Architecture

```
pkdx/                     # MoonBit CLI ツール (native binary)
  moon.mod.json            # モジュール定義
  src/
    main/                  # エントリポイント + SQLite C-FFI
      main.mbt, cwrap.c, sqlite3.c
    db/                    # DB接続 + クエリ関数
    damage/                # Gen9ダメージ計算エンジン (4096丸め, 16段階乱数)
    types/                 # 18x18タイプ相性テーブル (ハードコード)
    model/                 # Pokemon, Move, DamageCalcInput/Result 型
    cli/                   # サブコマンドパーサー + JSON/テーブルフォーマッタ

bin/
  pkdx                    # Unix用ラッパースクリプト (ローカルビルド優先)
  pkdx.cmd                # Windows用ラッパー

.claude/skills/
  pokemon-builder/
    SKILL.md              # 構築スキル本体（Phase 0-8 の対話フロー定義）
    references/
      format_rules.md     # メカニクス定義（メガ/ダイマ/Z/テラスタル）
      stat_thresholds.md  # 種族値ベンチマーク・素早さティア
  damage-calc/
    SKILL.md              # ダメージ計算スキル本体

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
```

## Skill Flow

### pokemon-builder

Phase 0（初期化）→ Phase 8（レポート出力）の順に進行。各フェーズ終了時に `=== Team State ===` ブロックを出力し、コンテキスト圧縮後も状態を復元可能にする。最終成果物は `{軸ポケモン名}-build-{YYYY-MM-DD}.md` として出力される。

### damage-calc

攻撃側・防御側・技名を受け取り、`pkdx damage` で計算を実行。16段階の乱数テーブル・確定数・割合をJSON出力する。オプションで特性・持ち物・天候・フィールド・テラスタル・急所を指定可能。
