// m015 / parse_field_set のスモークテスト。
//
// DB が用意されていない環境 (submodule 未初期化など) では他の DB 統合
// テストと同じく silent skip (`return`) する。setup.sh 済みの開発環境
// では必ず走る。
//
// このテストは段階 C-4 の verification: 「m015 が data.json を投入し、
// query_moves の COALESCE + parse_field_set が Move.field_set を正しく埋める」
// ことを E2E で確認する。State / EOT / apply_field は別段階で実装する。

///|
/// 「エレキフィールド」の `field_set` が `Some(Electric)` で返ること。m015 で
/// `field_set: "electric"` を投入しているので、parse_field_set が
/// `Some(Electric)` を生成する。
test "query_move: エレキフィールド has field_set=Electric (m015 smoke)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_move(
    db,
    "エレキフィールド",
    @model.Other("scarlet_violet"),
  )
  close(db)
  match result {
    Ok(mv) =>
      match mv.field_set {
        Some(Electric) => ()
        Some(_) =>
          fail(
            "エレキフィールド field_set expected Electric, got different variant",
          )
        None =>
          fail(
            "エレキフィールド field_set should be Some(Electric) but was None",
          )
      }
    Err(e) => fail("query_move エレキフィールド failed: " + e)
  }
}

///|
/// 「グラスフィールド」の `field_set` が `Some(Grassy)` で返ること。
test "query_move: グラスフィールド has field_set=Grassy (m015 smoke)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_move(
    db,
    "グラスフィールド",
    @model.Other("scarlet_violet"),
  )
  close(db)
  match result {
    Ok(mv) =>
      match mv.field_set {
        Some(Grassy) => ()
        Some(_) =>
          fail(
            "グラスフィールド field_set expected Grassy, got different variant",
          )
        None =>
          fail(
            "グラスフィールド field_set should be Some(Grassy) but was None",
          )
      }
    Err(e) => fail("query_move グラスフィールド failed: " + e)
  }
}

///|
/// 「ミストフィールド」の `field_set` が `Some(Misty)` で返ること。
test "query_move: ミストフィールド has field_set=Misty (m015 smoke)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_move(
    db,
    "ミストフィールド",
    @model.Other("scarlet_violet"),
  )
  close(db)
  match result {
    Ok(mv) =>
      match mv.field_set {
        Some(Misty) => ()
        Some(_) =>
          fail(
            "ミストフィールド field_set expected Misty, got different variant",
          )
        None =>
          fail(
            "ミストフィールド field_set should be Some(Misty) but was None",
          )
      }
    Err(e) => fail("query_move ミストフィールド failed: " + e)
  }
}

///|
/// 「サイコフィールド」の `field_set` が `Some(Psychic)` で返ること。
test "query_move: サイコフィールド has field_set=Psychic (m015 smoke)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_move(
    db,
    "サイコフィールド",
    @model.Other("scarlet_violet"),
  )
  close(db)
  match result {
    Ok(mv) =>
      match mv.field_set {
        Some(Psychic) => ()
        Some(_) =>
          fail(
            "サイコフィールド field_set expected Psychic, got different variant",
          )
        None =>
          fail(
            "サイコフィールド field_set should be Some(Psychic) but was None",
          )
      }
    Err(e) => fail("query_move サイコフィールド failed: " + e)
  }
}

///|
/// 既存技 (m015 が投入していないもの) の `field_set` は `None` を返すこと。
/// 「たいあたり」は field 系・healing 系のいずれにも該当しない。
test "query_move: たいあたり has field_set=None (default)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_move(db, "たいあたり", @model.Other("scarlet_violet"))
  close(db)
  match result {
    Ok(mv) => @debug.debug_inspect(mv.field_set, content="None")
    Err(e) => fail("query_move たいあたり failed: " + e)
  }
}

///|
/// m014 投入の天候設定技 (にほんばれ) も `field_set` は `None` を返すこと。
/// m014 と m015 が独立な列を担っており、weather と field が混ざらないことを pin する。
test "query_move: にほんばれ has weather_set=Sun but field_set=None (independence)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_move(db, "にほんばれ", @model.Other("scarlet_violet"))
  close(db)
  match result {
    Ok(mv) => {
      match mv.weather_set {
        Some(Sun) => ()
        _ => fail("にほんばれ weather_set should remain Some(Sun)")
      }
      @debug.debug_inspect(mv.field_set, content="None")
    }
    Err(e) => fail("query_move にほんばれ failed: " + e)
  }
}

///|
/// Schema compat (m015 未適用): m015 列が無い DB に対しても query_move が
/// prepare-time error せず graceful に field_set=None を返すこと。m014 で
/// 確立された PRAGMA-based column detection の field 列バリエーション。
test "query_move: gracefully handles legacy DB without field columns (m015 compat)" {
  let path = "_build/test_m015_legacy_schema.db"
  let _ = unlink_file(path)
  let db = match open_rwc(path) {
    Ok(d) => d
    Err(e) => {
      fail("open_rwc legacy schema db failed: " + e)
      return
    }
  }
  // m014 適用済 / m015 未適用 schema を再現: heal_* / weather_set 列はあるが
  // field_set / field_turns 列は無い。
  let ddl_move_meta =
    #|CREATE TABLE IF NOT EXISTS move_meta (
    #|  name_ja TEXT PRIMARY KEY,
    #|  priority INTEGER NOT NULL DEFAULT 0,
    #|  stat_effects_json TEXT NOT NULL DEFAULT '[]',
    #|  ailment_ja TEXT NOT NULL DEFAULT '',
    #|  ailment_chance INTEGER NOT NULL DEFAULT 100,
    #|  recoil_num INTEGER NOT NULL DEFAULT 0,
    #|  recoil_den INTEGER NOT NULL DEFAULT 1,
    #|  self_ko INTEGER NOT NULL DEFAULT 0,
    #|  recharge INTEGER NOT NULL DEFAULT 0,
    #|  heal_kind TEXT NOT NULL DEFAULT '',
    #|  heal_num INTEGER NOT NULL DEFAULT 0,
    #|  heal_den INTEGER NOT NULL DEFAULT 1,
    #|  heal_sunny_num INTEGER NOT NULL DEFAULT 0,
    #|  heal_sunny_den INTEGER NOT NULL DEFAULT 1,
    #|  heal_harsh_num INTEGER NOT NULL DEFAULT 0,
    #|  heal_harsh_den INTEGER NOT NULL DEFAULT 1,
    #|  weather_set TEXT NOT NULL DEFAULT '',
    #|  weather_turns INTEGER NOT NULL DEFAULT 0
    #|)
  let ddl_local_waza =
    #|CREATE TABLE IF NOT EXISTS local_waza (
    #|  waza TEXT,
    #|  version TEXT,
    #|  type TEXT,
    #|  category TEXT,
    #|  power INTEGER,
    #|  accuracy INTEGER,
    #|  pp INTEGER,
    #|  PRIMARY KEY (waza, version)
    #|)
  let ddl_local_waza_language =
    #|CREATE TABLE IF NOT EXISTS local_waza_language (
    #|  waza TEXT,
    #|  version TEXT,
    #|  language TEXT,
    #|  name TEXT,
    #|  PRIMARY KEY (waza, version, language)
    #|)
  let ins_local_waza_language =
    #|INSERT INTO local_waza_language (waza, version, language, name)
    #|VALUES ('tackle', 'Scarlet_Violet', 'jpn', 'たいあたり')
  let ins_local_waza =
    #|INSERT INTO local_waza (waza, version, type, category, power, accuracy, pp)
    #|VALUES ('tackle', 'Scarlet_Violet', 'ノーマル', '物理', 40, 100, 35)
  let create_sqls = [
    ddl_move_meta, ddl_local_waza, ddl_local_waza_language, ins_local_waza_language,
    ins_local_waza,
  ]
  for sql in create_sqls {
    match exec(db, sql) {
      Err(e) => {
        close(db)
        fail("CREATE/INSERT failed: " + e)
        return
      }
      Ok(_) => ()
    }
  }
  let result = query_move(db, "たいあたり", @model.Other("scarlet_violet"))
  close(db)
  let _ = unlink_file(path)
  match result {
    Ok(mv) => @debug.debug_inspect(mv.field_set, content="None")
    Err(e) =>
      fail(
        "query_move on m015-未適用 schema should not error — but got: " + e,
      )
  }
}

///|
/// parse_field_set 単体: canonical (DB) 文字列 → Field?。
test "parse_field_set: canonical strings → Field variant" {
  match parse_field_set("electric") {
    Some(Electric) => ()
    _ => fail("electric should yield Some(Electric)")
  }
  match parse_field_set("grassy") {
    Some(Grassy) => ()
    _ => fail("grassy should yield Some(Grassy)")
  }
  match parse_field_set("misty") {
    Some(Misty) => ()
    _ => fail("misty should yield Some(Misty)")
  }
  match parse_field_set("psychic") {
    Some(Psychic) => ()
    _ => fail("psychic should yield Some(Psychic)")
  }
  @debug.debug_inspect(parse_field_set(""), content="None")
  @debug.debug_inspect(parse_field_set("unknown"), content="None")
}
