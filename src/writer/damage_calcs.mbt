///|
/// `pkdx damage --attach-team` 用ヘルパ。計算結果を
/// `box/teams/<slug>.meta.json` の `damage_calcs[]` に追記する。
///
/// FE (site/src/lib/team-meta.ts) の `DamageCalc` schema は optional を
/// `z.string().optional()` で定義しており `null` は受け付けない。空値は
/// キーごと省略する (`null` を書き込むと z.safeParse が外れて team page の
/// メタ情報が丸ごと欠落する)。
fn weather_to_jp(w : @model.Weather) -> String {
  match w {
    None => ""
    Sun => "はれ"
    Rain => "あめ"
    Sand => "すなあらし"
    Snow => "ゆき"
  }
}

///|
fn field_to_jp(f : @model.Field) -> String {
  match f {
    None => ""
    Electric => "エレキ"
    Grassy => "グラス"
    Psychic => "サイコ"
    Misty => "ミスト"
  }
}

///|
/// ko_text ("確定N発" / "乱数N発(M/16)" / "5発以上") を
/// FE schema の `guaranteed_hits?: number` に戻す。
/// 乱数は None (FE 側で rolls_percent から再計算可)、5発以上も None。
fn parse_guaranteed_hits(ko_text : String) -> Int? {
  // 確定 = U+78BA U+5B9A
  let marker = "\u{78BA}\u{5B9A}"
  if !ko_text.has_prefix(marker) {
    return None
  }
  // "確定" 以降を走査して連続する数字を拾う。
  let mut i = marker.length()
  let mut n = 0
  let mut seen = false
  while i < ko_text.length() {
    let c = ko_text[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      n = n * 10 + (c - 0x30)
      seen = true
      i = i + 1
    } else {
      break
    }
  }
  if seen {
    Some(n)
  } else {
    None
  }
}

///|
fn nature_to_jp_opt(n : @model.Nature?) -> String {
  match n {
    Some(nat) => nat.name_ja
    None => ""
  }
}

///|
fn set_optional_string(
  m : Map[String, Json],
  key : String,
  value : String,
) -> Unit {
  if value.length() > 0 {
    m[key] = Json(value)
  }
}

///|
fn rank_entry(stat_key : String, rank : Int) -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  if rank != 0 {
    m[stat_key] = Json(rank)
  }
  m
}

///|
/// Build a damage_calcs entry matching site/src/lib/team-meta.ts DamageCalc.
/// title / note は呼び出し側で文字列として受け取り、空文字なら省略する。
/// stat_key は "atk" (Physical / ボディプレス等) もしくは "spa" (Special).
pub fn build_damage_calc_entry(
  input : @model.DamageCalcInput,
  result : @model.DamageCalcResult,
  title : String,
  note : String,
) -> Json {
  // ランク補正は Physical/Special で攻撃 stat の key が変わる。
  // Status 技で damage を呼ぶことはないため Physical/Special のみ考慮。
  let atk_stat_key = match input.move_.category {
    Physical => "atk"
    Special => "spa"
    Status => "atk"
  }
  let def_stat_key = match input.move_.category {
    Physical => "def"
    Special => "spd"
    Status => "def"
  }
  let attacker : Map[String, Json] = {
    "name": Json(input.attacker.name_ja),
    "level": Json((50 : Int)),
    "ranks": Json(rank_entry(atk_stat_key, input.atk_rank)),
  }
  set_optional_string(attacker, "ability", input.atk_ability)
  set_optional_string(attacker, "item", input.atk_item)
  set_optional_string(attacker, "nature", nature_to_jp_opt(input.atk_nature))
  set_optional_string(attacker, "tera_type", input.tera_type)
  let defender : Map[String, Json] = {
    "name": Json(input.defender.name_ja),
    "level": Json((50 : Int)),
    "hp_stat": Json(result.defender_hp),
    "ranks": Json(rank_entry(def_stat_key, input.def_rank)),
  }
  set_optional_string(defender, "ability", input.def_ability)
  set_optional_string(defender, "item", input.def_item)
  set_optional_string(defender, "nature", nature_to_jp_opt(input.def_nature))
  let move_obj : Map[String, Json] = {
    "name": Json(input.move_.name),
    "type": Json(input.move_.type_),
    "category": Json(@model.category_to_jp(input.move_.category)),
    "power": Json(input.move_.power),
  }
  let conditions : Map[String, Json] = { "crit": Json(input.critical) }
  set_optional_string(conditions, "weather", weather_to_jp(input.weather))
  set_optional_string(conditions, "field", field_to_jp(input.field))
  let rolls : Array[Json] = []
  for i = 0; i < 16; i = i + 1 {
    rolls.push(Json(result.percents[i]))
  }
  let entry : Map[String, Json] = {
    "attacker": Json(attacker),
    "defender": Json(defender),
    "move": Json(move_obj),
    "conditions": Json(conditions),
    "rolls_percent": Json(rolls),
    "min_percent": Json(result.min_percent),
    "max_percent": Json(result.max_percent),
  }
  set_optional_string(entry, "title", title)
  set_optional_string(entry, "note", note)
  match parse_guaranteed_hits(result.ko_text) {
    Some(n) => entry["guaranteed_hits"] = Json(n)
    None => ()
  }
  Json(entry)
}

///|
/// `--attach-team` で受け取ったパスを検証する。box/teams/ 配下の
/// .meta.json のみ許可する。`..` の混入や絶対パス / ホーム展開を禁じ、
/// 任意箇所への書き込み primitive として使われないようにする。
pub fn validate_attach_team_path(path : String) -> Result[Unit, String] {
  if path.length() == 0 {
    return Err("path is empty")
  }
  if path.has_prefix("/") || path.has_prefix("~") {
    return Err("path must be relative to the workspace")
  }
  if path.contains("..") {
    return Err("path must not contain '..'")
  }
  let under_box = path.has_prefix("box/teams/") ||
    path.has_prefix("./box/teams/")
  if !under_box {
    return Err("path must be under box/teams/")
  }
  if !path.has_suffix(".meta.json") {
    return Err("path must end in .meta.json")
  }
  Ok(())
}

///|
/// Append an entry to meta_json's `damage_calcs[]`. Creates the array if
/// missing. Top-level がオブジェクトでない場合はそのまま返す (呼び出し側で
/// 失敗として扱う)。
pub fn append_damage_calc(meta_json : Json, entry : Json) -> Json {
  guard meta_json is Object(root) else { return meta_json }
  let existing : Array[Json] = match root.get("damage_calcs") {
    Some(Array(arr)) => arr
    _ => []
  }
  let next : Array[Json] = []
  for e in existing {
    next.push(e)
  }
  next.push(entry)
  root["damage_calcs"] = Json(next)
  Json(root)
}
