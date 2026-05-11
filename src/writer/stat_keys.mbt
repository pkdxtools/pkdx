///|
/// 旧 schema (hp/atk/def/spa/spd/spe) と新 schema (h/a/b/c/d/s) の対応表。
/// migrator (convert.mbt) と legacy detector (validate.mbt) の両方が参照する
/// 単一情報源 (SSoT)。列挙を増やす場合はここ 1 箇所で変更する。
pub let stat_key_long_short : Array[(String, String)] = [
  ("hp", "h"),
  ("atk", "a"),
  ("def", "b"),
  ("spa", "c"),
  ("spd", "d"),
  ("spe", "s"),
]

///|
/// v011 より前の breed / team メタで stats 値を保持するフィールド名。
/// migrator は各要素を `normalize_stats_to_short` で正規化し、detector は同じ
/// 要素が long-key のまま残っていないかを検証する。
pub let stats_field_names : Array[String] = [
  "base_stats", "stat_points", "actual_stats", "ivs",
]

///|
/// stats オブジェクトに long-key (hp/atk/def/spa/spd/spe) が 1 つでも含まれるか。
/// `stat_key_long_short` を走査するため、列を増減してもここを書き換える必要はない。
pub fn has_long_stat_key(obj : Map[String, Json]) -> Bool {
  for pair in stat_key_long_short {
    let (long_k, _) = pair
    if obj.get(long_k) is Some(_) {
      return true
    }
  }
  false
}

///|
/// 旧 long-key stats {hp,atk,...} / 新 short-key stats {h,a,...} のどちらが来ても
/// 常に short-key で返す。new-format input は no-op (冪等)。
pub fn normalize_stats_to_short(value : Json) -> Json {
  guard value is Object(obj) else { return value }
  let out : Map[String, Json] = {}
  for pair in stat_key_long_short {
    let (long_k, short_k) = pair
    match obj.get(short_k) {
      Some(v) => out[short_k] = v
      None =>
        match obj.get(long_k) {
          Some(v) => out[short_k] = v
          None => ()
        }
    }
  }
  out.to_json()
}
