# 零和ゲーム LP の理論的背景

> **このドキュメントは外部 repo `ushironoko/nash-mbt` に移行済みです。**
>
> 一次資料: <https://github.com/pkdxtools/nash-mbt/blob/main/docs/theory.md>
>
> 内容: ミニマックス定理 / 零和 LP 等価性 / shift-and-normalize / 2-phase
> Simplex + Bland's rule / Fictitious play / MWU / 数値公差。
>
> Nash ソルバー本体 (`solve_zero_sum` / `simplex` / `fictitious_play` /
> `mwu`) は mooncakes パッケージ `ushironoko/nash-mbt` として独立配布
> されており、pkdx は `moon.mod.json` の deps からバージョンを指定して
> 参照する (現在の pin は `moon.mod.json` を確認)。

## pkdx 固有の使い方

pkdx ドメインで Nash ソルバーを呼ぶ際の流れは以下:

1. `src/payoff/` (Layer 2) が `FiniteMatrix` を構築
2. `@nash.solve_zero_sum(matrix)` を呼ぶ
3. 戻り値の `LpResult::Optimal(value, row_strategy, col_strategy)` を
   `pkdx nash solve` / `pkdx select` の JSON 出力に整形

`pkdx meta-divergence` はこのフローには乗らず、`@nash.solve_zero_sum` を呼ばない。
`cli_meta.mbt` が `usage` (実使用率 σ) と `matrix` から `Aσ` / `σᵀAσ` /
per-action regret / max row regret を直接計算する片側指標であり、詳細は
[`exploitability.md`](exploitability.md) を参照。

Layer 2 の payoff 構築 (SwitchingGame / ScreenedSwitchingGame) は
[`payoff_semantics.md`](payoff_semantics.md) を参照。
