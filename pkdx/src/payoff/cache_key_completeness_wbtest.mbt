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
  }
}

///|
fn ck_combatant(pokemon : @model.Pokemon, moves : Array[@model.Move]) -> Combatant {
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
  atk_rank~ : Int = 0,
  def_rank~ : Int = 0,
) -> String raise {
  let input = combatant_to_cache_key_input(atk, dfn, mv, atk_rank, def_rank)
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
  assert_eq(key_of(a, b, mv), key_of(a, b, mv))
}
