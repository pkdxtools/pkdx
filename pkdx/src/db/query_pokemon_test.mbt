// query_pokemon に対する integration テスト。
//
// 本来ユニットテストは DB に依存しないほうがいいが、ここで守りたいのは
// 「MoonBit ネイティブの ResultSet が external_object 化されていて、
//   decref が隣接する String バッファを壊さないこと」という FFI レベルの不変条件で、
// これはクエリ結果を実際に取り出してフィールドを検証しないと再現できない。
// そのため setup.sh 済みの `pokedex/pokedex.db` を直接 open する。
//
// CI など DB が無い環境では open に失敗した時点でテスト自体を skip 扱いにする
// （`fail` ではなく `return` することで moon test の pass カウントに影響させる）。
// 通常の開発環境（setup.sh 実行済み）では必ず走る。

///|
/// 開発環境で pokedex.db に到達するパスを返す。moon test の CWD は
/// 実行ごとに異なり得るので候補を順に試す。POKEDEX_DB 環境変数が設定
/// されていればそれを最優先する。
fn find_test_db() -> String? {
  match @sys.get_env_var("POKEDEX_DB") {
    Some(p) => return Some(p)
    None => ()
  }
  let candidates = [
    "pokedex/pokedex.db",
    "../pokedex/pokedex.db",
    "../../pokedex/pokedex.db",
    "../../../pokedex/pokedex.db",
    "../../../../pokedex/pokedex.db",
  ]
  for i = 0; i < candidates.length(); i = i + 1 {
    let path = candidates[i]
    match open(path) {
      Ok(db) => {
        close(db)
        return Some(path)
      }
      Err(_) => continue
    }
  }
  None
}

///|
/// 以前の `(rs - 8)` 書き込みバグでは、legendsza の カイリュー で
/// HP が 91 → 81、type1 が ひこう → ぱこう に破壊されていた。
/// external_object 化した後はすべて正しい値が返る。
test "query_pokemon: カイリュー legendsza (rc-bug regression)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "カイリュー", "legendsza")
  close(db)
  match result {
    Ok(p) => {
      // HP が 91 のままであること（バグ時は 81 になっていた）
      inspect(p.hp, content="91")
      // type1 が ひこう のままであること（バグ時は ぱこう / ばこう などに化けていた）
      inspect(p.type1, content="ひこう")
      inspect(p.type2, content="ドラゴン")
      inspect(p.name_ja, content="カイリュー")
      inspect(p.global_no, content="0149")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// scarlet_violet 側でも同じ不変条件を確認（版依存で回帰しないこと）。
test "query_pokemon: リザードン scarlet_violet" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "リザードン", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.hp, content="78")
      inspect(p.type1, content="ほのお")
      inspect(p.type2, content="ひこう")
      inspect(p.name_ja, content="リザードン")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 複数の数値フィールドをすべて検証する。バグは先頭 codeunit の -1 という
/// 値依存で起きるので、フィールドによって壊れる/壊れないが変わる。数値を
/// 網羅的に assert しておく。
///|
/// champions (デフォルトversion) でメガポケモンが正しくクエリできること。
test "query_pokemon: メガピクシー champions" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "メガピクシー", "champions")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.hp, content="95")
      inspect(p.atk, content="80")
      inspect(p.def_, content="93")
      inspect(p.spa, content="135")
      inspect(p.spd, content="110")
      inspect(p.spe, content="70")
      inspect(p.bst, content="583")
      inspect(p.type1, content="フェアリー")
      inspect(p.type2, content="ひこう")
      inspect(p.name_ja, content="メガピクシー")
      inspect(p.global_no, content="0036")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// champions で通常ポケモンのクエリとステータスが正しいこと。
test "query_pokemon: ガブリアス champions stats" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "ガブリアス", "champions")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.hp, content="108")
      inspect(p.atk, content="130")
      inspect(p.def_, content="95")
      inspect(p.spa, content="80")
      inspect(p.spd, content="85")
      inspect(p.spe, content="102")
      inspect(p.type1, content="ドラゴン")
      inspect(p.type2, content="じめん")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// champions で技クエリが正しく動作すること。
test "query_moves: ガブリアス champions" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_moves(db, "0445", "champions")
  close(db)
  match result {
    Ok(moves) => {
      // ガブリアスは champions で97技を覚える
      assert_true(moves.length() > 0)
      // じしんが含まれていること
      let mut found_eq = false
      for i = 0; i < moves.length(); i = i + 1 {
        if moves[i].name == "じしん" {
          found_eq = true
          inspect(moves[i].type_, content="じめん")
        }
      }
      assert_true(found_eq)
    }
    Err(e) => fail("query_moves failed: " + e)
  }
}

///|
/// yakkun番号とglobalNoが異なるGen9ポケモンが正しいglobalNoで登録されていること。
test "query_pokemon: スコヴィラン champions globalNo" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "スコヴィラン", "champions")
  close(db)
  match result {
    Ok(p) => {
      // yakkun n939 だが正しい globalNo は 0952
      inspect(p.global_no, content="0952")
      inspect(p.name_ja, content="スコヴィラン")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
test "query_pokemon: ガブリアス scarlet_violet stats" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "ガブリアス", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.hp, content="108")
      inspect(p.atk, content="130")
      inspect(p.def_, content="95")
      inspect(p.spa, content="80")
      inspect(p.spd, content="85")
      inspect(p.spe, content="102")
      inspect(p.bst, content="600")
      inspect(p.type1, content="じめん")
      inspect(p.type2, content="ドラゴン")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}
