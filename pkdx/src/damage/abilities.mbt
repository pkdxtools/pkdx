/// Apply attacker ability stat modifier. Returns modified atk_stat.
pub fn apply_atk_ability_stat(
  ability : String,
  is_physical : Bool,
  weather : String,
  field : String,
  atk_stat : Int
) -> Int {
  match ability {
    "ちからもち" | "ヨガパワー" =>
      if is_physical { atk_stat * 2 } else { atk_stat }
    "はりきり" => if is_physical { atk_stat * 3 / 2 } else { atk_stat }
    "サンパワー" =>
      if not(is_physical) && weather == "はれ" {
        atk_stat * 3 / 2
      } else {
        atk_stat
      }
    "こだいかっせい" =>
      if weather == "はれ" { atk_stat * 13 / 10 } else { atk_stat }
    "クォークチャージ" =>
      if field == "エレキ" { atk_stat * 13 / 10 } else { atk_stat }
    "ひひいろのこどう" =>
      if is_physical && weather == "はれ" {
        atk_stat * 5461 / 4096
      } else {
        atk_stat
      }
    "ハドロンエンジン" =>
      if not(is_physical) && field == "エレキ" {
        atk_stat * 5461 / 4096
      } else {
        atk_stat
      }
    _ => atk_stat
  }
}

/// Apply defender ability stat modifier. Returns modified def_stat.
pub fn apply_def_ability_stat(
  ability : String,
  is_physical : Bool,
  def_stat : Int
) -> Int {
  match ability {
    "ファーコート" => if is_physical { def_stat * 2 } else { def_stat }
    _ => def_stat
  }
}

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
      if move_type == "ほのお" { 0.5 } else { 1.0 }
    "もふもふ" => if move_type == "ほのお" { 2.0 } else { 1.0 }
    "かんそうはだ" => if move_type == "ほのお" { 1.25 } else { 1.0 }
    _ => 1.0
  }
}

/// Apply attacker ability power modifier. Returns modified power.
pub fn apply_atk_ability_power(
  ability : String,
  move_name : String,
  move_type : String,
  move_power : Int,
  weather : String
) -> Int {
  match ability {
    "テクニシャン" => if move_power <= 60 { move_power * 3 / 2 } else { move_power }
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
      if weather == "すなあらし" &&
        (move_type == "いわ" || move_type == "じめん" || move_type == "はがね") {
        move_power * 13 / 10
      } else {
        move_power
      }
    "すいほう" => if move_type == "みず" { move_power * 2 } else { move_power }
    "もらいび" => if move_type == "ほのお" { move_power * 3 / 2 } else { move_power }
    "かたいツメ" =>
      if is_contact_move(move_name) {
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

/// Get STAB multiplier (4096 base).
pub fn get_stab_mult(ability : String) -> Int {
  if ability == "てきおうりょく" { 8192 } else { 6144 }
}

/// Get attacker ability final modifier (4096 base). Returns 0 if not applicable.
pub fn get_atk_ability_final(
  ability : String,
  move_type : String
) -> Int {
  match ability {
    "トランジスタ" => if move_type == "でんき" { 5325 } else { 0 }
    "りゅうのあぎと" => if move_type == "ドラゴン" { 5325 } else { 0 }
    "はがねのせいしん" => if move_type == "はがね" { 5325 } else { 0 }
    "ちからずく" | "アナライズ" => 5325
    _ => 0
  }
}

/// Get defender ability final modifier (4096 base).
pub fn get_def_ability_final(
  ability : String,
  move_name : String,
  move_type : String,
  is_super_effective : Bool,
  is_special : Bool
) -> Int {
  match ability {
    "マルチスケイル" => 2048
    "フィルター" | "ハードロック" =>
      if is_super_effective { 3072 } else { 0 }
    "こおりのりんぷん" => if is_special { 2048 } else { 0 }
    "もふもふ" =>
      if is_contact_move(move_name) && move_type != "ほのお" {
        2048
      } else {
        0
      }
    "かんそうはだ" => if move_type == "ほのお" { 5120 } else { 0 }
    _ => 0
  }
}

/// Apply ruin ability cross-side stat modifier.
/// Attacker's ruin ability reduces defender's stat; defender's ruin ability reduces attacker's stat.
pub fn apply_ruin_cross_stat(
  atk_ability : String,
  def_ability : String,
  is_physical : Bool,
  atk_stat : Int,
  def_stat : Int
) -> (Int, Int) {
  let mut a = atk_stat
  let mut d = def_stat
  match def_ability {
    "わざわいのおふだ" => if is_physical { a = a * 3 / 4 }
    "わざわいのうつわ" => if not(is_physical) { a = a * 3 / 4 }
    _ => ()
  }
  match atk_ability {
    "わざわいのつるぎ" => if is_physical { d = d * 3 / 4 }
    "わざわいのたま" => if not(is_physical) { d = d * 3 / 4 }
    _ => ()
  }
  (a, d)
}
