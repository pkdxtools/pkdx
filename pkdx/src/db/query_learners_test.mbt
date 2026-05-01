///|
/// じしん (scarlet_violet) — 多くのポケモンが覚える代表的な技。
/// ガブリアスが含まれること、BST降順であること、結果が空でないことを検証。
test "query_learners: じしん scarlet_violet" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_learners(db, "じしん", "scarlet_violet")
  close(db)
  match result {
    Ok(results) => {
      assert_true(results.length() > 10)
      // ガブリアスが含まれていること
      let mut found = false
      for i = 0; i < results.length(); i = i + 1 {
        if results[i].name_ja == "ガブリアス" {
          found = true
          inspect(results[i].type1, content="じめん")
          inspect(results[i].type2, content="ドラゴン")
          inspect(results[i].bst, content="600")
        }
      }
      assert_true(found)
      // BST降順ソート
      for i = 1; i < results.length(); i = i + 1 {
        assert_true(results[i - 1].bst >= results[i].bst)
      }
    }
    Err(e) => fail("query_learners failed: " + e)
  }
}

///|
/// だいちのちから (champions) — パッチ適用済み環境で champions 版の技データが動作すること。
test "query_learners: だいちのちから champions" {
  let db = match open_test_champions_db() {
    Some(d) => d
    None => return
  }
  let result = query_learners(db, "だいちのちから", "champions")
  close(db)
  match result {
    Ok(results) => {
      assert_true(results.length() > 0)
      // ガブリアスが含まれていること
      let mut found = false
      for i = 0; i < results.length(); i = i + 1 {
        if results[i].name_ja == "ガブリアス" {
          found = true
        }
      }
      assert_true(found)
    }
    Err(e) => fail("query_learners failed: " + e)
  }
}

///|
/// 存在しない技名で空配列が返ること。
test "query_learners: nonexistent move returns empty" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_learners(db, "そんざいしないわざ", "scarlet_violet")
  close(db)
  match result {
    Ok(results) => inspect(results.length(), content="0")
    Err(e) => fail("query_learners failed: " + e)
  }
}

///|
/// 重複がないこと — UNION ALL + GROUP BY で同じポケモンが複数回出ないことを検証。
test "query_learners: no duplicate globalNo" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_learners(db, "じしん", "scarlet_violet")
  close(db)
  match result {
    Ok(results) => {
      for i = 0; i < results.length(); i = i + 1 {
        for j = i + 1; j < results.length(); j = j + 1 {
          if results[i].global_no == results[j].global_no {
            fail(
              "duplicate globalNo: " + results[i].global_no + " (" + results[i].name_ja +
              ")",
            )
          }
        }
      }
    }
    Err(e) => fail("query_learners failed: " + e)
  }
}
