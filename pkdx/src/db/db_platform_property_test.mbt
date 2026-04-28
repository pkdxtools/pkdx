///|
/// Cross-cutting property tests for the open_for routing layer (issue #95).
/// open_for itself lives in main.mbt (caller layer), so these tests focus
/// on db-package contracts: champions.db schema invariants and the
/// pokedex_latest:champions_latest fingerprint shape.

///|
test "validate_champions_schema accepts an empty champions.db (P1-B)" {
  // P1-B has no required tables yet — champions.db is bootstrapped
  // empty so #94 (items) has a target. Validation must be a no-op
  // until P2-C lands the first required table.
  let tmp = "/tmp/pkdx_empty_champions_test.db"
  let _ = unlink_file(tmp)
  match open_rwc(tmp) {
    Err(_) => return
    Ok(db) => {
      let r = validate_champions_schema(db)
      close(db)
      let _ = unlink_file(tmp)
      match r {
        Ok(_) => ()
        Err(e) =>
          fail(
            "validate_champions_schema rejected an empty DB despite empty required-list: " +
            e,
          )
      }
    }
  }
}
