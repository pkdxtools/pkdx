# pkdx

ポケモン対戦の構築支援ツールです。
Claude Code / Codex と対話しながらチームを組んだり、ポケモンの型を作ったり、ダメージ計算や対戦シミュレーションができます。

## できること

- **チームビルド**: 軸ポケモンを決めたら、タイプ補完・素早さ調整・メタ対策まで対話的にガイド。6体構築と3体選出パターンを提案する。チャンピオンズのバトルチームスクリーンショットから登録も可能
- **ダメージ計算**: 特性・持ち物・天候・テラスタル込みの乱数ダメージを計算。「確定2発」「乱数1発(12/16)」のような実戦的な確定数を出力する
- **育成シミュレーション**: 性格・特性・持ち物・技・努力値を対話的に設定し、Lv50実数値を算出。完成データはファイルに保存でき、チームビルドでも利用できる
- **耐久指数最適化**: H/B/D の努力値配分を最適化。HP条件（きのみ/オボン/たべのこし）・物理/特殊比重・top-N 候補の指定に対応し、「HBD 値が最大になる配分」を提示する
- **ポケモン検索**: 名前・タイプ・素早さ・覚えるわざなどの条件でポケモンを検索。技一覧やタイプ相性もすぐ引ける
- **バトルシミュレーション**: 登録済みのチーム2つを使って、選出から対戦結果までをシミュレーション。最適行動を取り続けた際の勝率を導出
- **構築記事・ブログ管理**: 登録したバトルチームデータを元に、構築ブログを公開できる。構築に紐づかないブログの作成も可能

## 対応バージョン

- 共有データ (`scarlet_violet` など): https://github.com/towakey/pokedex/
- Champions レギュレーション: https://github.com/projectpokemon/champout/ を入力ソースとして使用

## セットアップ

### A. データをクラウドに保存したい場合（GitHubアカウントあり）

GitHubアカウントがあれば、作成した構築・育成データをクラウドにバックアップでき、複数のPCで共有したり、過去のデータに戻すことができます。

1. GitHubの [pkdxtools/pkdx](https://github.com/pkdxtools/pkdx) ページ右上の「Fork」ボタンを押す
2. クローンしたリポジトリのURLをClaude Code / Codexに渡して「これ使いたい」
3. 以降は `/self-update` スキルで最新版に追従できる

### B. まず試してみたい場合（GitHubアカウントなし）

このリポジトリのURLをClaude Code / Codexに渡して「これ使いたい」でOK。データは手元のPCにのみ保存されます。
あとからGitHubアカウントを作成してクラウド保存に切り替えることも可能です。

## 使い方

Claude Code / Codex (CLI / デスクトップアプリどちらでも可) をこのリポジトリで開いて話しかけるだけ。

```
> ガブリアス軸で構築したい
> ガブリアスのげきりんでサーフゴーに何発？
> ガブリアスを育成したい
> ガブリアスの総合耐久を最適化したい
> 対戦シミュレーションをしたい
```

または、スキルを呼び出すことも可能

```sh
# 構築をはじめる
> /team-builder

# ダメージ計算をはじめる
> /calc

# 育成シミュレーションをはじめる
> /breed

# 対戦シミュレーションをはじめる
> /nash

# ブログの管理をはじめる
> /blog
```

作成したチーム・型は `./box` 配下に置かれる。手動で編集もできるし、Claude Code / Codex経由で閲覧・編集も可能。

### 構築をブログとして公開する（GitHub Pages）

GitHub にフォークしていれば、作成した構築記事とブログ記事を GitHub Pages に自動デプロイできる。

#### セットアップ (1 回だけ)

1. リポジトリの Settings → Pages → Source を **"GitHub Actions"** に切り替える
2. `main` に push すると、`.github/workflows/deploy-pages.yml` が自動で Astro サイトをビルドして公開する (URL は Actions ログに表示される)
3. 初回だけ手動でテストしたい場合は Actions タブから `Deploy Pages` → `Run workflow` をクリック

#### team-build → ブログ公開のデータフロー

```mermaid
flowchart LR
    subgraph Local["ローカル (fork clone)"]
        direction TB
        U["ユーザー"]:::user
        CC["Claude Code / Codex"]:::tool
        TB["/team-builder<br/>skill"]:::skill
        CA["/calc<br/>skill"]:::skill
        PKDX["bin/pkdx<br/>(MoonBit CLI)"]:::cli
        CACHE[("box/cache/<br/>team_cache_*.json")]:::store
        TEAMS[("box/teams/<br/>&lt;slug&gt;.md<br/>&lt;slug&gt;.meta.json")]:::store
        BLOG[("box/blog/<br/>*.md")]:::store
    end
    subgraph GitHub["GitHub (fork)"]
        direction TB
        GIT[("main branch")]:::store
        WF["deploy-pages.yml<br/>(Astro build)"]:::ci
        PAGES[("GitHub Pages<br/>&lt;user&gt;.github.io/pkdx/")]:::pub
    end

    U -- "対話" --> CC
    CC -- "Phase 0-8" --> TB
    TB -- "pkdx query/search<br/>pkdx hbd 等" --> PKDX
    TB -- "書き込み" --> CACHE
    CACHE -- "cat | pkdx write teams<br/>(+ frontmatter)" --> PKDX
    PKDX -- "生成" --> TEAMS
    CC -- "ダメ計" --> CA
    CA -- "pkdx damage<br/>--attach-team" --> PKDX
    PKDX -- "damage_calcs[] 追記" --> TEAMS
    U -- "手編集<br/>(edited: true)" --> TEAMS
    U -- "自由記事" --> BLOG
    TEAMS -- "git push" --> GIT
    BLOG -- "git push" --> GIT
    GIT -- "自動ビルド" --> WF
    WF -- "site/dist デプロイ" --> PAGES

    classDef user fill:#fef3c7,stroke:#b45309,color:#111
    classDef tool fill:#e0e7ff,stroke:#4338ca,color:#111
    classDef skill fill:#d1fae5,stroke:#047857,color:#111
    classDef cli fill:#f3e8ff,stroke:#6d28d9,color:#111
    classDef store fill:#f3f4f6,stroke:#4b5563,color:#111
    classDef ci fill:#fee2e2,stroke:#b91c1c,color:#111
    classDef pub fill:#cffafe,stroke:#0e7490,color:#111
```

#### 公開対象・編集ポリシー

カスタムドメイン: `site/public/CNAME` にドメイン名 1 行のファイルを置くと有効化。

公開を停止: Settings → Pages → Disable、または `box/site.config.json` の `enabled` を `false` にする。

サイト本体 (`site/` 配下) は upstream 管理なので直接編集は非推奨。カスタマイズは `box/site.config.json` と `site/public/` 経由で行う。

### CLI 単体でも使える

```bash
bin/pkdx query "ガブリアス"           # 種族値・特性を確認
bin/pkdx moves "ガブリアス"           # 覚える技を一覧
bin/pkdx search --type "ドラゴン" --min-speed 100  # 素早さ100以上のドラゴン
bin/pkdx damage "ガブリアス" "サーフゴー" "じしん"  # ダメージ計算
bin/pkdx hbd "カビゴン" --nature ずぶとい            # 耐久指数が最大になる努力値配分
bin/pkdx stat-calc "ガブリアス" --ev "0,252,0,0,4,252" --nature ようき  # 実数値計算
bin/pkdx type-chart "ほのお" "くさ"   # タイプ相性
bin/pkdx coverage "じめん,こおり"     # 攻撃範囲の確認
```

## 対応環境

macOS (Apple Silicon) / Linux (x86_64) / Windows (WSL2)

## ライセンス

MIT

## 対戦シミュレーションの対応範囲

`/nash` (選出最適化 / 最適戦略算出) が評価対象としているメカニクス。勝率・選出分布を読むときは ⚠️ / ❌ の影響を念頭に置いてください。

凡例: ✅ 対応済 / ⚠️ 部分対応 / ❌ 未対応

| カテゴリ | 要素 | 状態 | 備考 |
|---|---|:---:|---|
| フォーマット | 3v3 シングル | ✅ | 6匹 → 3匹選出 |
| フォーマット | ダブル (4v4) | ❌ | 未実装 |
| Nash 計算 | exact LP simplex solver | ✅ | LP simplex (Phase-1/Phase-2 + Bland's rule) で exact Nash 解。pure-saddle fast path で trivial degenerate ケースを sidestep |
| Nash 計算 | degenerate matrix fallback | ✅ | `pkdx select` で simplex iteration limit を超えた degenerate payoff matrix では fictitious_play (Robinson 1951) → multiplicative weights update (Freund & Schapire 1999) の順で iterative learner に自動 fallback、exploitability < tol (default 0.05 = 5% 勝率) で approximate Nash 採用。出力 JSON の `nash_solver` field で経路 (`"simplex"` / `"fictitious_play"` / `"mwu"`) を確認可能。入力 JSON の `nash_solver_config.tol` / `iterations` で上書き可。`pkdx nash solve` は user 任意 payoff のため別 PR で対応予定 |
| ダメージ計算 | 16段階乱数 / 一致 / 相性 / ランク / 急所 | ✅ | |
| ダメージ計算 | テラスタル | ✅ | |
| ダメージ計算 | 天候補正 | ✅ | 晴で炎 1.5x・水 0.5x、雨で水 1.5x・炎 0.5x、砂で岩タイプ防御側 SpD 1.5x、雪で氷タイプ防御側 Def 1.5x。`pkdx damage` 単体 / 状態遷移内 / 回復技 / EOT すべて現在天候を反映 |
| ダメージ計算 | フィールド補正 | ✅ | エレキ/グラス/サイコフィールドで対応タイプの技 1.3x (地上の攻撃側)、グラスフィールドで地震系 0.5x (地上の防御側)、ミストフィールドでドラゴン技 0.5x (地上の防御側)。`pkdx damage` 単体 / 状態遷移内 / EOT 全層で現在フィールドを反映 |
| 先手判定 | 優先度 (ねこだまし・しんそく等) + 実素早さ | ✅ | |
| 先手判定 | 素早さ同速 | ✅ | 0.5 / 0.5 分岐 |
| 命中率 | 確率ノードで分岐 | ✅ | 鬼火 85 / 電磁波 90 / ほうし 100 等 |
| ランク変化 | 自己強化 | ✅ | つるぎのまい / りゅうのまい / からをやぶる等 |
| ランク変化 | 相手ランク低下付与 | ✅ | あまえる / いやなおと / こわいかお / しっぽをふる / にらみつける等。瀕死ヒット時は付与スキップ |
| 状態異常 | まひ | ✅ | 行動不能 12.5% + S×1/2、電気タイプ免疫 |
| 状態異常 | やけど | ✅ | 物理×1/2 + HP/16、炎タイプ免疫 |
| 状態異常 | どく | ✅ | HP/8、鋼・毒タイプ免疫 |
| 状態異常 | もうどく | ✅ | n/16 加算スリップ、交代でカウンタリセット |
| 状態異常 | ねむり | ✅ | 2 ターン固定 |
| 状態異常 | あくび | ✅ | 1 ターン予告 → Sleep(2)、交代で解除 |
| 状態異常 | こおり / こんらん / メロメロ / バインド | ❌ | |
| 状態異常 | フィールド連動 | ✅ | ミストフィールド中、地上ポケモンへの全状態異常 (まひ・やけど・どく・もうどく・ねむり・こんらん) 付与を防止 |
| 継続効果 | やどりぎのタネ | ✅ | 付与 / 1/8 EOT 吸収 / Magic Guard で tick 無効化 / Liquid Ooze (ヘドロえき) で反転 damage / 交代で剥がし / くさタイプ免疫 (mega 反映後 type) |
| 継続効果 | グラスフィールド回復 | ✅ | グラスフィールド中、地上ポケモンが EOT で max HP / 16 回復 (たべのこしの直後、やどりぎのタネの直前) |
| 同ターン内順序 | 先行付与状態を後攻行動前に反映 | ✅ | やけどで後攻物理半減 / ねむりで後攻行動スキップ |
| 交代 | 基本交代 + ランクリセット | ✅ | |
| 交代 | 交代時発動効果 | ❌ | いかく / プレッシャー / 滅びのうた / おいうち |
| メガ進化 | ステ・タイプ・特性切替 | ✅ | 各サイド 1 回 |
| 攻撃技 | 連続技 (multi-hit) | ✅ | Random 2-5 hit (タネマシンガン等) / トリプル系 per-hit power 増加 (トリプルアクセル等) / ネズミざん 1-10 hit (per-hit 90% 幾何) / スキルリンク 5 固定 / おやこあい 2-hit。各 hit を確率分岐ノードで展開 |
| 攻撃技 | 副次効果 (攻撃側) | ❌ | どくづき 30% 毒 / パンチ系 10% 状態異常等 |
| 攻撃技 | 反動技 | ✅ | ブレイブバード 1/3 / すてみタックル 1/4 / はめつのひかり 1/2 等 12 種 |
| 攻撃技 | 自滅技 | ✅ | じばく / だいばくはつ |
| 攻撃技 | 反動硬直 (次ターン完全スキップ) | ✅ | はかいこうせん / ギガインパクト / ブラストバーン / ハイドロカノン / ハードプラント。技選択・交代ともに不可 |
| 攻撃技 | 優先度技 (フィールド連動) | ✅ | サイコフィールド中、地上ポケモンへの優先度 > 0 の技を無効化 (技は使用されるが効果が出ない、しんそく等の単体技対象) |
| 攻撃技 | 2 ターン溜め | ❌ | ソラビ / ロケットずつき / ダイビング等 |
| 攻撃技 | タイプ相性上書き | ❌ | フリーズドライ / フライングプレス |
| 特性 | 接触特性 (defender 側 proc) | ✅ | せいでんき / ほのおのからだ / どくしゅ (30% 各) / ほうし (11/10/9% 毒/まひ/眠) を per-hit で抽選 |
| 特性 | 多段補正 | ✅ | スキルリンク (固定 5 hit) / おやこあい (2 hit) / じきゅうりょく (per-hit B+1) |
| 特性 | スキン特性 | ✅ | フェアリースキン / エレキスキン等。技タイプ書換 + ×1.2 + 半減木の実判定に反映 |
| 特性 | 回復・状態異常干渉 | ✅ | ふみん / やるき / スイートベール (Sleep / あくび 免疫 + Rest 失敗) / マジックガード (やどりぎ tick 無効化) / ヘドロえき (Drain + やどりぎ 反転) / ぼうじん / すなかき / すながくれ / すなのちから (Sand chip 免疫) |
| 特性 | その他 | ❌ | いかく / 再生力 / トレース / じゅうなん / ばけのかわ等 (ばけのかわは damage 単体計算では反映、シミュレーションでは未反映) |
| 持ち物 | 半減木の実 | ✅ | オッカのみ等 17 種 + ホズのみ。効果ばつぐん時 (ホズのみは Normal neutral) に半減 + 1 回消費 |
| 持ち物 | きあいのタスキ | ✅ | 満タン → KO 級被弾を 1 HP rescue。multi-hit 集計 KO は救済しない |
| 持ち物 | 回復木の実 | ⚠️ | フィラのみ (1/2 HP 閾値 → 1/3 HP 回復) のみ。オボン等は未反映 |
| 持ち物 | 接触持ち物 | ✅ | とびだすハバネロ (100% やけど) / とびだすなかみ (100% まひ) を per-hit で抽選 |
| 持ち物 | ダメージ補正系 | ⚠️ | こだわりハチマキ / メガネ / いのちのたま / たつじんのおび等は計算に反映。拘りロック / とつげきチョッキロック / たべのこし / しろいハーブ等の挙動は未反映 |
| 変化技 | 壁 / 設置技 / 守る | ❌ | |
| 変化技 | 天候設定技 | ✅ | にほんばれ / あまごい / すなあらし / ゆきげしき、5T 固定。天候石 (あついいわ等) による持続延長は未対応。Sand 中は chip damage tick (max/16) |
| 変化技 | フィールド設定技 | ✅ | エレキフィールド / グラスフィールド / ミストフィールド / サイコフィールド、5T 固定。グランドコート (持続延長) は未対応 |
| 変化技 | 回復技 | ✅ | FixedFraction (じこさいせい / なまける / はねやすめ) / WeatherDependent (つきのひかり / あさのひざし / シンセシス、晴=2/3 雨砂雪=1/4 none=1/2) / Drain (ギガドレイン等、ヘドロえき反転) / Rest (Sleep 免疫 ability で失敗 + 満タン時 failure) / PainSplit (いたみわけ) / Wish (ねがいごと、slot bound、T+1 EOT 発動) |
| 特殊システム | Z 技 / ダイマックス | ❌ | 未実装 |
