///|
/// であいがしら (First Impression, Champions `WAZAINFO_SYN_660`, Index 444)。
///
/// 本文:
/// USA: "This move fails unless it is the first move used by the user after it
/// enters a battle."
/// JPN: "登場して最初に出す技でない場合失敗する。"
/// 技名は `WAZANAME_660` = First Impression / であいがしら。
///
/// ねこだまし (`WAZAINFO_SYN_252`) と同じ「first move」失敗文。ひるみの文は無いので
/// ひるみは付けない。失敗ゲートだけを、ねこだまし と同じ `my_fresh` / `opp_fresh`
/// (`fake_out.mbt`) に載せる。新しいフラグは足さない。
///
/// - `Some(false)` — 登場後に技の行動を使った。技自体が失敗する (ダメージ無し)。
///   命中した扱いにはしない。
/// - `Some(true)` — 登場後の初行動。失敗させない。ひるみは無い。
/// - `None` — 未追跡 (select の既定)。失敗させない。select は DB から fresh を埋めない。
///
/// 更新は ねこだまし と同じ。ターン開始値で判定し、`UseMove` / `Mega` の消費と
/// 交代の `Some(true)` はターン出口。途中のメガシンカは解決前に fresh を消費しない。
///
/// 基本スペックは champions の `move` 行のまま (`waza.json` id "660": むし / 物理 /
/// 威力 100 / 命中 100 / PP 12 / 接触 / priority 2)。priority 2 は m002 が既に
/// 入れている。`flinch_chance` 行は作らない (m020 / m021 は であいがしら を入れない)。
/// PP と威力は Showdown (PP 10 / 威力 90) に合わせない。

///|
const FIRST_IMPRESSION_NAME : String = "であいがしら"

///|
/// であいがしら で、かつ登場後の初行動ではない (`Some(false)`)。
/// `None` と `Some(true)` は失敗させない。他の技名は false。
pub fn first_impression_fails(mv : @model.Move, user_fresh : Bool?) -> Bool {
  if mv.name != FIRST_IMPRESSION_NAME {
    return false
  }
  match user_fresh {
    Some(false) => true
    _ => false
  }
}
