# pkdx アーキテクチャ: パスのステートマシン

ユーザー入力 → skill → CLI → DB → 出力 までの全パスを、粒度別に
ステートマシン / データフローとして可視化したもの。実装詳細は
各 skill の `SKILL.md` / `references/` を参照。

## 0. 全体像

```mermaid
flowchart LR
  User[ユーザー] --> Claude
  Claude --> Router{意図判定}
  Router -->|構築したい| TB[team-builder]
  Router -->|育成したい| Breed[breed]
  Router -->|ダメ計| Calc[calc]
  Router -->|Nash/選出/メタ| Nash[nash]
  Router -->|更新| SU[self-update]

  TB --> CLI
  Breed --> CLI
  Calc --> CLI
  Nash --> CLI

  subgraph CLI_LAYER[pkdx CLI]
    CLI[main.mbt dispatch] --> WithDB{DB要る?}
    WithDB -->|Yes| DB[(pokedex.db + pkdx_patch)]
    WithDB -->|No| STDIN[stdin JSON]
  end

  DB --> CLI
  STDIN --> CLI
  CLI --> Stdout[stdout JSON/table/MD]

  Stdout --> TB
  Stdout --> Breed
  Stdout --> Calc
  Stdout --> Nash

  TB --> BoxTeams[box/teams/*.md]
  Breed --> BoxMons[box/pokemons/**/*.md]
  TB -.cache.-> Cache[box/cache/*.json]
  Breed -.cache.-> Cache

  SU --> Upstream[(upstream: pkdxtools/pkdx)]
  Upstream --> SU
```

## 1. team-builder (Phase 0 → 8)

```mermaid
stateDiagram-v2
  [*] --> P0

  P0: Phase 0 初期化
  note right of P0
    DB 存在確認 / 参照データ読込
    バトル形式 / メカニクス / version 選択
    pkdx init-cache team → box/cache/team_cache_*.json
  end note

  P0 --> P1

  P1: Phase 1 軸ポケモン決定
  note right of P1
    pkdx query → 種族値・特性
    pkdx moves --format json → 技候補 (priority/stat_effects 込み)
  end note

  P1 --> P2

  P2: Phase 2 軸ポケモン分析
  note right of P2
    stat_thresholds.md 参照
    pkdx type-chart / coverage
  end note

  P2 --> P3
  P3: Phase 3 攻めの相性補完
  P3 --> P4
  P4: Phase 4 受けの相性補完
  P4 --> P5
  P5: Phase 5 素早さチェック
  note right of P5
    pkdx search --type X --min-speed N
  end note

  P5 --> P6
  P6: Phase 6 仮想敵分析 (6 体確定)
  P6 --> P7
  P7: Phase 7 選出パターン決定
  note right of P7
    optional: pkdx select (Phase 2b into nash)
    pkdx hbd / stat-calc で努力値最適化
  end note

  P7 --> P8
  P8: Phase 8 構築レポート
  note right of P8
    cat JSON | pkdx write teams --date D --axis A
    → box/teams/{軸}-build-{date}.md
  end note

  P8 --> [*]

  P0 --> P0: "=== Team State ===" エコー
  P1 --> P1: state echo
  P2 --> P2: state echo
  P3 --> P3: state echo
  P4 --> P4: state echo
  P5 --> P5: state echo
  P6 --> P6: state echo
  P7 --> P7: state echo

  P1 --> P0: 軸変更
  P6 --> P3: 穴発見で再検討
```

## 2. breed (Phase 0 → 8)

```mermaid
stateDiagram-v2
  [*] --> B0

  B0: Phase 0 初期化
  note right of B0
    DB 確認 / version 選択 (Champions SP or Standard)
    pkdx init-cache pokemon
  end note

  B0 --> B1
  B1: Phase 1 ポケモン選択
  note right of B1
    pkdx query → 種族値
    Stat Card 表示
    Training State 出力
  end note

  B1 --> B2
  B2: Phase 2 性格選択 (pkdx stat-calc)
  B2 --> B3
  B3: Phase 3 特性選択
  B3 --> B4
  B4: Phase 4 持ち物選択
  B4 --> B5
  B5: Phase 5 技選択 (pkdx moves)
  B5 --> B6
  B6: Phase 6 努力値配分
  note right of B6
    pkdx hbd / stat-calc で HBD 最適化
    Champions なら SP、Standard なら EV/IV
  end note

  B6 --> B7
  B7: Phase 7 完成サマリー & calc 連携
  note right of B7
    --atk-stat / --def-stat / --def-hp で calc に連携
    (実数値は rank 前の値として扱われ、rank/特性/天候は別途掛かる)
  end note

  B7 --> B8
  B8: Phase 8 保存
  note right of B8
    cat JSON | pkdx write pokemon --name N --file F
    → box/pokemons/{name}/{file}.md
  end note

  B8 --> [*]

  B2 --> B2: 性格変更
  B6 --> B2: 性格再調整
  B7 --> B6: 配分やり直し
```

## 3. nash / select / meta-divergence

```mermaid
stateDiagram-v2
  [*] --> N0
  N0: Phase 0 pkdx 存在確認 (macOS/Linux のみ)
  N0 --> N1

  N1: Phase 1 AskUserQuestion
  N1 --> NS: 零和行列 / monocycle
  N1 --> SEL: 選出最適化
  N1 --> MD: メタ乖離分析
  N1 --> GR: DOT グラフ

  NS: Phase 2a pkdx nash solve
  note right of NS
    stdin:  matrix or characters JSON
    stdout: value / row_strategy / col_strategy / support
  end note
  NS --> [*]

  SEL: Phase 2b pkdx select
  note right of SEL
    stdin:  team + opponent + format + team_payoff_model
    team_payoff_model ∈ {switching_game,
      screened_switching_game:T:S:Q}
    turn_limit 既定: MC=5, DP=5 (switching_game:<N> で上書き可)
  end note
  SEL --> [*]

  MD: Phase 2c pkdx meta-divergence
  note right of MD
    stdin:  usage + matrix
    stdout: exploitability / L1 / KL / optimal
  end note
  MD --> [*]

  GR: Phase 2d pkdx nash graph
  note right of GR
    stdin:  matrix JSON
    stdout: Graphviz DOT
  end note
  GR --> [*]
```

## 4. calc (単純なステートマシン)

```mermaid
stateDiagram-v2
  [*] --> C0
  C0: 攻撃側 / 防御側 / 技名を収集
  C0 --> C1: 揃った
  C1: optional: 特性 / 持ち物 / 天候 / フィールド / テラス / ランク / 急所
  C1 --> C2
  C2: pkdx damage A D M [options] --format json
  note right of C2
    attacker/defender/move を DB から取得
    engine.mbt で 16-roll ダメージテーブル生成
  end note
  C2 --> [*]: 乱数表 + 確定数 + 割合 を表示
```

## 5. CLI dispatch → DB テーブルアクセスマップ

```mermaid
flowchart TD
  Main[main.mbt] --> Cmd{subcommand}

  Cmd --> Q[query]
  Cmd --> MV[moves]
  Cmd --> SR[search]
  Cmd --> DMG[damage]
  Cmd --> LR[learners]
  Cmd --> TC[type-chart]
  Cmd --> CV[coverage]
  Cmd --> SC[stat-calc]
  Cmd --> SRV[stat-reverse]
  Cmd --> HBD[hbd]
  Cmd --> IC[init-cache]
  Cmd --> WR[write]
  Cmd --> NA[nash]
  Cmd --> SE[select]
  Cmd --> MD[meta-divergence]

  Q --> T1[pokedex_name + local_pokedex_*]
  MV --> T2[local_waza + local_waza_language]
  MV --> T3[champions_learnset]
  MV --> TMM[move_meta LEFT JOIN]
  SR --> T1
  DMG --> T2
  DMG --> TMM
  LR --> T1
  LR --> T2
  TC -.-> Static[[types/chart.mbt 静的テーブル]]
  CV -.-> Static
  SC -.-> Static
  SRV --> T1
  HBD --> T1
  IC -.-> Schema[[writer/schema.mbt]]
  WR -.-> Schema

  NA --> STDIN_JSON[stdin JSON]
  SE --> STDIN_JSON
  MD --> STDIN_JSON

  STDIN_JSON --> PayoffLayer[payoff/ module]

  T1 --> DB[(pokedex.db)]
  T2 --> DB
  T3 --> DB
  TMM --> DB
```

## 6. payoff 内部フロー (pkdx select の内側)

```mermaid
flowchart TD
  In[stdin JSON] --> Parse[cli_select::run_select]
  Parse --> Parsed{"team + opponent + format + model"}

  Parsed --> Disp{team_model}
  Disp -->|SwitchingGame| SG[switching_game_winrate]
  Disp -->|ScreenedSwitchingGame T:S:Q| SCR[team_payoff_matrix_screened]

  SG --> TPS[team_payoff_matrix_switching]

  SCR --> PhaseA["Phase A: team_monte_carlo_value × C(6,3)² cells"]
  PhaseA --> PhaseB["Phase B: mean-based row/col pruning (keep_top quantile)"]
  PhaseB --> PhaseC["Phase C: switching_game_winrate × retained sub-matrix"]
  PhaseC --> Sub[retained sub-matrix + retained indices]

  TPS --> Outer[outer Nash LP]
  Sub --> Outer

  Outer --> Build[build_select_result]
  Build --> Out[JSON: value / row_strategy / col_strategy / (retained) selections / exploitability]
```

## 7. SwitchingGame 内部ゲーム木 (再帰的ステートマシン)

```mermaid
stateDiagram-v2
  [*] --> Start

  Start: 初期状態\nmy/opp_active=0, 全 HP 満タン\nmy/opp_ranks=[0,0,0,0,0], turn=0

  Start --> Check

  Check: terminal_value 判定
  Check --> Terminal_Mine: my 全滅 → -1.0
  Check --> Terminal_Opp: opp 全滅 → +1.0
  Check --> Terminal_Limit: turn ≥ DP_TURN_LIMIT(5) → hp_ratio
  Check --> CacheLookup: それ以外

  CacheLookup --> Hit: cache hit (ValueStats.hits++)
  CacheLookup --> Miss: cache miss (ValueStats.misses++)

  Hit --> [*]: 値返却

  Miss --> Actions
  Actions: alive_actions 列挙\n(UseMove + Switch)

  Actions --> Loop
  Loop: 全 (A_i, A_j) ペア列挙
  Loop --> Trans: 各セル

  Trans: transition_with_cache
  note right of Trans
    UseMove x UseMove:
      turn_order_sign(優先度→effective_speed)
      dmg = mean_damage_cached(DamageCache hit/miss++)
      先攻KO で後攻スキップ
      stat_effects でランク更新 (clamp_rank)
    UseMove x Switch:
      交代側ランクリセット
      残る攻撃は新 active に当たる
    Switch x UseMove: 対称
    Switch x Switch:
      両者 active 更新 + 両ランクリセット
      damage なし
  end note

  Trans --> Child: 子 state で value 再帰
  Child --> Check: 再帰入る

  Loop --> Solve
  Solve: 全セル埋まったら\nsolve_zero_sum で Nash 値
  Solve --> Store: cache.set(state, value)
  Store --> [*]

  Terminal_Mine --> [*]
  Terminal_Opp --> [*]
  Terminal_Limit --> [*]
```

## 8. データ型のフロー

```mermaid
flowchart LR
  subgraph DB_LAYER[DB layer]
    W[local_waza] --> JW["wl.name, w.type, w.category,\npower, accuracy, pp"]
    MM[move_meta\npkdx_patch/006] --> JMM[name_ja, priority, stat_effects_json]
    W -.LEFT JOIN.-> MM
  end

  subgraph QUERY_LAYER["query_moves / query_damage"]
    JW --> Parse1[parse_stat_effects_json]
    JMM --> Parse1
    Parse1 --> MoveS["@model.Move"]
  end

  MoveS --> CliFmt[cli/format.moves_to_json]
  CliFmt --> MVOut["pkdx moves 出力 JSON\n名前/型/カテゴリ/威力/命中/PP/\n優先度/ランク効果"]

  MVOut -.skillがコピペ.-> SelectIn["pkdx select stdin JSON"]

  SelectIn --> PMJ["parse_move_json\n(inline priority + stat_effects を読む)"]
  PMJ --> MoveS2["@model.Move (同じ型)"]

  MoveS2 --> Combatant["@payoff.Combatant\n(Pokemon + Move[])"]

  Combatant --> PayoffOut["switching_game /\nmonte_carlo が\nmove.priority /\nmove.stat_effects を直参照"]
```

## 補足 / 設計ポリシー

| 観点 | パス |
|---|---|
| **DB 一次アクセス** | `pkdx query/moves/damage/learners/search` のみ (1 箇所に集約) |
| **純 JSON I/O** | `pkdx select/nash/meta-divergence/write` は stdin / stdout のみ |
| **計算ホットループ内の DB 禁止** | payoff 層の `value` / `simulate_battle` は DB 触らず、全情報は `Move` と `Combatant` 経由 |
| **状態の永続化** | box/ 配下のみ (`teams/`, `pokemons/`, `cache/`) |
| **メタ的な状態エコー** | team-builder / breed は各 Phase 末尾に Team/Training State をエコーし、context 圧縮後も再開可能 |
| **ゲーム木状態** | `SwitchingGameState` は `derive(Eq, Hash)` の pure struct。memoize + αβ 互換 |
