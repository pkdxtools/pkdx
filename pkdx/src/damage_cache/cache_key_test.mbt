///|
/// Baseline `CacheKeyInput` for tests — each test starts from this and
/// mutates exactly the fields under inspection.
fn baseline() -> CacheKeyInput {
  CacheKeyInput::{
    version: "champions",
    regulation: "",
    attacker: "ガブリアス",
    defender: "カイリュー",
    move_name: "じしん",
    atk_ability: "",
    def_ability: "",
    atk_item: "",
    def_item: "",
    weather: "",
    field: "",
    tera_type: "",
    critical: false,
    is_double: false,
    atk_stat: 0,
    def_stat: 0,
    def_hp: 0,
    atk_nature: "",
    def_nature: "",
    atk_rank: 0,
    def_rank: 0,
    fainted_count: 2,
    wall: "",
    screen_pierce: false,
    atk_status: "",
    def_status: "",
    atk_rank_up_count: 0,
    def_rank_up_count: 0,
    atk_hp_num: 0,
    atk_hp_den: 0,
    def_item_removable: false,
    multi_hit_mode: "",
    disguise_active: false,
  }
}

///|
/// The key must be deterministic: identical inputs produce identical keys.
test "build_cache_key: determinism across repeated calls" {
  let input = baseline()
  guard build_cache_key(input) is Ok(first) else { fail("unexpected Err") }
  for i = 0; i < 100; i = i + 1 {
    guard build_cache_key(input) is Ok(next) else { fail("unexpected Err") }
    assert_eq(next, first)
    let _ = i
  }
}

///|
/// Column coverage: changing any single field must produce a different key.
/// If two fields collapse into the same segment the encoding is broken.
test "build_cache_key: single-field change yields distinct key" {
  guard build_cache_key(baseline()) is Ok(base) else { fail("unexpected Err") }
  let mutations : Array[CacheKeyInput] = [
    { ..baseline(), version: "scarlet_violet" },
    { ..baseline(), regulation: "m-a" },
    { ..baseline(), attacker: "リザードン" },
    { ..baseline(), defender: "バンギラス" },
    { ..baseline(), move_name: "ドラゴンクロー" },
    { ..baseline(), atk_ability: "さめはだ" },
    { ..baseline(), def_ability: "マルチスケイル" },
    { ..baseline(), atk_item: "いのちのたま" },
    { ..baseline(), def_item: "オボンのみ" },
    { ..baseline(), weather: "はれ" },
    { ..baseline(), field: "エレキ" },
    { ..baseline(), tera_type: "じめん" },
    { ..baseline(), critical: true },
    { ..baseline(), is_double: true },
    { ..baseline(), atk_stat: 200 },
    { ..baseline(), def_stat: 200 },
    { ..baseline(), def_hp: 180 },
    { ..baseline(), atk_nature: "ようき" },
    { ..baseline(), def_nature: "ずぶとい" },
    { ..baseline(), atk_rank: 2 },
    { ..baseline(), def_rank: -2 },
    { ..baseline(), fainted_count: 0 },
    // rev2 additions: each new field must contribute to the key.
    { ..baseline(), wall: "reflect" },
    { ..baseline(), screen_pierce: true },
    { ..baseline(), atk_status: "burn" },
    { ..baseline(), def_status: "paralyze" },
    { ..baseline(), atk_rank_up_count: 3 },
    { ..baseline(), def_rank_up_count: 3 },
    { ..baseline(), atk_hp_num: 1 },
    { ..baseline(), atk_hp_den: 4 },
    { ..baseline(), def_item_removable: true },
    { ..baseline(), multi_hit_mode: "fixed:5" },
    { ..baseline(), disguise_active: true },
  ]
  for i = 0; i < mutations.length(); i = i + 1 {
    guard build_cache_key(mutations[i]) is Ok(k) else {
      fail("unexpected Err at i=\{i}")
    }
    assert_true(k != base)
  }
}

///|
/// Ordering / injectivity: swapping the values of two same-type fields must
/// yield a different key (otherwise the encoding aliases the two roles).
test "build_cache_key: swap attacker/defender ability yields distinct key" {
  let base_input : CacheKeyInput = {
    ..baseline(),
    atk_ability: "いかく",
    def_ability: "マルチスケイル",
  }
  let swapped : CacheKeyInput = {
    ..baseline(),
    atk_ability: "マルチスケイル",
    def_ability: "いかく",
  }
  guard build_cache_key(base_input) is Ok(k1) else { fail("unexpected Err") }
  guard build_cache_key(swapped) is Ok(k2) else { fail("unexpected Err") }
  assert_true(k1 != k2)
}

///|
/// Adjacent empty disambiguation: `(attacker="", defender="x")` and
/// `(attacker="x", defender="")` must not collapse to the same key.
test "build_cache_key: adjacent empty fields are disambiguated" {
  let a : CacheKeyInput = { ..baseline(), attacker: "", defender: "カイリュー" }
  let b : CacheKeyInput = { ..baseline(), attacker: "カイリュー", defender: "" }
  guard build_cache_key(a) is Ok(k1) else { fail("unexpected Err") }
  guard build_cache_key(b) is Ok(k2) else { fail("unexpected Err") }
  assert_true(k1 != k2)
}

///|
/// Pipe rejection: any input containing `|` must return Err.
test "build_cache_key: rejects pipe character in attacker" {
  let input : CacheKeyInput = { ..baseline(), attacker: "ガブ|リアス" }
  match build_cache_key(input) {
    Ok(_) => fail("expected Err for pipe in attacker")
    Err(_) => ()
  }
}

///|
/// Nature empty vs "まじめ": engine treats both as no-correction, but key
/// distinguishes them (future behavior may diverge).
test "build_cache_key: empty nature distinct from まじめ" {
  let a : CacheKeyInput = { ..baseline(), atk_nature: "" }
  let b : CacheKeyInput = { ..baseline(), atk_nature: "まじめ" }
  guard build_cache_key(a) is Ok(k1) else { fail("unexpected Err") }
  guard build_cache_key(b) is Ok(k2) else { fail("unexpected Err") }
  assert_true(k1 != k2)
}

///|
/// Whitespace policy: leading or trailing spaces are rejected so callers
/// cannot accidentally cache "ガブリアス" and " ガブリアス" separately.
test "build_cache_key: rejects leading whitespace" {
  let input : CacheKeyInput = { ..baseline(), attacker: " ガブリアス" }
  match build_cache_key(input) {
    Ok(_) => fail("expected Err for leading whitespace")
    Err(_) => ()
  }
}

///|
test "build_cache_key: rejects trailing whitespace" {
  let input : CacheKeyInput = { ..baseline(), attacker: "ガブリアス " }
  match build_cache_key(input) {
    Ok(_) => fail("expected Err for trailing whitespace")
    Err(_) => ()
  }
}
