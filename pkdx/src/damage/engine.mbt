///|
/// Main damage calculation function.
pub fn calc_damage(input : @model.DamageCalcInput) -> @model.DamageCalcResult {
  let atk = input.attacker
  let dfn = input.defender
  let mv = input.move_
  let mut move_type = mv.type_
  let move_name = mv.name
  let move_power = mv.power
  let is_physical = mv.category == @model.Physical
  let is_special = mv.category == @model.Special
  let weather = input.weather
  let field = input.field
  let tera_type = input.tera_type
  let atk_ability = input.atk_ability
  let def_ability = input.def_ability
  let atk_item = input.atk_item
  let def_item = input.def_item

  // 1. Skin ability
  let mut skin_bonus = false
  if atk_ability.length() > 0 {
    let (new_type, has_skin) = get_skin_type(atk_ability, move_type)
    move_type = new_type
    skin_bonus = has_skin
  }

  // Tera STAB setup
  let stab_types : Array[String] = [atk.type1]
  if atk.type2.length() > 0 {
    stab_types.push(atk.type2)
  }
  let mut tera_stab_bonus = false
  if tera_type.length() > 0 {
    stab_types.push(tera_type)
    if (tera_type == atk.type1 || tera_type == atk.type2) &&
      move_type == tera_type {
      tera_stab_bonus = true
    }
  }

  // ボディプレスは攻撃側のDefenseを攻撃値として使う物理技。
  // Attack系の補正（ちからもち・はりきり・ハチマキ等）は適用されず、
  // Defense系の補正（ファーコート・しんかのきせき等）が適用される。
  let is_body_press = move_name == "ボディプレス"

  // 2. Stat calculation
  let atk_base = if is_physical {
    if is_body_press {
      atk.def_
    } else {
      atk.atk
    }
  } else {
    atk.spa
  }
  let def_base_hp = dfn.hp
  let def_base = if is_physical { dfn.def_ } else { dfn.spd }

  // Nature が参照する stat index を決定する。
  // 攻撃側: body press は Def、それ以外は move カテゴリに従って Atk / SpA。
  // 防御側: move カテゴリに従って Def / SpD。
  let atk_stat_index : @model.StatIndex = if is_body_press {
    Def
  } else if is_physical {
    Atk
  } else {
    SpA
  }
  let def_stat_index : @model.StatIndex = if is_physical { Def } else { SpD }

  // Nature 補正 numerator/denominator:
  //   attacker default (None) = +10% (legacy 攻撃stat特化相当)
  //   defender default (None) = 無補正
  let (atk_num, atk_den) = match input.atk_nature {
    Some(n) => @model.nature_mult_int(n, atk_stat_index)
    None => (11, 10)
  }
  let (def_num, def_den) = match input.def_nature {
    Some(n) => @model.nature_mult_int(n, def_stat_index)
    None => (1, 1)
  }
  let mut atk_stat = if input.stat_system == @model.Champions {
    calc_stat_champions(
      atk_base,
      nature_num=atk_num,
      nature_den=atk_den,
      custom=input.atk_stat_override,
    )
  } else {
    calc_stat(
      atk_base,
      nature_num=atk_num,
      nature_den=atk_den,
      custom=input.atk_stat_override,
    )
  }
  // 防御側デフォルトは「無投資・性格補正なし」。
  // 攻撃側は最大投資前提のままだが、防御側を最大投資扱いにすると一般的な
  // ダメ計ツール (Showdown, PokeVision 等) と結果が乖離するため。
  let def_hp = if input.stat_system == @model.Champions {
    calc_def_stat_champions(
      def_base_hp, is_hp=true, custom=input.def_hp_override,
    )
  } else {
    calc_def_stat(def_base_hp, is_hp=true, custom=input.def_hp_override)
  }
  let mut def_stat = if input.stat_system == @model.Champions {
    calc_def_stat_champions(
      def_base,
      nature_num=def_num,
      nature_den=def_den,
      custom=input.def_stat_override,
    )
  } else {
    calc_def_stat(
      def_base,
      nature_num=def_num,
      nature_den=def_den,
      custom=input.def_stat_override,
    )
  }

  // 2a-2. Rank (stat stage) modifiers
  // override は「rank 前の実数値」として扱う。rank は常に掛ける。
  let atk_stage = if input.critical && input.atk_rank < 0 {
    0
  } else {
    input.atk_rank
  }
  atk_stat = apply_rank(atk_stat, atk_stage)
  let def_stage = if input.critical && input.def_rank > 0 {
    0
  } else {
    input.def_rank
  }
  def_stat = apply_rank(def_stat, def_stage)

  // 2b. Ability stat modifiers
  if is_body_press {
    if atk_ability.length() > 0 {
      atk_stat = apply_def_ability_stat(atk_ability, true, atk_stat)
    }
  } else if atk_ability.length() > 0 {
    atk_stat = apply_atk_ability_stat(
      atk_ability, is_physical, weather, field, atk_stat,
    )
  }
  if def_ability.length() > 0 {
    def_stat = apply_def_ability_stat(def_ability, is_physical, def_stat)
  }

  // 2b-2. Ruin ability cross-side stat modifiers
  // ボディプレスの場合、攻撃値として使われるのは自身のDefenseなので
  // わざわいのおふだ（相手の物理Atkを下げる）は影響しない。
  // わざわいのつるぎ（相手の物理Defを下げる）は通常通り適用される。
  if is_body_press {
    if atk_ability == "わざわいのつるぎ" {
      def_stat = def_stat * 3 / 4
    }
  } else if atk_ability.length() > 0 || def_ability.length() > 0 {
    let (new_atk, new_def) = apply_ruin_cross_stat(
      atk_ability, def_ability, is_physical, atk_stat, def_stat,
    )
    atk_stat = new_atk
    def_stat = new_def
  }

  // 2c. Item stat modifiers
  if is_body_press {
    if atk_item.length() > 0 {
      atk_stat = apply_def_item_stat(atk_item, true, atk_stat)
    }
  } else if atk_item.length() > 0 {
    atk_stat = apply_atk_item_stat(
      atk_item,
      is_physical,
      atk.global_no,
      atk_stat,
    )
  }
  if def_item.length() > 0 {
    def_stat = apply_def_item_stat(def_item, is_physical, def_stat)
  }

  // 2d. Weather defense modifiers
  if weather.is_active() {
    def_stat = apply_weather_def_mod(
      weather,
      (dfn.type1, dfn.type2),
      is_physical,
      def_stat,
    )
    // ボディプレスは自身のDefenseが攻撃値なので、攻撃側にも雪×こおりの
    // Def 1.5倍補正を適用する。
    if is_body_press {
      atk_stat = apply_weather_def_mod(
        weather,
        (atk.type1, atk.type2),
        true,
        atk_stat,
      )
    }
  }

  // Immunity check
  if def_ability.length() > 0 && check_def_immunity(def_ability, move_type) {
    return immune_result(def_hp)
  }

  // Type resist from defender ability
  let type_resist_mult = if def_ability.length() > 0 {
    get_def_type_resist(def_ability, move_type)
  } else {
    1.0
  }

  // 3. Power calculation
  let mut effective_power = move_power

  // おはかまいり: 基礎威力50 + 味方瀕死回数×50（最大100回=5050）
  if move_name == "おはかまいり" {
    let count = if input.fainted_count > 100 { 100 } else { input.fainted_count }
    effective_power = 50 + count * 50
  }

  // 体重参照技は固定威力を上書きする（後続のテクニシャン等の補正は通常通り乗る）。
  if move_name == "けたぐり" || move_name == "くさむすび" {
    let dw = effective_weight(dfn.weight, def_ability)
    effective_power = weight_based_power(dw)
  } else if move_name == "ヘビーボンバー" || move_name == "ヒートスタンプ" {
    let aw = effective_weight(atk.weight, atk_ability)
    let dw = effective_weight(dfn.weight, def_ability)
    effective_power = weight_ratio_power(aw, dw)
  }

  if atk_ability.length() > 0 {
    effective_power = apply_atk_ability_power(
      atk_ability, move_name, move_type, effective_power, weather,
    )
  }
  if atk_item.length() > 0 {
    effective_power = apply_type_boost_item(
      atk_item, move_type, effective_power,
    )
  }
  if type_resist_mult != 1.0 {
    effective_power = {
      let p = (effective_power.to_double() * type_resist_mult).to_int()
      if p < 1 {
        1
      } else {
        p
      }
    }
  }

  // 4. Base damage
  let inner = 22 * effective_power * atk_stat / def_stat
  let damage_base = inner / 50 + 2

  // Type effectiveness (using x4 integer encoding)
  let atk_type_opt = @types.type_from_jp(move_type)
  let def1_opt = @types.type_from_jp(dfn.type1)
  let def2_opt = if dfn.type2.length() > 0 {
    @types.type_from_jp(dfn.type2)
  } else {
    None
  }
  let (eff1_x4, eff2_x4) = match (atk_type_opt, def1_opt) {
    (Some(at), Some(d1)) => {
      let e1 = @types.get_effectiveness_x4(at, d1)
      let e2 = match def2_opt {
        Some(d2) => @types.get_effectiveness_x4(at, d2)
        None => 4
      }
      (e1, e2)
    }
    _ => (4, 4)
  }

  // Check for type immunity
  if eff1_x4 == 0 || eff2_x4 == 0 {
    return immune_result(def_hp)
  }

  let total_eff_x16 = eff1_x4 * eff2_x4
  let is_super_effective = total_eff_x16 > 16
  let is_not_very_effective = total_eff_x16 < 16

  // STAB
  let mut has_stab = false
  for i = 0; i < stab_types.length(); i = i + 1 {
    if stab_types[i] == move_type {
      has_stab = true
      break
    }
  }
  let stab_mult = if has_stab {
    if atk_ability == "てきおうりょく" || tera_stab_bonus {
      8192
    } else {
      6144
    }
  } else {
    4096
  }

  // 16-roll damage loop
  let damages : FixedArray[Int] = FixedArray::make(16, 0)
  let percents : FixedArray[Double] = FixedArray::make(16, 0.0)

  for idx = 0; idx < 16; idx = idx + 1 {
    let rand = 85 + idx
    let mut dmg = damage_base

    // Spread move modifier (double battle, 0.75x)
    if input.is_double && is_spread_move(move_name) {
      dmg = round5(dmg, 3072)
    }

    // Weather damage mod
    if weather.is_active() {
      let w_mod = get_weather_damage_mod(weather, move_type)
      if w_mod > 0 {
        dmg = round5(dmg, w_mod)
      }
    }

    // Field mod
    if field.is_active() {
      let f_mod = get_field_damage_mod(field, move_type)
      if f_mod > 0 {
        dmg = round5(dmg, f_mod)
      }
    }

    // Critical
    if input.critical {
      dmg = round5(dmg, 6144)
    }

    // Random roll
    dmg = dmg * rand / 100

    // STAB
    if has_stab {
      dmg = round5(dmg, stab_mult)
    }

    // Skin bonus
    if skin_bonus {
      dmg = round5(dmg, 4915)
    }

    // Type effectiveness (integer fraction)
    dmg = dmg * eff1_x4 / 4
    dmg = dmg * eff2_x4 / 4

    // Defender ability final
    if def_ability.length() > 0 {
      let d_mod = get_def_ability_final(
        def_ability, move_name, move_type, is_super_effective, is_special,
      )
      if d_mod > 0 {
        dmg = round5(dmg, d_mod)
      }
    }

    // Attacker ability final
    if atk_ability.length() > 0 {
      let a_mod = get_atk_ability_final(atk_ability, move_type, input.fainted_count)
      if a_mod > 0 {
        dmg = round5(dmg, a_mod)
      }
    }

    // Tinted Lens
    if atk_ability == "いろめがね" && is_not_very_effective {
      dmg = dmg * 2
    }

    // Attacker item final
    if atk_item.length() > 0 {
      let i_mod = get_atk_item_final(atk_item, is_physical, is_super_effective)
      if i_mod > 0 {
        dmg = round5(dmg, i_mod)
      }
    }

    // Resist berry
    if def_item.length() > 0 {
      let berry_type = get_resist_berry_type(def_item)
      if berry_type.length() > 0 && berry_type == move_type {
        if def_item == "ホズのみ" || is_super_effective {
          dmg = round5(dmg, 2048)
        }
      }
    }

    // Minimum 1
    if dmg < 1 {
      dmg = 1
    }

    damages[idx] = dmg
    percents[idx] = dmg.to_double() / def_hp.to_double() * 100.0
  }

  // KO calculation
  let min_d = damages[0]
  let max_d = damages[15]
  let ko_text = calc_ko_text(damages, def_hp)

  @model.DamageCalcResult::{
    damages,
    percents,
    min_damage: min_d,
    max_damage: max_d,
    min_percent: percents[0],
    max_percent: percents[15],
    ko_text,
    defender_hp: def_hp,
    is_immune: false,
  }
}

///|
/// ヘヴィメタル / ライトメタルによる体重補正。
/// ヘヴィメタル: 自身の体重×2, ライトメタル: 自身の体重×1/2。
fn effective_weight(base : Double, ability : String) -> Double {
  if ability == "ヘヴィメタル" {
    base * 2.0
  } else if ability == "ライトメタル" {
    base * 0.5
  } else {
    base
  }
}

///|
/// けたぐり / くさむすび の威力決定（相手の体重基準）。
fn weight_based_power(weight : Double) -> Int {
  if weight <= 10.0 {
    20
  } else if weight <= 25.0 {
    40
  } else if weight <= 50.0 {
    60
  } else if weight <= 100.0 {
    80
  } else if weight <= 200.0 {
    100
  } else {
    120
  }
}

///|
/// ヘビーボンバー / ヒートスタンプ の威力決定（自身 / 相手 の体重比）。
/// 体重が相手の 5倍以上→120, 4倍以上→100, 3倍以上→80, 2倍以上→60, それ未満→40。
fn weight_ratio_power(atk_weight : Double, def_weight : Double) -> Int {
  if def_weight <= 0.0 {
    return 40
  }
  if def_weight * 5.0 <= atk_weight {
    120
  } else if def_weight * 4.0 <= atk_weight {
    100
  } else if def_weight * 3.0 <= atk_weight {
    80
  } else if def_weight * 2.0 <= atk_weight {
    60
  } else {
    40
  }
}

///|
fn immune_result(def_hp : Int) -> @model.DamageCalcResult {
  @model.DamageCalcResult::{
    damages: FixedArray::make(16, 0),
    percents: FixedArray::make(16, 0.0),
    min_damage: 0,
    max_damage: 0,
    min_percent: 0.0,
    max_percent: 0.0,
    ko_text: "immune",
    defender_hp: def_hp,
    is_immune: true,
  }
}

///|
fn calc_ko_text(damages : FixedArray[Int], def_hp : Int) -> String {
  for n = 1; n < 5; n = n + 1 {
    let mut ko_count = 0
    for i = 0; i < 16; i = i + 1 {
      if damages[i] * n >= def_hp {
        ko_count = ko_count + 1
      }
    }
    if ko_count == 16 {
      return "\u{78BA}\u{5B9A}" + n.to_string() + "\u{767A}"
    } else if ko_count > 0 {
      return "\u{4E71}\u{6570}" +
        n.to_string() +
        "\u{767A}(" +
        ko_count.to_string() +
        "/16)"
    }
  }
  "5\u{767A}\u{4EE5}\u{4E0A}"
}
