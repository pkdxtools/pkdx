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

///|
/// 014–016 系 (反動・自滅・反動ターン・回復・天候設定・フィールド設定) の往復比較用の基底 Move。
/// 効果フィールドは全て既定値にしておき、テストごとに差分だけを record update で足す。
fn rt_blank_move(name : String) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
    power: 80,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
    flinch_chance: 0,
  }
}

///|
/// select 入力へ通した Move の 014–016 系フィールドが want と一致することを確認する。
fn rt_assert_014_16(got : @model.Move, want : @model.Move) -> Unit raise {
  assert_true(got.name == want.name)
  assert_true(got.recoil_num == want.recoil_num)
  assert_true(got.recoil_den == want.recoil_den)
  assert_true(got.self_ko == want.self_ko)
  assert_true(got.recharge == want.recharge)
  assert_true(got.healing == want.healing)
  assert_true(got.weather_set == want.weather_set)
  assert_true(got.field_set == want.field_set)
}

///|
/// DB を使わない: 014–016 系の全 variant を Move に直接組み立て、`pkdx moves` と同じ JSON に
/// して select の入力パーサへ通す。kind / 分数 / canonical 名の逆変換が全部 `@db` のパーサと
/// 一致することを、DB の有無に関係なく常に確認する。
test "pkdx moves -> select input (no DB): every 014-016 variant survives the round trip" {
  let base = rt_blank_move("base")
  let moves : Array[@model.Move] = [
    { ..base, name: "じごくぐるま", recoil_num: 1, recoil_den: 4 },
    { ..base, name: "じばく", self_ko: true },
    { ..base, name: "はかいこうせん", recharge: true },
    { ..base, name: "じこさいせい", healing: Some(@model.FixedFraction(1, 2)) },
    {
      ..base,
      name: "つきのひかり",
      healing: Some(@model.WeatherDependent(1, 2, 2, 3, 1, 4)),
    },
    { ..base, name: "ギガドレイン", healing: Some(@model.Drain(3, 4)) },
    { ..base, name: "ねむる", healing: Some(@model.Rest) },
    { ..base, name: "やどりぎのタネ", healing: Some(@model.LeechSeed) },
    { ..base, name: "いたみわけ", healing: Some(@model.PainSplit) },
    { ..base, name: "ねがいごと", healing: Some(@model.Wish) },
    { ..base, name: "にほんばれ", weather_set: Some(@model.Sun) },
    { ..base, name: "あまごい", weather_set: Some(@model.Rain) },
    { ..base, name: "すなあらし", weather_set: Some(@model.Sand) },
    { ..base, name: "ゆきげしき", weather_set: Some(@model.Snow) },
    { ..base, name: "エレキフィールド", field_set: Some(@model.Electric) },
    { ..base, name: "グラスフィールド", field_set: Some(@model.Grassy) },
    { ..base, name: "ミストフィールド", field_set: Some(@model.Misty) },
    { ..base, name: "サイコフィールド", field_set: Some(@model.Psychic) },
  ]
  let got = match rt_through_select_input(moves) {
    Some(g) => g
    None => fail("round trip through select input failed (synthetic 014-016)")
  }
  assert_true(got.length() == moves.length())
  for i = 0; i < moves.length(); i = i + 1 {
    rt_assert_014_16(got[i], moves[i])
  }
}

///|
/// 既定値の技 (効果なし) は、往復後も 014–016 系が全て既定値のまま (キーを省略した JSON が
/// select 側で既定値に戻る)。
test "pkdx moves -> select input (no DB): a move without 014-016 effects keeps every default" {
  let plain = rt_blank_move("たいあたり")
  let got = match rt_through_select_input([plain]) {
    Some(g) => g
    None => fail("round trip through select input failed (plain move)")
  }
  rt_assert_014_16(got[0], plain)
  assert_true(got[0].healing == None)
  assert_true(got[0].weather_set == None)
  assert_true(got[0].field_set == None)
  assert_true(got[0].recoil_den == 1)
}

///|
/// 回復技 (DB 実値: pokedex.db move_meta の heal_* 列) を champions.db 経由で読み、select 入力へ
/// 通しても同じ `HealingEffect` になる。期待値は move_meta の実値 (m014 data.json と DB 照合済み)。
test "pkdx moves -> select input (DB): heal variants じこさいせい / つきのひかり / ギガドレイン / ねむる / やどりぎのタネ / いたみわけ / ねがいごと" {
  let db = match rt_open_champions() {
    Some(d) => d
    None => return
  }
  let cases : Array[(String, @model.HealingEffect)] = [
    ("じこさいせい", @model.FixedFraction(1, 2)),
    ("つきのひかり", @model.WeatherDependent(1, 2, 2, 3, 1, 4)),
    ("あさのひざし", @model.WeatherDependent(1, 2, 2, 3, 1, 4)),
    ("こうごうせい", @model.WeatherDependent(1, 2, 2, 3, 1, 4)),
    ("ギガドレイン", @model.Drain(1, 2)),
    ("ねむる", @model.Rest),
    ("やどりぎのタネ", @model.LeechSeed),
    ("いたみわけ", @model.PainSplit),
    ("ねがいごと", @model.Wish),
  ]
  for c in cases {
    let (name, want) = c
    let mv = match @db.query_champions_move(db, name) {
      Ok(m) => m
      Err(e) => {
        @db.close(db)
        fail("query_champions_move(" + name + ") failed: " + e)
      }
    }
    // DB の値そのものが期待値と一致すること (期待値の取り違えを防ぐ)。
    assert_true(mv.healing == Some(want))
    match rt_through_select_input([mv]) {
      Some(got) => {
        assert_true(got[0].healing == Some(want))
        rt_assert_014_16(got[0], mv)
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
/// 反動 / 自滅 / 反動ターン (DB 実値: move_meta の recoil_* / self_ko / recharge、m005)。
/// てっていこうせん の反動 (最大 HP の 1/2) は名前で判定されるので、DB 列は空のまま (m016 で
/// 自己能力低下が除去済みで stat_effects も空)。
test "pkdx moves -> select input (DB): recoil / self_ko / recharge の実値" {
  let db = match rt_open_champions() {
    Some(d) => d
    None => return
  }
  // (name, recoil_num, recoil_den, self_ko, recharge)
  let cases : Array[(String, Int, Int, Bool, Bool)] = [
    ("もろはのずつき", 1, 2, false, false),
    ("ブレイブバード", 1, 3, false, false),
    ("ウッドハンマー", 1, 3, false, false),
    ("ワイルドボルト", 1, 4, false, false),
    ("じばく", 0, 1, true, false),
    ("だいばくはつ", 0, 1, true, false),
    ("はかいこうせん", 0, 1, false, true),
    ("ギガインパクト", 0, 1, false, true),
    ("てっていこうせん", 0, 1, false, false),
    ("とびひざげり", 0, 1, false, false),
  ]
  for c in cases {
    let (name, rn, rd, sk, rc) = c
    let mv = match @db.query_champions_move(db, name) {
      Ok(m) => m
      Err(e) => {
        @db.close(db)
        fail("query_champions_move(" + name + ") failed: " + e)
      }
    }
    assert_true(mv.recoil_num == rn)
    assert_true(mv.recoil_den == rd)
    assert_true(mv.self_ko == sk)
    assert_true(mv.recharge == rc)
    match rt_through_select_input([mv]) {
      Some(got) => rt_assert_014_16(got[0], mv)
      None => {
        @db.close(db)
        fail("round trip through select input failed: " + name)
      }
    }
  }
  // てっていこうせん は m016 で自己ステータス低下が消えており、反動は名前で判定される。
  let steel = match @db.query_champions_move(db, "てっていこうせん") {
    Ok(m) => m
    Err(e) => {
      @db.close(db)
      fail("query_champions_move(てっていこうせん) failed: " + e)
    }
  }
  assert_true(steel.stat_effects.length() == 0)
  @db.close(db)
}

///|
/// 天候設定 / フィールド設定 (DB 実値: move_meta の weather_set (m014) / field_set (m015))。
test "pkdx moves -> select input (DB): weather_set / field_set の実値" {
  let db = match rt_open_champions() {
    Some(d) => d
    None => return
  }
  let cases : Array[(String, @model.Weather?, @model.Field?)] = [
    ("にほんばれ", Some(@model.Sun), None),
    ("あまごい", Some(@model.Rain), None),
    ("すなあらし", Some(@model.Sand), None),
    ("ゆきげしき", Some(@model.Snow), None),
    ("エレキフィールド", None, Some(@model.Electric)),
    ("グラスフィールド", None, Some(@model.Grassy)),
    ("ミストフィールド", None, Some(@model.Misty)),
    ("サイコフィールド", None, Some(@model.Psychic)),
  ]
  for c in cases {
    let (name, want_w, want_f) = c
    let mv = match @db.query_champions_move(db, name) {
      Ok(m) => m
      Err(e) => {
        @db.close(db)
        fail("query_champions_move(" + name + ") failed: " + e)
      }
    }
    assert_true(mv.weather_set == want_w)
    assert_true(mv.field_set == want_f)
    match rt_through_select_input([mv]) {
      Some(got) => rt_assert_014_16(got[0], mv)
      None => {
        @db.close(db)
        fail("round trip through select input failed: " + name)
      }
    }
  }
  @db.close(db)
}

///|
/// 1 体分の技一覧 (フシギバナ 0003000: はかいこうせん / ギガドレイン / ねむる を含む) を丸ごと
/// 往復し、014–016 系の全フィールドが DB 値と一致すること。空振りを避けるため、回復・反動ターンの
/// 技が 1 つ以上あることも確認する。
test "pkdx moves list (フシギバナ 0003000) -> select input: 014-016 fields match the DB row by row" {
  let db = match rt_open_champions() {
    Some(d) => d
    None => return
  }
  let moves = match @db.query_champions_moves(db, "0003000") {
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
    None => fail("round trip through select input failed (フシギバナ list)")
  }
  assert_true(got.length() == moves.length())
  let mut with_heal = 0
  let mut with_recharge = 0
  for i = 0; i < moves.length(); i = i + 1 {
    rt_assert_014_16(got[i], moves[i])
    if moves[i].healing is Some(_) {
      with_heal = with_heal + 1
    }
    if moves[i].recharge {
      with_recharge = with_recharge + 1
    }
  }
  assert_true(with_heal > 0)
  assert_true(with_recharge > 0)
}
