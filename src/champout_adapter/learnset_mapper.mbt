///|
/// champout の `masterdata/waza_learn.json` を
/// `champions_schema.LearnsetEntry` 配列へ変換する。
///
/// 入力 (champout) のフォーマット:
///   `{"id": "0003000", "waza": "14,34,38,46,..."}`
///
/// `id` は personal.json の id と一対一。`waza` はカンマ区切りの技 ID
/// 文字列。champout は習得経路情報 (Lv1 / わざマシン / 進化など) を持たない
/// ため、`conditions` は一律 "基本" として出力する。
///
/// 出力には personal.json で `is_valid="1"` のポケモンに対応する learnset
/// だけ含める (それ以外は champions レギュレーションで使えない)。フィルタ
/// 用の `valid_ids` 集合は呼び出し側で `pokemon_mapper` の出力から導出する。

///|
/// `waza_learn.json` の root を受け取り LearnsetEntry 配列を生成。
/// `valid_ids` に含まれる pokemon id (= champout の id 7 桁) のみを採用。
pub fn map_learnset_entries(
  bundle : LabelBundle,
  waza_learn_json : Json,
  valid_ids : Map[String, Bool],
) -> Result[Array[@champions_schema.LearnsetEntry], String] {
  let arr = match waza_learn_json {
    Array(a) => a
    _ => return Err("waza_learn.json: expected top-level array")
  }
  let out : Array[@champions_schema.LearnsetEntry] = []
  for i = 0; i < arr.length(); i = i + 1 {
    let m = match arr[i] {
      Object(o) => o
      _ => return Err("waza_learn[" + i.to_string() + "]: not an object")
    }
    let id = match m.get("id") {
      Some(String(s)) => s
      _ => return Err("waza_learn[" + i.to_string() + "]: missing 'id'")
    }
    // pokemon_mapper でフィルタされた valid pokemon id にだけ追従
    match valid_ids.get(id) {
      Some(true) => ()
      _ => continue
    }
    let waza_csv = match m.get("waza") {
      Some(String(s)) => s
      _ => continue
    }
    if waza_csv.length() == 0 {
      continue
    }
    // CSV split → 各技 ID を名前解決
    let parts = split_csv(waza_csv)
    for j = 0; j < parts.length(); j = j + 1 {
      let move_id = parts[j]
      if move_id.length() == 0 {
        continue
      }
      let waza_name = resolve_move(bundle, move_id)
      if waza_name.length() == 0 {
        continue
      }
      out.push({ id, conditions: "基本", waza: waza_name })
    }
  }
  Ok(out)
}

///|
/// 単純な CSV split (区切りはカンマ '，' でなく ASCII ','. champout の
/// `waza` フィールドは ASCII カンマ固定)。空文字列は空配列を返す。
fn split_csv(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  for i = 0; i < s.length(); i = i + 1 {
    if s.unsafe_get(i) == 0x2C {
      out.push(s[start:i].to_string())
      start = i + 1
    }
  }
  if start < s.length() {
    out.push(s[start:s.length()].to_string())
  }
  out
}
