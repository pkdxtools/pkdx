///|
/// champions.db (新スキーマ: pokemon / pokemon_name / move / move_name /
/// learnset) に対するクエリ群。`pkdx_patch/00X_*/data.json` を champout
/// 由来へ切り替え、migrations を champions.db ターゲット (m014〜m018) に
/// 再構成した #N の対応として、`version="champions"` 経路は本ファイルに
/// 集約する。pokedex.db を main 接続にして JOIN していた旧コードからの
/// 移行は段階的で、まず本ファイルでは「ポケモン基本情報の取得」を担当する。
///
/// 接続: caller は champions.db を main にして開いた `Db` を渡す
/// (`open_champions_rw` で OK)。move_meta などの pokedex.db 由来テーブルが
/// 必要な場合は事前に `attach_pokedex` 済みであることを期待する。

///|
/// Champions ポケモンを名前 (jpn) で引く。`forms` は同 globalNo の他フォーム
/// を `pokemon_name.name (jpn)` 配列で返す。Mega 等のフォーム違いは pokemon
/// テーブルの `form` カラムが非空 / `id` が `<globalNo>FFF` (7 桁) の形で
/// 区別される。
pub fn query_champions_pokemon(
  db : Db,
  name : String,
) -> Result[@model.Pokemon, String] {
  // pokemon_name から id 解決 → pokemon を JOIN。重い alias 行 (form 別名)
  // は champions.db には今のところ持たない (pokemon 1 行 = 1 form の素直な
  // 構成)。jpn の base name と form 名の両方に対して直接マッチさせる。
  let sql =
    #|SELECT
    #|  p.id,
    #|  p.global_no,
    #|  pn.name AS name_ja,
    #|  '' AS name_en,
    #|  p.type1, p.type2,
    #|  p.hp, p.attack, p.defense, p.special_attack, p.special_defense, p.speed,
    #|  (p.hp + p.attack + p.defense + p.special_attack + p.special_defense + p.speed) AS bst,
    #|  p.ability1, p.ability2, p.dream_ability,
    #|  p.form
    #|FROM pokemon p
    #|JOIN pokemon_name pn ON p.id = pn.id AND pn.language = 'jpn'
    #|WHERE pn.name = ?
    #|LIMIT 1
  let rows = match query(db, sql, [name]) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if rows.length() == 0 {
    return Err("Pokemon not found: " + name)
  }
  let r = rows[0]
  let global_no = r[1]
  let form_str = r[16]
  // base 行 (form 空文字) を引いた時のみ forms[] を埋める。
  let forms : Array[String] = if form_str.length() == 0 {
    query_champions_forms(db, global_no, r[0])
  } else {
    []
  }
  Ok(@model.Pokemon::{
    global_no,
    name_ja: r[2],
    name_en: r[3],
    type1: r[4],
    type2: r[5],
    hp: parse_int_simple(r[6]),
    atk: parse_int_simple(r[7]),
    def_: parse_int_simple(r[8]),
    spa: parse_int_simple(r[9]),
    spd: parse_int_simple(r[10]),
    spe: parse_int_simple(r[11]),
    bst: parse_int_simple(r[12]),
    ability1: r[13],
    ability2: r[14],
    dream_ability: r[15],
    weight: 0.0,
    forms,
  })
}

///|
/// 同 globalNo の別フォームを表示名で返す。base 行 (form='') を引いた
/// ときに「Mega や別フォームへ移動するためのキー」として使う。
///
/// pokemon_name は (id, language, name) 複合 PK で、合成 alias
/// (`イダイトウ（メス）`) と form 名そのまま (`メスのすがた`) を 1 つの id
/// に対して両方持ちうる。forms[] に出すのは globalNo を跨いで一意に
/// 引ける合成 alias を優先したいので、id ごとに「`（` を含む alias」を
/// 採用し、なければ form 名 (任意の 1 行) にフォールバックする。
fn query_champions_forms(
  db : Db,
  global_no : String,
  self_id : String,
) -> Array[String] {
  let sql =
    #|SELECT
    #|  COALESCE(
    #|    (SELECT pn.name FROM pokemon_name pn
    #|     WHERE pn.id = p.id AND pn.language = 'jpn' AND pn.name LIKE '%（%'
    #|     LIMIT 1),
    #|    (SELECT pn.name FROM pokemon_name pn
    #|     WHERE pn.id = p.id AND pn.language = 'jpn'
    #|     LIMIT 1)
    #|  ) AS display_name
    #|FROM pokemon p
    #|WHERE p.global_no = ? AND p.id != ?
    #|ORDER BY p.id
  match query(db, sql, [global_no, self_id]) {
    Ok(rows) => {
      let out : Array[String] = []
      let seen : Map[String, Bool] = Map::new()
      for i = 0; i < rows.length(); i = i + 1 {
        let name = rows[i][0]
        if name.length() == 0 {
          continue
        }
        if seen.contains(name) {
          continue
        }
        seen[name] = true
        out.push(name)
      }
      out
    }
    Err(_) => []
  }
}

///|
/// Champions レギュレーションでの技プールを `pokemon.id` (例: "0959000")
/// 経由で引く。move_meta は pokedex.db 側のテーブルで、本関数は
/// `attach_pokedex` 済みの connection を期待する (= `pokedex.move_meta`
/// として参照可能)。move_meta が attached でないインストールでは LEFT JOIN
/// が黙って NULL を返し、`COALESCE` のデフォルトに落ちるので動作上は安全。
pub fn query_champions_moves(
  db : Db,
  pokemon_id : String,
) -> Result[Array[@model.Move], String] {
  let sql =
    #|SELECT DISTINCT m.waza, m.type, m.category,
    #|       m.power, m.accuracy, m.pp, l.conditions AS learn_method,
    #|       COALESCE(mm.priority, 0) AS priority,
    #|       COALESCE(mm.stat_effects_json, '[]') AS stat_effects_json,
    #|       COALESCE(mm.ailment_ja, '') AS ailment_ja,
    #|       COALESCE(mm.ailment_chance, 100) AS ailment_chance,
    #|       COALESCE(mm.recoil_num, 0) AS recoil_num,
    #|       COALESCE(mm.recoil_den, 1) AS recoil_den,
    #|       COALESCE(mm.self_ko, 0) AS self_ko,
    #|       COALESCE(mm.recharge, 0) AS recharge
    #|FROM learnset l
    #|JOIN move m ON l.waza = m.waza
    #|LEFT JOIN pokedex.move_meta mm ON mm.name_ja = m.waza
    #|WHERE l.id = ?
    #|ORDER BY CAST(REPLACE(m.power, '-', '0') AS INTEGER) DESC
  collect_champions_moves_rows(db, sql, [pokemon_id])
}

///|
fn collect_champions_moves_rows(
  db : Db,
  sql : String,
  binds : Array[String],
) -> Result[Array[@model.Move], String] {
  let rows = match query(db, sql, binds) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let moves : Array[@model.Move] = []
  for i = 0; i < rows.length(); i = i + 1 {
    let r = rows[i]
    let priority = parse_int_simple(r[7])
    let stat_effects = parse_stat_effects_json(r[8])
    let status_effect = parse_status_effect(r[9], r[10])
    let recoil_num = parse_int_simple(r[11])
    let recoil_den_raw = parse_int_simple(r[12])
    let recoil_den = if recoil_den_raw <= 0 { 1 } else { recoil_den_raw }
    let self_ko = parse_int_simple(r[13]) != 0
    let recharge = parse_int_simple(r[14]) != 0
    moves.push(@model.Move::{
      name: r[0],
      type_: r[1],
      category: @model.category_from_jp(r[2]),
      power: parse_int_simple(r[3]),
      accuracy: parse_int_simple(r[4]),
      pp: parse_int_simple(r[5]),
      learn_method: r[6],
      priority,
      stat_effects,
      status_effect,
      recoil_num,
      recoil_den,
      self_ko,
      recharge,
    })
  }
  Ok(moves)
}

///|
/// 単一の技を Japanese name で引く。`query_move(db, name, "champions")`
/// から delegate される。move_meta は pokedex.db 側なので ATTACH 済み接続を
/// 想定。
pub fn query_champions_move(
  db : Db,
  move_name : String,
) -> Result[@model.Move, String] {
  let sql =
    #|SELECT m.waza, m.type, m.category, m.power, m.accuracy, m.pp,
    #|       COALESCE(mm.priority, 0) AS priority,
    #|       COALESCE(mm.stat_effects_json, '[]') AS stat_effects_json,
    #|       COALESCE(mm.ailment_ja, '') AS ailment_ja,
    #|       COALESCE(mm.ailment_chance, 100) AS ailment_chance
    #|FROM move m
    #|LEFT JOIN pokedex.move_meta mm ON mm.name_ja = m.waza
    #|WHERE m.waza = ?
    #|LIMIT 1
  let rows = match query(db, sql, [move_name]) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if rows.length() == 0 {
    return Err("Move not found: " + move_name)
  }
  let r = rows[0]
  let priority = parse_int_simple(r[6])
  let stat_effects = parse_stat_effects_json(r[7])
  let status_effect = parse_status_effect(r[8], r[9])
  Ok(@model.Move::{
    name: r[0],
    type_: r[1],
    category: @model.category_from_jp(r[2]),
    power: parse_int_simple(r[3]),
    accuracy: parse_int_simple(r[4]),
    pp: parse_int_simple(r[5]),
    learn_method: "",
    priority,
    stat_effects,
    status_effect,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
  })
}

///|
/// pokemon.global_no + form (空 = base) から id を解決。caller が globalNo
/// しか持たないとき、Champions の learnset などを引く前段で id を取り出す。
pub fn resolve_champions_pokemon_id(
  db : Db,
  global_no : String,
  form : String,
) -> Result[String, String] {
  let sql = "SELECT id FROM pokemon WHERE global_no = ? AND form = ? LIMIT 1"
  let gno = normalize_global_no(global_no)
  let rows = match query(db, sql, [gno, form]) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if rows.length() == 0 {
    Err("Champions pokemon not found: globalNo=" + gno + " form='" + form + "'")
  } else {
    Ok(rows[0][0])
  }
}

///|
/// 単純な Int パース。負号と数字のみ。"-" 単独は 0 扱い (champout 由来の
/// power "-" を numeric として扱わないための防御)。
fn parse_int_simple(s : String) -> Int {
  let mut result = 0
  let mut i = 0
  let mut negative = false
  if i < s.length() && s[i] == '-' {
    if s.length() == 1 {
      return 0
    }
    negative = true
    i = i + 1
  }
  while i < s.length() {
    let c = s[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      result = result * 10 + (c - 0x30)
    } else {
      break
    }
    i = i + 1
  }
  if negative {
    -result
  } else {
    result
  }
}
