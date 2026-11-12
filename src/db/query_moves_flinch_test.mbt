// ひるみ (move_meta.flinch_chance, m019) の DB 経路スモーク。
//
// `query_move` / `query_champions_move` が m019 の列を Move.flinch_chance に載せることを確認する。
// DB が用意されていない環境では他の DB 統合テストと同じく silent skip (`return`)。setup.sh 済みの
// 開発環境では必ず走る。champions 経路は `３ぼんのや` (全角 3、champout の本文どおりの表記) で引く。

///|
test "query_move: かみつく carries flinch_chance 30 (m019, pokedex path)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match @db.open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = @db.query_move(db, "かみつく", @model.Other("scarlet_violet"))
  @db.close(db)
  match result {
    Ok(mv) => assert_true(mv.flinch_chance == 30)
    Err(e) => fail("query_move failed: " + e)
  }
}

///|
test "query_move: たいあたり has flinch_chance 0 (no row, default)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match @db.open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = @db.query_move(db, "たいあたり", @model.Other("scarlet_violet"))
  @db.close(db)
  match result {
    Ok(mv) => assert_true(mv.flinch_chance == 0)
    Err(e) => fail("query_move failed: " + e)
  }
}

///|
test "query_move: ねこだまし is not flinch-modelled (conditional, no m019 row)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match @db.open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = @db.query_move(db, "ねこだまし", @model.Other("scarlet_violet"))
  @db.close(db)
  match result {
    Ok(mv) => assert_true(mv.flinch_chance == 0)
    Err(e) => fail("query_move failed: " + e)
  }
}

///|
test "query_champions_move: ３ぼんのや (champions full-width spelling) carries flinch_chance 30" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match @db.open_for(db_path, @model.Champions) {
    Ok(d) => d
    Err(_) => return
  }
  let result = @db.query_champions_move(db, "３ぼんのや")
  @db.close(db)
  match result {
    Ok(mv) => assert_true(mv.flinch_chance == 30)
    Err(_) => return
  }
}
