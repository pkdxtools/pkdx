///|
/// Apply attacker ability stat modifier. Returns modified atk_stat.
pub fn apply_atk_ability_stat(
  ability : String,
  is_physical : Bool,
  weather : @model.Weather,
  field : @model.Field,
  atk_stat : Int,
) -> Int {
  match ability {
    "ちからもち" | "ヨガパワー" =>
      if is_physical {
        atk_stat * 2
      } else {
        atk_stat
      }
    "はりきり" => if is_physical { atk_stat * 3 / 2 } else { atk_stat }
    "サンパワー" =>
      if !is_physical && weather == @model.Sun {
        atk_stat * 3 / 2
      } else {
        atk_stat
      }
    "こだいかっせい" =>
      if weather == @model.Sun {
        atk_stat * 13 / 10
      } else {
        atk_stat
      }
    "クォークチャージ" =>
      if field == @model.Electric {
        atk_stat * 13 / 10
      } else {
        atk_stat
      }
    "ひひいろのこどう" =>
      if is_physical && weather == @model.Sun {
        atk_stat * 5461 / 4096
      } else {
        atk_stat
      }
    "ハドロンエンジン" =>
      if !is_physical && field == @model.Electric {
        atk_stat * 5461 / 4096
      } else {
        atk_stat
      }
    _ => atk_stat
  }
}

///|
/// Apply defender ability stat modifier. Returns modified def_stat.
pub fn apply_def_ability_stat(
  ability : String,
  is_physical : Bool,
  def_stat : Int,
) -> Int {
  match ability {
    "ファーコート" => if is_physical { def_stat * 2 } else { def_stat }
    _ => def_stat
  }
}

///|
/// Check if defender ability grants immunity.
pub fn check_def_immunity(ability : String, move_type : String) -> Bool {
  match ability {
    "ちょすい" | "よびみず" => move_type == "みず"
    "もらいび" => move_type == "ほのお"
    "ひらいしん" | "でんきエンジン" => move_type == "でんき"
    "ふゆう" => move_type == "じめん"
    "そうしょく" => move_type == "くさ"
    "かんそうはだ" => move_type == "みず"
    _ => false
  }
}

///|
/// Get type resist multiplier from defender ability.
pub fn get_def_type_resist(ability : String, move_type : String) -> Double {
  match ability {
    "あついしぼう" =>
      if move_type == "ほのお" || move_type == "こおり" {
        0.5
      } else {
        1.0
      }
    "たいねつ" | "すいほう" =>
      if move_type == "ほのお" {
        0.5
      } else {
        1.0
      }
    "もふもふ" => if move_type == "ほのお" { 2.0 } else { 1.0 }
    "かんそうはだ" => if move_type == "ほのお" { 1.25 } else { 1.0 }
    _ => 1.0
  }
}

///|
/// Apply attacker ability power modifier. Returns modified power.
/// `force_contact` がある場合は is_contact_move (name テーブル) より優先する。
/// シェルアームズ 物理モード等、動的に接触扱いへ切り替わる技用。
pub fn apply_atk_ability_power(
  ability : String,
  move_name : String,
  move_type : String,
  move_power : Int,
  weather : @model.Weather,
  force_contact~ : Bool? = None,
) -> Int {
  let is_contact = match force_contact {
    Some(v) => v
    None => is_contact_move(move_name)
  }
  match ability {
    "テクニシャン" =>
      if move_power <= 60 {
        move_power * 3 / 2
      } else {
        move_power
      }
    "てつのこぶし" =>
      if is_punch_move(move_name) {
        move_power * 12 / 10
      } else {
        move_power
      }
    "がんじょうあご" =>
      if is_bite_move(move_name) {
        move_power * 3 / 2
      } else {
        move_power
      }
    "メガランチャー" =>
      if is_pulse_move(move_name) {
        move_power * 3 / 2
      } else {
        move_power
      }
    "すてみ" =>
      if is_recoil_move(move_name) {
        move_power * 12 / 10
      } else {
        move_power
      }
    "すなのちから" =>
      if weather == @model.Sand &&
        (
          move_type == "いわ" ||
          move_type == "じめん" ||
          move_type == "はがね"
        ) {
        move_power * 13 / 10
      } else {
        move_power
      }
    "すいほう" =>
      if move_type == "みず" {
        move_power * 2
      } else {
        move_power
      }
    "もらいび" =>
      if move_type == "ほのお" {
        move_power * 3 / 2
      } else {
        move_power
      }
    "かたいツメ" =>
      if is_contact {
        move_power * 13 / 10
      } else {
        move_power
      }
    "きれあじ" =>
      if is_slash_move(move_name) {
        move_power * 3 / 2
      } else {
        move_power
      }
    _ => move_power
  }
}

///|
/// Get skin ability target type. Returns (new_type, should_apply_skin_bonus).
pub fn get_skin_type(ability : String, move_type : String) -> (String, Bool) {
  if move_type != "ノーマル" {
    return (move_type, false)
  }
  match ability {
    "フェアリースキン" => ("フェアリー", true)
    "スカイスキン" => ("ひこう", true)
    "フリーズスキン" => ("こおり", true)
    "エレキスキン" => ("でんき", true)
    _ => (move_type, false)
  }
}

///|
/// Get STAB multiplier (4096 base).
pub fn get_stab_mult(ability : String) -> Int {
  if ability == "てきおうりょく" {
    8192
  } else {
    6144
  }
}

///|
/// Get attacker ability final modifier (4096 base). Returns 0 if not applicable.
pub fn get_atk_ability_final(
  ability : String,
  move_type : String,
  fainted_count : Int,
) -> Int {
  match ability {
    "トランジスタ" => if move_type == "でんき" { 5325 } else { 0 }
    "りゅうのあぎと" =>
      if move_type == "ドラゴン" {
        5325
      } else {
        0
      }
    "はがねのせいしん" =>
      if move_type == "はがね" {
        5325
      } else {
        0
      }
    "ちからずく" | "アナライズ" => 5325
    "そうだいしょう" => {
      let count = if fainted_count < 0 {
        0
      } else if fainted_count > 5 {
        5
      } else {
        fainted_count
      }
      // 4096ベース: 1→x1.1(4506), 2→x1.2(4915), 3→x1.3(5325), 4→x1.4(5734), 5→x1.5(6144)
      match count {
        1 => 4506
        2 => 4915
        3 => 5325
        4 => 5734
        5 => 6144
        _ => 0
      }
    }
    _ => 0
  }
}

///|
/// Get defender ability final modifier (4096 base).
pub fn get_def_ability_final(
  ability : String,
  move_name : String,
  move_type : String,
  is_super_effective : Bool,
  is_special : Bool,
  force_contact~ : Bool? = None,
) -> Int {
  let is_contact = match force_contact {
    Some(v) => v
    None => is_contact_move(move_name)
  }
  match ability {
    "マルチスケイル" => 2048
    "フィルター" | "ハードロック" =>
      if is_super_effective {
        3072
      } else {
        0
      }
    "こおりのりんぷん" => if is_special { 2048 } else { 0 }
    "もふもふ" =>
      if is_contact && move_type != "ほのお" {
        2048
      } else {
        0
      }
    "かんそうはだ" => if move_type == "ほのお" { 5120 } else { 0 }
    _ => 0
  }
}

///|
/// Apply ruin ability cross-side stat modifier.
/// Attacker's ruin ability reduces defender's stat; defender's ruin ability reduces attacker's stat.
pub fn apply_ruin_cross_stat(
  atk_ability : String,
  def_ability : String,
  is_physical : Bool,
  atk_stat : Int,
  def_stat : Int,
) -> (Int, Int) {
  let mut a = atk_stat
  let mut d = def_stat
  match def_ability {
    "わざわいのおふだ" => if is_physical { a = a * 3 / 4 }
    "わざわいのうつわ" => if !is_physical { a = a * 3 / 4 }
    _ => ()
  }
  match atk_ability {
    "わざわいのつるぎ" => if is_physical { d = d * 3 / 4 }
    "わざわいのたま" => if !is_physical { d = d * 3 / 4 }
    _ => ()
  }
  (a, d)
}

///|
/// じきゅうりょく (Stamina): every time the holder is hit by a damaging
/// move, its Defense stage rises by 1 (capped at +6). For multi-hit
/// moves the rise applies after each hit, so the second hit's damage
/// roll sees +1 def, the third sees +2, and so on.
///
/// Used by `damage/engine.mbt`'s multi-hit loop to thread a per-hit
/// `def_stage_offset` through `compute_rolls` and to populate
/// `HitStep.def_stage_after` for downstream payoff fanout (#92 / #93).
pub fn is_stamina_ability(name : String) -> Bool {
  name == "じきゅうりょく"
}

///|
/// Whether a move triggers Stamina when it lands. The Pokemon Showdown
/// spec ramps Stamina on any damaging hit regardless of category, so
/// physical and special multi-hit moves alike see the per-hit ramp.
/// Status moves (those that don't deal damage) don't trigger.
///
/// In practice within pkdx the move-type filter is "any move that the
/// damage engine actually computes damage for" — `is_immune` /
/// `disguise_blocked` paths short-circuit before the variants loop, so
/// this guard only sees real damaging hits.
pub fn triggers_stamina(mv : @model.Move) -> Bool {
  // Status-category moves never reach the damage variants loop, but
  // gate them out defensively in case future callers reuse this helper
  // outside that flow.
  mv.category != @model.Status
}

///|
/// Contact-induced status procs on the attacker. Returns one or more
/// `(StatusKind, chance%)` entries the defender's ability inflicts on
/// the attacker when hit by a contact move; an empty array for
/// non-procking abilities.
///
/// Used by switching_game's `apply_contact_proc_fanout` to surface
/// chance nodes for ほのおのからだ / せいでんき / どくしゅ / ほうし.
/// てつのトゲ / さめはだ trigger recoil-style HP damage instead and are
/// handled separately (deterministic, not a chance node).
///
/// ほうし は per-hit で 11% どく / 10% まひ / 9% ねむり (合計 30%、Gen9 仕様)。
/// 単一エントリに畳むと「どく無効の攻撃側はすべての proc を回避」という
/// 過剰な近似になるため、3 エントリへ分けて返す。
pub fn contact_proc_ability(
  name : String,
) -> Array[(@model.StatusKind, Int)] {
  match name {
    "ほのおのからだ" => [(@model.BurnKind, 30)]
    "せいでんき" => [(@model.ParalyzeKind, 30)]
    "どくしゅ" => [(@model.PoisonKind, 30)]
    "ほうし" => [
      (@model.PoisonKind, 11),
      (@model.ParalyzeKind, 10),
      (@model.SleepKind, 9),
    ]
    _ => []
  }
}
