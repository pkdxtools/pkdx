///|
test "move_priority_known_priority_plus_one_moves" {
  assert_eq(move_priority("バレットパンチ"), 1)
  assert_eq(move_priority("こおりのつぶて"), 1)
  assert_eq(move_priority("アクアジェット"), 1)
  assert_eq(move_priority("かげうち"), 1)
  assert_eq(move_priority("マッハパンチ"), 1)
}

///|
test "move_priority_known_priority_plus_two_and_higher" {
  assert_eq(move_priority("しんそく"), 2)
  assert_eq(move_priority("ねこだまし"), 3)
  assert_eq(move_priority("まもる"), 4)
  assert_eq(move_priority("みきり"), 4)
}

///|
test "move_priority_unknown_move_defaults_to_zero" {
  assert_eq(move_priority("じしん"), 0)
  assert_eq(move_priority("10まんボルト"), 0)
  assert_eq(move_priority(""), 0)
}

///|
test "stat_boost_effect_sword_dance_a_plus_two" {
  match stat_boost_effect("つるぎのまい") {
    Some(effs) => {
      assert_eq(effs.length(), 1)
      assert_eq(effs[0], (0, 2))
    }
    None => assert_true(false)
  }
}

///|
test "stat_boost_effect_dragon_dance_a_plus_one_s_plus_one" {
  match stat_boost_effect("りゅうのまい") {
    Some(effs) => {
      assert_eq(effs.length(), 2)
      assert_eq(effs[0], (0, 1))
      assert_eq(effs[1], (4, 1))
    }
    None => assert_true(false)
  }
}

///|
test "stat_boost_effect_shell_smash_mixed_ups_and_downs" {
  match stat_boost_effect("からをやぶる") {
    Some(effs) => {
      assert_eq(effs.length(), 5)
      // A+2, C+2, S+2, B-1, D-1
      let mut sum = 0
      for eff in effs {
        let (_, d) = eff
        sum += d
      }
      assert_eq(sum, 4)
    }
    None => assert_true(false)
  }
}

///|
test "stat_boost_effect_damaging_move_returns_none" {
  match stat_boost_effect("じしん") {
    Some(_) => assert_true(false)
    None => ()
  }
}

///|
test "clamp_rank_collapses_to_two_and_minus_two" {
  assert_eq(clamp_rank(0), 0)
  assert_eq(clamp_rank(1), 1)
  assert_eq(clamp_rank(2), 2)
  assert_eq(clamp_rank(3), 2)
  assert_eq(clamp_rank(99), 2)
  assert_eq(clamp_rank(-1), -1)
  assert_eq(clamp_rank(-2), -2)
  assert_eq(clamp_rank(-3), -2)
  assert_eq(clamp_rank(-99), -2)
}

///|
test "effective_speed_positive_ranks_scale_correctly" {
  // +1 = ×1.5, +2 = ×2.0
  assert_eq(effective_speed(100, 0), 100)
  assert_eq(effective_speed(100, 1), 150)
  assert_eq(effective_speed(100, 2), 200)
}

///|
test "effective_speed_negative_ranks_scale_correctly" {
  // -1 = ÷1.5 ≈ ×0.667, -2 = ÷2 = ×0.5
  assert_eq(effective_speed(100, -1), 66)
  assert_eq(effective_speed(100, -2), 50)
}

///|
test "turn_order_sign_priority_beats_higher_speed" {
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 50),
    [mk_move("バレットパンチ", "はがね", @model.Physical, 40)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 200),
    [mk_move("じしん", "じめん", @model.Physical, 100)],
  )
  // a is slower (50 < 200) but uses +1 priority; it should act first.
  assert_eq(turn_order_sign(a, 1, 50, b, 0, 200), 1)
  // Symmetric: b first when no priority edge.
  assert_eq(turn_order_sign(a, 0, 50, b, 0, 200), -1)
  // Equal priority + same speed → tie.
  assert_eq(turn_order_sign(a, 0, 100, b, 0, 100), 0)
}

///|
test "turn_order_sign_higher_priority_dominates_lower_priority" {
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("ねこだまし", "ノーマル", @model.Physical, 40)],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [mk_move("バレットパンチ", "はがね", @model.Physical, 40)],
  )
  // +3 (ねこだまし) beats +1 (バレットパンチ).
  assert_eq(turn_order_sign(a, 3, 100, b, 1, 100), 1)
}

///|
test "load_move_meta_from_rows_populates_cache_for_queried_names" {
  let cache = new_move_meta_cache()
  load_move_meta_from_rows(cache, [
    ("つるぎのまい", 0, "[[0,2]]"),
    ("バレットパンチ", 1, "[]"),
  ])
  // lookup_priority prefers the cache (hit), not the fallback.
  assert_eq(lookup_priority(cache, "バレットパンチ"), 1)
  assert_eq(cache.hits, 1)
  // つるぎのまい has priority 0 in the DB; stat_effects hit the cache.
  let effs = lookup_stat_effects(cache, "つるぎのまい")
  assert_eq(effs.length(), 1)
  assert_eq(effs[0], (0, 2))
}

///|
test "lookup_priority_misses_fall_back_to_curated_table_and_bump_counters" {
  // Fresh empty cache: curated fallback for known moves should still fire.
  let cache = new_move_meta_cache()
  assert_eq(lookup_priority(cache, "しんそく"), 2)
  assert_eq(cache.misses, 1)
  assert_eq(cache.fallbacks, 1)
  // Unknown name: fallback returns 0 but does NOT count as a fallback hit.
  assert_eq(lookup_priority(cache, "存在しない技"), 0)
  assert_eq(cache.misses, 2)
  assert_eq(cache.fallbacks, 1)
}

///|
test "lookup_stat_effects_prefers_cache_over_curated_table" {
  // Cache entry differs from curated table for the same name — cache wins.
  let cache = new_move_meta_cache()
  load_move_meta_from_rows(cache, [("つるぎのまい", 0, "[[0,1]]")])
  let effs = lookup_stat_effects(cache, "つるぎのまい")
  assert_eq(effs.length(), 1)
  // Cached value is +1 (test override), curated is +2.
  assert_eq(effs[0], (0, 1))
}

///|
test "load_move_meta_from_rows_tolerates_malformed_json" {
  // Malformed JSON for stat_effects must not abort — entry is kept with an
  // empty effects list so one corrupt DB row cannot break a whole run.
  let cache = new_move_meta_cache()
  load_move_meta_from_rows(cache, [
    ("ブロークンJSON", 3, "[not-a-valid-json"),
  ])
  let effs = lookup_stat_effects(cache, "ブロークンJSON")
  assert_eq(effs.length(), 0)
  assert_eq(lookup_priority(cache, "ブロークンJSON"), 3)
}

///|
test "collect_move_names_dedupes_across_teams" {
  let a = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [
      mk_move("じしん", "じめん", @model.Physical, 100),
      mk_move("つるぎのまい", "ノーマル", @model.Status, 0),
    ],
  )
  let b = mk_combatant(
    mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 100),
    [
      mk_move("じしん", "じめん", @model.Physical, 100),
      mk_move("バレットパンチ", "はがね", @model.Physical, 40),
    ],
  )
  let names = collect_move_names([a, b], [a])
  // じしん appears twice (a and b share it); dedupe removes one.
  assert_eq(names.length(), 3)
}
