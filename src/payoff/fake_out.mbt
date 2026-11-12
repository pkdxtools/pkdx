///|
/// ねこだまし (Fake Out, Champions `WAZAINFO_SYN_252`)。
///
/// 本文 (`champout/rom-txt/usa/wazainfo_syn.json` 行 4432):
/// "Makes the target flinch. This move fails unless it is the first move
/// used by the user after it enters a battle."
///
/// `Bool?` をサイドごとに持つ。3 値なのは、既存の select 入力を 1 ビットの
/// 「もう動いた」に潰すと ねこだまし のダメージそのものが変わるため。
/// - `None` — 未指定 (select の既定)。失敗ゲートもひるみも掛けない。技は従来どおり
///   40 威力の先制技として解決し、`flinch_chance` が JSON に乗っていてもひるまない。
///   交代しても `None` のまま (追跡を始めない)。24 本の回帰入力はここに落ちる。
/// - `Some(true)` — 登場後の初行動。バトル開始のリードは呼び出し側が true を渡す
///   (select は「毎選択がターン 1」とは仮定しない)。交代で入った次のターンも true。
///   命中すれば既存のひるみ経路 (`flinch_chance`、せいしんりょく 等) で 100% ひるむ。
/// - `Some(false)` — 登場後に技の行動を使った。ねこだまし は失敗する (ダメージも
///   ひるみも無い)。命中した扱いにしない。
///
/// 行動の消費は Showdown `sim/battle-actions.ts` の `runMove` 先頭の
/// `activeMoveActions++` (BeforeMove より前) に合わせる。本文は「used」としか
/// 書かない。技を選んだターンは、ひるみ・眠り・まひ・反動で技本体が止まっても
/// `Some` を `Some(false)` にする。交代は技ではないので `Some(true)` に戻し、
/// そのターン自体は動かない (次のターンが初行動)。
///
/// はやてがえし (`WAZAINFO_SYN_918`) は相手の先制技が条件で、このフラグでは
/// 表せない。であいがしら (`WAZAINFO_SYN_660`) は同じ「first move」文を持つが
/// ひるみは無く、本変更の対象外。

///|
const FAKE_OUT_NAME : String = "ねこだまし"

///|
/// ねこだまし で、かつ登場後の初行動ではない (`Some(false)`)。
/// `None` は未追跡なので失敗させない (既存入力のダメージを保つ)。
pub fn fake_out_fails(mv : @model.Move, user_fresh : Bool?) -> Bool {
  if mv.name != FAKE_OUT_NAME {
    return false
  }
  match user_fresh {
    Some(false) => true
    _ => false
  }
}

///|
/// ねこだまし のひるみを既存経路に流してよいか。`Some(true)` のときだけ流す。
/// `None` は `flinch_chance` が 100 でもひるませない (回帰入力を変えない)。
/// `Some(false)` は失敗ゲートが先に立つが、ここでもひるみは落とす。
pub fn fake_out_suppresses_flinch(mv : @model.Move, user_fresh : Bool?) -> Bool {
  if mv.name != FAKE_OUT_NAME {
    return false
  }
  match user_fresh {
    Some(true) => false
    _ => true
  }
}

///|
/// ひるみ抽選・遅延に使う実効確率。ねこだまし を初行動以外で撃つときは 0。
pub fn flinch_chance_if_fresh(mv : @model.Move, user_fresh : Bool?) -> Int {
  if fake_out_suppresses_flinch(mv, user_fresh) {
    0
  } else {
    mv.flinch_chance
  }
}

///|
/// ターン開始時の fresh を、そのターンに選んだ行動で更新する。
/// `None` は何をしても `None`。`Some` は交代で `Some(true)`、技 (Mega 含む) で
/// `Some(false)`。技が実際に命中したかは見ない (Showdown は runMove の入口で数える)。
pub fn fresh_after_action(current : Bool?, action : ActionKind) -> Bool? {
  match current {
    None => None
    Some(_) =>
      match action {
        Switch(_) => Some(true)
        UseMove(_) | Mega(_) => Some(false)
      }
  }
}

///|
/// MC 用。`switched` が true なら交代 (次ターンが初行動)、false なら技の行動を消費。
pub fn fresh_after_switch(current : Bool?, switched : Bool) -> Bool? {
  match current {
    None => None
    Some(_) => if switched { Some(true) } else { Some(false) }
  }
}

///|
/// ターン結果の fresh を、ターン開始値と選んだ行動から書き直す。
/// 途中の state コピーがフラグを落としても、出口で入力側の値から決める。
pub fn with_turn_fresh(
  state : SwitchingGameState,
  my_start : Bool?,
  opp_start : Bool?,
  my_action : ActionKind,
  opp_action : ActionKind,
) -> SwitchingGameState {
  {
    ..state,
    my_fresh: fresh_after_action(my_start, my_action),
    opp_fresh: fresh_after_action(opp_start, opp_action),
  }
}

///|
/// 分岐の各状態へ `with_turn_fresh` を掛ける。入力はターン開始時の fresh。
/// すでに同じ開始値から決めた結果に重ねても同じ値になる (消費の二重適用にならない)。
pub fn settle_fresh_outcomes(
  outs : Array[(Double, SwitchingGameState)],
  my_start : Bool?,
  opp_start : Bool?,
  my_action : ActionKind,
  opp_action : ActionKind,
) -> Array[(Double, SwitchingGameState)] {
  outs.map(fn(pair) {
    let (p, s) = pair
    (p, with_turn_fresh(s, my_start, opp_start, my_action, opp_action))
  })
}
