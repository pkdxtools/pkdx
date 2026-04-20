///|
/// Integration test: build_cache_key + persistent_cache are expected to
/// work together without bespoke glue. Keys from real CLI-shaped inputs
/// survive the put/get round-trip, and two inputs that differ in exactly
/// one field end up as two distinct entries.
///
/// Heavier CLI-layer integration (--no-cache bypass, --format table
/// bypass, migration-head invalidation through the binary) is exercised
/// by `scripts/bench_damage.sh` and `pkdx damage-bench`, not here —
/// damage_cache must not depend on the main CLI package.

///|
fn int_test_path(name : String) -> String {
  "/tmp/pkdx_damage_cache_int_" + name + ".sqlite"
}

///|
fn int_cleanup(path : String) -> Unit {
  let _ = @db.unlink_file(path)

}

///|
fn int_baseline() -> CacheKeyInput {
  CacheKeyInput::{
    version: "champions",
    regulation: "",
    attacker: "ガブリアス",
    defender: "カイリュー",
    move_name: "じしん",
    atk_ability: "さめはだ",
    def_ability: "マルチスケイル",
    atk_item: "いのちのたま",
    def_item: "オボンのみ",
    weather: "はれ",
    field: "",
    tera_type: "じめん",
    critical: false,
    is_double: false,
    atk_stat: 0,
    def_stat: 0,
    def_hp: 0,
    atk_nature: "ようき",
    def_nature: "しんちょう",
    atk_rank: 0,
    def_rank: 0,
    fainted_count: 2,
  }
}

///|
test "integration: build_cache_key + persistent_cache round-trip" {
  let path = int_test_path("roundtrip")
  int_cleanup(path)
  let input = int_baseline()
  guard build_cache_key(input) is Ok(key) else {
    fail("build_cache_key failed")
  }
  let sample_json = "{\"attacker\":\"ガブリアス\",\"defender\":\"カイリュー\",\"move\":\"じしん\",\"damages\":[100,101,102],\"percents\":[50.0,51.0,52.0],\"min\":100,\"max\":102,\"defender_hp\":200,\"ko\":\"確定2発\"}"
  guard
    open_or_init(path, "0.4.10", "010_move_meta_posthit") is Ok(cache) else {
    fail("open_or_init failed")
  }
  guard put(cache, key, sample_json) is Ok(_) else { fail("put failed") }
  close(cache)
  guard
    open_or_init(path, "0.4.10", "010_move_meta_posthit") is Ok(cache2) else {
    fail("reopen failed")
  }
  let got = get(cache2, key)
  close(cache2)
  int_cleanup(path)
  match got {
    Some(s) => assert_eq(s, sample_json)
    None => fail("entry not persisted across close/reopen")
  }
}

///|
test "integration: two distinct inputs produce two distinct cache entries" {
  let path = int_test_path("distinct")
  int_cleanup(path)
  let a = int_baseline()
  let b : CacheKeyInput = { ..int_baseline(), atk_rank: 2 }
  guard build_cache_key(a) is Ok(ka) else { fail("key a failed") }
  guard build_cache_key(b) is Ok(kb) else { fail("key b failed") }
  assert_true(ka != kb)
  guard
    open_or_init(path, "0.4.10", "010_move_meta_posthit") is Ok(cache) else {
    fail("open failed")
  }
  guard put(cache, ka, "{\"rank\":0}") is Ok(_) else { fail("put a failed") }
  guard put(cache, kb, "{\"rank\":2}") is Ok(_) else { fail("put b failed") }
  let va = get(cache, ka)
  let vb = get(cache, kb)
  close(cache)
  int_cleanup(path)
  match (va, vb) {
    (Some(sa), Some(sb)) => {
      assert_eq(sa, "{\"rank\":0}")
      assert_eq(sb, "{\"rank\":2}")
    }
    _ => fail("one of the entries is missing")
  }
}
