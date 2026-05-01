///|
/// champout の `masterdata/item.json` を `champions_schema.ItemEntry` 配列
/// へ変換する。
///
/// 入力 (champout) の主要フィールド:
///   - `id`         : アイテム ID — itemname.json で表示名へ
///   - `category_a` : カテゴリ番号 (battleitem / berry / hold 等の大分類)
///   - `unlock`     : "0"=初期から所持可能 / その他=条件あり
///
/// 出力 `category` には category_a の数値をそのまま String で持たせる。
/// 既存の m013_items が使う分類名 (`"choice"` / `"misc"` / `"berry"` /
/// `"consume"` 等) との対応付けは Phase 5 / 6 のロジック層で吸収する想定で、
/// アダプター側ではゲーム内部値を非破壊で残す。
///
/// `name_en` は champout に直接持たない (rom-txt/usa を別途読み込んで
/// マージすれば可能だが本フェーズではスコープ外)。空文字で出力する。

///|
pub fn map_item_entries(
  bundle : LabelBundle,
  item_json : Json,
) -> Result[Array[@champions_schema.ItemEntry], String] {
  let arr = match item_json {
    Array(a) => a
    _ => return Err("item.json: expected top-level array")
  }
  let out : Array[@champions_schema.ItemEntry] = []
  for i = 0; i < arr.length(); i = i + 1 {
    let m = match arr[i] {
      Object(o) => o
      _ => return Err("item[" + i.to_string() + "]: not an object")
    }
    let id = match m.get("id") {
      Some(String(s)) => s
      _ => continue
    }
    let name_ja = resolve_item(bundle, id)
    if name_ja.length() == 0 {
      // LabelName 不在 = ゲーム内未使用なのでスキップ
      continue
    }
    let category = match m.get("category_a") {
      Some(String(s)) => s
      _ => "0"
    }
    out.push({ name_ja, name_en: "", category, flavor: "" })
  }
  Ok(out)
}
