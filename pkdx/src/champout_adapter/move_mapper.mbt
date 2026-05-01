///|
/// champout の `masterdata/waza.json` を `champions_schema.MoveEntry` 配列
/// へ変換する。
///
/// 入力 (champout) の主要フィールド:
///   - `id`        : 技 ID (1-based) — wazaname.json で表示名へ
///   - `type`      : 連続インデックス (0-17) — typename.json で名前へ
///   - `category`  : 0=物理 / 1=特殊 / 2=変化
///   - `power`     : 数値文字列 (`"40"` 等)、変化技は `"0"` などゲーム内仕様による
///   - `accuracy`  : 数値文字列、必中は `"0"` または `"100"` (champout 仕様)
///   - `pp`        : 数値文字列
///   - `available` : "1" のみ採用 (Champions ゲーム内で使用可能な技)
///
/// 出力時の正規化:
///   - power == "0" は表示上 "-" に正規化 (変化技 / 可変威力技の慣例)
///   - accuracy == "0" は "-" に正規化 (必中技の慣例)

///|
/// `waza.json` の root (Array) を受け取り MoveEntry 配列を生成。
/// `available != "1"` の行は Champions レギュレーションで使用不可なのでスキップ。
pub fn map_move_entries(
  bundle : LabelBundle,
  waza_json : Json,
) -> Result[Array[@champions_schema.MoveEntry], String] {
  let arr = match waza_json {
    Array(a) => a
    _ => return Err("waza.json: expected top-level array")
  }
  let out : Array[@champions_schema.MoveEntry] = []
  for i = 0; i < arr.length(); i = i + 1 {
    let m = match arr[i] {
      Object(o) => o
      _ => return Err("waza[" + i.to_string() + "]: not an object")
    }
    let available = match m.get("available") {
      Some(String(s)) => s == "1"
      _ => false
    }
    if not(available) {
      continue
    }
    let id = match m.get("id") {
      Some(String(s)) => s
      _ => return Err("waza[" + i.to_string() + "]: missing 'id'")
    }
    let waza = resolve_move(bundle, id)
    if waza.length() == 0 {
      // 名前解決できない技はスキップ (LabelName 不在 = ゲーム内未使用)
      continue
    }
    let type_id = match m.get("type") {
      Some(String(s)) => s
      _ => "0"
    }
    let type_ = resolve_type(bundle, type_id)
    let cat_id = match m.get("category") {
      Some(String(s)) => s
      _ => "0"
    }
    let category = resolve_move_category(cat_id)
    let pp = match m.get("pp") {
      Some(String(s)) => s
      _ => "0"
    }
    let power_raw = match m.get("power") {
      Some(String(s)) => s
      _ => "0"
    }
    let power = if power_raw == "0" { "-" } else { power_raw }
    let accuracy_raw = match m.get("accuracy") {
      Some(String(s)) => s
      _ => "0"
    }
    let accuracy = if accuracy_raw == "0" { "-" } else { accuracy_raw }
    let direct = match m.get("direct") {
      Some(String(s)) => s
      _ => "0"
    }
    let target = match m.get("target") {
      Some(String(s)) => s
      _ => "0"
    }
    out.push({
      waza,
      type_,
      category,
      pp,
      power,
      accuracy,
      direct,
      target,
    })
  }
  Ok(out)
}
