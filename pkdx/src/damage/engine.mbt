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
  let raw_def_stat = if input.stat_system == @model.Champions {
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

  // 2b-atk. Attacker-side ability stat modifier (independent of def_stage).
  if is_body_press {
    if atk_ability.length() > 0 {
      atk_stat = apply_def_ability_stat(atk_ability, true, atk_stat)
    }
  } else if atk_ability.length() > 0 {
    atk_stat = apply_atk_ability_stat(
      atk_ability, is_physical, weather, field, atk_stat,
    )
  }

  // 2b-2-atk. Atk-side ruin (defender's ability lowers attacker's stat).
  // ボディプレスは攻撃値として自分の Defense を使うため、わざわいのおふだ
  // / うつわ の影響を受けない。
  if not(is_body_press) {
    match def_ability {
      "わざわいのおふだ" => if is_physical { atk_stat = atk_stat * 3 / 4 }
      "わざわいのうつわ" => if !is_physical { atk_stat = atk_stat * 3 / 4 }
      _ => ()
    }
  }

  // 2c-atk. Attacker-side item stat modifier.
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

  // 2d-atk. Body-press: atk_stat is a Defense value, so apply 雪×こおり Def boost.
  if is_body_press && weather.is_active() {
    atk_stat = apply_weather_def_mod(
      weather,
      (atk.type1, atk.type2),
      true,
      atk_stat,
    )
  }

  // Defense-side pipeline factored as a closure so multi-hit じきゅうりょく
  // can recompute from raw_def_stat at any rank stage. Floor-sensitive
  // modifiers (しんかのきせき / とつげきチョッキ / ファーコート / Sand SpD /
  // Snow Def) must run AFTER the rank multiplier each time, otherwise
  // ratio-scaling the post-modifier value drifts (e.g. Eviolite on base
  // Def 101: stage 0 → floor(101*1.5)=151; stage +2 → floor(202*1.5)=303,
  // not 151*2=302).
  let compute_def_at_stage = fn(stage : Int) -> Int {
    let mut s = apply_rank(raw_def_stat, stage)
    if def_ability.length() > 0 {
      s = apply_def_ability_stat(def_ability, is_physical, s)
    }
    // 2b-2-def. Def-side ruin (attacker's ability lowers defender's stat).
    if is_body_press {
      if atk_ability == "わざわいのつるぎ" {
        s = s * 3 / 4
      }
    } else {
      match atk_ability {
        "わざわいのつるぎ" => if is_physical { s = s * 3 / 4 }
        "わざわいのたま" => if !is_physical { s = s * 3 / 4 }
        _ => ()
      }
    }
    if def_item.length() > 0 {
      s = apply_def_item_stat(def_item, is_physical, s)
    }
    if weather.is_active() {
      s = apply_weather_def_mod(weather, (dfn.type1, dfn.type2), is_physical, s)
    }
    s
  }
  let def_stat = compute_def_at_stage(def_stage)

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
  // TripleVariant (トリプルキック / トリプルアクセル) は hit ごとに base_power
  // が変わるので、ability/item/type-resist の最終チェインだけ closure 化して
  // hit ごとに再適用する (variable_power はこれらの move では恒等関数なので
  // 入口で 1 度だけ呼ぶ)。
  let resolved_var_power = resolve_variable_power(
    move_power, mv, input, dfn, atk, atk_ability, def_ability,
  )
  let apply_power_modifiers = fn(base : Int) -> Int {
    let mut p = base
    if atk_ability.length() > 0 {
      p = apply_atk_ability_power(
        atk_ability, move_name, move_type, p, weather,
        force_contact=sr.force_contact,
      )
    }
    if atk_item.length() > 0 {
      p = apply_type_boost_item(atk_item, move_type, p)
    }
    if type_resist_mult != 1.0 {
      let q = (p.to_double() * type_resist_mult).to_int()
      p = if q < 1 { 1 } else { q }
    }
    p
  }
  let mut effective_power = apply_power_modifiers(resolved_var_power)

  // Skin abilities (フェアリースキン / スカイスキン / フリーズスキン / エレキスキン).
  // Gen 7+ では技タイプ変換に加えて base power に 1.2x (4915/4096) を直接乗せる。
  // Gen 6 仕様 (STAB 後の damage modifier として 1.3x) とは丸めの位置が異なるため、
  // ここで power modifier として適用する必要がある。Showdown 準拠。
  if skin_bonus {
    effective_power = round5(effective_power, 4915)
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
  // `hit_def_stat` is the defender's Defense after the full ability/item/
  // weather pipeline at this hit's rank stage. For じきゅうりょく the multi-
  // hit loop recomputes via `compute_def_at_stage` so floor-sensitive
  // modifiers (Eviolite / Assault Vest / Sand / Snow / Fur Coat) round at
  // each stage rather than being ratio-scaled from a single anchor value.
  // `apply_resist_berry` gates the per-roll resist-berry power_mod. Multi-hit
  // moves consume the berry on the first qualifying hit; subsequent hits
  // must run without the halving even though the same `compute_rolls`
  // closure is reused for them. Single-hit callers always pass `true`.
  let compute_rolls = fn(
    eff_pow : Int,
    hit_def_stat : Int,
    apply_resist_berry : Bool,
  ) -> FixedArray[Int] {
    let safe_pow = if eff_pow < 1 { 1 } else { eff_pow }
    let safe_def = if hit_def_stat < 1 { 1 } else { hit_def_stat }
    let inner = 22 * safe_pow * atk_stat / safe_def
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

      // Resist berry. Skipped past the first hit of a multi-hit move so the
      // berry doesn't halve every hit (it is consumed on the first qualifying
      // hit and gone for the rest of the move).
      if apply_resist_berry && def_item.length() > 0 {
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
  let damages = compute_rolls(effective_power, def_stat, true)

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
  // multi_hit_mode が Auto のときは shared helper に委ねる; explicit
  // Fixed(n) だけは hit_plan が `FixedHits(n)` を抱えているのでこちらで
  // 単一エントリに畳む。
  let plan_distribution : Array[(Int, Double)] = match input.multi_hit_mode {
    @model.MultiHit::Auto => resolve_hit_distribution(mv, atk_ability)
    @model.MultiHit::Fixed(_) =>
      match hit_plan {
        FixedHits(n) => [(n, 1.0)]
        Single => [(1, 1.0)]
        ParentalBond => [(2, 1.0)]
        TripleVariant(_) => [(1, 0.10), (2, 0.09), (3, 0.81)]
      }
    @model.MultiHit::Expected =>
      abort(
        "MultiHit::Expected is a payoff-only approximation; pkdx damage does not accept it",
      )
  }

  // Pre-compute Parental Bond's second-hit damage outside the hit loop so
  // each variant's hits[h] can pick it up cheaply. The 2nd hit never re-fires
  // a resist berry — it was either consumed by the 1st hit or did not match.
  let pb_second_damages : FixedArray[Int]? = match hit_plan {
    ParentalBond => Some(compute_rolls(effective_power / 4, def_stat, false))
    _ => None
  }
  // P1-A (#100): contact フラグは StatResolution.force_contact を優先する。
  // シェルアームズ 物理モード等の動的接触判定が、HitStep.contact と payoff
  // 側 contact-proc fanout から漏れないようにここで一本化する。
  let move_is_contact = resolve_move_contact(mv, sr.force_contact)
  // Pre-compute the no-berry damage table for hits past the first when the
  // move is multi-hit. Single-hit moves never consult this. The branch
  // bypasses re-running the closure when the per-hit defense stage is
  // unchanged from entry.
  let need_no_berry_table = match hit_plan {
    Single => false
    _ => true
  }
  let damages_no_berry : FixedArray[Int]? = if need_no_berry_table {
    Some(compute_rolls(effective_power, def_stat, false))
  } else {
    None
  }
  // P2-B (#92): defender's じきゅうりょく ramps Defense by +1 after each
  // landed hit (capped at +6 from entry stage). The variants loop passes
  // the resulting `def_stage + offset` to `compute_def_at_stage` per hit
  // and surfaces `def_stage_after` to downstream payoff fanout (#93/#97).
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
      // TripleVariant (トリプルキック / トリプルアクセル) は hit が当たる
      // ごとに base_power が hit 番号ぶん上昇する: hit 1 = base、hit 2 =
      // base*2、hit 3 = base*3。すいりゅうれんだ / トリプルダイブ は
      // FixedHits(3) なのでこの分岐には落ちず、固定 base_power で 3 回殴る。
      // じきゅうりょく が active かつ stage が変わる hit では、防御側の
      // ability/item/weather チェインを raw_def_stat から組み直して
      // 床関数誤差を排除する (Eviolite / 突撃チョッキ 等)。
      let hit_def_stat = if stamina_active && this_offset != 0 {
        compute_def_at_stage(def_stage + this_offset)
      } else {
        def_stat
      }
      // Resist berry は 1 hit 目だけ消費されるので apply_berry_here で gating する。
      let apply_berry_here = h == 0
      let this_damages = match (hit_plan, h, pb_second_damages) {
        (ParentalBond, 1, Some(d2)) =>
          if stamina_active && this_offset != 0 {
            compute_rolls(effective_power / 4, hit_def_stat, false)
          } else {
            d2
          }
        (TripleVariant(_), _, _) => {
          let per_hit_pow = apply_power_modifiers(resolved_var_power * (h + 1))
          compute_rolls(per_hit_pow, hit_def_stat, apply_berry_here)
        }
        _ =>
          if this_offset == 0 {
            if apply_berry_here {
              damages
            } else {
              match damages_no_berry {
                Some(d) => d
                None => damages
              }
            }
          } else {
            compute_rolls(effective_power, hit_def_stat, apply_berry_here)
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
