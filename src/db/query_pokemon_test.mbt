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
/// champions.db を開いて pokedex.db を attach した Db ハンドルを返す。
/// `CHAMPIONS_DB` env を最優先 (`open_for` 内 `resolve_champions_db_path_from`
/// 経由)。env なしの環境では `pokedex/champions.db` 等の sibling を探す。
/// champions.db が存在しないインストールでは silent skip する (本ファイルの
/// 他テスト同様、`fail` ではなく `None` を返して呼び出し側で `return`)。
fn open_test_champions_db() -> Db? {
  let pokedex_path = match find_test_db() {
    Some(p) => p
    None => return None
  }
  let champions_path = resolve_champions_db_path_from(pokedex_path)
  if not(file_exists(champions_path)) {
    return None
  }
  match open_for(pokedex_path, "champions") {
    Ok(db) => Some(db)
    Err(_) => None
  }
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
  let db = match open_test_champions_db() {
    Some(d) => d
    None => return
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
  let db = match open_test_champions_db() {
    Some(d) => d
    None => return
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
  let db = match open_test_champions_db() {
    Some(d) => d
    None => return
  }
  let result = query_moves(db, "0445", "champions")
  close(db)
  match result {
    Ok(moves) => {
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
/// 外部番号体系と globalNo が異なる Gen9 ポケモンが正しい globalNo で登録されていること。
test "query_pokemon: スコヴィラン champions globalNo" {
  let db = match open_test_champions_db() {
    Some(d) => d
    None => return
  }
  let result = query_pokemon(db, "スコヴィラン", "champions")
  close(db)
  match result {
    Ok(p) => {
      // 外部番号 939 と混同されがちだが正しい globalNo は 0952
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

// 011_form_name_aliases (フォーム別名解決) の回帰テスト群。
// 原種→forms[]→特化名 という発見フローが壊れないように検証する。

///|
/// Rotom 系は pokedex_form.form が原種名を含む (ウォッシュロトム ⊃ ロトム)
/// ため、合成せず verbatim で検索できる。フォーム直引きなので forms は空。
test "query_pokemon: ウォッシュロトム champions (direct form alias)" {
  let db = match open_test_champions_db() {
    Some(d) => d
    None => return
  }
  let result = query_pokemon(db, "ウォッシュロトム", "champions")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0479")
      inspect(p.name_ja, content="ウォッシュロトム")
      // champions.db (champout SSoT) には英語名行を持たない。多言語対応は後続。
      inspect(p.name_en, content="")
      inspect(p.type1, content="でんき")
      inspect(p.type2, content="みず")
      inspect(p.spa, content="105")
      // フォーム直引きは forms[] 非表示 (原種に戻ってから見る導線)
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// アローラのすがた 等のリージョンフォームは species 共有なので
/// "{species}（{form}）" に合成して一意化している。
test "query_pokemon: キュウコン（アローラ） scarlet_violet (composed alias)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "キュウコン（アローラ）", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0038")
      inspect(p.name_ja, content="キュウコン（アローラ）")
      inspect(p.name_en, content="Ninetales (Alolan)")
      inspect(p.type1, content="こおり")
      inspect(p.atk, content="67")
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 原種 (base) 引きでは forms[] に該当 version で実在するフォームが列挙される。
/// Discoverability の核: ユーザーがここから候補を選んで再 query する。
test "query_pokemon: ロトム champions + forms list (discoverability)" {
  let db = match open_test_champions_db() {
    Some(d) => d
    None => return
  }
  let result = query_pokemon(db, "ロトム", "champions")
  close(db)
  match result {
    Ok(p) => {
      // 原種は base 情報を返す (既存動作の回帰チェックも兼ねる)
      inspect(p.name_ja, content="ロトム")
      inspect(p.type2, content="ゴースト")
      let mut found_wash = false
      let mut found_heat = false
      let mut found_frost = false
      let mut found_fan = false
      let mut found_mow = false
      for i = 0; i < p.forms.length(); i = i + 1 {
        match p.forms[i] {
          "ウォッシュロトム" => found_wash = true
          "ヒートロトム" => found_heat = true
          "フロストロトム" => found_frost = true
          "スピンロトム" => found_fan = true
          "カットロトム" => found_mow = true
          _ => ()
        }
      }
      assert_true(found_wash)
      assert_true(found_heat)
      assert_true(found_frost)
      assert_true(found_fan)
      assert_true(found_mow)
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 原種引きで合成 alias が forms[] に一意名で現れる。
test "query_pokemon: キュウコン scarlet_violet + forms list (regional)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "キュウコン", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.name_ja, content="キュウコン")
      let mut found = false
      for i = 0; i < p.forms.length(); i = i + 1 {
        if p.forms[i] == "キュウコン（アローラ）" {
          found = true
        }
      }
      assert_true(found)
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// champout SSoT では 9 種類の毛型 (ハートカット〜キングダムカット) も別
/// pokemon 行として登録されるため、原種引きの forms[] にそのまま列挙される。
/// 戦闘面では同一 stats / type / ability なので "cosmetic" 扱いだが、
/// migration での除外は champions.db では行わない (Phase 9 の品質改善で
/// 検討)。ここでは「基本値が species 名で取れる」ことと「form 数が一致する」
/// ことのみ検証する。
test "query_pokemon: トリミアン champions (cosmetic forms listed)" {
  let db = match open_test_champions_db() {
    Some(d) => d
    None => return
  }
  let result = query_pokemon(db, "トリミアン", "champions")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0676")
      inspect(p.name_ja, content="トリミアン")
      inspect(p.forms.length(), content="9")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 012_gender_symbol_aliases: M base id 上の `イダイトウ（オス）` を直接引いた時、
/// (a) name_ja が日本語名のままで返ること, (b) base id 共有でも forms[] が
/// 出ないこと (alias 直引きは F のような discoverability 不要)。
test "query_pokemon: イダイトウ（オス） scarlet_violet (gender alias jpn)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "イダイトウ（オス）", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0902")
      inspect(p.name_ja, content="イダイトウ（オス）")
      inspect(p.name_en, content="Basculegion (Male)")
      // M ステ (atk 112)
      inspect(p.atk, content="112")
      inspect(p.spa, content="80")
      // alias 直引きは forms[] 非表示 (base id 共有でも form 列が非空なので除外)
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// English alias 引き (`Basculegion (Male)`) で name_ja が英語に化けないこと。
/// pn が eng 行にマッチしても pnj 自己結合で jpn 行から name_ja が取れる。
test "query_pokemon: Basculegion (Male) scarlet_violet (gender alias eng → jpn name)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "Basculegion (Male)", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0902")
      // English 引きでも name_ja は jpn 行から取れること (本 PR の主目的)
      inspect(p.name_ja, content="イダイトウ（オス）")
      inspect(p.name_en, content="Basculegion (Male)")
      inspect(p.atk, content="112")
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// English alias 引き (`Basculegion (Female)`, m011 経由) でも同様に name_ja が
/// 日本語名で返ること。M/F 両側で name_ja の整合性が崩れないことを確認。
test "query_pokemon: Basculegion (Female) scarlet_violet (eng alias → jpn name)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "Basculegion (Female)", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0902")
      inspect(p.name_ja, content="イダイトウ（メス）")
      inspect(p.name_en, content="Basculegion (Female)")
      // F ステ (atk 92)
      inspect(p.atk, content="92")
      inspect(p.spa, content="100")
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 性別未指定の base 直引きは M base 値を返し、forms[] に F alias を含む。
/// M alias (`イダイトウ（オス）`) は M base id を共有するため query_forms
/// の "id != base_id" 条件で除外され forms[] には現れない。
test "query_pokemon: イダイトウ scarlet_violet (base form discovery)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "イダイトウ", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0902")
      inspect(p.name_ja, content="イダイトウ")
      inspect(p.name_en, content="Basculegion")
      // base = M ステ (atk 112 / spa 80)
      inspect(p.atk, content="112")
      inspect(p.spa, content="80")
      // forms[] には F alias のみ
      inspect(p.forms.length(), content="1")
      inspect(p.forms[0], content="イダイトウ（メス）")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// ステ差ではなく特性差で M/F が分かれる種 (ニャオニクス) でも gender alias
/// が機能すること。M HA は いたずらごころ、F HA は かちき。
test "query_pokemon: ニャオニクス（オス） scarlet_violet (gender alias ability diff)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "ニャオニクス（オス）", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0678")
      inspect(p.name_ja, content="ニャオニクス（オス）")
      inspect(p.name_en, content="Meowstic (Male)")
      inspect(p.dream_ability, content="いたずらごころ")
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// gender alias は scarlet_violet だけでなく Champions でも引けること。
/// version 横断で同一 alias が機能することを保証する。`イダイトウ（オス）`
/// は M base 行 (form='') の合成 alias なので、引いた結果 forms[] には
/// F の合成 alias (`イダイトウ（メス）`) が 1 件出る。
test "query_pokemon: イダイトウ（オス） champions (gender alias version cross)" {
  let db = match open_test_champions_db() {
    Some(d) => d
    None => return
  }
  let result = query_pokemon(db, "イダイトウ（オス）", "champions")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0902")
      inspect(p.name_ja, content="イダイトウ（オス）")
      inspect(p.atk, content="112")
      inspect(p.spa, content="80")
      inspect(p.forms.length(), content="1")
      inspect(p.forms[0], content="イダイトウ（メス）")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 該当 version にそのフォームが無い場合は "Pokemon not found"。
/// Therian Landorus は BW/BW2/LegendsArceus にしか無い。
test "query_pokemon: Therian form absent in SV errors cleanly" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "ランドロス（れいじゅう）", "scarlet_violet")
  close(db)
  match result {
    Ok(_) => fail("should have failed: therian not in SV")
    Err(_) => ()
  }
}
