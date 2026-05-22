// m014 / parse_healing / parse_weather_set のスモークテスト。
//
// DB が用意されていない環境 (submodule 未初期化など) では他の DB 統合
// テストと同じく silent skip (`return`) する。setup.sh 済みの開発環境
// では必ず走る。
//
// このテストは段階 1 の verification: 「m014 が data.json を投入し、
// query_moves の COALESCE + parse_healing が Move.healing を正しく埋める」
// ことを E2E で確認する。State / EOT / apply_healing は別段階で実装する。

///|
/// 「じこさいせい」が `FixedFraction(1, 2)` として返ること。data.json で
/// `heal_kind: "fixed", heal_num: 1, heal_den: 2` を投入しているので、
/// parse_healing が `Some(FixedFraction(1, 2))` を生成する。
test "query_move: じこさいせい has FixedFraction(1, 2) healing (m014 smoke)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_move(db, "じこさいせい", @model.Other("scarlet_violet"))
  close(db)
  match result {
    Ok(mv) => {
      match mv.healing {
        Some(FixedFraction(n, d)) => {
          @debug.debug_inspect(n, content="1")
          @debug.debug_inspect(d, content="2")
        }
        Some(_) => fail("じこさいせい healing expected FixedFraction(1,2), got different variant")
        None => fail("じこさいせい healing should be Some(FixedFraction(1,2)) but was None")
      }
      @debug.debug_inspect(mv.weather_set, content="None")
    }
    Err(e) => fail("query_move じこさいせい failed: " + e)
  }
}

///|
/// 既存技 (m014 が投入していないもの) の `healing` / `weather_set` は
/// `None` を返すこと。COALESCE デフォルト ('' / 0 / 1) で parse_healing が
/// None を返す不変条件を確認する。「たいあたり」を選んだのは回復系・天候
/// 系のいずれにも該当しないため。
test "query_move: たいあたり has no healing/weather_set (default None)" {
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
    Ok(mv) => {
      @debug.debug_inspect(mv.healing, content="None")
      @debug.debug_inspect(mv.weather_set, content="None")
    }
    Err(e) => fail("query_move たいあたり failed: " + e)
  }
}

///|
/// 「にほんばれ」の `weather_set` が `Some(Sun)` で返ること。m014 で
/// `weather_set: "sun"` を投入しているので、parse_weather_set が `Some(Sun)`
/// を生成する。
test "query_move: にほんばれ has weather_set=Sun (m014 smoke)" {
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
        Some(_) => fail("にほんばれ weather_set expected Sun, got different variant")
        None => fail("にほんばれ weather_set should be Some(Sun) but was None")
      }
      @debug.debug_inspect(mv.healing, content="None")
    }
    Err(e) => fail("query_move にほんばれ failed: " + e)
  }
}

///|
/// Issue #3 (Schema compat regression): m014 未適用の DB に対しても
/// `query_move` / `query_moves` が prepare-time error せず graceful に
/// `healing=None` / `weather_set=None` で返すこと。
///
/// シナリオ: ad-hoc に local_waza / local_waza_language / move_meta テーブルを
/// 「m014 適用前 (= heal_* / weather_set 列無し)」のスキーマで作成し、
/// query_move を呼ぶ。COALESCE は列存在を保証しないため、旧実装では
/// `no such column: mm.heal_kind` が prepare 段階で発生する (Red phase)。
/// 修正後 (Option A: PRAGMA-based column detection) では列が無ければ
/// 旧 SELECT を使い、Move.healing=None / weather_set=None を返す。
test "query_move: gracefully handles legacy DB without heal columns (Issue #3)" {
  let path = "_build/test_issue3_legacy_schema.db"
  let _ = unlink_file(path)
  let db = match open_rwc(path) {
    Ok(d) => d
    Err(e) => {
      fail("open_rwc legacy schema db failed: " + e)
      return
    }
  }
  // m014 適用前 schema を再現: move_meta は m002+m004+m005 までの 9 列。
  // heal_kind / heal_*_num / heal_*_den / weather_set / weather_turns は存在
  // しない。
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
    #|  recharge INTEGER NOT NULL DEFAULT 0
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
    ddl_move_meta,
    ddl_local_waza,
    ddl_local_waza_language,
    ins_local_waza_language,
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
  // 旧実装 (m014 列を unconditionally SELECT) では prepare で fail する。
  // Option A 修正後: PRAGMA で列が無いことを検出し、旧 SELECT (heal/weather 無し)
  // を実行して Move を返す。
  let result = query_move(db, "たいあたり", @model.Other("scarlet_violet"))
  close(db)
  let _ = unlink_file(path)
  match result {
    Ok(mv) => {
      // 修正後の期待挙動: graceful な None。
      @debug.debug_inspect(mv.healing, content="None")
      @debug.debug_inspect(mv.weather_set, content="None")
    }
    Err(e) =>
      fail(
        "query_move on legacy schema should not error (Issue #3) — but got: " +
        e,
      )
  }
}

///|
/// Issue #3 follow-up (部分適用 DB): m014 は `ensure_column` で 1 列ずつ
/// `ALTER TABLE` するため、途中で異常終了すると `heal_kind` だけ存在し
/// 他の heal_* / weather_set 列が無い "部分適用" 状態の DB が残り得る。
/// 旧実装は `heal_kind` 単独で列存在を判定していたため、こうした DB に
/// 対しても新 SELECT を投げてしまい `no such column: mm.heal_num` で
/// prepare 失敗していた。
///
/// 修正後 (Option A 強化): `healing_select_columns()` が参照する全 8 列を
/// PRAGMA でチェックし、1 列でも欠けたら旧 SELECT にフォールバックする。
test "query_move: gracefully handles partial m014 schema (heal_kind only)" {
  let path = "_build/test_issue3_partial_schema.db"
  let _ = unlink_file(path)
  let db = match open_rwc(path) {
    Ok(d) => d
    Err(e) => {
      fail("open_rwc partial schema db failed: " + e)
      return
    }
  }
  // 部分適用: heal_kind は付いているが heal_num / heal_den / heal_sunny_num /
  // heal_sunny_den / heal_harsh_num / heal_harsh_den / weather_set が無い。
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
    #|  heal_kind TEXT NOT NULL DEFAULT ''
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
    ddl_move_meta,
    ddl_local_waza,
    ddl_local_waza_language,
    ins_local_waza_language,
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
    Ok(mv) => {
      @debug.debug_inspect(mv.healing, content="None")
      @debug.debug_inspect(mv.weather_set, content="None")
    }
    Err(e) =>
      fail(
        "query_move on partial m014 schema should not error (Issue #3 follow-up) — but got: " +
        e,
      )
  }
}

///|
/// 「つきのひかり」が `WeatherDependent(1, 2, 2, 3, 1, 4)` として返ること。
/// 天候依存回復技の 3 fraction が正しく往復するか確認する。
test "query_move: つきのひかり has WeatherDependent (default/sunny/harsh)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_move(db, "つきのひかり", @model.Other("scarlet_violet"))
  close(db)
  match result {
    Ok(mv) => {
      match mv.healing {
        Some(WeatherDependent(dn, dd, sn, sd, hn, hd)) => {
          @debug.debug_inspect(dn, content="1")
          @debug.debug_inspect(dd, content="2")
          @debug.debug_inspect(sn, content="2")
          @debug.debug_inspect(sd, content="3")
          @debug.debug_inspect(hn, content="1")
          @debug.debug_inspect(hd, content="4")
        }
        Some(_) =>
          fail(
            "つきのひかり healing expected WeatherDependent, got different variant",
          )
        None => fail("つきのひかり healing should be Some(WeatherDependent(...))")
      }
    }
    Err(e) => fail("query_move つきのひかり failed: " + e)
  }
}
