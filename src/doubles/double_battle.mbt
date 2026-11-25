///|
/// Champions ダブルの段階 0。ダメージ計算と Nash は呼ばない。
///
/// 形式は「6 匹から 4 匹を選び、2 匹ずつ出す」。ここでは次だけを持つ。
///
/// - `waza.json` の `target` を技の範囲へ写す表
/// - その技がどのスロットに当たるか
/// - 先発 2 + 控え 2 の列挙（左右を区別しない 90 が標準、区別する 180）
/// - 1 ターンの同時行動（技と対象、または交代）
///
/// `target` は `@model.Move` に載せない。`champions.db` の `move.target` を
/// 別の表で引く。シングルのキャッシュキーには触れない。
///
/// スロットは自陣左、自陣右、相手左、相手右の 4 つ。控えは先発の左右とは
/// 別に、添字の集合として扱う。
///
/// 空いているスロットとひんしのスロットは行動しない。技の対象にも当たらない。
/// ひんしの補充は同時行動ではなく、ここには含めない。生きているスロットが
/// 技も交代先も持てないとき、そのターンの同時行動は空である。わるあがきは
/// まだ入れない。

///|
/// 場の 4 スロット。自陣から見た左右。
pub(all) enum DoubleSlot {
  MyLeft
  MyRight
  FoeLeft
  FoeRight
} derive(Debug, Eq)

///|
pub extend DoubleSlot with Debug::{to_repr}

///|
pub extend DoubleSlot with Eq::{not_equal, equal}

///|
/// スロットの中身。`Vacant` は空、`Fainted` は倒れている、`Alive` は行動できる。
pub(all) enum DoubleOccupant {
  Vacant
  Fainted
  Alive
} derive(Debug, Eq)

///|
pub extend DoubleOccupant with Debug::{to_repr}

///|
pub extend DoubleOccupant with Eq::{not_equal, equal}

///|
/// ダブルの場。行動列挙は自陣 2 体と相手 2 体から同じ形を作る。
pub(all) struct DoubleField {
  my_left : DoubleOccupant
  my_right : DoubleOccupant
  foe_left : DoubleOccupant
  foe_right : DoubleOccupant
} derive(Debug, Eq)

///|
pub extend DoubleField with Debug::{to_repr}

///|
pub extend DoubleField with Eq::{not_equal, equal}

///|
/// `waza.json` の `target`（champout `50e7233`、available = 1 の分布と一致）。
///
/// | target | 範囲 |
/// |---:|---|
/// | 0 | 選んだ相手 1 体 |
/// | 1 | 自分か味方 |
/// | 2 | 味方 1 体 |
/// | 3 | 未使用 |
/// | 4 | 自分以外の全員（味方を含む） |
/// | 5 | 相手側の全員 |
/// | 6 | 自分と味方 |
/// | 7 | 自分 |
/// | 8 | 場の全員 |
/// | 9 | あばれ状態（ランダムな相手） |
/// | 10 | 全体の場 |
/// | 11 | 相手の場 |
/// | 12 | 味方の場 |
/// | 13 | そのターンに受けたダメージを返す |
/// | 14 | 味方（隣接する味方） |
pub(all) enum DoubleMoveRange {
  ChooseFoe
  ChooseSelfOrAlly
  ChooseAlly
  UnusedTarget
  AllExceptUser
  AllOpponents
  UserAndAlly
  UserOnly
  AllPokemon
  RageRandom
  FieldWhole
  FieldFoe
  FieldAlly
  DamageReflect
  ChooseAdjacentAlly
} derive(Debug, Eq)

///|
pub extend DoubleMoveRange with Debug::{to_repr}

///|
pub extend DoubleMoveRange with Eq::{not_equal, equal}

///|
/// 当たる先。ポケモンに当たらない技は `Battlefield`。
/// `RandomOne` の配列は候補で、解決時にそのうち 1 体。
/// 空スロットとひんしはどちらの配列にも入れない。
pub(all) enum DoubleResolved {
  Struck(Array[DoubleSlot])
  RandomOne(Array[DoubleSlot])
  Battlefield(DoubleMoveRange)
  NoStrike
} derive(Debug, Eq)

///|
pub extend DoubleResolved with Debug::{to_repr}

///|
pub extend DoubleResolved with Eq::{not_equal, equal}

///|
/// ワイドフォース。`waza.json` の id は 797、`target` は 0。
/// サイコフィールド下では相手全体（target 5 と同じ）になる。
pub const EXPANDING_FORCE_MOVE_ID : Int = 797

///|
/// 表示名。`champions.db` の `move` は id を持たないので、名前でも判定する。
pub const EXPANDING_FORCE_NAME : String = "ワイドフォース"

///|
/// `target` を範囲へ写す。0 から 14 以外は `None`。
pub fn double_move_range(target : Int) -> DoubleMoveRange? {
  match target {
    0 => Some(ChooseFoe)
    1 => Some(ChooseSelfOrAlly)
    2 => Some(ChooseAlly)
    3 => Some(UnusedTarget)
    4 => Some(AllExceptUser)
    5 => Some(AllOpponents)
    6 => Some(UserAndAlly)
    7 => Some(UserOnly)
    8 => Some(AllPokemon)
    9 => Some(RageRandom)
    10 => Some(FieldWhole)
    11 => Some(FieldFoe)
    12 => Some(FieldAlly)
    13 => Some(DamageReflect)
    14 => Some(ChooseAdjacentAlly)
    _ => None
  }
}

///|
/// 対象を選ぶ target。0 / 1 / 2 / 14 だけ。
pub fn double_target_chooses(target : Int) -> Bool {
  target == 0 || target == 1 || target == 2 || target == 14
}

///|
fn is_expanding_force(move_id : Int, name : String) -> Bool {
  move_id == EXPANDING_FORCE_MOVE_ID || name == EXPANDING_FORCE_NAME
}

///|
fn occupant_of(field : DoubleField, slot : DoubleSlot) -> DoubleOccupant {
  match slot {
    MyLeft => field.my_left
    MyRight => field.my_right
    FoeLeft => field.foe_left
    FoeRight => field.foe_right
  }
}

///|
fn on_my_side(slot : DoubleSlot) -> Bool {
  match slot {
    MyLeft => true
    MyRight => true
    FoeLeft => false
    FoeRight => false
  }
}

///|
fn is_ally(actor : DoubleSlot, slot : DoubleSlot) -> Bool {
  actor != slot && on_my_side(actor) == on_my_side(slot)
}

///|
fn is_foe(actor : DoubleSlot, slot : DoubleSlot) -> Bool {
  on_my_side(actor) != on_my_side(slot)
}

///|
fn choice_legal(
  target : Int,
  actor : DoubleSlot,
  slot : DoubleSlot,
  field : DoubleField,
) -> Bool {
  if occupant_of(field, slot) != Alive {
    return false
  }
  match target {
    0 => is_foe(actor, slot)
    1 => slot == actor || is_ally(actor, slot)
    2 => is_ally(actor, slot)
    // ダブルでは味方が 1 体で、その 1 体が隣接する味方。
    14 => is_ally(actor, slot)
    _ => false
  }
}

///|
fn alive_in(field : DoubleField, slots : Array[DoubleSlot]) -> Array[DoubleSlot] {
  let out : Array[DoubleSlot] = []
  for slot in slots {
    if occupant_of(field, slot) == Alive {
      out.push(slot)
    }
  }
  out
}

///|
fn foes_of(actor : DoubleSlot) -> Array[DoubleSlot] {
  if on_my_side(actor) {
    [FoeLeft, FoeRight]
  } else {
    [MyLeft, MyRight]
  }
}

///|
fn ally_of(actor : DoubleSlot) -> DoubleSlot {
  match actor {
    MyLeft => MyRight
    MyRight => MyLeft
    FoeLeft => FoeRight
    FoeRight => FoeLeft
  }
}

///|
fn all_slots() -> Array[DoubleSlot] {
  [MyLeft, MyRight, FoeLeft, FoeRight]
}

///|
/// `actor` の技が当たるスロット。
///
/// `chosen` を使うのは対象を選ぶ技だけ。選んだ先が空・ひんし・範囲外なら
/// `NoStrike`。全体技は生きているスロットだけを、場の左から順に返す。
/// ワイドフォース（id 797、または名前が `ワイドフォース`）は
/// `psychic_terrain` のとき相手全体になり、`chosen` は見ない。
pub fn double_slots_hit(
  move_id : Int,
  target : Int,
  actor : DoubleSlot,
  chosen : DoubleSlot?,
  field : DoubleField,
  psychic_terrain : Bool,
  name? : String = "",
) -> DoubleResolved {
  let effective = if is_expanding_force(move_id, name) && psychic_terrain {
    5
  } else {
    target
  }
  match double_move_range(effective) {
    None => NoStrike
    Some(UnusedTarget) => NoStrike
    Some(FieldWhole) => Battlefield(FieldWhole)
    Some(FieldFoe) => Battlefield(FieldFoe)
    Some(FieldAlly) => Battlefield(FieldAlly)
    Some(DamageReflect) => Battlefield(DamageReflect)
    Some(RageRandom) => RandomOne(alive_in(field, foes_of(actor)))
    Some(ChooseFoe | ChooseSelfOrAlly | ChooseAlly | ChooseAdjacentAlly) =>
      match chosen {
        None => NoStrike
        Some(slot) =>
          if choice_legal(effective, actor, slot, field) {
            Struck([slot])
          } else {
            NoStrike
          }
      }
    Some(UserOnly) => Struck(alive_in(field, [actor]))
    Some(UserAndAlly) => Struck(alive_in(field, [actor, ally_of(actor)]))
    Some(AllOpponents) => Struck(alive_in(field, foes_of(actor)))
    Some(AllPokemon) => Struck(alive_in(field, all_slots()))
    Some(AllExceptUser) => {
      let out : Array[DoubleSlot] = []
      for slot in all_slots() {
        if slot != actor && occupant_of(field, slot) == Alive {
          out.push(slot)
        }
      }
      Struck(out)
    }
  }
}

///|
/// 先発 2 体と控え 2 体。`leads` は左右を区別しないときの昇順。
/// `bench` は常に昇順。選ばれなかった `n - 4` 体は持たない。
pub(all) struct DoubleBring {
  leads : (Int, Int)
  bench : (Int, Int)
} derive(Debug, Eq)

///|
pub extend DoubleBring with Debug::{to_repr}

///|
pub extend DoubleBring with Eq::{not_equal, equal}

///|
/// 左右を区別しない先発。これが標準。`n = 6` で `C(6,2) * C(4,2) = 90`。
/// `n < 4` は空。先発・控えともに昇順で、辞書順に並べる。
pub fn double_brings(n : Int) -> Array[DoubleBring] {
  let out : Array[DoubleBring] = []
  if n < 4 {
    return out
  }
  for i in 0..<n {
    for j in (i + 1)..<n {
      for a in 0..<n {
        if a == i || a == j {
          continue
        }
        for b in (a + 1)..<n {
          if b == i || b == j {
            continue
          }
          out.push(DoubleBring::{ leads: (i, j), bench: (a, b) })
        }
      }
    }
  }
  out
}

///|
/// 左右を区別する先発。`leads` は `(左, 右)`。控えは区別しない。
/// `n = 6` で `P(6,2) * C(4,2) = 180`。`n < 4` は空。
pub fn double_brings_ordered(n : Int) -> Array[DoubleBring] {
  let out : Array[DoubleBring] = []
  if n < 4 {
    return out
  }
  for left in 0..<n {
    for right in 0..<n {
      if left == right {
        continue
      }
      for a in 0..<n {
        if a == left || a == right {
          continue
        }
        for b in (a + 1)..<n {
          if b == left || b == right {
            continue
          }
          out.push(DoubleBring::{ leads: (left, right), bench: (a, b) })
        }
      }
    }
  }
  out
}

///|
/// 同時行動の 1 体分。`Use` は対象を選ばない技。`UseOn` は選んだスロット。
/// `BenchTo` は控え配列の添字。
pub(all) enum DoubleAction {
  Use(Int)
  UseOn(Int, DoubleSlot)
  BenchTo(Int)
} derive(Debug, Eq)

///|
pub extend DoubleAction with Debug::{to_repr}

///|
pub extend DoubleAction with Eq::{not_equal, equal}

///|
/// 自陣 2 体の同時行動。ひんしと空スロットは `None`。
pub(all) struct DoubleJointAction {
  left : DoubleAction?
  right : DoubleAction?
} derive(Debug, Eq)

///|
pub extend DoubleJointAction with Debug::{to_repr}

///|
pub extend DoubleJointAction with Eq::{not_equal, equal}

///|
/// 行動する側の技。`id` が 797、または `name` がワイドフォースで、
/// サイコフィールドのときは対象を選ばない。
pub(all) struct DoubleMoveSpec {
  id : Int
  name : String
  target : Int
} derive(Debug, Eq)

///|
pub extend DoubleMoveSpec with Debug::{to_repr}

///|
pub extend DoubleMoveSpec with Eq::{not_equal, equal}

///|
/// 自陣の 1 スロット。`occupant` が `Alive` でないとき `moves` は見ない。
pub(all) struct DoubleActive {
  occupant : DoubleOccupant
  moves : Array[DoubleMoveSpec]
} derive(Debug)

///|
pub extend DoubleActive with Debug::{to_repr}

///|
priv enum SideChoices {
  SideIdle
  SideActs(Array[DoubleAction])
  SideStuck
}

///|
fn actor_slot(is_left : Bool) -> DoubleSlot {
  if is_left {
    MyLeft
  } else {
    MyRight
  }
}

///|
fn legal_targets(
  target : Int,
  actor : DoubleSlot,
  field : DoubleField,
) -> Array[DoubleSlot] {
  let out : Array[DoubleSlot] = []
  for slot in all_slots() {
    if choice_legal(target, actor, slot, field) {
      out.push(slot)
    }
  }
  out
}

///|
fn side_choices(
  active : DoubleActive,
  is_left : Bool,
  field : DoubleField,
  bench : Array[DoubleOccupant],
  psychic_terrain : Bool,
) -> SideChoices {
  if active.occupant != Alive {
    return SideIdle
  }
  let actions : Array[DoubleAction] = []
  let actor = actor_slot(is_left)
  for i in 0..<active.moves.length() {
    let spec = active.moves[i]
    let spread = is_expanding_force(spec.id, spec.name) && psychic_terrain
    if !spread && double_target_chooses(spec.target) {
      let choices = legal_targets(spec.target, actor, field)
      for slot in choices {
        actions.push(UseOn(i, slot))
      }
    } else {
      actions.push(Use(i))
    }
  }
  for i in 0..<bench.length() {
    if bench[i] == Alive {
      actions.push(BenchTo(i))
    }
  }
  if actions.length() == 0 {
    SideStuck
  } else {
    SideActs(actions)
  }
}

///|
fn as_options(choices : SideChoices) -> Array[DoubleAction?]? {
  match choices {
    SideStuck => None
    SideIdle => Some([None])
    SideActs(actions) => {
      let out : Array[DoubleAction?] = []
      for action in actions {
        out.push(Some(action))
      }
      Some(out)
    }
  }
}

///|
fn same_bench(left : DoubleAction?, right : DoubleAction?) -> Bool {
  match (left, right) {
    (Some(BenchTo(i)), Some(BenchTo(j))) => i == j
    _ => false
  }
}

///|
/// 自陣 2 体の 1 ターン。各体は技（対象が要るならそのスロット）か交代。
///
/// - 対象を選ぶのは target 0 / 1 / 2 / 14 だけ。合法なのは生きているスロット。
/// - ワイドフォースはサイコフィールド下で対象を選ばない。
/// - 空の控えとひんしの控えへは交代しない。
/// - 2 体が同じ控え添字へ交代する組は除く。別々の控えへの交代は残す。
/// - ひんしと空スロットは `None`。両方がそうなら空配列。
/// - 生きているのに選べる行動が無い体がいるときも空配列。
///
/// 並びは左の行動を外側、右を内側にする。技は配列順、対象は
/// 自陣左・自陣右・相手左・相手右の順、交代はその後に控えの添字順。
pub fn double_joint_actions(
  left : DoubleActive,
  right : DoubleActive,
  bench : Array[DoubleOccupant],
  foe_left : DoubleOccupant,
  foe_right : DoubleOccupant,
  psychic_terrain : Bool,
) -> Array[DoubleJointAction] {
  let field = DoubleField::{
    my_left: left.occupant,
    my_right: right.occupant,
    foe_left,
    foe_right,
  }
  let left_list = as_options(
    side_choices(left, true, field, bench, psychic_terrain),
  )
  let right_list = as_options(
    side_choices(right, false, field, bench, psychic_terrain),
  )
  let out : Array[DoubleJointAction] = []
  match (left_list, right_list) {
    (None, _) | (_, None) => out
    (Some(ls), Some(rs)) => {
      let both_idle = ls.length() == 1 &&
        rs.length() == 1 &&
        ls[0] == None &&
        rs[0] == None
      if both_idle {
        out
      } else {
        for l in ls {
          for r in rs {
            if !same_bench(l, r) {
              out.push(DoubleJointAction::{ left: l, right: r })
            }
          }
        }
        out
      }
    }
  }
}

///|
/// `SELECT waza, target` の行から技名 → target の表を作る。
/// 数値でない target は捨てる。`@model.Move` は作らない。
pub fn move_target_table_from_rows(
  rows : Array[Array[String]],
) -> Map[String, Int] {
  let out : Map[String, Int] = Map([])
  for row in rows {
    if row.length() < 2 {
      continue
    }
    let code = @string.parse_int(row[1]) catch {
      _ => -1
    }
    if code >= 0 {
      out[row[0]] = code
    }
  }
  out
}

///|
/// `champions.db` の `move` から target を引く。接続は champions 側が main。
pub fn load_move_target_table(
  db : @db.Db,
) -> Result[Map[String, Int], String] {
  let rows = match @db.query(db, "SELECT waza, target FROM move", []) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  Ok(move_target_table_from_rows(rows))
}
