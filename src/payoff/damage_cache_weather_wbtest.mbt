///|
/// Stage B (healing-moves plan): the L1 damage cache wrappers
/// (`mean_damage_cached` / `damage_variants_cached`) must accept a `weather~`
/// keyword and thread it through to `compute_mean_damage` /
/// `compute_damage_variants` → `build_input_with_ranks`. Without this:
///   - `state.weather` set by Sunny Day / Rain Dance never reaches the
///     damage engine, so Sun → fire 1.5x and Rain → water 1.5x silently
///     reduce to ×1.0 in every DP recursion that goes through the cache.
///   - Cache key is enriched in Stage B-3; without weather in the key,
///     a single matchup keyed under Weather::None would shadow the
///     post-Sunny-Day recomputation forever.
///
/// This whitebox test exercises only the wiring contract:
///   1. Different `weather~` values yield different cached values for a
///      weather-sensitive move (fire under Sun vs None).
///   2. The default (weather omitted) matches `weather=Weather::None`
///      so existing callers stay green during the migration window.
///
/// We bypass the L2 disk to keep the test deterministic & cache-isolated.

///|
fn dcw_atk() -> Combatant {
  let p = mk_pokemon("リザードン", "ほのお", "ひこう", 100, 100, 100, 200, 100, 100)
  mk_combatant(p, [mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)])
}

///|
fn dcw_dfn() -> Combatant {
  let p = mk_pokemon("ガブリアス", "ドラゴン", "じめん", 200, 100, 100, 100, 100, 100)
  mk_combatant(p, [mk_move("じしん", "じめん", @model.Physical, 100)])
}

///|
test "mean_damage_cached: weather~ argument propagates Sun multiplier to fire move (B-2)" {
  let atk = dcw_atk()
  let dfn = dcw_dfn()
  let my_team = [atk]
  let opp_team = [dfn]
  let zero = [0, 0, 0, 0, 0]

  // Baseline: Weather::None — engine sees flat 1.0× weather modifier.
  let cache_none = new_damage_cache()
  let d_none = mean_damage_cached(
    cache_none, true, 0, zero, 0, zero, 0, my_team, opp_team,
    weather=@model.Weather::None,
  )
  assert_true(d_none > 0)

  // Sun: fire moves are boosted by ×1.5 in @damage.calc_damage.
  let cache_sun = new_damage_cache()
  let d_sun = mean_damage_cached(
    cache_sun, true, 0, zero, 0, zero, 0, my_team, opp_team,
    weather=@model.Weather::Sun,
  )
  // Wiring contract: Sun must strictly exceed None for a fire move,
  // proving `weather` reached @damage.calc_damage instead of being
  // silently dropped at the cache boundary.
  assert_true(d_sun > d_none)

  // Default (weather omitted) must equal explicit Weather::None so
  // pre-Stage-B callers' semantics are preserved during migration.
  let cache_default = new_damage_cache()
  let d_default = mean_damage_cached(
    cache_default, true, 0, zero, 0, zero, 0, my_team, opp_team,
  )
  @debug.assert_eq(d_default, d_none)
}

///|
test "damage_variants_cached: weather~ argument propagates Sun multiplier (B-2)" {
  let atk = dcw_atk()
  let dfn = dcw_dfn()
  let my_team = [atk]
  let opp_team = [dfn]
  let zero = [0, 0, 0, 0, 0]
  let cache_none = new_damage_cache()
  let vs_none = damage_variants_cached(
    cache_none, true, 0, zero, 0, zero, 0, my_team, opp_team,
    weather=@model.Weather::None,
  )
  let cache_sun = new_damage_cache()
  let vs_sun = damage_variants_cached(
    cache_sun, true, 0, zero, 0, zero, 0, my_team, opp_team,
    weather=@model.Weather::Sun,
  )
  // Single-variant fire move — compare the means directly.
  assert_true(vs_none.length() == 1)
  assert_true(vs_sun.length() == 1)
  assert_true(vs_sun[0].mean_damage > vs_none[0].mean_damage)
}

///|
/// Stage B-3: DamageKey (L1 cache key) must include weather so that toggling
/// state.weather across two cached lookups in the SAME cache produces TWO
/// distinct entries (and TWO different values for weather-sensitive moves).
/// Without weather in the key, the first lookup's mean would be cached under
/// a weather-agnostic key and the second lookup would silently return the
/// stale value — defeating Stage B's wiring goal in the recursion-shared
/// cache path used by switching_game_turn.
///
/// Red→Green: count cache misses across two lookups with different weathers
/// against the same cache. Expectation post-B-3 is exactly two misses (one
/// per weather) plus zero hits.
test "mean_damage_cached: weather differentiates L1 cache key (B-3)" {
  let atk = dcw_atk()
  let dfn = dcw_dfn()
  let my_team = [atk]
  let opp_team = [dfn]
  let zero = [0, 0, 0, 0, 0]
  let cache = new_damage_cache()
  let d_none = mean_damage_cached(
    cache, true, 0, zero, 0, zero, 0, my_team, opp_team,
    weather=@model.Weather::None,
  )
  let misses_after_first = cache.misses
  let d_sun = mean_damage_cached(
    cache, true, 0, zero, 0, zero, 0, my_team, opp_team,
    weather=@model.Weather::Sun,
  )
  // Different weather → distinct cached entries, so Sun lookup must be a
  // miss (not a hit-against-the-None entry).
  @debug.assert_eq(cache.misses, misses_after_first + 1)
  // And the cached values must agree with what B-2 already proved (Sun
  // strictly larger for a fire move). If the key collided, d_sun would
  // equal d_none here.
  assert_true(d_sun > d_none)
  // Repeating the same weather should now be a hit, not another miss —
  // proves the encode-then-lookup path is consistent within one weather.
  let hits_before = cache.hits
  let d_sun_again = mean_damage_cached(
    cache, true, 0, zero, 0, zero, 0, my_team, opp_team,
    weather=@model.Weather::Sun,
  )
  @debug.assert_eq(d_sun_again, d_sun)
  @debug.assert_eq(cache.hits, hits_before + 1)
}

///|
/// Stage F-3/F-4: the L1 damage cache wrappers must accept a `field~`
/// keyword and thread it through `compute_mean_damage` → `build_input_with_
/// ranks` → engine. Without this, `state.field` set by Electric/Grassy/
/// Psychic Terrain never reaches @damage.calc_damage and the 1.3x boost
/// (and 0.5x Grassy じしん debuff) silently degrade to ×1.0 inside the
/// recursion-shared cache path used by switching_game_turn.
///
/// Wiring contract: Electric field strictly boosts a でんき move via the
/// 5325/4096 multiplier; default (no field~) must equal explicit
/// Field::None.
test "mean_damage_cached: field~ argument propagates Electric boost to でんき move (F-3)" {
  // Pikachu-like Electric attacker (grounded — no ひこう / ふゆう / ふうせん)
  // vs Garchomp-like ground/dragon defender (grounded for damage purposes:
  // 4x electric immunity is via type chart, but we use a non-immune
  // defender so the boost actually shows).
  let atk_p = mk_pokemon("Test-E", "でんき", "", 100, 100, 100, 200, 100, 100)
  let atk = mk_combatant(
    atk_p, [mk_move("10まんボルト", "でんき", @model.Special, 90)],
  )
  let dfn_p = mk_pokemon("Test-W", "みず", "", 200, 100, 100, 100, 100, 100)
  let dfn = mk_combatant(dfn_p, [mk_move("たいあたり", "ノーマル", @model.Physical, 40)])
  let my_team = [atk]
  let opp_team = [dfn]
  let zero = [0, 0, 0, 0, 0]
  //
  let cache_none = new_damage_cache()
  let d_none = mean_damage_cached(
    cache_none, true, 0, zero, 0, zero, 0, my_team, opp_team,
    field=@model.Field::None,
  )
  assert_true(d_none > 0)
  //
  let cache_electric = new_damage_cache()
  let d_electric = mean_damage_cached(
    cache_electric, true, 0, zero, 0, zero, 0, my_team, opp_team,
    field=@model.Field::Electric,
  )
  // Wiring contract: Electric must strictly exceed None for a grounded
  // でんき attacker, proving `field` reached @damage.calc_damage.
  assert_true(d_electric > d_none)
  //
  let cache_default = new_damage_cache()
  let d_default = mean_damage_cached(
    cache_default, true, 0, zero, 0, zero, 0, my_team, opp_team,
  )
  @debug.assert_eq(d_default, d_none)
}

///|
/// Stage F-4: DamageKey must include `field` so toggling state.field across
/// two cached lookups in the SAME cache produces TWO distinct entries.
/// Without field in the key, the first lookup's mean would be cached under
/// a field-agnostic key and the second lookup would silently return the
/// stale value, defeating Stage F's wiring goal in the recursion-shared
/// cache path used by switching_game_turn.
///
/// Red→Green: count cache misses across two lookups with different fields
/// against the same cache. Expectation post-F-4 is exactly two misses (one
/// per field) plus zero hits.
test "mean_damage_cached: field differentiates L1 cache key (F-4)" {
  let atk_p = mk_pokemon("Test-E", "でんき", "", 100, 100, 100, 200, 100, 100)
  let atk = mk_combatant(
    atk_p, [mk_move("10まんボルト", "でんき", @model.Special, 90)],
  )
  let dfn_p = mk_pokemon("Test-W", "みず", "", 200, 100, 100, 100, 100, 100)
  let dfn = mk_combatant(dfn_p, [mk_move("たいあたり", "ノーマル", @model.Physical, 40)])
  let my_team = [atk]
  let opp_team = [dfn]
  let zero = [0, 0, 0, 0, 0]
  let cache = new_damage_cache()
  let d_none = mean_damage_cached(
    cache, true, 0, zero, 0, zero, 0, my_team, opp_team,
    field=@model.Field::None,
  )
  let misses_after_first = cache.misses
  let d_electric = mean_damage_cached(
    cache, true, 0, zero, 0, zero, 0, my_team, opp_team,
    field=@model.Field::Electric,
  )
  // Different field → distinct cached entries, so Electric lookup must be
  // a miss (not a hit-against-the-None entry).
  @debug.assert_eq(cache.misses, misses_after_first + 1)
  // And the cached values must differ (Electric strictly larger). If the
  // key collided, d_electric would equal d_none here.
  assert_true(d_electric > d_none)
  // Repeating the same field should now be a hit, not another miss.
  let hits_before = cache.hits
  let d_electric_again = mean_damage_cached(
    cache, true, 0, zero, 0, zero, 0, my_team, opp_team,
    field=@model.Field::Electric,
  )
  @debug.assert_eq(d_electric_again, d_electric)
  @debug.assert_eq(cache.hits, hits_before + 1)
}

///|
/// Stage F-4: `field_to_cache_key` jp-label encoding pin. Centralized helper
/// — assert each variant maps to its canonical jp label (mirroring the
/// inline weather match in `combatant_to_cache_key_input`). Field::None
/// collapses to "" so pre-Stage-F disk entries remain readable.
test "field_to_cache_key: each variant has a distinct jp label (F-4)" {
  @debug.assert_eq(field_to_cache_key(@model.Field::None), "")
  @debug.assert_eq(field_to_cache_key(@model.Field::Electric), "エレキ")
  @debug.assert_eq(field_to_cache_key(@model.Field::Grassy), "グラス")
  @debug.assert_eq(field_to_cache_key(@model.Field::Misty), "ミスト")
  @debug.assert_eq(field_to_cache_key(@model.Field::Psychic), "サイコ")
}
