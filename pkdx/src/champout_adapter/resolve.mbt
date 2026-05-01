///|
/// champout の数値 ID → 表示名解決ヘルパ。各 mapper はここで型・特性・技名・
/// アイテム名を引いてから中間 JSON のフィールドへ流し込む。
///
/// 番号体系の特殊性:
///   - typename.json は 18 タイプ (Index 0-8, 10-18) を保持し Index 9 は
///     欠番。一方 personal.json / waza.json の `type` 値は 0-17 の連続
///     インデックスで、9 以降は LabelName で 1 ずれる。`resolve_type` が
///     この差分を吸収する。
///   - tokusei.json は TOKUSEI_001 から始まる (1-based)。0 は「特性なし」
///     を意味するためマップに存在せず、空文字を返す。
///   - wazaname.json は WAZANAME_001 から始まる (1-based)。0 は技なし。
///   - itemname.json は ITEMNAME_xxx (1-based 想定だが連番に飛びがある)。
///     存在しない LabelName は空文字。

///|
/// 0-padding 3 桁。`123 -> "123"`, `9 -> "009"`, `0 -> "000"`。
/// LabelName のサフィックスは TYPENAME / WAZANAME / TOKUSEI / ITEMNAME
/// すべて 3 桁ゼロ埋め。
fn pad3(n : Int) -> String {
  if n >= 100 {
    n.to_string()
  } else if n >= 10 {
    "0" + n.to_string()
  } else if n >= 0 {
    "00" + n.to_string()
  } else {
    "000"
  }
}

///|
/// 文字列を Int にパース。失敗時は 0 を返す (champout は数値も文字列で
/// 表現するため、空文字や `-` も入り得る)。
fn to_int_or_zero(s : String) -> Int {
  try @strconv.parse_int(s) catch {
    _ => 0
  }
}

///|
/// type id (personal.json / waza.json の `type` フィールド値) を表示名へ。
/// 値域は 0-17。Index 9 欠番を吸収するため、`id >= 9` のとき LabelName
/// 側を 1 加算する。値が範囲外、または LabelName が存在しないときは空文字。
pub fn resolve_type(bundle : LabelBundle, id_str : String) -> String {
  let n = to_int_or_zero(id_str)
  if n < 0 || n > 17 {
    return ""
  }
  let label_idx = if n >= 9 { n + 1 } else { n }
  match bundle.type_name.get("TYPENAME_" + pad3(label_idx)) {
    Some(s) => s
    None => ""
  }
}

///|
/// 特性 id (toku0 / toku1 / toku2) を表示名へ。0 は「特性なし」を意味し
/// 空文字を返す。LabelName が見つからない場合も空文字。
pub fn resolve_ability(bundle : LabelBundle, id_str : String) -> String {
  let n = to_int_or_zero(id_str)
  if n <= 0 {
    return ""
  }
  match bundle.tokusei.get("TOKUSEI_" + pad3(n)) {
    Some(s) => s
    None => ""
  }
}

///|
/// 技 id (waza.json の `id`、waza_learn.json の split 後の各 id) を表示名へ。
pub fn resolve_move(bundle : LabelBundle, id_str : String) -> String {
  let n = to_int_or_zero(id_str)
  if n <= 0 {
    return ""
  }
  match bundle.wazaname.get("WAZANAME_" + pad3(n)) {
    Some(s) => s
    None => ""
  }
}

///|
/// 全国図鑑番号 (1-based) を base 日本語名へ。フォーム違いがあっても base
/// 名は no で固定 — フォーム識別はアダプター側の `form` 文字列で別管理。
pub fn resolve_monsname(bundle : LabelBundle, no_str : String) -> String {
  let n = to_int_or_zero(no_str)
  if n <= 0 {
    return ""
  }
  match bundle.monsname.get("MONSNAME_" + pad3(n)) {
    Some(s) => s
    None => ""
  }
}

///|
/// アイテム id (item.json の `id`) を表示名へ。
pub fn resolve_item(bundle : LabelBundle, id_str : String) -> String {
  let n = to_int_or_zero(id_str)
  if n <= 0 {
    return ""
  }
  match bundle.itemname.get("ITEMNAME_" + pad3(n)) {
    Some(s) => s
    None => ""
  }
}

///|
/// move category 数値 → "物理" / "特殊" / "変化"。
/// champout 内部値: 0 = 物理, 1 = 特殊, 2 = 変化。
pub fn resolve_move_category(id_str : String) -> String {
  match id_str {
    "0" => "物理"
    "1" => "特殊"
    "2" => "変化"
    _ => ""
  }
}
