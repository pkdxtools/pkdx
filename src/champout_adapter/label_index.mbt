///|
/// rom-txt 配下のラベルファイル (`typename.json`, `tokusei.json`,
/// `monsname_syn.json`, `wazaname.json`, `itemname.json`,
/// `zkn_form_syn.json` 等) は同一の構造を持つ:
///
/// ```json
/// {
///   "m_Name": "<file_name>",
///   "mSDataSet": [
///     { "LabelName": "TYPENAME_000", "OriginalText": "ノーマル", ... },
///     ...
///   ]
/// }
/// ```
///
/// `build_label_index` はこの `mSDataSet` を走査し
/// `Map[LabelName -> OriginalText]` を返す。`OriginalText` が空文字
/// (該当なしを示すゲーム内フィールド) の行も index に含める — caller が
/// 「未定義」と「空文字」を区別したい場合は `Map.get` の結果を使い分けること。

///|
/// JSON ルートから (LabelName, OriginalText) を抜き出し Map に積む。
/// 期待形式と異なる行は黙ってスキップする (champout の生 JSON は
/// LabelName / OriginalText 以外にも m_GameObject などのメタを含むため)。
pub fn build_label_index(json : Json) -> Map[String, String] {
  let out : Map[String, String] = Map::new()
  let root = match json {
    Object(o) => o
    _ => return out
  }
  let items = match root.get("mSDataSet") {
    Some(Array(a)) => a
    _ => return out
  }
  for i = 0; i < items.length(); i = i + 1 {
    let entry = match items[i] {
      Object(o) => o
      _ => continue
    }
    let name = match entry.get("LabelName") {
      Some(String(s)) => s
      _ => continue
    }
    let text = match entry.get("OriginalText") {
      Some(String(s)) => s
      _ => continue
    }
    out[name] = text
  }
  out
}

///|
/// ラベルファイルを path から読み込み、JSON パース → `build_label_index`
/// を一気通貫で実行する。読み込み失敗・パース失敗は `Err` で返す。
pub fn load_label_index(path : String) -> Result[Map[String, String], String] {
  let raw = match @db.read_file(path) {
    None => return Err("file not found: " + path)
    Some(s) => s
  }
  let json = try @json.parse(raw) catch {
    e => return Err("JSON parse failed at " + path + ": " + e.to_string())
  }
  Ok(build_label_index(json))
}

///|
/// champout のラベルファイル群を一括ロードした結果。各 mapper はこの構造体を
/// 受け取り、ID → 表示名解決を行う。`base_dir` には `<repo_root>/champout`
/// 相当のパスが入る想定。
pub(all) struct LabelBundle {
  type_name : Map[String, String]      // TYPENAME_xxx -> "ほのお" 等
  tokusei : Map[String, String]        // TOKUSEI_xxx -> "もらいび" 等
  monsname : Map[String, String]       // MONSNAME_xxx -> "リザードン" 等
  wazaname : Map[String, String]       // WAZANAME_xxx -> "かえんほうしゃ" 等
  itemname : Map[String, String]       // ITEMNAME_xxx -> "こだわりハチマキ" 等
  zkn_form : Map[String, String]       // ZKN_FORM_xxx_yyy -> "メガリザードンX" 等
}

///|
/// 6 つのラベルファイルを `<base_dir>/rom-txt/jpn/<file>.json` から
/// 一括ロード。1 ファイルでも欠けたら最初のエラーを返す。
pub fn load_label_bundle(base_dir : String) -> Result[LabelBundle, String] {
  let prefix = base_dir + "/rom-txt/jpn/"
  let type_name = match load_label_index(prefix + "typename.json") {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  let tokusei = match load_label_index(prefix + "tokusei.json") {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  let monsname = match load_label_index(prefix + "monsname_syn.json") {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  let wazaname = match load_label_index(prefix + "wazaname.json") {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  let itemname = match load_label_index(prefix + "itemname.json") {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  let zkn_form = match load_label_index(prefix + "zkn_form_syn.json") {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  Ok({ type_name, tokusei, monsname, wazaname, itemname, zkn_form })
}
