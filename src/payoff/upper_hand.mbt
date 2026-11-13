///|
/// はやてがえし (Upper Hand, Champions `WAZAINFO_SYN_918`, Index 673)。
///
/// 本文 (`champout/rom-txt/usa/wazainfo_syn.json`):
/// "Makes the target flinch. This move fails if the target isn’t about to
/// use a priority attack."
/// 日本語 (`rom-txt/jpn/wazainfo_syn.json` の同じラベル):
/// "相手が　先制できる攻撃を使っていない場合失敗する。相手をひるませる。"
/// `help_syn.json` には該当文が無い。技名は `WAZANAME_918` = Upper Hand / はやてがえし。
///
/// 優先度は `champout/masterdata/waza.json` の id "918" (`"priority": "3"`)。
/// m002 はこの技の `move_meta` 行を作らないので、行が無いとモデルは priority 0 として扱う。
/// 失敗ゲートを入れたあと、m021 が priority 3 と `flinch_chance` 100 を投入する。
/// ひるみは「Makes the target flinch」/「相手をひるませる」なので、成功して命中したときは
/// 既存のひるみ経路 (#210: せいしんりょく / りんぷん / ちからずく / ひんし / 先攻だけ /
/// ふくつのこころ) で 100% 付く。ねこだまし の fresh フラグは使わない。
///
/// 「about to use」/「使っていない」はこのターンにロックした選択を見る。あとから
/// 実際に打てたか (ひるみ・眠り・まひ・リチャージで止まるか) は見ない。交代は
/// 先制攻撃ではないので失敗する。
///
/// 「priority attack」/「先制できる攻撃」は選択技の実効優先度 > 0。
/// 変化技の先制 (まもる +4 / みきり +4 / ファストガード +3) も含む。本文の
/// attack / 攻撃は説明文の言い方で、カテゴリでは切らない。サイコフィールドが
/// あとから相手の先制技を無効にしても、ゲートは選択時点の優先度を見る
/// (本文は地形に触れていない)。はやてがえし 自身は priority 3 なので、地上の
/// 相手への自分の技は既存のサイコフィールド無効 (G-3) のまま。
///
/// 実効優先度は `effective_priority` (いたずらごころの変化技 +1、満タン時の
/// はやてのつばさのひこう技 +1)。特性本文が優先度を上げた技は先制できる。
/// 省略した特性 / HP は補正 0 で、`Move.priority` だけを見る (既存呼び出しと同じ)。
/// Showdown の `category === 'Status'` 除外は Champions 本文に無いので入れない。
/// であいがしら (`WAZAINFO_SYN_660`) はこのゲートの対象外。登場後の初行動で
/// 失敗するのは `first_impression_fails` (ねこだまし と同じ fresh) で、ひるみは無い。
///
/// `pkdx select` は DB から priority も `flinch_chance` も埋めない。入力 JSON の
/// 技が正。名前が はやてがえし でも、入力の `flinch_chance` が 0 ならひるまない。

///|
const UPPER_HAND_NAME : String = "はやてがえし"

///|
/// はやてがえし で、相手のこのターンの選択の実効優先度が 0 以下。
/// 交代・技なし (`None`) は失敗。他の技名は false。
/// `foe_ability` / HP を省略すると補正は 0 で、選択技の `Move.priority` だけを見る。
pub fn upper_hand_fails(
  mv : @model.Move,
  foe_move : @model.Move?,
  foe_ability? : String = "",
  foe_hp? : Int = 0,
  foe_max_hp? : Int = 0,
) -> Bool {
  if mv.name != UPPER_HAND_NAME {
    return false
  }
  match foe_move {
    None => true
    Some(foe) =>
      effective_priority(foe_ability, foe, foe_hp, foe_max_hp) <= 0
  }
}

///|
/// ひるみの遅延に使う実効確率。はやてがえし が失敗する相手には 0
/// (失敗した技はダメージもひるみも無いので、相手の試行を遅らせない)。
/// 成功する相手には `flinch_chance_if_fresh` と同じ (ねこだまし 以外はそのまま)。
pub fn flinch_chance_vs_choice(
  mv : @model.Move,
  user_fresh : Bool?,
  foe_move : @model.Move?,
  foe_ability? : String = "",
  foe_hp? : Int = 0,
  foe_max_hp? : Int = 0,
) -> Int {
  if upper_hand_fails(mv, foe_move, foe_ability~, foe_hp~, foe_max_hp~) {
    0
  } else {
    flinch_chance_if_fresh(mv, user_fresh)
  }
}
