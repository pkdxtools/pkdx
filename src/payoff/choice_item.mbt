///|
/// こだわりスカーフ。Champions `champout` `50e7233` の `ITEMNAME_287` /
/// `ITEMINFO_SYN_287`:
/// "Boosts the holder’s Speed stat by 50%. However, once the holder uses a
/// move, it becomes unable to use any other move but that one until it
/// switches out of battle."
///
/// 日本語名は `rom-txt/jpn/itemname.json` の「こだわりスカーフ」。同じ 166 件の
/// itemname に こだわりハチマキ / こだわりメガネ / とつげきチョッキ は無い。
/// 技固定も変化技の禁止も、この 3 つには入れない。ダメージ計算の既存の
/// `* 3 / 2`（`src/damage/items.mbt`）は Champions 外の文字列として残す。
///
/// 素早さ +50% の丸めは本文に無い。ダメージ計算の道具補正と同じ切り捨ての
/// `staged * 3 / 2`（`floor(x * 1.5)`。Showdown の `chainModify(1.5)` =
/// `floor(stat * 6144 / 4096)` と同じ整数）。掛ける位置はランク補正のあと、
/// まひの 1/2 の前。本文は順番を書かない。Showdown `Pokemon#getStat` は
/// `ModifySpe` のあとでまひを掛ける。スカーフ以外では `staged` をそのまま
/// 返すので、既存の素早さは 1 ビットも変わらない。
///
/// 技固定は -1 が未固定、0 以上が技 index。スカーフを所持していて未消費の
/// ときだけ行動をその index に絞る。失敗する技（ねこだまし等）も行動集合から
/// 外さない。既存の解決が失敗させる。PP は未モデル。固定 index が既存フィルタ
/// （とっておき）で消えて交代も無いときは、行動が空の既存終端のまま。
/// わるあがきは入れない。
///
/// 固定するのは `UseMove` / `Mega` を選んだとき。命中・ひるみ・眠り・まひで
/// 技本体が止まっても選んだ index に固定する。本文は "uses a move"。
/// Showdown は道具の `onBeforeMove` で `choicelock` を立て、そのイベントは
/// 失敗より前。リチャージの `UseMove(0)` プレースホルダは選択ではないので、
/// 前の固定を残す。
///
/// 解除は交代（本文 "until it switches out"）。道具を失ったときも解除する。
/// 本文は書いていない。Showdown は道具の `onEnd` で `choicelock` を消す。
/// ここでの「失った」は既存の `item_consumed`、または持ち物がスカーフで
/// なくなったとき。はたきおとすは威力だけ上げて持ち物は残す。トリック等は
/// 未モデル。

///|
/// 未固定。
const CHOICE_UNLOCKED : Int = -1

///|
const CHOICE_SCARF : String = "こだわりスカーフ"

///|
/// itemname にあるこだわり道具はスカーフだけ。
pub fn holds_choice_scarf(item : String) -> Bool {
  item == CHOICE_SCARF
}

///|
fn slot_flag(flags : Array[Bool], slot : Int) -> Bool {
  slot >= 0 && slot < flags.length() && flags[slot]
}

///|
/// 行動生成に使う固定 index。スカーフ以外、消費済み、負の index は -1。
/// スカーフ以外の入力は行動列を変えない。
pub fn effective_choice_lock(
  item : String,
  consumed : Bool,
  lock : Int,
) -> Int {
  if consumed || item != CHOICE_SCARF || lock < 0 {
    CHOICE_UNLOCKED
  } else {
    lock
  }
}

///|
/// ランク補正後の素早さ。スカーフ以外と消費済みは `staged` 自体を返す。
pub fn speed_after_choice_scarf(
  staged : Int,
  item : String,
  consumed : Bool,
) -> Int {
  if !consumed && item == CHOICE_SCARF {
    staged * 3 / 2
  } else {
    staged
  }
}

///|
/// ターン終了後の固定。交代は常に -1。スカーフを持っていない、または消費
/// 済みなら -1。リチャージ開始ターンは前の固定を残す。それ以外の
/// `UseMove` / `Mega` は選んだ index。
pub fn choice_lock_after_action(
  prev : Int,
  action : ActionKind,
  item : String,
  consumed : Bool,
  started_recharge : Bool,
) -> Int {
  match action {
    Switch(_) => CHOICE_UNLOCKED
    UseMove(i) | Mega(i) =>
      if consumed || item != CHOICE_SCARF {
        CHOICE_UNLOCKED
      } else if started_recharge {
        if prev < 0 {
          CHOICE_UNLOCKED
        } else {
          prev
        }
      } else {
        i
      }
  }
}

///|
/// 両側の固定を、ターン開始時の値と選んだ行動から書き直す。スカーフ以外で
/// 結果が同じなら同じ state を返す（新しいレコードを作らない）。
pub fn apply_choice_locks(
  state : SwitchingGameState,
  prev_my : Int,
  prev_opp : Int,
  my_action : ActionKind,
  opp_action : ActionKind,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  my_started_recharge : Bool,
  opp_started_recharge : Bool,
) -> SwitchingGameState {
  let my_item = if state.my_active >= 0 && state.my_active < my_team.length() {
    my_team[state.my_active].item
  } else {
    ""
  }
  let opp_item = if state.opp_active >= 0 && state.opp_active < opp_team.length() {
    opp_team[state.opp_active].item
  } else {
    ""
  }
  let my_next = choice_lock_after_action(
    prev_my,
    my_action,
    my_item,
    slot_flag(state.my_item_consumed, state.my_active),
    my_started_recharge,
  )
  let opp_next = choice_lock_after_action(
    prev_opp,
    opp_action,
    opp_item,
    slot_flag(state.opp_item_consumed, state.opp_active),
    opp_started_recharge,
  )
  if my_next == state.my_choice && opp_next == state.opp_choice {
    state
  } else {
    { ..state, my_choice: my_next, opp_choice: opp_next }
  }
}
