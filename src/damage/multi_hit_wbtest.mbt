///|
/// Whitebox tests for `resolve_auto_hits` and `resolve_hit_plan`. Fail until
/// `multi_hit.mbt` is implemented.

///|
fn mh_move(name : String) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
    power: 25,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
  }
}

// ---- resolve_auto_hits ----

///|
test "resolve_auto_hits: single-hit move returns SingleHit" {
  inspect(resolve_auto_hits("たいあたり"), content="SingleHit")
}

///|
test "resolve_auto_hits: にどげり returns FixedHit(2)" {
  inspect(resolve_auto_hits("にどげり"), content="FixedHit(2)")
}

///|
test "resolve_auto_hits: トリプルキック returns FixedHit(3)" {
  inspect(resolve_auto_hits("トリプルキック"), content="FixedHit(3)")
}

///|
test "resolve_auto_hits: みずしゅりけん returns Random2to5" {
  inspect(resolve_auto_hits("みずしゅりけん"), content="Random2to5")
}

///|
test "resolve_auto_hits: ロックブラスト returns Random2to5" {
  inspect(resolve_auto_hits("ロックブラスト"), content="Random2to5")
}

///|
test "resolve_auto_hits: つっぱり returns Random2to5" {
  inspect(resolve_auto_hits("つっぱり"), content="Random2to5")
}

///|
test "resolve_auto_hits: スケイルショット returns Random2to5" {
  inspect(resolve_auto_hits("スケイルショット"), content="Random2to5")
}

///|
test "resolve_auto_hits: ドラゴンアロー returns FixedHit(2)" {
  inspect(resolve_auto_hits("ドラゴンアロー"), content="FixedHit(2)")
}

///|
test "resolve_auto_hits: トリプルアクセル returns FixedHit(3)" {
  inspect(resolve_auto_hits("トリプルアクセル"), content="FixedHit(3)")
}

///|
test "resolve_auto_hits: れんぞくぎり is SingleHit (not multi-hit)" {
  // れんぞくぎり (Fury Cutter) は 1-hit で連続使用時に威力が倍増する技。
  // 以前のテーブルに誤って含まれていた false positive の regression 防止。
  inspect(resolve_auto_hits("れんぞくぎり"), content="SingleHit")
}

///|
test "resolve_auto_hits: ゴッドバード is SingleHit (2-turn charge)" {
  // ゴッドバード (Sky Attack) は 2 ターン溜め 1-hit の技。
  inspect(resolve_auto_hits("ゴッドバード"), content="SingleHit")
}

// ---- resolve_hit_plan ----

///|
test "resolve_hit_plan: single-hit + no ability + Auto → Single" {
  let mv = mh_move("たいあたり")
  inspect(
    resolve_hit_plan(mv, "", @model.MultiHit::Auto),
    content="Single",
  )
}

///|
test "resolve_hit_plan: fixed-2 base + Auto → FixedHits(2)" {
  let mv = mh_move("にどげり")
  inspect(
    resolve_hit_plan(mv, "", @model.MultiHit::Auto),
    content="FixedHits(2)",
  )
}

///|
test "resolve_hit_plan: random 2-5 without Skill Link → FixedHits(3)" {
  // Auto の Random2to5 は実際の期待値 (19/6 ≈ 3.17) に近い中央値 3 で解決
  // する (Plan の簡便化ルート)。
  let mv = mh_move("みずしゅりけん")
  inspect(
    resolve_hit_plan(mv, "", @model.MultiHit::Auto),
    content="FixedHits(3)",
  )
}

///|
test "resolve_hit_plan: random 2-5 with Skill Link → FixedHits(5)" {
  let mv = mh_move("みずしゅりけん")
  inspect(
    resolve_hit_plan(mv, "スキルリンク", @model.MultiHit::Auto),
    content="FixedHits(5)",
  )
}

///|
test "resolve_hit_plan: explicit Fixed(n) overrides auto resolution" {
  let mv = mh_move("たいあたり")
  inspect(
    resolve_hit_plan(mv, "", @model.MultiHit::Fixed(5)),
    content="FixedHits(5)",
  )
}

///|
test "resolve_hit_plan: Parental Bond fires on single-hit base move" {
  let mv = mh_move("たいあたり")
  inspect(
    resolve_hit_plan(mv, "おやこあい", @model.MultiHit::Auto),
    content="ParentalBond",
  )
}

///|
test "resolve_hit_plan: Parental Bond skipped on multi-hit base move" {
  // Parental Bond does not apply to moves that are already multi-hit.
  let mv = mh_move("みずしゅりけん")
  inspect(
    resolve_hit_plan(mv, "おやこあい", @model.MultiHit::Auto),
    content="FixedHits(3)",
  )
}

///|
test "resolve_hit_plan: Fixed(0) clamps to FixedHits(1)" {
  let mv = mh_move("たいあたり")
  // Defensive: 0 hits is a degenerate input; engine should still produce a
  // usable plan rather than divide-by-zero downstream.
  inspect(
    resolve_hit_plan(mv, "", @model.MultiHit::Fixed(0)),
    content="FixedHits(1)",
  )
}
