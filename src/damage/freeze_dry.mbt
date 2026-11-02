///|
/// 技名ごとの追加相性タイプ。
///
/// フライングプレスは技タイプ (通常はかくとう。ノーマライズ / スキン等で
/// 書き換わったあとのタイプでもよい) の相性と、ひこう相性の積でダメージを
/// 決める。Showdown の `onEffectiveness` は防御タイプごとの typeMod に
/// `getEffectiveness('Flying', type)` を足す。STAB・半減実のタイプ一致・
/// タイプ強化道具・特性無効は技タイプ側だけを見る (この関数の外)。
///
/// 追加タイプを持つ技は現状フライングプレスだけ。新しい複合相性技は
/// ここへ足す。
pub fn extra_effectiveness_type(move_name : String) -> @types.PokemonType? {
  match move_name {
    "フライングプレス" => Some(@types.Flying)
    _ => None
  }
}

///|
/// 技を考慮した、防御タイプ 1 つに対するタイプ相性 (x4 整数エンコード)。
///
/// 1. フリーズドライは技タイプに関わらずみずへ 2 倍 (x4=8)。タイプ変化後も
///    技名で判定する (Gen9)。
/// 2. `extra_effectiveness_type` がある技は、その結果に追加タイプの相性を
///    掛ける。x4 同士の積は `(a/4)*(b/4)` なので x4 へ戻すとき `a*b/4`。
///    同じ防御タイプで +1 と -1 が打ち消し合うと等倍 (4) になり、ダメージ
///    乗算の前に相殺される (Showdown の typeMod 加算と同じ)。
///    どちらかが無効 (0) なら積も 0。ひこう側がゴースト無効を打ち消すことはない。
///
/// チャート値は {0, 2, 4, 8} なので `a*b` は 4 で割り切れる。
pub fn move_effectiveness_x4(
  move_name : String,
  atk_type : @types.PokemonType,
  def_type : @types.PokemonType,
) -> Int {
  let base = match (move_name, def_type) {
    ("フリーズドライ", @types.Water) => 8
    _ => @types.get_effectiveness_x4(atk_type, def_type)
  }
  match extra_effectiveness_type(move_name) {
    Some(extra) => {
      let extra_x4 = @types.get_effectiveness_x4(extra, def_type)
      base * extra_x4 / 4
    }
    None => base
  }
}

///|
/// 防御側 1 または 2 タイプに対する相性スロット (x4)。
/// 第 2 タイプが無いときは 4 (等倍、乗算の単位元)。エンジンの
/// `eff1_x4 * eff2_x4` と `is_super_effective` はここを共有する。
pub fn effectiveness_slots_x4(
  move_name : String,
  atk_type : @types.PokemonType,
  def1 : @types.PokemonType,
  def2 : @types.PokemonType?,
) -> (Int, Int) {
  let e1 = move_effectiveness_x4(move_name, atk_type, def1)
  let e2 = match def2 {
    Some(d2) => move_effectiveness_x4(move_name, atk_type, d2)
    None => 4
  }
  (e1, e2)
}

///|
/// 技タイプ・防御タイプが日本語名のときの相性スロット。
/// 名前が解決できないスロットはエンジンと同じく 4 (等倍) に倒す。
/// payoff の接触判定が `calc_damage` と同じ無効条件を使うために公開する。
pub fn move_effectiveness_slots_x4(
  move_name : String,
  move_type : String,
  def_type1 : String,
  def_type2 : String,
) -> (Int, Int) {
  let atk = match @types.type_from_jp(move_type) {
    Some(t) => t
    None => return (4, 4)
  }
  let d1 = match @types.type_from_jp(def_type1) {
    Some(t) => t
    None => return (4, 4)
  }
  let d2 = if def_type2.length() > 0 {
    @types.type_from_jp(def_type2)
  } else {
    None
  }
  effectiveness_slots_x4(move_name, atk, d1, d2)
}
