///|
/// Main damage calculation function.
pub fn calc_damage(input : @model.DamageCalcInput) -> @model.DamageCalcResult {
  let atk = input.attacker
  let dfn = input.defender
  let mv = input.move_
  let move_name = mv.name
  // ウェザーボール等の type/power 上書きは Skin ability / STAB 判定の前に行う。
  // Normal→他タイプに変わった結果としてスキンが効かなくなる挙動が自然に成立。
  let (resolved_power, resolved_type) = resolve_move_type_override(mv, input)
  let mut move_type = resolved_type
  let move_power = resolved_power
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

  // StatResolution に body press / psyshock / shell side arm / secret sword /
  // unaware / critical を集約する。ここでは base stat (未補正) を比較材料と
  // して渡す — shell side arm の動的判定は本来 nature/item 補正後の値で行う
  // のが Showdown 準拠だが、現状 PR-A では base 比較で十分な近似とし、将来
  // PR で精度向上する。既存テストは shell side arm を含まないため挙動不変。
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=atk.atk, atk_spa=atk.spa,
    def_def=dfn.def_, def_spd=dfn.spd,
    atk_ability~,
    def_ability~,
    critical=input.critical,
  )
  // シェルアームズ は mv.category=Special のままで物理経路を辿る必要がある。
  // 下流の ability / item / wall / weather / ruin 分岐は必ず sr.effective_physical
  // 由来のこのフラグを参照すること (mv.category を直接参照してはならない)。
  let is_physical = sr.effective_physical
  let is_special = not(sr.effective_physical)
  // ボディプレスは攻撃側のDefenseを攻撃値として使う物理技。
  // Attack系の補正（ちからもち・はりきり・ハチマキ等）は適用されず、
  // Defense系の補正（ファーコート・しんかのきせき等）が適用される。
  // StatResolution 経由で判定: atk_stat_kind=Def かつ物理扱いなら body press
  // 相当 (技名で判定するより拡張性が高い)。
  let is_body_press = sr.atk_stat_kind == @model.StatIndex::Def &&
    sr.effective_physical

  // 2. Stat calculation
  let atk_base = match sr.atk_stat_kind {
    @model.StatIndex::Atk => atk.atk
    @model.StatIndex::Def => atk.def_
    @model.StatIndex::SpA => atk.spa
    // 下記 3 つは StatResolution が返さない値だが網羅性のため残す。
    _ => atk.atk
  }
  let def_base_hp = dfn.hp
  let def_base = match sr.def_stat_kind {
    @model.StatIndex::Def => dfn.def_
    @model.StatIndex::SpD => dfn.spd
    _ => dfn.def_
  }
  let atk_stat_index : @model.StatIndex = sr.atk_stat_kind
  let def_stat_index : @model.StatIndex = sr.def_stat_kind

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
  // StatResolution の mask 情報に従って、てんねん / 急所 / せいなるつるぎ /
  // SecretSword を直交合成する。
  let atk_stage = apply_rank_masks(
    input.atk_rank,
    sr.atk_rank_mask,
    sr.atk_rank_positive_mask,
    sr.atk_rank_negative_mask,
  )
  atk_stat = apply_rank(atk_stat, atk_stage)
  let def_stage = apply_rank_masks(
    input.def_rank,
    sr.def_rank_mask,
    sr.def_rank_positive_mask,
    sr.def_rank_negative_mask,
  )
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
  // 威力可変技 (おはかまいり / 体重依存 / つけあがる / アシストパワー /
  // やけっぱち / はたきおとす / たたりめ) は variable_power.mbt に集約。
  let mut effective_power = resolve_variable_power(
    move_power, mv, input, dfn, atk, atk_ability, def_ability,
  )
  if atk_ability.length() > 0 {
    effective_power = apply_atk_ability_power(
      atk_ability, move_name, move_type, effective_power, weather,
      force_contact=sr.force_contact,
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

  // 16-roll damage loop, factored into a closure so Parental Bond can re-run
  // it at quarter power for the 2nd hit (Showdown-accurate per-hit pipeline).
  // All non-power state (stat, ability, item, wall, STAB, type effectiveness,
  // Tinted Lens) is closed over and shared between the two invocations.
  // `def_stage_offset` is the #92 (じきゅうりょく) per-hit defense ramp;
  // each call to compute_rolls inside the multi-hit loop passes the number
  // of stamina-induced rank rises the defender has accrued so far. Rank is
  // applied as a ratio on the existing post-modifier def_stat — recomputing
  // the full ability/item/weather chain per hit would be Showdown-perfect
  // but adds 5+ extra modifier passes; the ratio approach matches typical
  // payoff fanout precision and leaves room for a follow-up to refine.
  let compute_rolls = fn(eff_pow : Int, def_stage_offset : Int) -> FixedArray[
    Int,
  ] {
    let safe_pow = if eff_pow < 1 { 1 } else { eff_pow }
    let effective_def_stat = if def_stage_offset == 0 {
      def_stat
    } else {
      let scaler_num = apply_rank(1000000, def_stage + def_stage_offset)
      let scaler_den = apply_rank(1000000, def_stage)
      if scaler_den == 0 {
        def_stat
      } else {
        def_stat * scaler_num / scaler_den
      }
    }
    let inner = 22 * safe_pow * atk_stat / effective_def_stat
    let damage_base = inner / 50 + 2
    let out : FixedArray[Int] = FixedArray::make(16, 0)
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
          force_contact=sr.force_contact,
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

      // Walls (Reflect / Light Screen / Aurora Veil).
      // Inserted between ability finals and Tinted Lens — matches the
      // Showdown final-mod chain. Critical, screen_pierce (move-side bypass),
      // and mold-breaker-family abilities each skip the multiplier
      // independently.
      let wall_ok = wall_applies(input.wall, is_physical) &&
        not(input.critical) &&
        not(input.screen_pierce) &&
        not(is_wall_bypass_ability(atk_ability))
      if wall_ok {
        let wall_mod = if input.is_double { 2732 } else { 2048 }
        dmg = round5(dmg, wall_mod)
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

      out[idx] = dmg
    }
    out
  }
  let damages = compute_rolls(effective_power, 0)

  // Disguise: ばけのかわ の初撃は実ダメージを素通し、状態遷移だけ行う。
  // State transition precedes any multi-hit expansion — disguise absorbs the
  // full move regardless of how many hits it would have landed.
  if def_ability == "ばけのかわ" && input.disguise_active {
    return disguise_blocked_result(def_hp)
  }

  // Multi-hit post-processing. Parental Bond's 2nd hit re-runs the full
  // 16-roll pipeline at 1/4 base power (Gen7+ spec, Showdown-accurate).
  let hit_plan = resolve_hit_plan(mv, atk_ability, input.multi_hit_mode)

  // Resolve the chance-node probability distribution. Random2to5 fans out
  // into 4 variants (without Skill Link), TripleVariant into 3 with the
  // mid-flight-miss weights, others stay deterministic with prob 1.0.
  let auto_spec = resolve_auto_hits(move_name)
  let plan_distribution : Array[(Int, Double)] = match hit_plan {
    Single => [(1, 1.0)]
    ParentalBond => [(2, 1.0)]
    TripleVariant(_) => [(1, 0.2), (2, 0.2), (3, 0.6)]
    FixedHits(n) =>
      match auto_spec {
        Random2to5 =>
          if atk_ability == "スキルリンク" {
            [(n, 1.0)]
          } else {
            expand_random_2_5_variants()
          }
        _ => [(n, 1.0)]
      }
  }

  // Pre-compute Parental Bond's second-hit damage outside the hit loop so
  // each variant's hits[h] can pick it up cheaply.
  let pb_second_damages : FixedArray[Int]? = match hit_plan {
    ParentalBond => Some(compute_rolls(effective_power / 4, 0))
    _ => None
  }
  let move_is_contact = is_contact_move(move_name)
  // P2-B (#92): defender's じきゅうりょく ramps Defense by +1 after each
  // landed hit (capped at +6 from entry stage). Build the per-hit
  // def_stage_offset / def_stage_after now so the variants loop can pass
  // the offset to compute_rolls and surface the rise to consumers
  // (#93/#97 fanout layers).
  let stamina_active = is_stamina_ability(def_ability) && triggers_stamina(mv)

  // Build the variants[] payload. Each variant carries one hits_count
  // possibility and its probability mass.
  let variants : Array[@model.DamageVariant] = []
  for vi = 0; vi < plan_distribution.length(); vi = vi + 1 {
    let (hits_count, prob) = plan_distribution[vi]
    let hits : Array[@model.HitStep] = []
    let cumulative : FixedArray[Int] = FixedArray::make(16, 0)
    for h = 0; h < hits_count; h = h + 1 {
      // Stage seen by hit h's damage roll: entry + h prior stamina procs,
      // clamped at +6. Stage AFTER hit h = entry + (h + 1) clamped.
      let this_offset = if stamina_active {
        let target = def_stage + h
        let clamped = if target > 6 { 6 } else { target }
        clamped - def_stage
      } else {
        0
      }
      let after_stage = if stamina_active {
        let next = def_stage + h + 1
        if next > 6 { 6 } else { next }
      } else {
        def_stage
      }
      let this_damages = match (hit_plan, h, pb_second_damages) {
        (ParentalBond, 1, Some(d2)) =>
          if stamina_active && this_offset != 0 {
            compute_rolls(effective_power / 4, this_offset)
          } else {
            d2
          }
        _ =>
          if this_offset == 0 {
            damages
          } else {
            compute_rolls(effective_power, this_offset)
          }
      }
      hits.push({
        damage_per_roll: this_damages,
        def_stage_after: after_stage,
        contact: move_is_contact,
        event: None,
      })
      for j = 0; j < 16; j = j + 1 {
        cumulative[j] = cumulative[j] + this_damages[j]
      }
    }
    let v_min = cumulative[0]
    let v_max = cumulative[15]
    let v_ko = calc_ko_text(cumulative, def_hp)
    variants.push({
      probability: prob,
      hits,
      hits_count,
      total_damages: cumulative,
      min: v_min,
      max: v_max,
      ko_text: v_ko,
    })
  }

  // Pick the most-likely variant for legacy field derivation. Ties on
  // probability resolve to the higher hits_count to preserve old behavior
  // — Random2to5 was previously collapsed to FixedHits(3), so the new
  // most-likely on the 0.375/0.375 tie should keep hits=3 (not 2).
  let mut best_idx = 0
  for i = 1; i < variants.length(); i = i + 1 {
    let cur = variants[i]
    let best = variants[best_idx]
    let strictly_better = cur.probability > best.probability
    let tie_higher_hits = cur.probability == best.probability &&
      cur.hits_count > best.hits_count
    if strictly_better || tie_higher_hits {
      best_idx = i
    }
  }
  let chosen = variants[best_idx]
  let final_damages = chosen.total_damages
  let final_percents : FixedArray[Double] = FixedArray::make(16, 0.0)
  for i = 0; i < 16; i = i + 1 {
    final_percents[i] = final_damages[i].to_double() / def_hp.to_double() *
      100.0
  }
  @model.DamageCalcResult::{
    damages: final_damages,
    percents: final_percents,
    min_damage: chosen.min,
    max_damage: chosen.max,
    min_percent: final_percents[0],
    max_percent: final_percents[15],
    ko_text: chosen.ko_text,
    defender_hp: def_hp,
    is_immune: false,
    disguise_blocked: false,
    hits_dealt: chosen.hits_count,
    variants,
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
  let zero_damages : FixedArray[Int] = FixedArray::make(16, 0)
  let immune_step : @model.HitStep = {
    damage_per_roll: zero_damages,
    def_stage_after: 0,
    contact: false,
    event: None,
  }
  @model.DamageCalcResult::{
    damages: zero_damages,
    percents: FixedArray::make(16, 0.0),
    min_damage: 0,
    max_damage: 0,
    min_percent: 0.0,
    max_percent: 0.0,
    ko_text: "immune",
    defender_hp: def_hp,
    is_immune: true,
    disguise_blocked: false,
    hits_dealt: 1,
    // Single-variant payload preserves the invariant
    // `variants.length() >= 1` for downstream consumers.
    variants: [
      {
        probability: 1.0,
        hits: [immune_step],
        hits_count: 1,
        total_damages: zero_damages,
        min: 0,
        max: 0,
        ko_text: "immune",
      },
    ],
  }
}

///|
/// Disguise initial hit: no damage dealt; state transition (1/8 max HP chip)
/// is the caller's responsibility.
fn disguise_blocked_result(def_hp : Int) -> @model.DamageCalcResult {
  let zero_damages : FixedArray[Int] = FixedArray::make(16, 0)
  // Disguise's intercepted hit deals no damage but the move did connect
  // — represent it as a single variant with hits.length() == 0 to mark
  // that no hit landed (hits_count == 0 also signals the absorbed hit).
  @model.DamageCalcResult::{
    damages: zero_damages,
    percents: FixedArray::make(16, 0.0),
    min_damage: 0,
    max_damage: 0,
    min_percent: 0.0,
    max_percent: 0.0,
    ko_text: "けがわブロック",
    defender_hp: def_hp,
    is_immune: false,
    disguise_blocked: true,
    hits_dealt: 0,
    variants: [
      {
        probability: 1.0,
        hits: [],
        hits_count: 0,
        total_damages: zero_damages,
        min: 0,
        max: 0,
        ko_text: "けがわブロック",
      },
    ],
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
