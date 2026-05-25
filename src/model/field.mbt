///|
/// Battle field (terrain) conditions.
///
/// derive 句は Weather に揃え、加えて `Hash` を持つ:
///   - `Hash`: Stage F で damage cache key に埋め込むため `Map[Field, _]` を
///     使えるようにする
///   - `Debug`: `debug_inspect` で variant 名を出すため (Weather / Move 等の
///     derive(Debug) 連鎖の prerequisite)
pub(all) enum Field {
  None
  Electric
  Grassy
  Misty
  Psychic
} derive(Debug, Eq, Hash)

///|
/// Convert a field name to a `Field` enum.
///
/// 二系統の入力を受ける:
///   - CLI 入力 (日本語短縮形): "エレキ" / "グラス" / "ミスト" / "サイコ"
///   - DB 入力 (m015 の `field_set` カラム canonical): "electric" / "grassy" /
///     "misty" / "psychic"
/// 空文字 / 未知文字列は `Field::None` を返す。caller (CLI / DB query layer) が
/// 同じ関数を共有することで、どちらの経路でも値域 (5 variant) を一意に
/// 制約できる。`weather_from_jp` と同じ責務分担。
pub fn field_from_jp(name : String) -> Field {
  match name {
    // DB canonical (m015 `field_set` カラム)
    "electric" => Electric
    "grassy" => Grassy
    "misty" => Misty
    "psychic" => Psychic
    // CLI 日本語短縮形 (--field エレキ 等)
    "エレキ" => Electric
    "グラス" => Grassy
    "ミスト" => Misty
    "サイコ" => Psychic
    _ => None
  }
}

///|
/// Check if field is active.
pub fn Field::is_active(self : Field) -> Bool {
  match self {
    None => false
    _ => true
  }
}
