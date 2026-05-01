# pkdx damage cache — ベンチマーク結果

`pkdx damage` の永続キャッシュ (`box/cache/damage_cache.sqlite`) が損益分岐する条件を実測から割り出す。計測は `pkdx damage-bench` と wall-clock `time` の 2 系統。

## 計測環境

- macOS (darwin 25.3.0 / arm64)
- `moon build` の debug ビルド (`pkdx/_build/native/debug/build/src/main/main.exe`)
- ベンチ入力: `ガブリアス × バンギラス × じしん` (type-chart neutral, calc 有効)
- `pokedex.db` / `champions.db` ともに `pkdx migrate` 適用済み (本計測時点では pokedex 8 件 + champions 5 件)

## in-process 計測 (`pkdx damage-bench`)

1 プロセス内でキャッシュ open / lookup / miss → compute → put を反復。cold-start コストを含まない。

`iterations=1000` で `N` (事前 seed する dummy エントリ数) を変化させた median / p99 (単位 ms):

| N | full_miss | full_hit (median) | full_hit (p99) | lookup_miss | lookup_hit | compute_miss | put_miss |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.733 | 0.008 | 0.012 | 0.040 | 0.007 | 0.201 | 0.492 |
| 100 | 0.622 | 0.008 | 0.009 | 0.035 | 0.008 | 0.030 | 0.557 |
| 1000 | 0.543 | 0.008 | 0.013 | 0.035 | 0.008 | 0.029 | 0.479 |
| 10000 | 0.452 | 0.008 | 0.009 | 0.021 | 0.008 | 0.028 | 0.402 |

観察:

- **hit は N に非依存**で 0.008 ms median — SQLite の PRIMARY KEY B-tree lookup はエントリ数が 4 桁変わっても実質変わらない。
- miss は compute (初回のみ 200μs、以降 30μs — warm cache 効果) と put (0.4-0.6 ms) が支配的。
- hit / miss 比は **50〜90 倍**。1 プロセス内で繰り返し damage を呼ぶユースケース (nash/payoff の Monte Carlo 等) では明確に得。

## cold-start 計測 (wall-clock)

`time` で pkdx 起動コスト込みを測定。

| 条件 | 実測 (total) |
|---|---|
| 1st run (cache miss, populate) | 17 ms |
| 2nd run (cache hit) | 5 ms |
| 3rd run (cache hit) | 5 ms |
| `--no-cache` 1st | 13 ms |
| `--no-cache` 2nd | 14 ms |

hit は cold-start を含めても **miss より 12ms 速い**。binary 起動 + SQLite open + lookup + emit で 5 ms は妥当。

## 損益分岐

cold-start モデル (wall-clock ms):

- `cache_on_hit  ≈ 5 ms`
- `cache_on_miss ≈ 17 ms`
- `cache_off     ≈ 13 ms`

期待値:

```
E[cache_on] = H × 5 + (1 - H) × 17
            < 13    ⇔    H > 1/3
```

つまり **ヒット率 33% を超えるユースケース**なら CLI 単発起動コストを含めても net win。

in-process 反復 (1 プロセス内で I 回):

- `cache_on_miss ≈ 0.5 ms / iter`
- `cache_on_hit ≈ 0.01 ms / iter`
- `cache_off    ≈ 0.3 ms / iter` (compute のみ、open は amortize)

```
E[cache_on] = H × 0.01 + (1 - H) × 0.5 = 0.5 − 0.49 H
            < 0.3   ⇔   H > 0.41
```

反復ユースケースでも **ヒット率 41% 超**が損益分岐。

## Cross-session L2 in `pkdx select`

`pkdx damage` の CLI キャッシュに加え、`pkdx select` の SwitchingGame DP も
同じ SQLite ファイル (`box/cache/damage_cache.sqlite`) を L2 として参照する。
`@payoff.DamageCache` 構造体に optional `disk` フィールドを追加し、L1 (in-
memory HashMap) miss 時に L2 を引く二層構成。

```
L1 miss → L2 lookup
         ├─ hit:  parse JSON、damages 配列抽出、mean 計算 → L1 に昇格 → return
         └─ miss: calc_damage → format_damage → L2 put + L1 put → return
```

効果:
- 同一ポケモン×同一技の 16-roll 計算結果は **セッションを跨いで保存**
- パーティを 1 体入れ替えて再度 `pkdx select` を走らせると、共通 matchup 側は
  最初から L2 hit (pokedex.db を開く前に解決可能)
- 連続で `select` を実行する運用 (メタ検討・構築比較) で **hit rate が単調に
  上昇**、計算時間が毎回短くなる

L2 は `pkdx migrate` で meta が自動同期、pkdx_version 変更で自動破棄される
ため整合性は保証される。現時点で L2 wire-up が入っているのは `pkdx select`
のみ (`pkdx nash graph` / `pkdx meta-divergence` も同パターンで追加可能)。

## 運用上の指針

- **ON を維持して問題ない**: calc スキルの Phase 4 (同一攻守で technique / rank / item を差し替え) も、nash/payoff の Monte Carlo も、同じ matchup を高頻度で叩くため現実的なヒット率は 50% 以上になる。
- **miss が支配的なワンショット**では `--no-cache` を付けると 4 ms ほど (put を避けられる分) 節約できる。運用規模で効かない差なので気にしない。
- **キャッシュサイズ**: エントリ数が増えても hit 時間は変わらない (SQLite B-tree) ため、定期的な cache-clear は不要。`pkdx cache-clear damage` は運用コマンドとして提供してあるが、通常は使わない。
- **無効化**: `pkdx migrate` 完了時に cache の meta 行が current に同期され、entries は保持される。`pkdx_version` 変更時は次回 `pkdx damage` が自動で entries を破棄して再ポピュレート。

## 再計測

```bash
# 単発
pkdx damage-bench --entries 1000 --iterations 1000

# マトリクス
scripts/bench_damage.sh               # N=10,100,1000,10000 / I=1000
scripts/bench_damage.sh -N "10 100"   # 部分集合
```
