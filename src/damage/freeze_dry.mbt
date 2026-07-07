///|
/// 技を考慮したタイプ相性 (x4 整数エンコード)。
/// フリーズドライは技のタイプに関わらずみずタイプへ 2 倍 (x4=8) を取る
/// (Gen9 準拠: タイプ変化後も技「名」で判定される)。みず以外のスロットと
/// その他の技は通常チャートに委譲する。
pub fn move_effectiveness_x4(
  move_name : String,
  atk_type : @types.PokemonType,
  def_type : @types.PokemonType,
) -> Int {
  match (move_name, def_type) {
    ("フリーズドライ", @types.Water) => 8
    _ => @types.get_effectiveness_x4(atk_type, def_type)
  }
}
