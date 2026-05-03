///|
/// 利用可能なレギュレーション名のリストを返す。
///
/// レギュレーションの membership (どの globalNo がそのレギュレーションで
/// 使えるか) は、もはや本ファイルで判定しない。champions.db 自体が
/// レギュレーション準拠のサブセットを保持しているため、`--version
/// champions` 経路では DB に存在する pokemon が即「使用可」を意味する。
/// ここで保持しているのは「CLI で受け付けるレギュレーション名」だけで、
/// `pkdx regulation set` の入力検証と `pkdx regulation list` の出力に使う。
pub fn available_regulations() -> Array[String] {
  ["M-A"]
}

///|
/// レギュレーション名をキャノニカル形（available_regulations() の表記）に正規化する。
/// 大文字小文字の差分のみ吸収し、未登録の名前は None を返す。
/// `m-a` / `M-A` / `M-a` をすべて `M-A` に揃えるため、`pkdx regulation set` が
/// PR テストプランに記載された小文字入力を受け付けられるようにする。
pub fn canonicalize_regulation(name : String) -> String? {
  let known = available_regulations()
  for i = 0; i < known.length(); i = i + 1 {
    if eq_ascii_case_insensitive(known[i], name) {
      return Some(known[i])
    }
  }
  None
}

///|
fn eq_ascii_case_insensitive(a : String, b : String) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    let ca = ascii_to_upper(a.unsafe_get(i).to_int())
    let cb = ascii_to_upper(b.unsafe_get(i).to_int())
    if ca != cb {
      return false
    }
  }
  true
}

///|
fn ascii_to_upper(c : Int) -> Int {
  if c >= 0x61 && c <= 0x7A { c - 0x20 } else { c }
}
