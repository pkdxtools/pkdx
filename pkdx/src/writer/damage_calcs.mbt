///|
/// `pkdx damage --attach-team` 用ヘルパ。計算結果を
/// `box/teams/<slug>.meta.json` の `damage_calcs[]` に追記する。
///
/// FE (site/src/lib/team-meta.ts) の `DamageCalc` schema に合わせて
/// JSON を組み立てる。未指定フィールド (note / title / 空性格等) は
/// optional 側に倒し、FE の z.safeParse が外れないように null / missing
/// を使い分ける。
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
  if seen { Some(n) } else { None }
}

///|
fn nature_to_jp_opt(n : @model.Nature?) -> String {
  match n {
    Some(nat) => nat.name_ja
    None => ""
  }
}

///|
fn optional_string(s : String) -> Json {
  if s.length() == 0 {
    Json::null()
  } else {
    s.to_json()
  }
}

///|
fn rank_entry(stat_key : String, rank : Int) -> Map[String, Json] {
  let m : Map[String, Json] = {}
  if rank != 0 {
    m[stat_key] = rank.to_json()
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
    "name": input.attacker.name_ja.to_json(),
    "level": (50 : Int).to_json(),
    "ability": optional_string(input.atk_ability),
    "item": optional_string(input.atk_item),
    "nature": optional_string(nature_to_jp_opt(input.atk_nature)),
    "tera_type": optional_string(input.tera_type),
    "ranks": rank_entry(atk_stat_key, input.atk_rank).to_json(),
  }
  let defender : Map[String, Json] = {
    "name": input.defender.name_ja.to_json(),
    "level": (50 : Int).to_json(),
    "ability": optional_string(input.def_ability),
    "item": optional_string(input.def_item),
    "nature": optional_string(nature_to_jp_opt(input.def_nature)),
    "tera_type": Json::null(),
    "hp_stat": result.defender_hp.to_json(),
    "ranks": rank_entry(def_stat_key, input.def_rank).to_json(),
  }
  let move_obj : Map[String, Json] = {
    "name": input.move_.name.to_json(),
    "type": input.move_.type_.to_json(),
    "category": @model.category_to_jp(input.move_.category).to_json(),
    "power": input.move_.power.to_json(),
  }
  let conditions : Map[String, Json] = {
    "weather": optional_string(weather_to_jp(input.weather)),
    "field": optional_string(field_to_jp(input.field)),
    "crit": input.critical.to_json(),
  }
  let rolls : Array[Json] = []
  for i = 0; i < 16; i = i + 1 {
    rolls.push(result.percents[i].to_json())
  }
  let entry : Map[String, Json] = {
    "title": optional_string(title),
    "attacker": attacker.to_json(),
    "defender": defender.to_json(),
    "move": move_obj.to_json(),
    "conditions": conditions.to_json(),
    "rolls_percent": rolls.to_json(),
    "min_percent": result.min_percent.to_json(),
    "max_percent": result.max_percent.to_json(),
    "note": optional_string(note),
  }
  match parse_guaranteed_hits(result.ko_text) {
    Some(n) => entry["guaranteed_hits"] = n.to_json()
    None => ()
  }
  entry.to_json()
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
  root["damage_calcs"] = next.to_json()
  root.to_json()
}
