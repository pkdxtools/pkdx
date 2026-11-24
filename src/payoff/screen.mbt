///|
/// 壁 (champout `50e7233`)。
///
/// 対象は `waza.json` `available = 1` だけ。
/// - リフレクター (`WAZAINFO_SYN_115` / `help_11_05_03`): 物理を半減。5 ターン。
/// - ひかりのかべ (`WAZAINFO_SYN_113` / `help_11_05_04`): 特殊を半減。5 ターン。
/// - オーロラベール (`WAZAINFO_SYN_694` / `help_11_05_05`): ゆきのときだけ。
///   物理と特殊を半減。5 ターン。
///
/// シングルの倍率は本文「半減」。ダブルは「２／３」。payoff はシングル
/// (`is_double = false`) なのでエンジンの 2048/4096 だけが掛かる。
/// ひかりのねんど (`ITEMNAME_269` / `ITEMINFO_SYN_269`): 合計 8 ターン。
///
/// 急所は `help_11_01_01` の「特定の能力変化　状態変化が無視されます」。
/// エンジンは `critical` のとき壁を掛けない。payoff の期待値は従来どおり
/// `critical = false` 固定で、1/24 は混ぜない。
///
/// 壊す技 (`available = 1`): かわらわり (`_280`)、サイコファング (`_706`)、
/// レイジングブル (`_873`)、きりばらい (`_432`)。本文が三つの壁を名指しする
/// 攻撃は命中前に割る。きりばらいは「リフレクター　まきびし　しんぴのまもり
/// フィールド等」なので壁三つを外す。まきびし・フィールド解除は入れない。
/// すりぬけ (`TOKUSEIINFO_SYN_151`) はダメージだけ無視し、壁は残す。
///
/// 壁は場の状態。交代では消さない。ターン終了のカウントは天候・フィールドの
/// あと (Showdown の side residual が field residual の後)。切れるターンの
/// 行動中は残っている。
///
/// 入れない: バリアフリー (登場時の解除)、レイジングブルのフォルムタイプ、
/// カウンター系の Step1 への壁、急所率の期待値混合。

const SCREEN_REFLECT : Int = 1

const SCREEN_LIGHT : Int = 2

const SCREEN_AURORA : Int = 3

///|
fn screen_kind(name : String) -> Int {
  if name == "リフレクター" {
    SCREEN_REFLECT
  } else if name == "ひかりのかべ" {
    SCREEN_LIGHT
  } else if name == "オーロラベール" {
    SCREEN_AURORA
  } else {
    0
  }
}

///|
fn is_screen_move(name : String) -> Bool {
  screen_kind(name) != 0
}

///|
fn breaks_screens(name : String) -> Bool {
  name == "かわらわり" ||
  name == "サイコファング" ||
  name == "レイジングブル" ||
  name == "きりばらい"
}

///|
/// 所持者が使ったときだけ 8。消費済み (item が空) は 5。
fn screen_duration(item : String) -> Int {
  if item == "ひかりのねんど" {
    8
  } else {
    5
  }
}

///|
fn tick_screen(turns : Int) -> Int {
  if turns <= 1 {
    0
  } else {
    turns - 1
  }
}

///|
/// 壁が一つも無いときは `NoWall` を即返す。倍率の経路は変えない。
fn screen_wall(
  reflect : Int,
  light : Int,
  aurora : Int,
  category : @model.MoveCategory,
  ability : String,
  move_name : String,
) -> @model.Wall {
  if reflect <= 0 && light <= 0 && aurora <= 0 {
    return @model.Wall::NoWall
  }
  if breaks_screens(move_name) || ability == "すりぬけ" {
    return @model.Wall::NoWall
  }
  match category {
    @model.Physical =>
      if reflect > 0 {
        @model.Wall::Reflect
      } else if aurora > 0 {
        @model.Wall::AuroraVeil
      } else {
        @model.Wall::NoWall
      }
    @model.Special =>
      if light > 0 {
        @model.Wall::LightScreen
      } else if aurora > 0 {
        @model.Wall::AuroraVeil
      } else {
        @model.Wall::NoWall
      }
    @model.Status => @model.Wall::NoWall
  }
}

///|
fn wall_cache_label(wall : @model.Wall) -> String {
  match wall {
    @model.Wall::NoWall => ""
    @model.Wall::Reflect => "リフレクター"
    @model.Wall::LightScreen => "ひかりのかべ"
    @model.Wall::AuroraVeil => "オーロラベール"
  }
}

///|
fn wall_id(wall : @model.Wall) -> Int {
  match wall {
    @model.Wall::NoWall => 0
    @model.Wall::Reflect => 1
    @model.Wall::LightScreen => 2
    @model.Wall::AuroraVeil => 3
  }
}

///|
fn with_side_screen(
  state : SwitchingGameState,
  is_me : Bool,
  kind : Int,
  turns : Int,
) -> SwitchingGameState {
  if is_me {
    match kind {
      SCREEN_REFLECT =>
        if state.my_reflect == turns {
          state
        } else {
          { ..state, my_reflect: turns }
        }
      SCREEN_LIGHT =>
        if state.my_light == turns {
          state
        } else {
          { ..state, my_light: turns }
        }
      _ =>
        if state.my_aurora == turns {
          state
        } else {
          { ..state, my_aurora: turns }
        }
    }
  } else {
    match kind {
      SCREEN_REFLECT =>
        if state.opp_reflect == turns {
          state
        } else {
          { ..state, opp_reflect: turns }
        }
      SCREEN_LIGHT =>
        if state.opp_light == turns {
          state
        } else {
          { ..state, opp_light: turns }
        }
      _ =>
        if state.opp_aurora == turns {
          state
        } else {
          { ..state, opp_aurora: turns }
        }
    }
  }
}

///|
/// オーロラベールはゆき以外では張らない。Protean は残す。
fn screen_use_outcomes(
  state : SwitchingGameState,
  is_me : Bool,
  slot : Int,
  team : Array[Combatant],
  mv : @model.Move,
  item_consumed : Bool,
) -> Array[(Double, SwitchingGameState)] {
  let base = with_protean_on_use_state(state, is_me, slot, team, mv)
  if mv.name == "オーロラベール" && base.weather != @model.Weather::Snow {
    return [(1.0, base)]
  }
  let item = if item_consumed || slot < 0 || slot >= team.length() {
    ""
  } else {
    team[slot].item
  }
  let turns = screen_duration(item)
  [(1.0, with_side_screen(base, is_me, screen_kind(mv.name), turns))]
}

///|
/// 受け側の壁を割る。壁が無い、または壊す技でないときは同じ state。
fn shatter_defender_state(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  mv : @model.Move,
) -> SwitchingGameState {
  if !breaks_screens(mv.name) {
    return state
  }
  if attacker_is_me {
    if state.opp_reflect == 0 && state.opp_light == 0 && state.opp_aurora == 0 {
      return state
    }
    { ..state, opp_reflect: 0, opp_light: 0, opp_aurora: 0 }
  } else if state.my_reflect == 0 && state.my_light == 0 && state.my_aurora == 0 {
    state
  } else {
    { ..state, my_reflect: 0, my_light: 0, my_aurora: 0 }
  }
}

///|
fn state_defender_has_screen(
  state : SwitchingGameState,
  attacker_is_me : Bool,
) -> Bool {
  if attacker_is_me {
    state.opp_reflect > 0 || state.opp_light > 0 || state.opp_aurora > 0
  } else {
    state.my_reflect > 0 || state.my_light > 0 || state.my_aurora > 0
  }
}

///|
fn defender_has_screen(ws : TurnWorkspace, attacker_is_me : Bool) -> Bool {
  if attacker_is_me {
    ws.opp_reflect > 0 || ws.opp_light > 0 || ws.opp_aurora > 0
  } else {
    ws.my_reflect > 0 || ws.my_light > 0 || ws.my_aurora > 0
  }
}

///|
fn clear_defender_screens_ws(
  ws : TurnWorkspace,
  attacker_is_me : Bool,
) -> TurnWorkspace {
  if attacker_is_me {
    { ..ws, opp_reflect: 0, opp_light: 0, opp_aurora: 0 }
  } else {
    { ..ws, my_reflect: 0, my_light: 0, my_aurora: 0 }
  }
}

///|
/// MC の 6 整数。0..2 が自分、3..5 が相手。長さが足りない呼び出しは何もしない。
fn mc_screen_ok(buf : Array[Int]) -> Bool {
  buf.length() >= 6
}

///|
fn mc_set_screen(
  buf : Array[Int],
  attacker_is_own : Bool,
  kind : Int,
  turns : Int,
) -> Unit {
  if !mc_screen_ok(buf) {
    return
  }
  let base = if attacker_is_own { 0 } else { 3 }
  if kind == SCREEN_REFLECT {
    buf[base] = turns
  } else if kind == SCREEN_LIGHT {
    buf[base + 1] = turns
  } else if kind == SCREEN_AURORA {
    buf[base + 2] = turns
  }
}

///|
fn mc_clear_defender(buf : Array[Int], attacker_is_own : Bool) -> Unit {
  if !mc_screen_ok(buf) {
    return
  }
  let base = if attacker_is_own { 3 } else { 0 }
  buf[base] = 0
  buf[base + 1] = 0
  buf[base + 2] = 0
}

///|
fn mc_defender_turns(
  buf : Array[Int],
  attacker_is_own : Bool,
) -> (Int, Int, Int) {
  if !mc_screen_ok(buf) {
    return (0, 0, 0)
  }
  let base = if attacker_is_own { 3 } else { 0 }
  (buf[base], buf[base + 1], buf[base + 2])
}

///|
fn mc_tick_screens(buf : Array[Int]) -> Unit {
  if !mc_screen_ok(buf) {
    return
  }
  if buf[0] == 0 &&
    buf[1] == 0 &&
    buf[2] == 0 &&
    buf[3] == 0 &&
    buf[4] == 0 &&
    buf[5] == 0 {
    return
  }
  buf[0] = tick_screen(buf[0])
  buf[1] = tick_screen(buf[1])
  buf[2] = tick_screen(buf[2])
  buf[3] = tick_screen(buf[3])
  buf[4] = tick_screen(buf[4])
  buf[5] = tick_screen(buf[5])
}
