///|
/// Issue #3 (Schema compat): m014 が `move_meta` に追加する heal/weather 系列
/// がすべて存在するか PRAGMA で検出する。m014 未適用の DB に対して
/// unconditionally に SELECT 列を投げると SQLite が prepare 段階で
/// `no such column` で失敗する (COALESCE は実行時の NULL 補完であり、列存在
/// チェックではない) ため、query 関数側で先に列存在を検出して旧 SELECT / 新
/// SELECT を切り替える。
///
/// 戻り値:
///   - true  = `healing_select_columns()` が参照する 8 列がすべて揃っている
///             (m014 適用済み DB)。新 SELECT を投げる
///   - false = 1 列でも欠落している (m014 未適用 / 部分適用 DB)。旧 SELECT
///             (heal/weather 無し) を投げ、caller 側で Move.healing=None /
///             weather_set=None を埋める
///
/// m014 は ensure_column で 1 列ずつ ALTER TABLE するため、途中で異常終了
/// すると `heal_kind` だけ存在し他の列が無い "部分適用" 状態の DB が残り得る。
/// このとき `heal_kind` 単独チェックだと新 SELECT を投げて prepare 失敗する
/// ため、`healing_select_columns()` が参照する全列を検査する。
///
/// PRAGMA 失敗時は false にフォールバック (= 安全側、旧 SELECT で動作)。
/// `qualifier` は ATTACH された DB 名 (champions.db が pokedex.db を attach
/// するときの `pokedex` 等)。""= main DB を見る。
fn move_meta_has_heal_columns(db : Db, qualifier : String) -> Bool {
  let prefix = if qualifier == "" { "" } else { qualifier + "." }
  let sql = "PRAGMA " + prefix + "table_info(move_meta)"
  let rows = match query(db, sql, []) {
    Ok(r) => r
    Err(_) => return false
  }
  let required = [
    "heal_kind", "heal_num", "heal_den", "heal_sunny_num", "heal_sunny_den", "heal_harsh_num",
    "heal_harsh_den", "weather_set",
  ]
  let found : Array[Bool] = Array::make(required.length(), false)
  for row in rows {
    // PRAGMA table_info 出力の column index 1 が name。
    if row.length() > 1 {
      let name = row[1]
      for i = 0; i < required.length(); i = i + 1 {
        if name == required[i] {
          found[i] = true
        }
      }
    }
  }
  for present in found {
    if !present {
      return false
    }
  }
  true
}

///|
/// m015 が `move_meta` に追加する `field_set` / `field_turns` 列の有無を
/// PRAGMA table_info で検出する。`move_meta_has_heal_columns` と同じ pattern。
///
/// 戻り値:
///   - true  = 2 列とも存在する (m015 適用済み DB)。SELECT に列を加える
///   - false = 1 列でも欠落 (m015 未適用 / 部分適用 DB)。SELECT に加えず、
///             caller 側で Move.field_set=None を default で埋める
///
/// m014/m015 は **独立な migration** で異なる列を触る (heal_* vs field_*)
/// ため、本関数は `move_meta_has_heal_columns` と独立に呼ぶ。両者が独立に
/// 適用済み/未適用の組み合わせを取りうる。
fn move_meta_has_field_columns(db : Db, qualifier : String) -> Bool {
  let prefix = if qualifier == "" { "" } else { qualifier + "." }
  let sql = "PRAGMA " + prefix + "table_info(move_meta)"
  let rows = match query(db, sql, []) {
    Ok(r) => r
    Err(_) => return false
  }
  let required = ["field_set", "field_turns"]
  let found : Array[Bool] = Array::make(required.length(), false)
  for row in rows {
    if row.length() > 1 {
      let name = row[1]
      for i = 0; i < required.length(); i = i + 1 {
        if name == required[i] {
          found[i] = true
        }
      }
    }
  }
  for present in found {
    if !present {
      return false
    }
  }
  true
}

///|
/// Query all moves a Pokemon can learn (level-up + TM).
/// For champions version, reads from champions_learnset; other versions
/// use local_pokedex_waza + local_pokedex_waza_machine.
pub fn query_moves(
  db : Db,
  global_no : String,
  version : @model.GameVersion,
  include_inactive? : Bool = false,
) -> Result[Array[@model.Move], String] {
  match version {
    @model.Champions => query_moves_champions(db, global_no, include_inactive)
    @model.Other(v) => query_moves_legacy(db, global_no, v)
  }
}

///|
/// Champions のルートは新スキーマ (champions.db.learnset + move) を引く
/// `query_champions_moves` に delegate する。caller は globalNo を渡し、
/// ここで base 形態 (`<gno>000`) の id を組み立てる。Mega / 別フォームは
/// 上位の caller が `query_champions_moves` を直接呼んで個別 id を渡す
/// 想定 (現状は base のみ)。`include_inactive` は champout 由来 learnset に
/// inactive 概念がないため無視する。
fn query_moves_champions(
  db : Db,
  global_no : String,
  _include_inactive : Bool,
) -> Result[Array[@model.Move], String] {
  let id = normalize_global_no(global_no) + "000"
  query_champions_moves(db, id)
}

///|
fn query_moves_legacy(
  db : Db,
  global_no : String,
  version : String,
) -> Result[Array[@model.Move], String] {
  let waza_ver = to_waza_version(version)
  let gno = normalize_global_no(global_no)
  // Issue #3: m014 未適用の DB では heal_* 列が存在しないので、列存在を
  // PRAGMA で検出してから projection を組み立てる。
  let heal_cols = if move_meta_has_heal_columns(db, "") {
    healing_select_columns()
  } else {
    ""
  }
  // C-4 / m015: 同じ理由で field_set/field_turns 列も独立に PRAGMA detect。
  // heal/field は別 migration なので組み合わせは 4 通り取りうる。
  let field_cols = if move_meta_has_field_columns(db, "") {
    field_select_columns()
  } else {
    ""
  }
  // LEFT JOIN move_meta per both UNION branches so priority / stat_effects
  // ride along on the returned Move. COALESCE defaults preserve the legacy
  // "no metadata" behaviour for moves not in the seed table.
  let sql = "SELECT DISTINCT wl.name AS move_name, w.type, w.category,\n" +
    "       w.power, w.accuracy, w.pp, pw.conditions AS learn_method,\n" +
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
    "\nFROM local_pokedex_waza pw\n" +
    "JOIN local_waza w ON pw.waza = w.waza AND w.version = ?\n" +
    "JOIN local_waza_language wl ON pw.waza = wl.waza\n" +
    "  AND wl.version = ? AND wl.language = 'jpn'\n" +
    "LEFT JOIN move_meta mm ON mm.name_ja = wl.name\n" +
    "WHERE pw.globalNo = ? AND pw.version = ?\n" +
    "UNION\n" +
    "SELECT DISTINCT wl.name AS move_name, w.type, w.category,\n" +
    "       w.power, w.accuracy, w.pp, 'TM' AS learn_method,\n" +
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
    "\nFROM local_pokedex_waza_machine pm\n" +
    "JOIN local_waza_machine wm ON pm.machine_no = wm.waza AND wm.version = ?\n" +
    "JOIN local_waza w ON wm.machine_no = w.waza AND w.version = ?\n" +
    "JOIN local_waza_language wl ON w.waza = wl.waza\n" +
    "  AND wl.version = ? AND wl.language = 'jpn'\n" +
    "LEFT JOIN move_meta mm ON mm.name_ja = wl.name\n" +
    "WHERE pm.globalNo = ? AND pm.version = ?\n" +
    "  AND COALESCE(pm.form, '') = '' AND COALESCE(pm.region, '') = ''\n" +
    "ORDER BY power DESC"
  let binds = [
    waza_ver, waza_ver, gno, waza_ver, waza_ver, waza_ver, waza_ver, gno, waza_ver,
  ]
  collect_moves_rows(
    db,
    sql,
    binds,
    has_heal=heal_cols != "",
    has_field=field_cols != "",
  )
}

///|
/// Issue #3: m014 列があるときだけ SELECT projection に付与する 9 列文字列を
/// 返す。先頭にカンマ + 改行を含むため、caller は単純に連結すれば良い。
fn healing_select_columns() -> String {
  ",\n       COALESCE(mm.heal_kind, '') AS heal_kind,\n" +
  "       COALESCE(mm.heal_num, 0) AS heal_num,\n" +
  "       COALESCE(mm.heal_den, 1) AS heal_den,\n" +
  "       COALESCE(mm.heal_sunny_num, 0) AS heal_sunny_num,\n" +
  "       COALESCE(mm.heal_sunny_den, 1) AS heal_sunny_den,\n" +
  "       COALESCE(mm.heal_harsh_num, 0) AS heal_harsh_num,\n" +
  "       COALESCE(mm.heal_harsh_den, 1) AS heal_harsh_den,\n" +
  "       COALESCE(mm.weather_set, '') AS weather_set"
}

///|
/// m015 列があるときだけ SELECT projection に付与する 2 列文字列を返す。
/// `healing_select_columns()` と同じ pattern。`field_turns` は本 PR では
/// クエリ側で参照しない (Stage E で SwitchingGame 側に持つため将来 hook)
/// が、PRAGMA detect と同期させるため列ごと SELECT する。
fn field_select_columns() -> String {
  ",\n       COALESCE(mm.field_set, '') AS field_set,\n" +
  "       COALESCE(mm.field_turns, 0) AS field_turns"
}

///|
/// `has_heal` / `has_field` は caller 側で PRAGMA detect した結果。SELECT に
/// 含めた列だけが行に乗るため、ここでの index 解釈もそれに合わせる。
/// - has_heal=false なら m014 列は row 末尾に無い (r[14] まで)
/// - has_heal=true / has_field=false: heal 8 列が r[15..22] に乗る
/// - has_heal=true / has_field=true: 加えて field 2 列が r[23..24] に乗る
/// - has_heal=false / has_field=true: heal を飛ばして field 2 列が r[15..16]
///
/// 4 通りの組み合わせを `r.length() > N` ガードで一様に扱う。
fn collect_moves_rows(
  db : Db,
  sql : String,
  binds : Array[String],
  has_heal? : Bool = true,
  has_field? : Bool = true,
) -> Result[Array[@model.Move], String] {
  let rows = match query(db, sql, binds) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let moves : Array[@model.Move] = []
  // m014 / m015 列の row index は SELECT に含めた順で決まる。
  let heal_base = 15
  let field_base = if has_heal { 23 } else { 15 }
  for i = 0; i < rows.length(); i = i + 1 {
    let r = rows[i]
    let priority = if r.length() > 7 { parse_int(r[7]) } else { 0 }
    let stat_effects = if r.length() > 8 {
      parse_stat_effects_json(r[8])
    } else {
      []
    }
    let status_effect = if r.length() > 10 {
      parse_status_effect(r[9], r[10])
    } else {
      None
    }
    let recoil_num = if r.length() > 11 { parse_int(r[11]) } else { 0 }
    let recoil_den_raw = if r.length() > 12 { parse_int(r[12]) } else { 1 }
    let recoil_den = if recoil_den_raw <= 0 { 1 } else { recoil_den_raw }
    let self_ko = if r.length() > 13 { parse_int(r[13]) != 0 } else { false }
    let recharge = if r.length() > 14 { parse_int(r[14]) != 0 } else { false }
    let healing = if has_heal {
      let heal_kind = if r.length() > heal_base { r[heal_base] } else { "" }
      let heal_num = if r.length() > heal_base + 1 {
        parse_int(r[heal_base + 1])
      } else {
        0
      }
      let heal_den = if r.length() > heal_base + 2 {
        parse_int(r[heal_base + 2])
      } else {
        1
      }
      let heal_sunny_num = if r.length() > heal_base + 3 {
        parse_int(r[heal_base + 3])
      } else {
        0
      }
      let heal_sunny_den = if r.length() > heal_base + 4 {
        parse_int(r[heal_base + 4])
      } else {
        1
      }
      let heal_harsh_num = if r.length() > heal_base + 5 {
        parse_int(r[heal_base + 5])
      } else {
        0
      }
      let heal_harsh_den = if r.length() > heal_base + 6 {
        parse_int(r[heal_base + 6])
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
      let field_set_str = if r.length() > field_base {
        r[field_base]
      } else {
        ""
      }
      parse_field_set(field_set_str)
    } else {
      None
    }
    moves.push(@model.Move::{
      name: r[0],
      type_: r[1],
      category: @model.category_from_jp(r[2]),
      power: parse_int(r[3]),
      accuracy: parse_int(r[4]),
      pp: parse_int(r[5]),
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
/// Convert `move_meta` heal columns into a `HealingEffect?`. Empty
/// `heal_kind` (the default for `move_meta` rows that have no healing
/// metadata in m014's `data.json`) yields `None`. Denominators ≤ 0 are
/// clamped to 1 to defend against malformed seed data — the engine never
/// multiplies by 0 here. m014 must have been applied before this is
/// called — the SELECT projection references `heal_*` / `weather_set`
/// columns unconditionally and SQLite will fail at prepare time on a
/// DB that has not been migrated.
pub fn parse_healing(
  heal_kind : String,
  heal_num : Int,
  heal_den : Int,
  heal_sunny_num : Int,
  heal_sunny_den : Int,
  heal_harsh_num : Int,
  heal_harsh_den : Int,
) -> @model.HealingEffect? {
  if heal_kind == "" {
    return None
  }
  let den = if heal_den <= 0 { 1 } else { heal_den }
  let sden = if heal_sunny_den <= 0 { 1 } else { heal_sunny_den }
  let hden = if heal_harsh_den <= 0 { 1 } else { heal_harsh_den }
  match heal_kind {
    "fixed" => Some(FixedFraction(heal_num, den))
    "weather" =>
      Some(
        WeatherDependent(
          heal_num, den, heal_sunny_num, sden, heal_harsh_num, hden,
        ),
      )
    "drain" => Some(Drain(heal_num, den))
    "rest" => Some(Rest)
    "leech_seed" => Some(LeechSeed)
    "pain_split" => Some(PainSplit)
    "wish" => Some(Wish)
    _ => None
  }
}

///|
/// Convert `move_meta.weather_set` ('' / 'sun' / 'rain' / 'sand' / 'snow')
/// into `Weather?`. Empty / unknown strings yield `None`.
pub fn parse_weather_set(weather_set : String) -> @model.Weather? {
  match weather_set {
    "" => None
    "sun" => Some(Sun)
    "rain" => Some(Rain)
    "sand" => Some(Sand)
    "snow" => Some(Snow)
    _ => None
  }
}

///|
/// Convert `move_meta.field_set` ('' / 'electric' / 'grassy' / 'misty' /
/// 'psychic') into `Field?`. Empty / unknown strings yield `None`. m015 で
/// 投入される canonical 値を `@model.field_from_jp` と同じパーサで解決する
/// (関数は内部で日本語 CLI 表記と DB canonical を両方受けるので、ここから
/// 共有して値域を一意に保つ)。
pub fn parse_field_set(field_set : String) -> @model.Field? {
  if field_set == "" {
    return None
  }
  match @model.field_from_jp(field_set) {
    @model.Field::None => None
    f => Some(f)
  }
}

///|
/// Parse a JSON-encoded array of stat-effect entries into
/// `Array[StatEffect]`. Accepts two shapes to preserve backwards compat:
///
/// - Legacy 2-element: `[stat, delta]` — `target` defaults to `0` (self)
/// - New 3-element: `[stat, delta, target]` — `target` 0=self, 1=opp
///
/// Returns `[]` on any parse error or non-conforming shape so a single
/// malformed DB row cannot break a whole moveset query.
fn parse_stat_effects_json(raw : String) -> Array[@model.StatEffect] {
  let out : Array[@model.StatEffect] = []
  let json = @json.parse(raw) catch { _ => return out }
  match json {
    Array(arr) =>
      for item in arr {
        match item {
          Array(triple) => {
            let len = triple.length()
            if len == 2 || len == 3 {
              let a = json_number_to_int(triple[0])
              let b = json_number_to_int(triple[1])
              let t = if len == 3 {
                match json_number_to_int(triple[2]) {
                  Some(x) => x
                  None => 0
                }
              } else {
                0
              }
              match (a, b) {
                (Some(ai), Some(bi)) =>
                  out.push(@model.StatEffect::{ stat: ai, delta: bi, target: t })
                _ => ()
              }
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
fn json_number_to_int(j : Json) -> Int? {
  match j {
    Number(n, ..) => Some(n.to_int())
    _ => None
  }
}

///|
/// Build a `status_effect` tuple from the `ailment_ja` / `ailment_chance`
/// columns of `move_meta`. Empty string or unrecognised Japanese ailment
/// names yield `None`; chances < 0 or > 100 are clamped to 100 (matches the
/// MVP scope where dedicated status moves have deterministic-looking chance
/// fields in the seed data, not secondary-effect percentages).
fn parse_status_effect(
  ailment_ja : String,
  chance_str : String,
) -> (@model.StatusKind, Int)? {
  if ailment_ja == "" {
    return None
  }
  match @model.status_kind_from_jp(ailment_ja) {
    None => None
    Some(kind) => {
      let raw = parse_int(chance_str)
      let chance = if raw <= 0 { 100 } else if raw > 100 { 100 } else { raw }
      Some((kind, chance))
    }
  }
}

///|
/// Look up a move by name (Japanese) — single move lookup distinct from the
/// learnset-oriented `query_moves`. Used by damage CLI and any caller that
/// only needs the move metadata, not a learnset listing.
///
/// version="champions" は champions.db (新スキーマ) ルートに delegate する。
pub fn query_move(
  db : Db,
  move_name : String,
  version : @model.GameVersion,
) -> Result[@model.Move, String] {
  let version = match version {
    @model.Champions => return query_champions_move(db, move_name)
    @model.Other(v) => v
  }
  let waza_ver = to_waza_version(version)
  // Issue #3: m014 未適用 DB では heal_* 列が無いため、列存在を PRAGMA で検出。
  let heal_cols = if move_meta_has_heal_columns(db, "") {
    healing_select_columns()
  } else {
    ""
  }
  // C-4 / m015: field_set/field_turns 列も独立 PRAGMA detect。
  let field_cols = if move_meta_has_field_columns(db, "") {
    field_select_columns()
  } else {
    ""
  }
  let has_heal = heal_cols != ""
  let has_field = field_cols != ""
  let sql = "SELECT wl.name, w.type, w.category, w.power, w.accuracy, w.pp,\n" +
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
    "\nFROM local_waza_language wl\n" +
    "JOIN local_waza w ON wl.waza = w.waza AND w.version = ?\n" +
    "LEFT JOIN move_meta mm ON mm.name_ja = wl.name\n" +
    "WHERE wl.version = ? AND wl.language = 'jpn' AND wl.name = ?\n" +
    "LIMIT 1"
  let rows = match query(db, sql, [waza_ver, waza_ver, move_name]) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if rows.length() == 0 {
    return Err("Move not found: " + move_name)
  }
  let r = rows[0]
  let priority = if r.length() > 6 { parse_int(r[6]) } else { 0 }
  let stat_effects = if r.length() > 7 {
    parse_stat_effects_json(r[7])
  } else {
    []
  }
  let status_effect = if r.length() > 9 {
    parse_status_effect(r[8], r[9])
  } else {
    None
  }
  let recoil_num = if r.length() > 10 { parse_int(r[10]) } else { 0 }
  let recoil_den_raw = if r.length() > 11 { parse_int(r[11]) } else { 1 }
  let recoil_den = if recoil_den_raw <= 0 { 1 } else { recoil_den_raw }
  let self_ko = if r.length() > 12 { parse_int(r[12]) != 0 } else { false }
  let recharge = if r.length() > 13 { parse_int(r[13]) != 0 } else { false }
  // m014/m015 列: SELECT projection 順は heal 8 列 → field 2 列。query_move
  // は SELECT 先頭に 14 列固定 (w.* + mm.*)、heal 列があれば r[14..21]、その
  // 後 field 列があれば r[22..23]。
  let heal_base = 14
  let field_base = if has_heal { 22 } else { 14 }
  let healing = if has_heal {
    let heal_kind = if r.length() > heal_base { r[heal_base] } else { "" }
    let heal_num = if r.length() > heal_base + 1 {
      parse_int(r[heal_base + 1])
    } else {
      0
    }
    let heal_den = if r.length() > heal_base + 2 {
      parse_int(r[heal_base + 2])
    } else {
      1
    }
    let heal_sunny_num = if r.length() > heal_base + 3 {
      parse_int(r[heal_base + 3])
    } else {
      0
    }
    let heal_sunny_den = if r.length() > heal_base + 4 {
      parse_int(r[heal_base + 4])
    } else {
      1
    }
    let heal_harsh_num = if r.length() > heal_base + 5 {
      parse_int(r[heal_base + 5])
    } else {
      0
    }
    let heal_harsh_den = if r.length() > heal_base + 6 {
      parse_int(r[heal_base + 6])
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
    power: parse_int(r[3]),
    accuracy: parse_int(r[4]),
    pp: parse_int(r[5]),
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
