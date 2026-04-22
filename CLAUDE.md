# Project Overview

ポケモン対戦を支援する統合ツール。pkdx cliとワークフローを記述したAgent Skillによるハーネスで構成されている。

- **team-builder**: 6体構築のシングル（3体選出）/ダブル（4体選出）対戦チームビルドを対話的にガイド。取り込んだ構築を元に構築ブログの作成
- **calc**: Lv50ダメージ計算（特性・持ち物・天候・フィールド・テラスタル・急所対応、16段階乱数テーブル出力）
- **breed**: ポケモン育成シミュレーション（性格・努力値・実数値の対話的計算、.mdファイル出力）
- **nash**: 零和ナッシュ均衡ソルバー / 選出最適化（`pkdx select`） / メタ乖離分析（`pkdx meta-divergence`）
- **self-update**: フォーク先でupstreamの最新変更を安全にマージ
- **blog**: 構築ブログの管理

CLIツール `pkdx` (MoonBit native binary) が pokedex.db への全クエリ、ダメージ計算、実数値計算・逆算、および構築・育成データのマークダウン出力、ゲーム理論に基づいた選出最適化計算などを担う。

**運用モデル**: fork-based。ユーザーはリポジトリをフォークし、`box/` 配下に構築・育成データを蓄積。`self-update` スキルでupstreamに追従する。

## 求められる振る舞い

1. ユーザーの情報を未確認のままupstreamへ送信してはならない。必ずremoteを確認し、送信対象が合っているかユーザーへ確認すること。
2. 利用可能なポケモン、道具、技のプールを常にDBへ問い合わせ確認する。ユーザーが指定したフォーマット外の情報をフィードバックしてはならない
    例: `Champions M-A` レギュレーション選択中に、準伝説ポケモンやサーフゴーを案内してしまう（M-Aフォーマット外）
    例: `Champions M-A` レギュレーション選択中に、こだわりハチマキやとつげきチョッキを案内してしまう（M-Aフォーマット外）
    例: DBデータからわからない場合は、ユーザーに許可をもらってから `WebSearch` を実行して最新の情報を取得する
3. ダメージ計算に関しては必ず `pkdx damage` で計算してからフィードバックする。あなたが次に間違えやすい箇所
4. タイプ相性に関しては必ず `pkdx type-chart` で計算してからフィードバックする。あなたが最も間違える箇所

## Setup

各種ツールを実行する前に必ず setup.sh を実行すること。これによりDBの作成、マイグレーション適用、バイナリダウンロードが冪等実行される。
setup.sh実行前ではすべてのツールが利用不可。

```bash
./setup.sh    # remote設定 + submodule初期化 + pokedex.db生成 + pkdxバイナリDL + box/ディレクトリ作成 を一括実行
```

`setup.sh` はフォーク/クローンを自動判定し、フォークの場合は upstream remote を自動設定する。

### セットアップ方法

#### A. GitHubアカウントがある場合（推奨）

1. GitHub で `pkdxtools/pkdx` をフォーク
2. `git clone https://github.com/<user>/pkdx.git && cd pkdx && ./setup.sh`
3. upstream remote は `setup.sh` が自動設定（手動不要）
4. 出力は `box/` 配下に保存。`self-update` スキルでupstreamに追従

クラウドバックアップ・PC間共有・変更履歴の保存と復元が利用可能。

#### B. GitHubアカウントがない場合

1. `git clone https://github.com/pkdxtools/pkdx.git && cd pkdx && ./setup.sh`
2. 全機能が利用可能。データは手元のPCにのみ保存される
3. あとからGitHubアカウントを作成してフォークに移行可能

`pokedex.db` と `pkdx` バイナリが存在しないとスキルは動作しない。

## Architecture

```
pkdx/                     # MoonBit CLI ツール (native binary)
  moon.mod.json            # モジュール定義 (deps: moonbitlang/x, mizchi/markdown) — バージョンの SSoT
  src/
    main/                  # エントリポイント + SQLite C-FFI + File I/O FFI
      main.mbt, cwrap.c, sqlite3.c, io_ffi.mbt
      version.mbt           # 自動生成 (scripts/sync_version.sh → moon.mod.json から同期)
    db/                    # DB接続 + クエリ関数
    damage/                # Gen9ダメージ計算エンジン (4096丸め, 16段階乱数)
    types/                 # 18x18タイプ相性テーブル (ハードコード)
    model/                 # Pokemon, Move, DamageCalcInput/Result 型
    cli/                   # サブコマンドパーサー + JSON/テーブルフォーマッタ
    writer/                # JSON→マークダウンCST変換 (mizchi/markdown使用)
      validate.mbt          # JSONスキーマ検証
      teams.mbt             # TeamReport JSON→CST
      pokemon.mbt           # PokemonBuild JSON→CST
    nash/                  # 零和 Nash ソルバー (numbt/BLAS) — Layer 1
      matrix_game.mbt, simplex.mbt, solver.mbt, fictitious.mbt, divergence.mbt
    payoff/                # pkdx ドメイン変換 + nash CLI ハンドラ — Layer 2 + 3
      semantics.mbt         # TeamPayoffModel enum (SwitchingGame / ScreenedSwitchingGame)
      from_character.mbt    # monocycle (p, v) モデル (pkdx nash solve 用)
      damage_utils.mbt      # damage 共通ヘルパー (avg_damage / build_input_with_ranks)
      monte_carlo.mbt       # seeded RNG + ε-greedy helpers (team_monte_carlo から利用)
      team_monte_carlo.mbt  # team-level 3v3 MC rollout
      switching_game.mbt    # team-level extensive-form DP (+ αβ pruning)
      screened_switching_game.mbt  # MC screening → SwitchingGame refine パイプライン
      team_payoff.mbt       # 選出 (k-combination) ディスパッチ
      cli_nash.mbt, cli_select.mbt, cli_meta.mbt  # JSON/DOT ハンドラ
    migrate/               # pkdx_patch マイグレーションランナー
      runner.mbt            # pkdx_migrations 管理 + トランザクション + 順次適用
      migrations.mbt        # 登録配列 (001〜010)
      json_util.mbt         # Json アクセサ
      m001_mega_legendsza.mbt 〜 m010_move_meta_posthit.mbt

bin/
  pkdx                    # Unix用ラッパースクリプト (ローカルビルド優先)
  pkdx.cmd                # Windows用ラッパー

scripts/
  sync_version.sh          # moon.mod.json → version.mbt バージョン同期

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
  nash/
    SKILL.md              # Nash 均衡ソルバー / pkdx select / meta-divergence
    references/
      theory.md              # 零和 LP / Simplex / Fictitious play / MWU
      exploitability.md      # exploitability / NashConv / KL / L1
      payoff_semantics.md    # SwitchingGame / ScreenedSwitchingGame 仕様
  self-update/
    SKILL.md              # upstream追従スキル
  blog/
    SKILL.md              # site/配下のブログ情報を管理するスキル

pokedex/                  # git submodule (towakey/pokedex)
  pokedex.db              # SQLiteデータベース（生成が必要）
  er.md                   # DB ER図
site/
  src/                    # GitHub PagesへデプロイされるAstro製のブログ
```

## Database Notes

- `pokedex.db` のテーブル群は `globalNo` + フォーム識別カラム（`form`, `region`, `mega_evolution`, `gigantamax`）で結合する
- 通常フォームの取得には `COALESCE(form, '') = ''` 等の条件が必要（NULL/空文字が混在）
- `local_pokedex_*` テーブルの `version` は小文字スネーク（`scarlet_violet`）
- `local_waza*` / `local_pokedex_waza*` テーブルの `version` は Mixed Case（`Scarlet_Violet`）— pkdx 内部で自動変換
- タイプ名は日本語（`ほのお`, `みず` 等）
- `globalNo` はゼロ埋め4桁（`0445`）— pkdx は入力を自動正規化
- `pkdx_patch/NNN_name/data.json` にパッチデータを置き、マイグレーションロジックは `pkdx/src/migrate/mNNN_*.mbt` で実装する。`setup.sh` Step 3.5 が `pkdx migrate` を呼び出し、pokedex.db へ順次適用する。pkdx バイナリ内蔵 SQLite3 で完結するため Ruby / sqlite3 gem は不要（cc on the web 等のコンテナでも動作）。パッチは冪等（`pkdx_migrations` テーブルで適用済み管理）

## Champions SP (Stat Points) システム

**重要**: Champions (`--version champions`) では従来の EV/IV が**完全に廃止**され、SP に統一されている。従来作品の EV/IV の知識をそのまま適用してはならない。計算式: `HP = base + SP + 75`, `他 = floor((base + SP + 20) × Nature)`。各ステ最大 32、合計 66。従来の 508 EV 配分を SP で再現すると 1 ポイント余り、追加ステに振れる（SP の +1 優位）。CLI では `--ev` が SP として解釈され `--iv` は無視される。

**詳細は `.claude/skills/team-builder/references/champions_sp.md` を参照。** SP 計算式の導出、従来式との同値性証明、+1 優位の具体例、性格補正境界、HBD 最適化の差分、逆算アルゴリズムを記載。

## Version Management

バージョンは `pkdx/moon.mod.json` の `version` フィールドが SSoT。変更時:

```bash
# 1. moon.mod.json の version を編集
# 2. 同期スクリプトを実行
scripts/sync_version.sh
# 3. moon.mod.json と version.mbt をコミット
```

## Reference documents

ドメイン理論・設計背景・数式導出など、コードからは読み取れない知識は `.claude/skills/*/references/` に置き、エージェントが質問に自力で回答できるようにする。システム全体のパス / データフロー俯瞰は `.claude/architecture.md` に Mermaid 図で整理されている。

- **`.claude/architecture.md`** — ユーザー入力 → skill → CLI → DB → 出力までの全パスを Mermaid ステートマシン / フローチャートで図示。skill の Phase 遷移、CLI dispatch、DB テーブルアクセス、payoff 内部ゲーム木、データ型の流れ。新機能を足す前にまずここを眺めて全体整合性を確認する。
- **`.claude/skills/team-builder/references/bulk_theory.md`** — 耐久指数 HBD/(B+D) の導出、H=B+D 則、greedy 勾配法アルゴリズム、11n調整との関係、HP条件の根拠。`hbd` サブコマンドや努力値配分に関する質問はここを第一参照。
- **`.claude/skills/team-builder/references/champions_sp.md`** — Champions SP システムの全仕様。EV/IV との同値性、+1 優位、性格補正境界、HBD 最適化差分、逆算アルゴリズム。Champions フォーマットのステータス計算に関する質問はここを第一参照。
- **`.claude/skills/team-builder/references/format_rules.md`** — メガ/ダイマ/Z/テラスタル等のメカニクス定義
- **`.claude/skills/team-builder/references/stat_thresholds.md`** — 種族値ベンチマーク・素早さティア
- **`.claude/skills/team-builder/references/items_abilities.md`** — 道具・特性の考察用データ
- **`.claude/skills/nash/references/theory.md`** — 零和 LP / Simplex / Fictitious play / MWU の数式と根拠。`pkdx nash solve` の正当性、数値安定性 (shift-and-normalize)、退化ケースの扱いに関する質問はここを第一参照。
- **`.claude/skills/nash/references/exploitability.md`** — exploitability / NashConv / KL / L1 の定義と使い分け。Nash 判定基準 (≤ 1e-6)、メタ乖離分析の解釈に関する質問はここ。
- **`.claude/skills/nash/references/payoff_semantics.md`** — `TeamPayoffModel` (SwitchingGame / ScreenedSwitchingGame) の仕様・計算量・選択基準。選出最適化のどのモデルを使うべきか、廃止済みの pairwise 系に関する履歴もここ。
