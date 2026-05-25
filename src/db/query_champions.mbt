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
      let seen : Map[String, Bool] = Map([])
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
/// として参照可能)。
///
/// m014 (move_meta に heal_* / weather_set 列を追加) が pokedex.db に
/// 適用済みであることが prerequisite。SELECT 列が存在しない pokedex.db
/// では SQLite が `no such column` を返して prepare に失敗するため、
/// `setup.sh` (= 全 migration を走らせる) を実行してから本クエリを呼ぶ
/// 運用にする。`COALESCE` は行の NULL を埋めるだけで列の存在は保証しない
/// 点に注意。
pub fn query_champions_moves(
  db : Db,
  pokemon_id : String,
) -> Result[Array[@model.Move], String] {
  // Issue #3: ATTACH 済み `pokedex.move_meta` に対して PRAGMA で列存在を確認。
  let heal_cols = if move_meta_has_heal_columns(db, "pokedex") {
    healing_select_columns()
  } else {
    ""
  }
  // C-4 / m015: field 列も独立 PRAGMA detect (ATTACH 済 pokedex.move_meta)
  let field_cols = if move_meta_has_field_columns(db, "pokedex") {
    field_select_columns()
  } else {
    ""
  }
  let sql =
    "SELECT DISTINCT m.waza, m.type, m.category,\n" +
    "       m.power, m.accuracy, m.pp, l.conditions AS learn_method,\n" +
    "       COALESCE(mm.priority, 0) AS priority,\n" +
    "       COALESCE(mm.stat_effects_json, '[]') AS stat_effects_json,\n" +
    "       COALESCE(mm.ailment_ja, '') AS ailment_ja,\n" +
    "       COALESCE(mm.ailment_chance, 100) AS ailment_chance,\n" +
    "       COALESCE(mm.recoil_num, 0) AS recoil_num,\n" +
    "       COALESCE(mm.recoil_den, 1) AS recoil_den,\n" +
    "       COALESCE(mm.self_ko, 0) AS self_ko,\n" +
    "       COALESCE(mm.recharge, 0) AS recharge" +
    heal_cols +
    field_cols +
    "\nFROM learnset l\n" +
    "JOIN move m ON l.waza = m.waza\n" +
    "LEFT JOIN pokedex.move_meta mm ON mm.name_ja = m.waza\n" +
    "WHERE l.id = ?\n" +
    "ORDER BY CAST(REPLACE(m.power, '-', '0') AS INTEGER) DESC"
  collect_champions_moves_rows(
    db,
    sql,
    [pokemon_id],
    has_heal=heal_cols != "",
    has_field=field_cols != "",
  )
}

///|
/// has_heal / has_field の意味は `collect_moves_rows` と同じ。row index 配置:
///   - 14 列固定 + heal 8 列 (has_heal=true) + field 2 列 (has_field=true)
///   - heal_base = 15, field_base = 23 (heal あり) / 15 (heal なし)
fn collect_champions_moves_rows(
  db : Db,
  sql : String,
  binds : Array[String],
  has_heal~ : Bool = true,
  has_field~ : Bool = true,
) -> Result[Array[@model.Move], String] {
  let rows = match query(db, sql, binds) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let moves : Array[@model.Move] = []
  let heal_base = 15
  let field_base = if has_heal { 23 } else { 15 }
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
    let healing = if has_heal {
      let heal_kind = if r.length() > heal_base { r[heal_base] } else { "" }
      let heal_num = if r.length() > heal_base + 1 {
        parse_int_simple(r[heal_base + 1])
      } else {
        0
      }
      let heal_den = if r.length() > heal_base + 2 {
        parse_int_simple(r[heal_base + 2])
      } else {
        1
      }
      let heal_sunny_num = if r.length() > heal_base + 3 {
        parse_int_simple(r[heal_base + 3])
      } else {
        0
      }
      let heal_sunny_den = if r.length() > heal_base + 4 {
        parse_int_simple(r[heal_base + 4])
      } else {
        1
      }
      let heal_harsh_num = if r.length() > heal_base + 5 {
        parse_int_simple(r[heal_base + 5])
      } else {
        0
      }
      let heal_harsh_den = if r.length() > heal_base + 6 {
        parse_int_simple(r[heal_base + 6])
      } else {
        1
      }
      parse_healing(
        heal_kind, heal_num, heal_den, heal_sunny_num, heal_sunny_den, heal_harsh_num,
        heal_harsh_den,
      )
    } else {
      None
    }
    let weather_set = if has_heal {
      let weather_set_str = if r.length() > heal_base + 7 {
        r[heal_base + 7]
      } else {
        ""
      }
      parse_weather_set(weather_set_str)
    } else {
      None
    }
    let field_set = if has_field {
      let field_set_str = if r.length() > field_base { r[field_base] } else { "" }
      parse_field_set(field_set_str)
    } else {
      None
    }
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
      healing,
      weather_set,
      field_set,
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
  // Issue #3: ATTACH 済み `pokedex.move_meta` の列存在を PRAGMA で確認。
  let heal_cols = if move_meta_has_heal_columns(db, "pokedex") {
    healing_select_columns()
  } else {
    ""
  }
  // C-4 / m015: field 列も独立 PRAGMA detect。
  let field_cols = if move_meta_has_field_columns(db, "pokedex") {
    field_select_columns()
  } else {
    ""
  }
  let has_heal = heal_cols != ""
  let has_field = field_cols != ""
  let sql =
    "SELECT m.waza, m.type, m.category, m.power, m.accuracy, m.pp,\n" +
    "       COALESCE(mm.priority, 0) AS priority,\n" +
    "       COALESCE(mm.stat_effects_json, '[]') AS stat_effects_json,\n" +
    "       COALESCE(mm.ailment_ja, '') AS ailment_ja,\n" +
    "       COALESCE(mm.ailment_chance, 100) AS ailment_chance,\n" +
    "       COALESCE(mm.recoil_num, 0) AS recoil_num,\n" +
    "       COALESCE(mm.recoil_den, 1) AS recoil_den,\n" +
    "       COALESCE(mm.self_ko, 0) AS self_ko,\n" +
    "       COALESCE(mm.recharge, 0) AS recharge" +
    heal_cols +
    field_cols +
    "\nFROM move m\n" +
    "LEFT JOIN pokedex.move_meta mm ON mm.name_ja = m.waza\n" +
    "WHERE m.waza = ?\n" +
    "LIMIT 1"
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
  let recoil_num = if r.length() > 10 { parse_int_simple(r[10]) } else { 0 }
  let recoil_den_raw = if r.length() > 11 { parse_int_simple(r[11]) } else { 1 }
  let recoil_den = if recoil_den_raw <= 0 { 1 } else { recoil_den_raw }
  let self_ko = if r.length() > 12 { parse_int_simple(r[12]) != 0 } else {
    false
  }
  let recharge = if r.length() > 13 { parse_int_simple(r[13]) != 0 } else {
    false
  }
  let heal_base = 14
  let field_base = if has_heal { 22 } else { 14 }
  let healing = if has_heal {
    let heal_kind = if r.length() > heal_base { r[heal_base] } else { "" }
    let heal_num = if r.length() > heal_base + 1 {
      parse_int_simple(r[heal_base + 1])
    } else {
      0
    }
    let heal_den = if r.length() > heal_base + 2 {
      parse_int_simple(r[heal_base + 2])
    } else {
      1
    }
    let heal_sunny_num = if r.length() > heal_base + 3 {
      parse_int_simple(r[heal_base + 3])
    } else {
      0
    }
    let heal_sunny_den = if r.length() > heal_base + 4 {
      parse_int_simple(r[heal_base + 4])
    } else {
      1
    }
    let heal_harsh_num = if r.length() > heal_base + 5 {
      parse_int_simple(r[heal_base + 5])
    } else {
      0
    }
    let heal_harsh_den = if r.length() > heal_base + 6 {
      parse_int_simple(r[heal_base + 6])
    } else {
      1
    }
    parse_healing(
      heal_kind, heal_num, heal_den, heal_sunny_num, heal_sunny_den, heal_harsh_num,
      heal_harsh_den,
    )
  } else {
    None
  }
  let weather_set = if has_heal {
    let weather_set_str = if r.length() > heal_base + 7 {
      r[heal_base + 7]
    } else {
      ""
    }
    parse_weather_set(weather_set_str)
  } else {
    None
  }
  let field_set = if has_field {
    let field_set_str = if r.length() > field_base { r[field_base] } else { "" }
    parse_field_set(field_set_str)
  } else {
    None
  }
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
    recoil_num,
    recoil_den,
    self_ko,
    recharge,
    healing,
    weather_set,
    field_set,
  })
}

///|
/// 名前 (jpn) から champions pokemon の 7 桁 id を直接解決。form 込みの
/// learnset を引く前段で使う。
///
/// `query_champions_pokemon` が `@model.Pokemon` を返すのに対し、本関数は
/// id (= `<globalNo:4><form:3>`) だけを返す。CLI の moves サブコマンドが
/// `query_champions_moves(db, id)` に直接渡して、ロトム各フォルムの固有技
/// (ハイドロポンプ / オーバーヒート / ふぶき / エアスラッシュ /
/// リーフストーム) や、メガ等のフォーム別 learnset を取り出すために使用。
pub fn query_champions_pokemon_id_by_name(
  db : Db,
  name : String,
) -> Result[String, String] {
  let sql =
    #|SELECT pn.id
    #|FROM pokemon_name pn
    #|WHERE pn.language = 'jpn' AND pn.name = ?
    #|LIMIT 1
  let rows = match query(db, sql, [name]) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if rows.length() == 0 {
    return Err("Pokemon not found: " + name)
  }
  Ok(rows[0][0])
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
