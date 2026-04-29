# ダメージ計算の特殊パターン

`pkdx damage` エンジンに実装されている「通常の物理/特殊ダメージ式から外れる計算」の網羅リファレンス。SKILL.md Phase 2 のフラグ定義では意味が取りきれない「なぜこのフラグがあるのか」「どう発動するのか」「出力 JSON に何が出るのか」をここにまとめる。

実装ファイル (`pkdx/src/` 配下) と行番号を都度添える。疑わしい時は必ず実装で裏を取ること (仕様の更新で本ドキュメントが先に陳腐化する可能性がある)。

---

## 1. 特性に由来する特殊処理

### おやこあい (Parental Bond)

- **発動条件**: 攻撃側特性 `おやこあい` かつ **単発技**。既に連続技 (Double Kick, Bullet Seed 等) には非適用
- **hit plan 解決**: `resolve_hit_plan` が `ParentalBond` variant を返す (`damage/multi_hit.mbt:115`)
- **計算**: 1 撃目は通常どおり 16 段階ロールを取る。2 撃目は **威力 1/4** で **フルパイプラインを再実行** (STAB / Skin / タイプ相性 / 特性 / 壁 / 道具 / きのみ / min-1 床補正 が独立に掛かる)。その上で 16 段階ごとに `damages[i] + damages2[i]` で合算 (`damage/engine.mbt:465-476`)
- **JSON 出力**: `hits_dealt: 2`
- **Skill Link・連続技との関係**: 連続技には乗らない (hit plan が `FixedHits(n)` / `Random2to5` に落ちるルートでは ParentalBond 分岐に来ない)

```bash
# おやこあいの検証 (単発技)
pkdx damage "メガガルーラ" "ハピナス" "すてみタックル" \
  --atk-ability おやこあい --format json
# → hits_dealt=2, damages は 1撃目 + 2撃目(威力1/4) の合算
```

### ばけのかわ (Disguise)

- **発動条件**: 防御側特性 `ばけのかわ` かつ `--disguise-active` (`disguise_active: true`)
- **挙動**: 初撃として全 damages を 0 で返し、状態遷移を示すフラグを立てる (`damage/engine.mbt:441-443`, `560-580`)
- **JSON 出力**:
  - `damages: [0]×16`, `percents: [0.0]×16`
  - `disguise_blocked: true`
  - `ko_text: "けがわブロック"`
  - `is_immune: false` (**免疫ではない** ─ 1/8 HP チップは呼び出し側責任)
  - `hits_dealt: 0`
- **2 撃目以降**: `--disguise-active` を外して再計算 (エンジンは状態を持たない)

### てんねん (Unaware)

- **双方向・独立**: 攻撃側が持てば防御側ランクを無視、防御側が持てば攻撃側ランクを無視 (両方同時可)
- **実装**: `damage/stat_resolution.mbt:135-140` で `atk_rank_mask` / `def_rank_mask` を OR で立てる
- **注**: `--atk-stat` / `--def-stat` の override は「rank 前の実数値」として扱われるため、てんねん下でも override は効く

### スキルリンク (Skill Link)

- **発動条件**: 攻撃側特性 `スキルリンク` かつ 2-5 乱数技
- **挙動**: `Random2to5` を `FixedHits(5)` に昇格 (`damage/multi_hit.mbt:119`)
- **ParentalBond との優先順位**: 連続技判定が先に来るので、スキルリンクで 5 固定になった技にはおやこあいは乗らない

### わざわい系と Body Press の相互作用

- **わざわいのつるぎ (Sword of Ruin)** ─ 通常技では相手 Def × 3/4。**ボディプレスに限り** 攻撃側自身の Def が攻撃値として使われるので、同じ能力が「攻撃値を下げる」方向に働く (`damage/engine.mbt:175-178`)
- **わざわいのおふだ (Tablets of Ruin)** ─ 物理技時に攻撃側 Atk × 3/4 (`damage/abilities.mbt:303`)。ボディプレス時は Atk を参照しないので非適用

### 体重依存技

- **けたぐり / くさむすび**: 防御側の体重で威力決定
- **ヘビーボンバー / ヒートスタンプ**: 自身 / 相手の体重比で 40 / 60 / 80 / 100 / 120 を決定 (`damage/engine.mbt:532-547`)
- **ヘヴィメタル** ×2 / **ライトメタル** ×1/2 を体重に適用 (`damage/engine.mbt:501-509`)
- **フラグ**: ユーザー側で制御するものは無い。ポケモンデータの `weight` 列で自動計算

---

## 2. 技に由来する特殊処理

### カテゴリ／参照ステータス override

| 技分類 | 判定 | 効果 | 実装 |
|--------|------|------|------|
| サイコショック / サイコブレイク / しんぴのつるぎ | 技名で自動 | Special のまま **防御側 Def を参照** | `stat_resolution.mbt:89-97` |
| ボディプレス | 技名で自動 | Physical のまま **攻撃側 Def を参照** | `stat_resolution.mbt:84-87`, `engine.mbt:61-67` |
| シェルアームズ | 動的 | `atk_atk × def_spd > atk_spa × def_def` で物理/特殊を選択 (**同点は特殊に落ちる**) | `stat_resolution.mbt:102-116` |
| せいなるつるぎ | 技名で自動 | **防御側の正ランクのみ無視** (負ランクは乗る) | `stat_resolution.mbt:130-132` |

- **シェルアームズの同点処理**: 厳密 `>` で物理判定。等号は特殊側 ─ 境界ケースで期待と食い違いやすいので注意
- **Wonder Room**: 上記すべて **未対応** (`WONDER_ROOM_NOT_SUPPORTED` コメント多数)。シングル前提で設計されているため、Wonder Room 下の Def/SpD 入れ替えは考慮していない
- **ボディプレス時の `--atk-rank`**: B ランクを渡す (攻撃ランクではなく防御ランク)。SKILL.md 側でもユーザーに注記する

### ウェザーボール

- **タイプ変化**: 晴 → ほのお / 雨 → みず / 砂 → いわ / 雪 → こおり (`damage/variable_power.mbt:20-35`)
- **威力変化**: 基本 35 → 天候あれば 100
- **Skin 特性との順序**: `resolve_move_type_override` がフェアリースキン等の前段で走るため、ウェザーボールはまず天候でタイプ解決されてから Skin 判定に掛かる

### 可変威力技

すべて `damage/variable_power.mbt` 内。引数は技名で分岐。

| 技 | フラグ | 発動条件 | 威力変化 |
|----|--------|----------|----------|
| アシストパワー | `--atk-rank-up-count <n>` | `n` = 攻撃側の正ランクアップ累積段数 | `20 + 20n` (上限 860) |
| つけあがる | `--def-rank-up-count <n>` | `n` = 防御側の正ランクアップ累積段数 | `20 + 20n` |
| やけっぱち | `--atk-hp <ratio>` | 攻撃側 HP ≤ 1/2 (`num×2 ≤ den` で判定) | `base × 2` |
| からげんき | `--atk-status <cond>` | まひ / やけど / どく / もうどく (**ねむり・あくび は対象外**) | `base × 2` |
| たたりめ | `--def-status <cond>` | 相手が任意の状態異常 | `base × 2` |
| はたきおとす | `--def-item-removable` | 相手が剥がせる持ち物を持つ | `base × 3/2` (65 → 97 整数切り捨て) |

- **ランクアップ数は「現時点のランク段数」ではなく「累積」**: つけあがるの仕様上、相手が +2 状態でも「+2 を経由して 0 に戻った」なら 2。呼び出し側が累積を管理する
- **やけっぱちの HP 書式**: CLI 側でパースして `atk_hp_num` / `atk_hp_den` に分解。`1/2`, `50%`, `1/3` などが渡せる
- **からげんき の BadPoison カウンタ**: `BadPoison(n)` の `n` は無視。どくターン数に関わらず発動

```bash
# アシストパワー (A+2 を 2 stat ぶん = 計 +4 段)
pkdx damage "ミュウツー" "ハピナス" "アシストパワー" --atk-rank-up-count 4
# → 威力 = 20 + 20×4 = 100

# やけっぱち (HP ちょうど半分)
pkdx damage "パチリス" "ガブリアス" "やけっぱち" --atk-hp 1/2

# はたきおとす (持ち物剥がせる相手)
pkdx damage "サザンドラ" "ハピナス" "はたきおとす" --def-item-removable
# → 威力 65 × 3 / 2 = 97
```

---

## 3. 壁 (Reflect / Light Screen / Aurora Veil)

### 適用ペア

`damage/wall.mbt:16-23`:

| 壁 | 物理 | 特殊 |
|----|------|------|
| `Reflect` (リフレクター) | 0.5x / Double 0.667x | ─ |
| `LightScreen` (ひかりのかべ) | ─ | 0.5x / Double 0.667x |
| `AuroraVeil` (オーロラベール) | 0.5x / Double 0.667x | 0.5x / Double 0.667x |

- **シングル乗数**: `2048 / 4096 = 0.5` 厳密
- **ダブル乗数**: `2732 / 4096 ≈ 0.6670` (**0.75x ではない**)
- **ダブル時は `--double` フラグが必要** (壁の乗数判定に `is_double` を参照する)

### 貫通条件

以下のどれかを満たすと壁はスキップ (`damage/engine.mbt:391-398`):

1. `--critical` (急所)
2. `--pierce-screen` (技側の貫通フラグ ─ かわらわり / サイコファング / ブリックブレイク等)
3. 攻撃側特性が壁貫通 (`damage/wall.mbt:29-34`):
   - かたやぶり / すりぬけ / ターボブレイズ / テラボルテージ

### 適用順序

Showdown 準拠で **「特性 final → 壁 → いろめがね → 道具 final → きのみ」** の順に掛かる (`damage/engine.mbt:388-404`)。「壁のあとに弱点保険で反撃」等のタイミングとは別物なので注意。

```bash
# シングル・リフレクター下 (物理技 → 0.5x)
pkdx damage "ガブリアス" "カイリュー" "じしん" --wall reflect

# ダブル・オーロラベール下 (0.667x)
pkdx damage "ウーラオス" "ハピナス" "すいりゅうれんだ" \
  --wall aurora-veil --double

# 貫通技は壁無視
pkdx damage "ローブシン" "ハピナス" "かわらわり" \
  --wall reflect --pierce-screen
```

---

## 4. 連続技 (Multi-hit)

### 技の分類 (`damage/multi_hit.mbt`)

| 分類 | 例 | hit plan |
|------|-----|----------|
| `Single` | 単発技一般 | `Single` (+ ParentalBond で 2 回に昇格可) |
| `FixedHits(2)` | にどげり / ダブルアタック / ダブルウイング / ドラゴンアロー / ツインビーム | 2 固定 |
| `FixedHits(3)` | トリプルキック / トリプルアクセル / トリプルダイブ / すいりゅうれんだ | 3 固定 |
| `Random2to5` | みだれひっかき / みだれづき / ボーンラッシュ / ロックブラスト 等 10 種 | Auto 時 **中央値 3**、Skill Link で 5 |

### `--multi-hit` フラグ値域 (`damage/multi_hit.mbt:20-52`)

- `auto` (既定): move table を参照
- `1..5` の整数: その回数で固定 (範囲外は 1 / 5 にクランプ)
- `expected`: **pkdx damage では拒否される** (payoff レイヤ専用の期待値近似)

```bash
# Skill Link ロックブラスト (auto でも 5 固定)
pkdx damage "ドリュウズ" "ナットレイ" "ロックブラスト" \
  --atk-ability スキルリンク --multi-hit 5
# あるいは
pkdx damage "ドリュウズ" "ナットレイ" "ロックブラスト" \
  --atk-ability スキルリンク  # auto で自動的に 5 になる

# 最小ケース (乱数の下振れ想定)
pkdx damage "ニャース" "ハピナス" "みだれひっかき" --multi-hit 2
```

### 連続技と ParentalBond の相互作用

`resolve_hit_plan` は以下の優先順で評価される (`damage/multi_hit.mbt`):

1. 技が `Random2to5` **かつ** スキルリンク → `FixedHits(5)`
2. 技が `FixedHits(n)` / `Random2to5` → そのまま (ParentalBond 分岐には来ない)
3. 技が `Single` **かつ** 攻撃側が `おやこあい` → `ParentalBond`
4. それ以外 → `Single`

つまり **「連続技 × おやこあい」は連続技が勝つ**。

### JSON 出力との対応

- `hits_dealt`: 実際に命中した回数 (1 / 2 / 3 / 5 / ParentalBond で 2)
- `damages[]` / `percents[]`: 合算済みの 16 段階値 (各回分を足したもの)
- `ko` / `ko_text`: 合算ダメージから計算された確定数

### `variants[]` (hit-by-hit chance-node 出力)

P1-A (issue #90) で導入された **`variants[]` 配列**は連続技の確率分岐を hit 単位で表現する。各 variant は `probability`, `hits_count`, `hits[]` (各 hit のメタ) と派生キャッシュ (`total_damages` / `min` / `max` / `ko`) を持つ。`variants[].probability` の合計は **1.0 ± 1e-9** が保証される (chance-node soundness)。

| 技分類 | variants 数 | 確率 |
|---|---|---|
| 単発技 / `FixedHits(n)` 固定 / ParentalBond / Skill Link 経由の `FixedHits(5)` | 1 | 1.0 |
| `Random2to5` (Skill Link 無し) | 4 | 0.375 / 0.375 / 0.125 / 0.125 (hits=2/3/4/5) |
| `TripleVariant` (トリプルアクセル / トリプルキック) | 3 | 0.10 / 0.09 / 0.81 (hits=1/2/3、命中率 90% × 各回独立判定) |

各 `hits[i]` は `damage_per_roll` (この hit 単独の 16 段階) / `def_stage_after` (この hit 後の防御段階、#92 じきゅうりょくが mutate) / `contact` (`is_contact_move(name)`、#93 が参照) を持つ。`event` は将来 (#93/#97) 用の予約フィールドで現状は常に `None`。

legacy `damages` / `hits_dealt` / `min` / `max` / `ko` フィールドは **最確 variant** から派生される。確率タイの場合は **大きい hits_count** が選ばれる (`Random2to5` の 0.375 タイ → hits=3 を採用、旧 `FixedHits(3)` 中央値挙動と整合)。

```bash
# トリプルアクセルの 3 variants を観測
pkdx damage "ガラルニャース" "ハピナス" "トリプルアクセル" --format json \
  | jq '.variants[] | {hits: .hits_count, p: .probability, total_min: .min}'

# Random2to5 (みだれづき) の 4 variants
pkdx damage "ニャース" "ハピナス" "みだれづき" --format json \
  | jq '.variants[] | {hits: .hits_count, p: .probability}'

# Skill Link で variants が 1 個に縮退
pkdx damage "ドリュウズ" "ナットレイ" "ロックブラスト" \
  --atk-ability スキルリンク --format json | jq '.variants | length'  # → 1
```

下流フェーズ (#91 leaf 分岐 / #92 じきゅうりょく / #97 resist berry) はこの中間表現を入力に取り、`Array[(probability, state_after)]` の chance-node fanout を構築する。

---

## 5. 状態異常 (Status Condition)

### パーサ値域 (`damage/status_condition.mbt:82-93`, `model/status_condition.mbt`)

英語 / 日本語どちらでも受け付ける:

| enum | 英語 | 日本語 |
|------|------|--------|
| `Paralyze` | `paralyze` | `まひ` |
| `Burn` | `burn` | `やけど` |
| `Poison` | `poison` | `どく` |
| `BadPoison(n)` | `badpoison` | `もうどく` |
| `Sleep` | `sleep` | `ねむり` |
| `Drowsy` | `drowsy` | `あくび` |

既定値: `None` (無状態)。

### 対応技

- **からげんき** (`--atk-status`): Paralyze / Burn / Poison / BadPoison で 2x
- **たたりめ** (`--def-status`): None 以外なら何でも 2x (Sleep / Drowsy 含む)

### 未実装

- **特性由来の状態異常補正** は `damage/variable_power.mbt` ではなく `abilities.mbt` 側で扱う。例: こんじょう (状態異常で Atk×1.5) は ability 経由で掛かり、`--atk-status` 単独では効かないので併せて `--atk-ability こんじょう` を指定する
- **やけどの物理威力半減** は自動では掛からない。ユーザーが `--atk-stat` で手動計算するか、近い将来の実装に備えて状態異常を渡す運用

---

## 6. 急所 (Critical Hit)

### ランク無視ルール (`damage/stat_resolution.mbt:143-146`)

急所時は以下 **2 マスクだけ** が立つ:

- `atk_rank_negative_mask = true` → **攻撃側の負ランクを無視**
- `def_rank_positive_mask = true` → **防御側の正ランクを無視**

**適用されるランク**:

| ランク方向 | 急所時 |
|------------|--------|
| 攻撃側 + | **効く** |
| 攻撃側 − | 無視 |
| 防御側 + | 無視 |
| 防御側 − | **効く** |

### 乗数

`1.5x` 厳密 (4096 ベースで `6144`)。`damage/engine.mbt:347` の `round5(dmg, 6144)`。

### 急所 × 壁

急所時は壁を必ず貫通 (`damage/engine.mbt:391-398` の `wall_ok` 条件に `not(input.critical)` が入っている)。

---

## 7. JSON 出力フィールド一覧

`model/calc_result.mbt` 参照。

| フィールド | 型 | 意味 |
|------------|-----|------|
| `damages` | `[Int; 16]` | 85..100 の 16 段階ダメージ (合算済み) |
| `percents` | `[Double; 16]` | `damages[i] / defender_hp × 100` |
| `min_damage` / `max_damage` | `Int` | damages の min/max |
| `min_percent` / `max_percent` | `Double` | percents の min/max |
| `ko` / `ko_text` | `String` | 確定数テキスト (`"確定1発"` / `"乱数1発(X/16)"` / `"確定2発"` ...) |
| `defender_hp` | `Int` | 防御側 HP 実数値 |
| `is_immune` | `Bool` | タイプ相性 0 / 特性無効時 `true`。**ばけのかわの場合は `false`** |
| `disguise_blocked` | `Bool` | ばけのかわで初撃が通らなかった時 `true` |
| `hits_dealt` | `Int` | 実際の命中回数 (免疫時 1、Disguise 時 0、ParentalBond 時 2) |

---

## 8. 未実装・注意点

### 未実装

- **イカサマ (Foul Play)**: 相手 ATK 参照の自動化は未実装。回避策として `--atk-stat <相手のATK実数値>` を渡す
- **Wonder Room**: Def/SpD 入れ替え環境は全面的に非対応 (Psyshock / Shell Side Arm で明示コメント)
- **特性由来の状態異常免疫の damage 層での自動補正**: じゅうなん等のタイプ免疫は model 層で処理されるが、みずのベール等の "特性で状態異常にならない" 類は damage 計算側では考慮しない (そもそも状態異常フラグを渡さなければ問題ない)

### 設計上の注意点

- **`--atk-stat` / `--def-stat` / `--def-hp` の override は「rank 前の実数値」**: ランク補正・特性補正・道具補正・天候補正はすべて override の後にも掛かる。イカサマ用途では相手の Atk 実数値を渡せば OK (自分のランクは無視、相手の状態異常は乗る挙動を期待する場合は別途フラグ指定)
- **`--multi-hit expected` は damage では禁止**: payoff レイヤ (nash / select / meta-divergence) 専用の 19/6 期待値近似。pkdx damage で指定すると abort する
- **`resolve_hit_plan` と ParentalBond の排他性**: 連続技 × おやこあい は連続技が優先。ダブルアタック持ちメガガルーラに `--atk-ability おやこあい` を渡しても 2 回のままで、3〜4 回にはならない

---

## 9. 4096 ベースの乗数表 (参考)

Showdown 準拠の整数乗算ベース。`round5(dmg, m) = (dmg × m + 2048) / 4096` の丸め規則。

| 補正 | 値 (/4096) | 近似 |
|------|------------|------|
| STAB 通常 | 6144 | 1.5x |
| STAB テラスタル一致 | 8192 | 2.0x |
| STAB テラスタル不一致新タイプ | 6144 | 1.5x |
| 急所 | 6144 | 1.5x |
| Skin 特性 (フェアリースキン等) | 4915 | 1.2x |
| 壁 (シングル) | 2048 | 0.5x |
| 壁 (ダブル) | 2732 | ≈ 0.667x |
| テクニシャン (威力 ≤ 60) | 6144 | 1.5x |

具体的な適用順序と丸めタイミングは `damage/engine.mbt` の `compute_rolls` を直接読むこと。
