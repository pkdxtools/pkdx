///|
/// Whitebox tests: every factor that `compute_mean_damage` ultimately feeds
/// into `@damage.calc_damage` must be reflected in the L2 cache key built
/// by `combatant_to_cache_key_input`. Without this net, two distinct matchup
/// states that only differ on a factor the cache key forgot to encode would
/// collapse to the same SQLite entry — so `pkdx select` could hand back a
/// stale winrate from a previous session.
///
/// Each test toggles exactly one damage-affecting input and asserts the
/// resulting v1 key differs. The canonicalized-to-constant fields
/// (`weather`, `field`, `critical`, `is_double`, `fainted_count`) are not
/// probed here — payoff never varies them, so they are a correctness-by-
/// -construction contract documented on `combatant_to_cache_key_input`.

///|
/// Local helpers — the shared `mk_*` fixtures live in `test_helpers_test.mbt`,
/// which is only visible to blackbox `_test.mbt` files. This file is a
/// whitebox test (`_wbtest.mbt`) so we inline minimal constructors here.
fn ck_pokemon(name : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1: "ほのお",
    type2: "",
    hp: 100,
    atk: 150,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 120,
    bst: 670,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 0.0,
    forms: [],
  }
}

///|
fn ck_move(name : String) -> @model.Move {
  {
    name,
    type_: "ほのお",
    category: @model.Physical,
    power: 80,
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
    healing: None,
    weather_set: None,
    field_set: None,
  }
}

///|
fn ck_combatant(
  pokemon : @model.Pokemon,
  moves : Array[@model.Move],
) -> Combatant {
  {
    pokemon,
    moves,
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
}

///|
fn base_atk() -> Combatant {
  {
    ..ck_combatant(ck_pokemon("A"), [ck_move("mv")]),
    ability: "もうか",
    item: "いのちのたま",
    tera_type: "ほのお",
  }
}

///|
fn base_def() -> Combatant {
  {
    ..ck_combatant(ck_pokemon("B"), [ck_move("mv")]),
    ability: "げきりゅう",
    item: "とつげきチョッキ",
  }
}

///|
fn base_move() -> @model.Move {
  ck_move("mv")
}

///|
/// Build the v1 cache key or `fail` — mirrors the `guard is Ok else fail`
/// idiom used throughout `damage_cache/cache_key_test.mbt`, but wraps the
/// Combatant-flavored call so each test below reads as one assertion line.
fn key_of(
  atk : Combatant,
  dfn : Combatant,
  mv : @model.Move,
  atk_rank? : Int = 0,
  def_rank? : Int = 0,
  weather? : @model.Weather = @model.Weather::None,
  atk_protean_locked? : String = "",
  def_protean_locked? : String = "",
) -> String raise {
  let input = combatant_to_cache_key_input(
    atk,
    dfn,
    mv,
    atk_rank,
    def_rank,
    weather~,
    atk_protean_locked~,
    def_protean_locked~,
  )
  guard @damage_cache.build_cache_key(input) is Ok(k) else {
    fail("build_cache_key failed")
  }
  k
}

///|
test "cache key: ability swap on attacker distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let a2 = { ..a, ability: "すなのちから" }
  assert_true(key_of(a, b, mv) != key_of(a2, b, mv))
}

///|
test "cache key: ability swap on defender distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let b2 = { ..b, ability: "ちょすい" }
  assert_true(key_of(a, b, mv) != key_of(a, b2, mv))
}

///|
test "cache key: item swap on attacker distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let a2 = { ..a, item: "こだわりハチマキ" }
  assert_true(key_of(a, b, mv) != key_of(a2, b, mv))
}

///|
test "cache key: item swap on defender distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let b2 = { ..b, item: "たべのこし" }
  assert_true(key_of(a, b, mv) != key_of(a, b2, mv))
}

///|
test "cache key: attacker tera type distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let a2 = { ..a, tera_type: "みず" }
  assert_true(key_of(a, b, mv) != key_of(a2, b, mv))
}

///|
test "cache key: move name distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv1 = ck_move("mv1")
  let mv2 = ck_move("mv2")
  assert_true(key_of(a, b, mv1) != key_of(a, b, mv2))
}

///|
test "cache key: attacker species name distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let a2 = { ..a, pokemon: ck_pokemon("A2") }
  assert_true(key_of(a, b, mv) != key_of(a2, b, mv))
}

///|
test "cache key: defender species name distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let b2 = { ..b, pokemon: ck_pokemon("B2") }
  assert_true(key_of(a, b, mv) != key_of(a, b2, mv))
}

///|
test "cache key: atk_rank distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  assert_true(key_of(a, b, mv, atk_rank=0) != key_of(a, b, mv, atk_rank=2))
}

///|
test "cache key: def_rank distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  assert_true(key_of(a, b, mv, def_rank=0) != key_of(a, b, mv, def_rank=-1))
}

///|
test "cache key: attacker actual_stats override distinguishes the key" {
  // Physical move → build_input_with_ranks reads attacker A (index 1).
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let a1 = { ..a, actual_stats: Some([200, 180, 100, 100, 100, 130]) }
  let a2 = { ..a, actual_stats: Some([200, 200, 100, 100, 100, 130]) }
  assert_true(key_of(a1, b, mv) != key_of(a2, b, mv))
}

///|
test "cache key: defender actual_stats override distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  // Physical move → defender B (index 2) varies.
  let b1 = { ..b, actual_stats: Some([205, 100, 120, 100, 100, 80]) }
  let b2 = { ..b, actual_stats: Some([205, 100, 160, 100, 100, 80]) }
  assert_true(key_of(a, b1, mv) != key_of(a, b2, mv))
}

///|
test "cache key: defender HP override distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let b_lo = { ..b, actual_stats: Some([180, 100, 120, 100, 100, 80]) }
  let b_hi = { ..b, actual_stats: Some([220, 100, 120, 100, 100, 80]) }
  assert_true(key_of(a, b_lo, mv) != key_of(a, b_hi, mv))
}

///|
test "cache key: attacker nature distinguishes the key" {
  let a_none = base_atk()
  let b = base_def()
  let mv = base_move()
  let a_adamant = { ..a_none, nature: @model.nature_from_ja("いじっぱり") }
  let a_modest = { ..a_none, nature: @model.nature_from_ja("ひかえめ") }
  // None vs Some distinguishes.
  assert_true(key_of(a_none, b, mv) != key_of(a_adamant, b, mv))
  // Two distinct natures distinguish.
  assert_true(key_of(a_adamant, b, mv) != key_of(a_modest, b, mv))
}

///|
test "cache key: defender nature distinguishes the key" {
  let a = base_atk()
  let b_none = base_def()
  let mv = base_move()
  let b_bold = { ..b_none, nature: @model.nature_from_ja("ずぶとい") }
  let b_impish = { ..b_none, nature: @model.nature_from_ja("わんぱく") }
  assert_true(key_of(a, b_none, mv) != key_of(a, b_bold, mv))
  assert_true(key_of(a, b_bold, mv) != key_of(a, b_impish, mv))
}

///|
test "cache key: stat_system (Champions vs Standard) distinguishes the key" {
  let a_std = base_atk()
  let b = base_def()
  let mv = base_move()
  let a_champ = { ..a_std, stat_system: @model.Champions }
  // `combatant_to_cache_key_input` reads the attacker's stat_system only,
  // so toggling it on the attacker must change the version component and
  // therefore the key.
  assert_true(key_of(a_std, b, mv) != key_of(a_champ, b, mv))
}

///|
/// Sanity: identical inputs must yield identical keys. If this ever starts
/// failing the cache key has gained a non-deterministic component.
test "cache key: two identical matchup calls produce identical keys" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  @debug.assert_eq(key_of(a, b, mv), key_of(a, b, mv))
}

///|
/// Stage B-3: weather distinguishes the L2 cache key. Each Weather variant
/// must map to a distinct CLI-shaped string so disk entries written by
/// `pkdx damage --weather はれ` and by the payoff layer's Sun branch share
/// identity, and so Weather::None / Sun / Rain / Sand / Snow can coexist in
/// the SQLite cache for one matchup. Pairs `Weather::None` against each
/// active weather so a regression that collapses one variant back to "" is
/// caught directly.
test "cache key: weather variants each distinguish the key (B-3)" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  let k_none = key_of(a, b, mv, weather=@model.Weather::None)
  let k_sun = key_of(a, b, mv, weather=@model.Weather::Sun)
  let k_rain = key_of(a, b, mv, weather=@model.Weather::Rain)
  let k_sand = key_of(a, b, mv, weather=@model.Weather::Sand)
  let k_snow = key_of(a, b, mv, weather=@model.Weather::Snow)
  assert_true(k_none != k_sun)
  assert_true(k_none != k_rain)
  assert_true(k_none != k_sand)
  assert_true(k_none != k_snow)
  // Pairwise distinctness across active weathers — guards against two
  // labels collapsing to the same string (e.g. typo'd "はれ" / "あめ").
  assert_true(k_sun != k_rain)
  assert_true(k_sun != k_sand)
  assert_true(k_sun != k_snow)
  assert_true(k_rain != k_sand)
  assert_true(k_rain != k_snow)
  assert_true(k_sand != k_snow)
}

///|
/// Stage 6 (protean-libero): attacker の Protean/Libero ロックタイプは
/// `effective_combatant` が type1/type2 を override しダメージを変えるが、
/// name_ja は不変なので attacker トークンだけでは衝突する。未ロック ("") と
/// ほのおロックで L2 key が分離することを pin する。
test "cache key: attacker protean lock distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  assert_true(
    key_of(a, b, mv, atk_protean_locked="") !=
    key_of(a, b, mv, atk_protean_locked="ほのお"),
  )
}

///|
/// 異なるロックタイプ同士 (ほのお vs みず) も別キーへ分離する — 1 つのトークンへ
/// 全ロックが畳まれる regression を直接捕捉する。
test "cache key: distinct attacker locked types distinguish the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  assert_true(
    key_of(a, b, mv, atk_protean_locked="ほのお") !=
    key_of(a, b, mv, atk_protean_locked="みず"),
  )
}

///|
/// defender 側ロックも独立して key を分ける (両側トークンが同じ segment に
/// 縮退していないことの担保)。
test "cache key: defender protean lock distinguishes the key" {
  let a = base_atk()
  let b = base_def()
  let mv = base_move()
  assert_true(
    key_of(a, b, mv, def_protean_locked="") !=
    key_of(a, b, mv, def_protean_locked="ほのお"),
  )
}

// ─── SwitchingGameState Hash 完全性 (stage 2: healing infra) ──────────────────
//
// Plan K-4: each new state field added in stage 2 (weather / weather_turns_left
// / my_leech_seeded / opp_leech_seeded / my_wish_turns / opp_wish_turns) must
// be part of the derive(Hash) so the DP memoisation cache does not collide
// two distinct states that only differ on a healing-infrastructure field.
//
// Strategy: build a baseline state, then perturb exactly one new field at a
// time. The two states must compare !=, hash to distinct buckets when used
// as @hashmap keys, AND the spread-update path must propagate the change
// (so a `{ ..base, ... }` modification cannot silently drop the new fields).

///|
fn ck_state_base() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
/// Probe (a, b) with both `Eq` and HashMap-keyed retrieval: stores `a`'s value
/// and asserts that `b` does NOT collide with it. Confirms `b` hashes to a
/// distinct bucket AND compares not-equal to `a` — the two prerequisites a
/// state cache key needs to keep two distinct states apart.
fn assert_distinct_state_keys(
  a : SwitchingGameState,
  b : SwitchingGameState,
) -> Unit raise {
  assert_true(a != b)
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  cache[a] = 1.0
  match cache.get(b) {
    Some(_) => assert_true(false)
    None => ()
  }
}

///|
test "state cache key: weather field distinguishes the key" {
  let base = ck_state_base()
  let with_sun = { ..base, weather: @model.Weather::Sun }
  assert_distinct_state_keys(base, with_sun)
}

///|
test "state cache key: weather_turns_left distinguishes the key" {
  let base = ck_state_base()
  let with_turns = { ..base, weather_turns_left: 5 }
  assert_distinct_state_keys(base, with_turns)
}

///|
test "state cache key: my_leech_seeded distinguishes the key" {
  let base = ck_state_base()
  let seeded = { ..base, my_leech_seeded: [true, false] }
  assert_distinct_state_keys(base, seeded)
}

///|
test "state cache key: opp_leech_seeded distinguishes the key" {
  let base = ck_state_base()
  let seeded = { ..base, opp_leech_seeded: [false, true] }
  assert_distinct_state_keys(base, seeded)
}

///|
test "state hash: protean lock distinguishes states" {
  let base = ck_state_base()
  let locked = { ..base, my_protean_locked: ["ほのお", ""] }
  assert_distinct_state_keys(base, locked)
}

///|
test "state hash: empty protean lock is a no-op" {
  // 2 つの base state（両側 protean_locked が all-""）は完全に等しい =
  // 空既定が key/Hash/Eq に対して no-op であることを pin する。
  let a = ck_state_base()
  let b = ck_state_base()
  assert_true(a == b)
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  cache[a] = 1.0
  match cache.get(b) {
    Some(v) => assert_true(v == 1.0)
    None => assert_true(false)
  }
}

///|
test "state cache key: my_wish_turns distinguishes the key" {
  let base = ck_state_base()
  let wished = { ..base, my_wish_turns: 2 }
  assert_distinct_state_keys(base, wished)
}

///|
test "state cache key: opp_wish_turns distinguishes the key" {
  let base = ck_state_base()
  let wished = { ..base, opp_wish_turns: 0 }
  assert_distinct_state_keys(base, wished)
}

///|
/// All-equal sanity: untouched copy of the base state must compare equal and
/// collide on the HashMap. Catches accidental Hash regressions on the new
/// fields that would silently fail every other assertion above.
test "state cache key: identical states with all new fields collide" {
  let a = ck_state_base()
  let b = ck_state_base()
  @debug.assert_eq(a, b)
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  cache[a] = 0.42
  match cache.get(b) {
    Some(v) => @debug.assert_eq(v, 0.42)
    None => assert_true(false)
  }
}

// ─── SwitchingGameState Hash 完全性 (stage D: field infra) ────────────────────
//
// Stage D-1: state.field / state.field_turns_left は derive(Hash) に含まれ、
// 同じ matchup でも field が異なれば別の DP cache entry に分離される必要が
// ある。Stage E で field-setting moves が state を書き換える前提として、まず
// state hash が field を区別できることを担保する。

///|
test "state cache key: field variant distinguishes the key" {
  let base = ck_state_base()
  let with_electric = { ..base, field: @model.Field::Electric }
  assert_distinct_state_keys(base, with_electric)
}

///|
test "state cache key: field_turns_left distinguishes the key" {
  let base = ck_state_base()
  let with_turns = { ..base, field_turns_left: 3 }
  assert_distinct_state_keys(base, with_turns)
}

///|
/// Pairwise distinctness across all active field variants — guards against two
/// variants collapsing to the same hash bucket (e.g. derive(Hash) regression
/// that only encodes the discriminant index incorrectly).
test "state cache key: field variants pairwise distinct" {
  let base = ck_state_base()
  let electric = { ..base, field: @model.Field::Electric }
  let grassy = { ..base, field: @model.Field::Grassy }
  let misty = { ..base, field: @model.Field::Misty }
  let psychic = { ..base, field: @model.Field::Psychic }
  assert_distinct_state_keys(electric, grassy)
  assert_distinct_state_keys(electric, misty)
  assert_distinct_state_keys(electric, psychic)
  assert_distinct_state_keys(grassy, misty)
  assert_distinct_state_keys(grassy, psychic)
  assert_distinct_state_keys(misty, psychic)
}

///|
/// Cross-axis distinctness: weather と field の両方が変化していても hash が
/// 分離されることを確認。derive(Hash) は構造体全体のフィールドを混ぜるので
/// 単独テストが通れば自動的に通るはずだが、(weather, field) のいずれかが
/// 同じ bucket に集約される regression を早期に検出するために pin する。
test "state cache key: weather + field both differ distinguishes the key" {
  let base = ck_state_base()
  let a = {
    ..base,
    weather: @model.Weather::Sun,
    field: @model.Field::Electric,
  }
  let b = { ..base, weather: @model.Weather::Rain, field: @model.Field::Grassy }
  assert_distinct_state_keys(a, b)
}
