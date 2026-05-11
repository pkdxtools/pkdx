///|
/// Unique test file in the test working directory so native Windows runs do
/// not depend on POSIX-style `/tmp` path handling.
fn test_path(name : String) -> String {
  "pkdx_damage_cache_test_" + name + ".sqlite"
}

///|
/// Pre/post cleanup helper — failure to remove the file is intentionally
/// ignored so the first-ever run (where the file didn't exist) succeeds.
fn cleanup(path : String) -> Unit {
  let _ = @db.unlink_file(path)

}

///|
test "persistent_cache: missing file → open_or_init creates empty cache" {
  let path = test_path("missing")
  cleanup(path)
  guard open_or_init(path, "0.4.10") is Ok(cache) else {
    fail("expected Ok on fresh create")
  }
  let v = get(cache, "any-key")
  close(cache)
  cleanup(path)
  match v {
    Some(_) => fail("fresh cache should not contain entries")
    None => ()
  }
}

///|
test "persistent_cache: existing cache with matching meta retains entries" {
  let path = test_path("meta_matches")
  cleanup(path)
  guard open_or_init(path, "0.4.10") is Ok(c1) else {
    fail("first open should succeed")
  }
  guard put(c1, "k1", "{\"a\":1}") is Ok(_) else { fail("put failed") }
  close(c1)
  guard open_or_init(path, "0.4.10") is Ok(c2) else {
    fail("second open should succeed")
  }
  let v = get(c2, "k1")
  close(c2)
  cleanup(path)
  match v {
    Some(s) => assert_eq(s, "{\"a\":1}")
    None => fail("entry dropped despite matching meta")
  }
}

///|
test "persistent_cache: pkdx_version mismatch clears entries" {
  let path = test_path("version_mismatch")
  cleanup(path)
  guard open_or_init(path, "0.4.10") is Ok(c1) else {
    fail("first open failed")
  }
  guard put(c1, "k1", "v1") is Ok(_) else { fail("put failed") }
  close(c1)
  guard open_or_init(path, "0.4.11") is Ok(c2) else {
    fail("second open failed")
  }
  let v = get(c2, "k1")
  close(c2)
  cleanup(path)
  match v {
    Some(_) => fail("version mismatch should clear entries")
    None => ()
  }
}

///|
test "persistent_cache: schema_version mismatch clears entries" {
  let path = test_path("schema_mismatch")
  cleanup(path)
  // seed with a fake older schema version by writing meta directly,
  // then confirm open_or_init wipes entries on mismatch.
  guard open_or_init(path, "0.4.10") is Ok(c1) else {
    fail("first open failed")
  }
  guard put(c1, "k1", "v1") is Ok(_) else { fail("put failed") }
  // Manually overwrite the schema_version row to simulate an older install.
  guard @db.exec_binds(
      c1.db,
      "UPDATE damage_cache_meta SET v = ? WHERE k = 'schema_version'",
      [@db.BindText("0")],
    )
    is Ok(_) else {
    fail("schema_version downgrade failed")
  }
  close(c1)
  guard open_or_init(path, "0.4.10") is Ok(c2) else {
    fail("second open failed")
  }
  let v = get(c2, "k1")
  close(c2)
  cleanup(path)
  match v {
    Some(_) => fail("schema_version mismatch should clear entries")
    None => ()
  }
}

///|
test "persistent_cache: corrupted file recovers to empty cache" {
  let path = test_path("corrupted")
  cleanup(path)
  // Plant non-SQLite bytes at the cache path so the first `open_or_init`
  // fails SQLite header validation and the unlink-then-retry recovery
  // path has to run to produce a usable cache.
  let _ = write_raw_file(path, "not a sqlite database")
  guard open_or_init(path, "0.4.10") is Ok(cache) else {
    fail("corrupted file should still yield a fresh cache")
  }
  let v = get(cache, "anything")
  close(cache)
  cleanup(path)
  match v {
    Some(_) => fail("fresh cache should be empty")
    None => ()
  }
}

///|
test "persistent_cache: put/get round-trip preserves Japanese JSON" {
  let path = test_path("roundtrip")
  cleanup(path)
  guard open_or_init(path, "0.4.10") is Ok(cache) else { fail("open failed") }
  let value = "{\"attacker\":\"ガブリアス\",\"move\":\"じしん\",\"damages\":[100,101]}"
  guard put(cache, "key-ja", value) is Ok(_) else { fail("put failed") }
  let got = get(cache, "key-ja")
  close(cache)
  cleanup(path)
  match got {
    Some(s) => assert_eq(s, value)
    None => fail("entry lost after put")
  }
}

///|
test "persistent_cache: survives close/reopen" {
  let path = test_path("close_reopen")
  cleanup(path)
  guard open_or_init(path, "0.4.10") is Ok(c1) else {
    fail("first open failed")
  }
  guard put(c1, "k1", "first") is Ok(_) else { fail("put failed") }
  close(c1)
  guard open_or_init(path, "0.4.10") is Ok(c2) else {
    fail("second open failed")
  }
  let got = get(c2, "k1")
  close(c2)
  cleanup(path)
  match got {
    Some(s) => assert_eq(s, "first")
    None => fail("entry not persisted across close/reopen")
  }
}

///|
test "persistent_cache: clear_all removes all entries" {
  let path = test_path("clear_all")
  cleanup(path)
  guard open_or_init(path, "0.4.10") is Ok(cache) else { fail("open failed") }
  guard put(cache, "k1", "v1") is Ok(_) else { fail("put failed") }
  guard put(cache, "k2", "v2") is Ok(_) else { fail("put failed") }
  guard clear_all(cache) is Ok(_) else { fail("clear_all failed") }
  let v1 = get(cache, "k1")
  let v2 = get(cache, "k2")
  close(cache)
  cleanup(path)
  match v1 {
    Some(_) => fail("k1 should be gone after clear_all")
    None => ()
  }
  match v2 {
    Some(_) => fail("k2 should be gone after clear_all")
    None => ()
  }
}

///|
test "persistent_cache: sync_meta_after_migrate updates meta without touching entries" {
  let path = test_path("sync_meta")
  cleanup(path)
  guard open_or_init(path, "0.4.10") is Ok(c1) else {
    fail("first open failed")
  }
  guard put(c1, "k1", "v1") is Ok(_) else { fail("put failed") }
  close(c1)
  guard sync_meta_after_migrate(path, "0.4.11") is Ok(_) else {
    fail("sync_meta_after_migrate failed")
  }
  // After sync, opening with the new version should keep entries
  // (because sync advanced the stored meta).
  guard open_or_init(path, "0.4.11") is Ok(c2) else {
    fail("second open failed")
  }
  let v = get(c2, "k1")
  close(c2)
  cleanup(path)
  match v {
    Some(s) => assert_eq(s, "v1")
    None => fail("sync_meta should preserve entries")
  }
}

///|
/// Minimal wrapper around `pkdx_write_file` FFI for test setup when we
/// need to write arbitrary bytes (e.g. to corrupt a cache file).
fn write_raw_file(path : String, content : String) -> Int {
  pkdx_write_file_extern(@db.to_c_bytes(path), @db.to_c_bytes(content))
}

///|
#borrow(path, content)
extern "C" fn pkdx_write_file_extern(
  path : Bytes,
  content : Bytes,
) -> Int = "pkdx_write_file"
