///|
/// `pkdx moves --format json` の出力を `pkdx select` の入力として読み直す経路の回帰。
///
/// champions.db の行 (`query_champions_move` / `query_champions_moves`) → `@cli.format_moves`
/// (pkdx moves と同じ整形) → `parse_team_array` (select の入力パーサ) の順に通し、
/// 017 (こおり) / 018 (やけど・まひ・どく・もうどく) の `status_effect` と 019 (ひるみ) の
/// `flinch_chance` が select の Move に落ちずに届くことを確認する。
///
/// 期待値は DB / champout 本文の実値 (アイアンヘッドは 20%、どくどくのキバ はひるみ無し)。
/// DB が見つからない環境では他の DB 統合テストと同じく silent skip する。

///|
fn rt_open_champions() -> @db.Db? {
  let candidates = [
    "pokedex/pokedex.db", "../pokedex/pokedex.db", "../../pokedex/pokedex.db",
    "../../../pokedex/pokedex.db", "../../../../pokedex/pokedex.db",
  ]
  for p in candidates {
    if @db.file_exists(@db.resolve_champions_db_path_from(p)) {
      match @db.open_for(p, @model.Champions) {
        Ok(db) => return Some(db)
        Err(_) => continue
      }
    }
  }
  None
}

///|
/// 技の列を `pkdx moves` と同じ JSON にして、select の入力パーサで Move に戻す。
/// 戻せなかったら None (テストは fail にする)。
fn rt_through_select_input(moves : Array[@model.Move]) -> Array[@model.Move]? {
  // `pkdx moves --format json` と同じ経路 (CLI の書式指定を解析して得た値をそのまま渡す)。
  let moves_json = @cli.format_moves(moves, @cli.parse_output_format("json"))
  let combatant = "{\"name\":\"RT\",\"type1\":\"ノーマル\",\"type2\":\"\",\"hp\":100,\"atk\":100,\"def\":100,\"spa\":100,\"spd\":100,\"spe\":100,\"moves\":" +
    moves_json +
    "}"
  let team_json = @json.parse("[" + combatant + "]") catch {
    _ => return None
  }
  let team = parse_team_array(team_json, "team") catch {
    _ => return None
  }
  if team.length() != 1 {
    return None
  }
  Some(team[0].moves)
}

///|
test "pkdx moves -> select input: かえんほうしゃ 10% やけど / れいとうビーム 10% こおり / かみなりのキバ まひ 10 + ひるみ 10" {
  let db = match rt_open_champions() {
    Some(d) => d
    None => return
  }
  let names_and_expect : Array[(String, (@model.StatusKind, Int)?, Int)] = [
    ("かえんほうしゃ", Some((@model.BurnKind, 10)), 0),
    ("れいとうビーム", Some((@model.FreezeKind, 10)), 0),
    ("かみなりのキバ", Some((@model.ParalyzeKind, 10)), 10),
  ]
  for c in names_and_expect {
    let (name, want_status, want_flinch) = c
    let mv = match @db.query_champions_move(db, name) {
      Ok(m) => m
      Err(e) => {
        @db.close(db)
        fail("query_champions_move(" + name + ") failed: " + e)
      }
    }
    match rt_through_select_input([mv]) {
      Some(got) => {
        assert_true(got[0].status_effect == want_status)
        assert_true(got[0].flinch_chance == want_flinch)
      }
      None => {
        @db.close(db)
        fail("round trip through select input failed: " + name)
      }
    }
  }
  @db.close(db)
}

///|
test "pkdx moves -> select input: アイアンヘッド はひるみ 20% (本文どおり), no status; どくどくのキバ もうどく 50% without flinch" {
  let db = match rt_open_champions() {
    Some(d) => d
    None => return
  }
  let iron = match @db.query_champions_move(db, "アイアンヘッド") {
    Ok(m) => m
    Err(e) => {
      @db.close(db)
      fail("query_champions_move(アイアンヘッド) failed: " + e)
    }
  }
  let fang = match @db.query_champions_move(db, "どくどくのキバ") {
    Ok(m) => m
    Err(e) => {
      @db.close(db)
      fail("query_champions_move(どくどくのキバ) failed: " + e)
    }
  }
  match rt_through_select_input([iron, fang]) {
    Some(got) => {
      assert_true(got[0].status_effect == None)
      assert_true(got[0].flinch_chance == 20)
      assert_true(got[1].status_effect == Some((@model.BadPoisonKind, 50)))
      assert_true(got[1].flinch_chance == 0)
    }
    None => {
      @db.close(db)
      fail("round trip through select input failed (iron/fang)")
    }
  }
  @db.close(db)
}

///|
test "pkdx moves -> select input: pure status moves arrive with the DB-normalised chance 100" {
  let db = match rt_open_champions() {
    Some(d) => d
    None => return
  }
  // おにび は DB の ailment_chance が 85 (= 命中)。DB 経路で 100 に正規化済みなので、
  // JSON 経由でも 命中 × 確率 の二重抽選にならない。
  let oni = match @db.query_champions_move(db, "おにび") {
    Ok(m) => m
    Err(e) => {
      @db.close(db)
      fail("query_champions_move(おにび) failed: " + e)
    }
  }
  match rt_through_select_input([oni]) {
    Some(got) => {
      assert_true(got[0].status_effect == Some((@model.BurnKind, 100)))
      assert_true(got[0].accuracy == 85)
    }
    None => {
      @db.close(db)
      fail("round trip through select input failed (おにび)")
    }
  }
  @db.close(db)
}

///|
test "pkdx moves list (メガカイリュー 0149001) -> select input: every move keeps status_effect / flinch_chance / stat_effects" {
  let db = match rt_open_champions() {
    Some(d) => d
    None => return
  }
  let moves = match @db.query_champions_moves(db, "0149001") {
    Ok(m) => m
    Err(e) => {
      @db.close(db)
      fail("query_champions_moves failed: " + e)
    }
  }
  @db.close(db)
  assert_true(moves.length() > 0)
  let got = match rt_through_select_input(moves) {
    Some(g) => g
    None => fail("round trip through select input failed (list)")
  }
  assert_true(got.length() == moves.length())
  let mut with_status = 0
  let mut with_flinch = 0
  for i = 0; i < moves.length(); i = i + 1 {
    let want = moves[i]
    let have = got[i]
    assert_true(have.name == want.name)
    assert_true(have.power == want.power)
    assert_true(have.accuracy == want.accuracy)
    assert_true(have.priority == want.priority)
    assert_true(have.stat_effects == want.stat_effects)
    assert_true(have.status_effect == want.status_effect)
    assert_true(have.flinch_chance == want.flinch_chance)
    if want.status_effect is Some(_) {
      with_status = with_status + 1
    }
    if want.flinch_chance > 0 {
      with_flinch = with_flinch + 1
    }
  }
  // 空振りのテストにならないことを確認する (この個体は両方を覚える)。
  assert_true(with_status > 0)
  assert_true(with_flinch > 0)
}
