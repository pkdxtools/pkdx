///|
/// Paralyze: 12.5% chance of full-turn failure (gen7+ freeze/paralysis rate).
pub const PARALYZE_SKIP_RATE : Double = 0.125

///|
/// Enumerate the attempt outcomes for a side given its current status, the
/// declared action, and the move's accuracy (ignored for Switch; 100 for the
/// selected move if `UseMove`/`Mega`). Outcomes with probability 0 are
/// filtered out so downstream fan-out doesn't enumerate dead branches.
///
/// The Switch action is always deterministic — status / accuracy don't gate
/// switching. Only `UseMove` / `Mega` can skip.
///
/// `must_recharge` short-circuits `UseMove` / `Mega` to a guaranteed no-op
/// skip (paralysis/sleep overrides do not stack on top; recharge wins
/// outright when set). Switch is **never** gated here — `alive_actions`
/// collapses the enumeration to the `UseMove(0)` placeholder while the
/// active is alive, so any Switch that reaches this helper with
/// `must_recharge = true` is a forced replacement after the recharging slot
/// fainted to end-of-turn damage. Short-circuiting that would strand the
/// side with an illegal dead active.
pub fn per_side_attempt(
  status : @model.StatusCondition,
  must_recharge : Bool,
  action : ActionKind,
  accuracy : Int,
) -> Array[SideAttempt] {
  if must_recharge {
    match action {
      UseMove(_) | Mega(_) =>
        return [{ prob: 1.0, acts: false, action, post_status: status }]
      Switch(_) => ()
    }
  }
  let acts_only : Array[SideAttempt] = [
    { prob: 1.0, acts: true, action, post_status: status },
  ]
  match action {
    Switch(_) => acts_only
    UseMove(_) | Mega(_) => {
      let acc_hit = accuracy.to_double() / 100.0
      let acc_miss = 1.0 - acc_hit
      let outs : Array[SideAttempt] = []
      match status {
        @model.Sleep(n) =>
          if n > 0 {
            outs.push({
              prob: 1.0,
              acts: false,
              action,
              post_status: @model.Sleep(n - 1),
            })
          } else {
            // Sleep(0): this turn is the wake-up; act normally afterward.
            if acc_hit > 0.0 {
              outs.push({
                prob: acc_hit,
                acts: true,
                action,
                post_status: @model.None,
              })
            }
            if acc_miss > 0.0 {
              outs.push({
                prob: acc_miss,
                acts: false,
                action,
                post_status: @model.None,
              })
            }
          }
        @model.Paralyze => {
          outs.push({
            prob: PARALYZE_SKIP_RATE,
            acts: false,
            action,
            post_status: @model.Paralyze,
          })
          let non_para = 1.0 - PARALYZE_SKIP_RATE
          if acc_hit > 0.0 {
            outs.push({
              prob: non_para * acc_hit,
              acts: true,
              action,
              post_status: @model.Paralyze,
            })
          }
          if acc_miss > 0.0 {
            outs.push({
              prob: non_para * acc_miss,
              acts: false,
              action,
              post_status: @model.Paralyze,
            })
          }
        }
        _ => {
          if acc_hit > 0.0 {
            outs.push({ prob: acc_hit, acts: true, action, post_status: status })
          }
          if acc_miss > 0.0 {
            outs.push({
              prob: acc_miss,
              acts: false,
              action,
              post_status: status,
            })
          }
        }
      }
      outs
    }
  }
}

///|
/// Badpoison counter denominator cap. Toxic deals `min(counter+1, TOXIC_MAX)/16`
/// of max HP per EOT tick. The gen-accurate cap is 15/16 (counter saturates
/// at 15); mirrored here so the state space stays bounded.
pub const TOXIC_MAX_TICKS : Int = 15

///|
/// Return `true` when `field` prevents a status of `kind` from being applied
/// to a **grounded** Pokemon. The grounded check itself is the caller's
/// responsibility (it needs the post-mega type/ability/item) — this helper
/// only encodes the field → status-kind truth table:
///
///   - ミストフィールド (Misty): blocks every status the model carries
///     (まひ / やけど / どく / もうどく / ねむり / あくび予告) — mainline
///     「状態異常にならない」.
///   - エレキフィールド (Electric): blocks sleep only — direct ねむり
///     (SleepKind) と あくび の予告 (DrowsyKind)。他の状態異常は通常通り入る。
///   - Grassy / Psychic / None: no status block.
///
/// Shared SSoT for the DP status fanout (`maybe_apply_status_fanout`), the DP
/// Rest path (`apply_healing`), and the MC status roll (`mc_try_apply_status`)
/// so terrain semantics stay identical across the two value paths.
pub fn field_blocks_status(
  field : @model.Field,
  kind : @model.StatusKind,
) -> Bool {
  match field {
    @model.Field::Misty => true
    @model.Field::Electric =>
      match kind {
        SleepKind | DrowsyKind => true
        _ => false
      }
    _ => false
  }
}

///|
/// Produce probabilistic next-state outcomes for a status-effect fan-out.
/// Given `state_after_dmg` (already updated for damage and stat boosts) plus
/// the attacking `move` and the target slot, returns either a single 1.0
/// outcome (no status applied — move has no effect, target is fainted /
/// already statused / type immune, or chance is 0) or two outcomes
/// `[(1-p, no_status), (p, with_status)]`.
///
/// `target_is_me = true` means the status would land on `state.my_status`
/// (i.e., the opponent used the move). `target_slot` is the slot receiving
/// the status, which is usually the active but may be a switched-in slot.
pub fn maybe_apply_status_fanout(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  target_team : Array[Combatant],
  mv : @model.Move,
  hits_count~ : Int = 1,
) -> Array[(Double, SwitchingGameState)] {
  let eff = match mv.status_effect {
    None => return [(1.0, state)]
    Some(x) => x
  }
  let (kind, chance) = eff
  if chance <= 0 {
    return [(1.0, state)]
  }
  let target_hps = if target_is_me { state.my_hps } else { state.opp_hps }
  if target_hps[target_slot] <= 0 {
    return [(1.0, state)]
  }
  let target_status = if target_is_me { state.my_status } else { state.opp_status }
  let cur = target_status[target_slot]
  if cur != @model.None {
    return [(1.0, state)]
  }
  let combatant = target_team[target_slot]
  if @model.immune_to_status(
    kind, combatant.pokemon.type1, combatant.pokemon.type2,
  ) {
    return [(1.0, state)]
  }
  // Stage G-2 / H: terrain blocks status infliction on grounded defenders.
  // ミストフィールド は major status (まひ / やけど / どく / もうどく / ねむり /
  // こおり) + confusion (こんらん) を全て阻止 (Misty Surge の「状態異常に
  // ならない」)。エレキフィールド は grounded を眠らせない効果しか持たないため
  // ねむり (SleepKind) と あくび予告 (DrowsyKind) のみ阻止する。どの field ×
  // kind が阻止対象かは `field_blocks_status` に集約 (DP / MC 共通 SSoT)。Gen9
  // mainline 仕様。
  //
  // Mega 後の type/ability/item を反映するため `effective_combatant` 経由で
  // grounded 判定する (Mega Gengar はメガ後にふゆうが消えて grounded になる等)。
  // grounded SSoT は `@damage.is_grounded` (Stage F-1)。
  // `target_megaed` は target_is_me に応じて my_megaed / opp_megaed を選ぶ。
  if field_blocks_status(state.field, kind) {
    let target_megaed = if target_is_me {
      state.my_megaed
    } else {
      state.opp_megaed
    }
    let is_mega = target_slot < target_megaed.length() &&
      target_megaed[target_slot]
    let eff = effective_combatant(combatant, is_mega)
    if @damage.is_grounded(
        type1=eff.pokemon.type1,
        type2=eff.pokemon.type2,
        ability=eff.ability,
        item=eff.item,
      ) {
      return [(1.0, state)]
    }
  }
  // #91 Phase 2-C: per-hit independent secondary roll. p_per_hit = chance/100,
  // p_set after `hits_count` hits = 1 - (1 - p_per_hit)^hits_count. hits_count
  // defaults to 1 to preserve legacy single-hit semantics for callers that
  // have not yet been migrated to pass the variant-specific count.
  let p_per_hit = chance.to_double() / 100.0
  let n = if hits_count < 1 { 1 } else { hits_count }
  let mut q = 1.0
  for _i = 0; _i < n; _i = _i + 1 {
    q = q * (1.0 - p_per_hit)
  }
  let p = 1.0 - q
  if p >= 1.0 {
    return [(1.0, with_status_set(state, target_is_me, target_slot, kind))]
  }
  if p <= 0.0 {
    return [(1.0, state)]
  }
  [
    (1.0 - p, state),
    (p, with_status_set(state, target_is_me, target_slot, kind)),
  ]
}

///|
/// Contact-proc chance node (#93 / P4): when the attacker hits the
/// defender with a contact move, the defender's ability or held item
/// can inflict a status on the attacker. Mirrors the
/// `maybe_apply_status_fanout` shape so `compose_fanouts` can append
/// it as another `Array[(prob, state)]` step.
///
/// MVP scope:
///   - abilities: ほのおのからだ / せいでんき / どくしゅ / ほうし
///     (status procs at 30%, see `damage.contact_proc_ability`)
///   - items: とびだすハバネロ / とびだすなかみ (100% procs)
///   - recoil-style abilities (てつのトゲ / さめはだ) are deterministic
///     HP shaves, modelled in damage application rather than as a
///     chance node, and stay out of this fanout.
///
/// `attacker_is_me` says which side just attacked; the inflicted
/// status lands on that side. `defender_team` is the side whose
/// ability / item triggers, `attacker_team` is consulted for type
/// immunity (electric immune to paralysis, fire immune to burn, etc).
///
/// 多段技 (#100): 各 contact 着弾は独立に判定し、1 hit 内では ability proc →
/// item proc の順に逐次解決する (Showdown / Gen9 仕様)。
/// q_a = 1 - viable_ability_chance/100、q_i = 1 - viable_item_chance/100、
/// 1 hit あたりの kind k 設定確率 p_set_k = a_k/100 + q_a × i_k/100。
/// hit_dist で q_total^n = (q_a × q_i)^n を畳んで終端 no-status 確率を求める。
/// ability + item を 1 つの categorical roll に flatten すると、せいでんき
/// (paralyze 30%) + とびだすハバネロ (burn 100%) のような異 kind 合算で
/// 30/130 vs 100/130 という、どちらの解決順でも再現できない不可能な分布が
/// 出る (合算 130% を 100 に cap してしまうため)。逐次モデルでは ability 先行
/// で 30% para + 70% burn が正しい。
/// シェルアームズ 物理モード等の動的 contact (force_contact) も damage engine
/// と同じ `resolve_stat_resolution` 経由で判定する。
/// 加えて mega 後の ability/stats を反映する: `effective_combatant` を
/// 通すことで Mega Kangaskhan の おやこあい (Parental Bond で 2-hit 化) や
/// Mega Heracross の スキルリンク (Random2to5 → 5-hit) が contact proc 計算
/// にも乗る。
pub fn apply_contact_proc_fanout(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_slot : Int,
  defender_slot : Int,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
  hits_count~ : Int? = None,
) -> Array[(Double, SwitchingGameState)] {
  // mega 後の ability/stats を damage 計算側と同じ経路で解決する。
  // raw team の ability を読むと Mega Kangaskhan の おやこあい や
  // Mega Heracross の スキルリンク が反映されず、hit 分布が damage と
  // ズレてしまう。
  let atk_megaed = if attacker_is_me {
    state.my_megaed[attacker_slot]
  } else {
    state.opp_megaed[attacker_slot]
  }
  let def_megaed = if attacker_is_me {
    state.opp_megaed[defender_slot]
  } else {
    state.my_megaed[defender_slot]
  }
  let attacker = effective_combatant(attacker_team[attacker_slot], atk_megaed)
  let defender = effective_combatant(defender_team[defender_slot], def_megaed)
  // 動的 contact (シェルアームズ) を engine と同じ判定で解決する。
  let sr = @damage.resolve_stat_resolution(
    mv,
    atk_atk=attacker.pokemon.atk,
    atk_spa=attacker.pokemon.spa,
    def_def=defender.pokemon.def_,
    def_spd=defender.pokemon.spd,
    atk_ability=attacker.ability,
    def_ability=defender.ability,
    critical=false,
  )
  if !(@damage.resolve_move_contact(mv, sr.force_contact)) {
    return [(1.0, state)]
  }
  // move 自体が連結しないケース (type immunity / ability immunity) は
  // contact proc を起こさない。Showdown / Gen9 では「damage が解決された hit」
  // のみが contact proc trigger になるため、たいあたり (ノーマル) を ほのおの
  // からだ 持ちゴーストに当てても やけど branch を生んではならない。damage
  // engine 側の immunity 判定 (engine.mbt の check_def_immunity / 18x18 type
  // chart) と同じ条件をここでも踏み、payoff が虚偽の status branch で揺れる
  // のを防ぐ。
  // 動的タイプ書き換え (フェアリースキン等の Skin / Weather Ball) を engine と
  // 同じ経路で解決する。raw `mv.type_` で immunity を判定すると、たとえば
  // フェアリースキン + たいあたり (raw Normal, effective Fairy) を ゴースト
  // 防御に当てたとき engine は damage を解決するのに fanout 側だけ Normal × Ghost
  // で immune 扱いし burn branch を落としてしまう。逆に エレキスキン contact 技 →
  // ひらいしん 防御は engine が ability immunity で 0 ダメージを返すのに、raw
  // Normal では check_def_immunity が false を返すため、虚偽の proc branch が
  // 出る。payoff の weather は build_input_with_ranks と同じく None 固定。
  let resolved_move_type = @damage.resolve_effective_move_type(
    mv, @model.Weather::None, attacker.ability,
  )
  if @damage.check_def_immunity(defender.ability, resolved_move_type) {
    return [(1.0, state)]
  }
  match @types.type_from_jp(resolved_move_type) {
    Some(at) =>
      match @types.type_from_jp(defender.pokemon.type1) {
        Some(d1) => {
          let e1 = @types.get_effectiveness_x4(at, d1)
          let e2 = if defender.pokemon.type2.length() > 0 {
            match @types.type_from_jp(defender.pokemon.type2) {
              Some(d2) => @types.get_effectiveness_x4(at, d2)
              None => 4
            }
          } else {
            4
          }
          if e1 == 0 || e2 == 0 {
            return [(1.0, state)]
          }
        }
        None => ()
      }
    None => ()
  }
  // 各 hit 内で defender の ability proc → item proc の順に独立判定する
  // (Showdown / Gen9 仕様)。両者を一つの categorical roll に畳むと
  // mathematically invalid: せいでんき (paralyze 30%) + とびだすハバネロ
  // (burn 100%) では能力先行で 30% para + 70% burn になるが、合算 130%
  // モデルでは 30/130 vs 100/130 が出てしまい、どの順でも再現できない。
  // q_a = 1 - viable_ability_chance/100、q_i = 1 - viable_item_chance/100。
  // 1 hit あたりの kind k 設定確率 = a_k/100 + q_a × i_k/100。
  let ability_procs = @damage.contact_proc_ability(defender.ability)
  let item_procs = @damage.contact_proc_item(defender.item)
  if ability_procs.length() == 0 && item_procs.length() == 0 {
    return [(1.0, state)]
  }
  let attacker_hps = if attacker_is_me { state.my_hps } else { state.opp_hps }
  if attacker_hps[attacker_slot] <= 0 {
    return [(1.0, state)]
  }
  let attacker_status = if attacker_is_me {
    state.my_status
  } else {
    state.opp_status
  }
  if attacker_status[attacker_slot] != @model.None {
    return [(1.0, state)]
  }
  // viable proc のみ採用 (タイプ耐性で fizzle した proc は status を残さない
  // ので q への寄与もしない)。
  let viable_ability : Array[(@model.StatusKind, Int)] = []
  let mut viable_ability_chance = 0
  for i = 0; i < ability_procs.length(); i = i + 1 {
    let (kind, chance) = ability_procs[i]
    if chance <= 0 {
      continue
    }
    if @model.immune_to_status(
      kind, attacker.pokemon.type1, attacker.pokemon.type2,
    ) {
      continue
    }
    viable_ability_chance = viable_ability_chance + chance
    viable_ability.push((kind, chance))
  }
  let viable_item : Array[(@model.StatusKind, Int)] = []
  let mut viable_item_chance = 0
  for i = 0; i < item_procs.length(); i = i + 1 {
    let (kind, chance) = item_procs[i]
    if chance <= 0 {
      continue
    }
    if @model.immune_to_status(
      kind, attacker.pokemon.type1, attacker.pokemon.type2,
    ) {
      continue
    }
    viable_item_chance = viable_item_chance + chance
    viable_item.push((kind, chance))
  }
  if viable_ability.length() == 0 && viable_item.length() == 0 {
    return [(1.0, state)]
  }
  // 各 source は単発の roll なので 100% に cap。current data では既に <=100 だが、
  // 将来データ拡張 (proc 同士の合算や cap 越え item 追加) で破綻しないよう保険。
  let cap_a = if viable_ability_chance > 100 { 100 } else { viable_ability_chance }
  let cap_i = if viable_item_chance > 100 { 100 } else { viable_item_chance }
  let q_a = 1.0 - cap_a.to_double() / 100.0
  let q_i = 1.0 - cap_i.to_double() / 100.0
  let q_total = q_a * q_i
  // kind ごとの per-hit 設定確率 = a_k/100 + q_a × i_k/100。
  // ability エントリを先に積んでから item エントリを順次合流させ、ability 側の
  // 既存 kind には q_a × i_k を加算、新規 kind は q_a × i_k で push。
  // 同じ kind を持つ ability + item (せいでんき + とびだすなかみ) はここで
  // 1 エントリに畳まれ、leaf 数増を防ぐ。
  let combined : Array[(@model.StatusKind, Double)] = []
  for i = 0; i < viable_ability.length(); i = i + 1 {
    let (kind, chance) = viable_ability[i]
    combined.push((kind, chance.to_double() / 100.0))
  }
  for i = 0; i < viable_item.length(); i = i + 1 {
    let (kind, chance) = viable_item[i]
    let item_contrib = q_a * chance.to_double() / 100.0
    let mut merged = false
    for j = 0; j < combined.length(); j = j + 1 {
      let (kind_j, set_j) = combined[j]
      if kind_j == kind {
        combined[j] = (kind_j, set_j + item_contrib)
        merged = true
        break
      }
    }
    if !(merged) {
      combined.push((kind, item_contrib))
    }
  }
  // #91 Phase 2-C: variant-specific hits_count を caller が渡してくれば、
  // q_total^hits_count を直接適用する (compose_fanouts が既に variants ごとに
  // この関数を呼ぶので fanout 側で hit 分布を fold するのは二重カウントになる
  // — codex Critical 2)。caller が None を渡したらレガシー経路として
  // resolve_hit_distribution で fold する (旧 callsite との後方互換)。
  let expected_no_status = match hits_count {
    Some(n) => {
      let nn = if n < 0 { 0 } else { n }
      let mut qn = 1.0
      for _k = 0; _k < nn; _k = _k + 1 {
        qn = qn * q_total
      }
      qn
    }
    None => {
      let hit_dist = @damage.resolve_hit_distribution(mv, attacker.ability)
      let mut acc = 0.0
      for i = 0; i < hit_dist.length(); i = i + 1 {
        let (n, prob) = hit_dist[i]
        let mut qn = 1.0
        for _k = 0; _k < n; _k = _k + 1 {
          qn = qn * q_total
        }
        acc = acc + prob * qn
      }
      acc
    }
  }
  let p_set = 1.0 - expected_no_status
  if p_set <= 1.0e-12 {
    return [(1.0, state)]
  }
  // 100% proc 確定 (per-hit q_total = 0 で 1 hit 以上) + 単一 viable kind なら 1 leaf。
  if expected_no_status <= 1.0e-12 && combined.length() == 1 {
    let (kind, _) = combined[0]
    return [(1.0, with_status_set(state, attacker_is_me, attacker_slot, kind))]
  }
  // 各 kind の最終発火確率: p_set × per_hit_set_k / (1 - q_total)。
  // per_hit_set の合計は 1 - q_total に等しいので、これは「proc が起きた」
  // 条件下の kind 分布で按分しているのと同値 (Markov 終端分布)。
  let denom = 1.0 - q_total
  let outcomes : Array[(Double, SwitchingGameState)] = []
  outcomes.push((expected_no_status, state))
  for i = 0; i < combined.length(); i = i + 1 {
    let (kind, per_hit_set) = combined[i]
    let mass = p_set * per_hit_set / denom
    outcomes.push((
      mass,
      with_status_set(state, attacker_is_me, attacker_slot, kind),
    ))
  }
  outcomes
}

///|
/// Resist-berry consumption tracker (#97 / P5). The engine's damage path
/// (`damage/engine.mbt`) already applies the berry's 1/2 power_mod on
/// super-effective hits when the defender's `item` is set, so this
/// fanout does **not** alter HP. It only flips
/// `(my|opp)_item_consumed[slot]` to `true` so the next attack on the
/// same defender stops being halved.
///
/// Wiring `item_consumed` into the engine call (so it sees `item = ""`
/// once the berry is consumed) lives in `damage_utils` (T7); until that
/// lands, the consumption flag is set here but the engine still re-applies
/// the resist berry on the second hit. Tests assert the flag transition;
/// the second-hit double-halving bug is tracked as a P5 follow-up.
///
/// Trigger conditions:
///   - defender's item is a resist berry (`get_resist_berry_type`)
///   - move type matches the berry's resisted type
///   - move is super-effective on the defender's typing
///   - `(my|opp)_item_consumed[slot]` is `false`
///   - the visible delta `pre_dmg_hp - post_hp` is positive (i.e. damage
///     was actually dealt)
///
/// Single-leaf fanout (probability 1.0).
///
/// Mirror the engine's move-type resolution chain (`resolve_move_type_override`
/// + `get_skin_type`) to the extent payoff cares about. Payoff is weatherless,
/// so Weather Ball never rewrites here; Skin abilities still need to be
/// applied because they fire on the attacker independent of weather, and the
/// engine's resist-berry branch keys off the post-Skin type.
fn resolve_engine_move_type(mv : @model.Move, atk_ability : String) -> String {
  let (skin_type, _) = @damage.get_skin_type(atk_ability, mv.type_)
  skin_type
}

///|
pub fn apply_item_pre_damage_proc_fanout(
  state : SwitchingGameState,
  defender_is_me : Bool,
  defender_slot : Int,
  defender_team : Array[Combatant],
  attacker_team : Array[Combatant],
  pre_dmg_hp : Int,
  mv : @model.Move,
  hits_count~ : Int = 1,
) -> Array[(Double, SwitchingGameState)] {
  // #91 Phase 2-C: hits_count 引数は将来の per-hit item proc 拡張用。現状は
  // 1 hit しか反映しない resist berry / item consumption ロジックなので、
  // hits_count 引数を受け取るだけで内部処理は不変 (single-shot consumption)。
  let _ = hits_count
  // Defensive: legacy test fixtures sometimes size *_item_consumed shorter
  // than the corresponding team. Treat out-of-bounds slots as "no berry
  // wired up at this index" — equivalent to a fresh, unconsumed state.
  let consumed_arr = if defender_is_me {
    state.my_item_consumed
  } else {
    state.opp_item_consumed
  }
  if defender_slot >= consumed_arr.length() {
    return [(1.0, state)]
  }
  let consumed = consumed_arr[defender_slot]
  if consumed {
    return [(1.0, state)]
  }
  // Resolve mega-aware combatants so post-mega ability/type/stats flow into
  // berry consumption (#101). Without this, Mega Gardevoir / Mega Pinsir's
  // フェアリースキン (Normal → Fairy rewrite) would halve damage in the
  // engine but leave item_consumed unflipped here, so future hits keep
  // getting halved. defender.pokemon.type1/type2 also moves to post-mega
  // for the super-effective check.
  let def_megaed = if defender_is_me {
    state.my_megaed[defender_slot]
  } else {
    state.opp_megaed[defender_slot]
  }
  let defender = effective_combatant(
    defender_team[defender_slot], def_megaed,
  )
  let berry_type = @damage.get_resist_berry_type(defender.item)
  if berry_type.length() == 0 {
    return [(1.0, state)]
  }
  let attacker_active = if defender_is_me {
    state.opp_active
  } else {
    state.my_active
  }
  let atk_megaed = if defender_is_me {
    state.opp_megaed[attacker_active]
  } else {
    state.my_megaed[attacker_active]
  }
  let attacker = effective_combatant(
    attacker_team[attacker_active], atk_megaed,
  )
  let resolved_type = resolve_engine_move_type(mv, attacker.ability)
  if resolved_type != berry_type {
    return [(1.0, state)]
  }
  // ホズのみ triggers on any Normal-type hit (including neutral); other
  // resist berries trigger only on super-effective hits. Mirrors the engine
  // gate in `damage/engine.mbt`'s resist-berry block.
  let triggers_on_neutral = defender.item == "ホズのみ"
  if !(triggers_on_neutral) &&
    !(
      @damage.is_super_effective(
        resolved_type, defender.pokemon.type1, defender.pokemon.type2,
      ),
    ) {
    return [(1.0, state)]
  }
  let post_hp = if defender_is_me {
    state.my_hps[defender_slot]
  } else {
    state.opp_hps[defender_slot]
  }
  let dealt = pre_dmg_hp - post_hp
  if dealt <= 0 {
    return [(1.0, state)]
  }
  // Mark consumed; HP is left at the engine-halved value already in `state`.
  [
    (
      1.0,
      with_hp_and_item_consumed(state, defender_is_me, defender_slot, post_hp),
    ),
  ]
}

///|
/// Post-damage held-item chance node (#97 / P5). Handles items that fire
/// *after* damage has been resolved on the defender's HP:
///
/// - **きあいのタスキ** (`consume_on_hit`): if the defender entered the
///   hit at full HP and the hit would have left HP <= 0, the sash is
///   consumed and HP is set to 1.
/// - **フィラのみ** (`hp_threshold`): if the defender's post-hit HP is
///   above 0 and at or below `max_hp / 2`, restore `max_hp / 3` (capped
///   at `max_hp`) and consume the berry. Healing berries do not revive
///   a fainted holder.
///
/// `pre_dmg_hp` is the defender's HP just before damage was applied at
/// this attack site — the call sites of `compose_fanouts` capture it.
/// `mv` is reserved for future move-class gating (e.g. `しおふき` should
/// not trigger Cell Battery despite being water-type).
///
/// Single-leaf fanout (probability 1.0).
///
/// `attacker_team` is consulted for the attacker's ability so the multi-hit
/// detection picks up Parental Bond / Skill Link. きあいのタスキ is gated
/// out of multi-hit attacks because the aggregate (pre, post) HP pair sees
/// only the cumulative damage — saving the defender at 1 HP from a multi-hit
/// KO would be mechanically wrong (Sash should only stop the first hit, and
/// later hits should still KO).
pub fn apply_item_post_damage_proc_fanout(
  state : SwitchingGameState,
  defender_is_me : Bool,
  defender_slot : Int,
  defender_team : Array[Combatant],
  attacker_team : Array[Combatant],
  pre_dmg_hp : Int,
  mv : @model.Move,
  hits_count~ : Int = 1,
) -> Array[(Double, SwitchingGameState)] {
  // #91 Phase 2-C: hits_count 引数は将来の per-hit item proc 拡張用。現状は
  // single-shot consumption ロジックのみで内部不変。
  let _ = hits_count
  // Defensive: see apply_item_pre_damage_proc_fanout for rationale.
  let consumed_arr = if defender_is_me {
    state.my_item_consumed
  } else {
    state.opp_item_consumed
  }
  if defender_slot >= consumed_arr.length() {
    return [(1.0, state)]
  }
  let consumed = consumed_arr[defender_slot]
  if consumed {
    return [(1.0, state)]
  }
  // Mega-aware (#101): post-mega ability決まる multi-hit が Sash gating に
  // 効くようにする。Mega Kangaskhan (おやこあい) で raw ability="" のままだと
  // Single 扱いされ Sash が誤発動、aggregate KO で 1 HP 残してしまう。
  let def_megaed = if defender_is_me {
    state.my_megaed[defender_slot]
  } else {
    state.opp_megaed[defender_slot]
  }
  let defender = effective_combatant(
    defender_team[defender_slot], def_megaed,
  )
  let max_hp = defender.pokemon.hp
  let post_hp = if defender_is_me {
    state.my_hps[defender_slot]
  } else {
    state.opp_hps[defender_slot]
  }
  if defender.item == "きあいのタスキ" &&
    pre_dmg_hp == max_hp &&
    post_hp <= 0 {
    let attacker_active = if defender_is_me {
      state.opp_active
    } else {
      state.my_active
    }
    let atk_megaed = if defender_is_me {
      state.opp_megaed[attacker_active]
    } else {
      state.my_megaed[attacker_active]
    }
    let attacker = effective_combatant(
      attacker_team[attacker_active], atk_megaed,
    )
    let hit_plan = @damage.resolve_hit_plan(
      mv, attacker.ability, @model.MultiHit::Auto,
    )
    let is_multi_hit = match hit_plan {
      @damage.HitPlan::Single => false
      _ => true
    }
    if !(is_multi_hit) {
      return [
        (
          1.0,
          with_hp_and_item_consumed(state, defender_is_me, defender_slot, 1),
        ),
      ]
    }
    // Multi-hit Sash needs hit-level damage threading to model the "save on
    // hit 1, KO on hit 2+" mechanic. Until that lands, leave the aggregate
    // KO untouched rather than incorrectly rescuing the defender.
  }
  // フィラのみ / オボンのみ requires the hit to *cross* the 1/2-HP threshold:
  // the holder must have been above max/2 going in and at-or-below max/2
  // coming out. Without the `pre_dmg_hp` check, an immune / 0-damage hit on
  // a holder already at low HP would heal+consume despite no damage having
  // occurred.
  //
  // 回復量はアイテム別:
  //   - フィラのみ (混乱実): max_hp / 3
  //   - オボンのみ (Sitrus Berry): max_hp / 4
  // 混乱実の "性格に合わない" 副作用 (confusion) はモデル外。
  let heal_denom = match defender.item {
    "フィラのみ" => Some(3)
    "オボンのみ" => Some(4)
    _ => None
  }
  match heal_denom {
    Some(denom) =>
      if post_hp > 0 && pre_dmg_hp * 2 > max_hp && post_hp * 2 <= max_hp {
        let heal = max_hp / denom
        let new_hp = post_hp + heal
        let capped = if new_hp > max_hp { max_hp } else { new_hp }
        return [
          (
            1.0,
            with_hp_and_item_consumed(state, defender_is_me, defender_slot, capped),
          ),
        ]
      }
    None => ()
  }
  [(1.0, state)]
}

///|
/// Copy `state`, write `hp` to the chosen side's `slot`, and mark that
/// slot's held item as consumed. Used by the P5 item-proc fanouts to
/// produce a single composite mutation per trigger.
fn with_hp_and_item_consumed(
  state : SwitchingGameState,
  side_is_me : Bool,
  slot : Int,
  hp : Int,
) -> SwitchingGameState {
  let my_hps = state.my_hps.copy()
  let opp_hps = state.opp_hps.copy()
  let my_item_consumed = state.my_item_consumed.copy()
  let opp_item_consumed = state.opp_item_consumed.copy()
  if side_is_me {
    my_hps[slot] = hp
    my_item_consumed[slot] = true
  } else {
    opp_hps[slot] = hp
    opp_item_consumed[slot] = true
  }
  { ..state, my_hps, opp_hps, my_item_consumed, opp_item_consumed }
}

///|
/// Copy `state` and set `target_slot`'s status on the chosen side to the
/// freshly-inflicted `StatusCondition` for `kind` (via `inflict_status`).
fn with_status_set(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  kind : @model.StatusKind,
) -> SwitchingGameState {
  let new_cond = @model.inflict_status(kind)
  let my_status = if target_is_me {
    override_active_status(state.my_status, target_slot, new_cond)
  } else {
    state.my_status.copy()
  }
  let opp_status = if target_is_me {
    state.opp_status.copy()
  } else {
    override_active_status(state.opp_status, target_slot, new_cond)
  }
  {
    my_active: state.my_active,
    opp_active: state.opp_active,
    my_hps: state.my_hps.copy(),
    opp_hps: state.opp_hps.copy(),
    my_ranks: state.my_ranks.copy(),
    opp_ranks: state.opp_ranks.copy(),
    my_mega_used: state.my_mega_used,
    opp_mega_used: state.opp_mega_used,
    my_megaed: state.my_megaed.copy(),
    opp_megaed: state.opp_megaed.copy(),
    my_status,
    opp_status,
    my_must_recharge: state.my_must_recharge.copy(),
    opp_must_recharge: state.opp_must_recharge.copy(),
    my_item_consumed: state.my_item_consumed.copy(),
    opp_item_consumed: state.opp_item_consumed.copy(),
    my_moves_used: state.my_moves_used.copy(),
    opp_moves_used: state.opp_moves_used.copy(),
    weather: state.weather,
    weather_turns_left: state.weather_turns_left,
    my_leech_seeded: state.my_leech_seeded.copy(),
    opp_leech_seeded: state.opp_leech_seeded.copy(),
    my_wish_turns: state.my_wish_turns,
    opp_wish_turns: state.opp_wish_turns,
    field: state.field,
    field_turns_left: state.field_turns_left,
    turn: state.turn,
  }
}

///|
/// Apply one end-of-turn slip / counter update for the given active slot.
/// Returns `(new_hp, new_status)`. HP never falls below 0 from slip damage.
/// - Burn / Poison: subtract max_hp / 16 or max_hp / 8 respectively.
/// - BadPoison(n): subtract max_hp * min(n+1, TOXIC_MAX_TICKS) / 16 and
///   advance to BadPoison(min(n+1, TOXIC_MAX_TICKS)).
/// - Sleep / Paralyze / None: no-op.
pub fn eot_slip_active(
  current_hp : Int,
  max_hp : Int,
  status : @model.StatusCondition,
) -> (Int, @model.StatusCondition) {
  if current_hp <= 0 {
    return (current_hp, status)
  }
  match status {
    @model.Burn => {
      let dmg = max_hp / 16
      (clamp_zero(current_hp - dmg), status)
    }
    @model.Poison => {
      let dmg = max_hp / 8
      (clamp_zero(current_hp - dmg), status)
    }
    @model.BadPoison(n) => {
      let ticks = if n + 1 > TOXIC_MAX_TICKS { TOXIC_MAX_TICKS } else { n + 1 }
      let dmg = max_hp * ticks / 16
      (clamp_zero(current_hp - dmg), @model.BadPoison(ticks))
    }
    @model.Drowsy(n) => {
      // n>0: まだ猶予あり、カウンタを 1 減らす。n==0: ここでねむり発動。
      if n > 0 {
        (current_hp, @model.Drowsy(n - 1))
      } else {
        (current_hp, @model.Sleep(2))
      }
    }
    _ => (current_hp, status)
  }
}

///|
/// たべのこし / くろいヘドロ 系の EOT 自動回復を 1 スロット分計算する。
/// 回復は max_hp / 16、HP 上限でキャップ。HP=0 (瀕死) と既に max のスロット
/// は no-op。
/// くろいヘドロ は持ち主の type が どく なら回復、それ以外なら max_hp / 8 の
/// ダメージだが、本実装では未対応 (たべのこし のみ)。
///
/// HP 加算と上限クランプ部分は `add_hp_capped` 共通ヘルパーに委譲し、
/// 段階 4 以降で追加される回復技 (`apply_healing` の FixedFraction 等) と
/// 同じ実装パスを通る。ひんし (HP <= 0) は EOT 自動回復としては起こらない
/// 既存契約を守るため、本関数側で `current_hp <= 0` 早期 return を維持
/// (helper 側は ひんしスロット を蘇生してしまうため、契約を helper に
/// 押し付けない)。`item` の判定も EOT 固有なのでここに残る。
pub fn eot_leftovers_heal(current_hp : Int, max_hp : Int, item : String) -> Int {
  if current_hp <= 0 {
    return current_hp
  }
  if item != "たべのこし" {
    return current_hp
  }
  // add_hp_capped 経由で「max 以上は no-op」「加算後 max クランプ」を共通化。
  // 単要素 buffer を立てて in-place mutation を return 値に取り出す。
  let buf = [current_hp]
  add_hp_capped(buf, 0, max_hp / 16, max_hp)
  buf[0]
}

///|
/// Apply end-of-turn slip damage, item heal, residual chip and counter ticks
/// to both actives of `state` on fresh copies; returns the updated state.
/// Only the active slot receives most EOT effects — bench Pokemon don't tick
/// outside of slot-scoped Wish. Called at the end of every turn resolution
/// in `attempt_turn_with_cache`.
///
/// Stage 12 (EOT 順序整理): tick blocks are arranged in the Gen9 mainline
/// "residual" order. Plan H-2 specifies the canonical sequence as:
///
///   1. 天候ダメ (Sand chip on non-はがね/いわ/じめん, non-immune ability)
///   2. アイテム回復 (たべのこし)
///   3. やどりぎのタネ tick
///   4. 状態異常スリップ (Burn / Poison / BadPoison / Drowsy → Sleep)
///   5. ねがいごと tick+activate (atomic single block; see "Wish timing
///      contract" below)
///   6. 天候カウンタ tick (decrement / reset to None)
///   7. sleep カウンタ tick — handled in attempt_turn_with_cache, out of scope
///
/// Wish timing contract (SSoT — referenced from the wish_turns docstring on
/// SwitchingGameState):
///   - On use during turn T's action phase, `with_post_hit_effects` sets
///     `wish_turns = 2`. `transition_with_cache` then bumps `state.turn` to
///     T+1 and `attempt_turn_with_cache` invokes this `apply_eot`.
///   - This EOT (T+1 in `state.turn` terms but conceptually "EOT of turn T"
///     in narrative terms) ticks `2 → 1`. No heal yet.
///   - The next turn's EOT ticks `1 → 0` and atomically fires the heal at
///     the same step (single block; see step 5 below). This matches
///     Bulbapedia's Gen5+ "at the end of the next turn" wording: Wish used
///     on turn T heals at end-of-turn(T+1).
///   - The two-step (tick, then check) ordering inside the wish block is
///     atomic — set=2 with tick-then-check is the only way to fire at
///     end-of-turn(T+1). Splitting tick and activate into separate EOT
///     steps would require set=1 to keep the same fire turn, and breaking
///     the atomic block in a future refactor needs the set value to flip
///     to 1 accordingly. The end-to-end test through `attempt_turn_with_
///     cache` (see `Wish real-path` test in switching_game_healing_wbtest)
///     locks this contract independent of internal step ordering.
///
/// Order changes vs Stage 11 (pre-refactor) and the observable consequences:
///
/// * **Sand chip is new** (step 1). Any non-immune Pokemon now loses max/16 HP
///   under Sand weather before any item heal or status slip is applied. This
///   can cause an Pokemon that previously survived (Sand + leftovers neutral
///   shape) to faint at EOT if HP <= max/16 entering the EOT under Sand.
/// * **Leech tick moved from after status slip to before status slip**
///   (positions 3 ↔ 4). Burn / Poison damage no longer "front-runs" Leech
///   Seed when both apply on the same EOT. The two ticks are still
///   independent slot accesses, but if Leech reduces HP to 0 first, the
///   status slip falls into the `current_hp <= 0` early-return in
///   `eot_slip_active` and contributes zero further damage. (Pre-refactor
///   status would chip first and Leech would skip on the corpse.) Both
///   orderings have the same "death" outcome but the recovered HP on the
///   opposing seed source differs: the new order always banks max/8 to the
///   seed source before status considers fainting.
/// * **Wish activation no longer races against status slip** — it now fires
///   after status slip, matching Plan H-2 step 5. Effect on a turn where the
///   wish receiver enters EOT at HP=max/16 with Burn: pre-refactor Wish
///   tick+heal happened after status, observable as +max/2 then -max/16. The
///   new order preserves this (status before Wish), so this case is
///   regression-safe.
pub fn apply_eot(
  state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> SwitchingGameState {
  let my_hps = state.my_hps.copy()
  let opp_hps = state.opp_hps.copy()
  let my_status = state.my_status.copy()
  let opp_status = state.opp_status.copy()
  let my_max = effective_hp(my_team[state.my_active])
  let opp_max = effective_hp(opp_team[state.opp_active])

  // === Step 1: 天候ダメ (Sand chip) ===
  // Gen9 Sand deals max/16 chip damage at EOT to every active Pokemon that is
  // not はがね / いわ / じめん and whose ability does not block it (Magic
  // Guard / すなかき / すながくれ / すなのちから / ぼうじん). Type lookup
  // uses `effective_combatant` so the post-mega type pair is honoured —
  // an Aerodactyl that megas into Rock-typed form will not take Sand chip on
  // the same turn it megas (and pre-mega it was Rock anyway, so this is
  // mostly insurance). Other weathers (Rain / Sun / Snow / None) deal no
  // chip damage in Gen9 (Hail was retired in favour of Snow).
  apply_sand_damage_active(
    state.my_active, my_hps, my_team, state.my_megaed, my_max, state.weather,
  )
  apply_sand_damage_active(
    state.opp_active, opp_hps, opp_team, state.opp_megaed, opp_max,
    state.weather,
  )

  // === Step 2: アイテム回復 (たべのこし) ===
  // たべのこし は HP=0 (瀕死) では発動しないので Sand チップで KO されたあと
  // の同 EOT 内では heal が発火しない。これは Gen9 公式挙動とも一致 (item
  // heal は alive 判定を内部で持つ)。`eot_leftovers_heal` 側で current_hp<=0
  // 早期 return が掛かっており、helper の add_hp_capped 経路と契約が分離
  // されているため、Sand → leftovers の順序が間違いなく観測できる。
  let my_hp_after_heal = eot_leftovers_heal(
    my_hps[state.my_active], my_max, my_team[state.my_active].item,
  )
  let opp_hp_after_heal = eot_leftovers_heal(
    opp_hps[state.opp_active], opp_max, opp_team[state.opp_active].item,
  )
  my_hps[state.my_active] = my_hp_after_heal
  opp_hps[state.opp_active] = opp_hp_after_heal

  // === Step 2-bis: Grassy field heal (Stage G-1) ===
  // state.field == Grassy で active が grounded なら HP += max(1, max_hp/16)。
  // leftovers (step 2) の **後**、leech tick (step 3) の **前** に走る
  // (Gen9 mainline residual order)。max クランプは `add_hp_capped` が担当。
  // ひんし (HP <= 0) は heal 対象外 (本家挙動 — Grassy heal は alive 限定)。
  // grounded 判定は `@damage.is_grounded` の単一 SSoT を再利用し、mega 後の
  // type/ability/item を反映するため `effective_combatant` 経由で読む。
  apply_grassy_heal_active(
    state.my_active, my_hps, my_team, state.my_megaed, my_max, state.field,
  )
  apply_grassy_heal_active(
    state.opp_active, opp_hps, opp_team, state.opp_megaed, opp_max, state.field,
  )

  // === Step 3: やどりぎのタネ tick ===
  // 種付き側 (`*_leech_seeded[active] == true`) は HP -= max/8、相手 active
  // HP += 同量。種付き側 ability が マジックガード のとき tick は完全に
  // skip (seed 側 HP 不変、相手側加算も 0)。種付き側 HP <= 0 のスロットは
  // tick skip (faint 後の二度発火を抑止)。種付き側が tick で HP=0 になっても、
  // その同ターン分の吸収は相手に入る (ダメージ量は clamp 前の max/8 で計算)。
  // 両側同時に seeded の場合は my → opp の固定順序で逐次適用。中間状態を
  // 介して計算するため、加算側が満タンで cap に当たって失われるケースが
  // 起こり得る (mainline でも発生する自然な挙動)。
  //
  // Stage 12 配置: leftovers の **後** / 状態異常 slip の **前** へ移動。
  // pre-stage12 では status slip の後にあったため、Burn と seed が同時の
  // ターンに seed 側が status で先死 → leech skip という挙動だったが、
  // 新順序では leech tick が先になり、seed 側が max/8 削れた上で status が
  // 動く。両者ともに max/8 < HP <= max/16 の境界では「leech で死亡 → status
  // skip」が観測される (eot_slip_active が `current_hp <= 0` early return)。
  //
  // Defensive: legacy test fixtures may size leech_seeded shorter than the
  // team. Out-of-bounds is treated as "not seeded" and skips the tick.
  let my_seeded = state.my_active < state.my_leech_seeded.length() &&
    state.my_leech_seeded[state.my_active]
  if my_seeded && my_hps[state.my_active] > 0 {
    let attacker_blocks = ability_blocks_leech_seed(
      my_team[state.my_active].ability,
    )
    if !attacker_blocks {
      // 種付き側 HP が max/8 未満なら実際に吸えた分しか相手に渡らない (本家
      // 挙動: ドレイン同様 actual drained 量を基準にし、overkill 分を相手の
      // 回復に転用しない)。Issue #4: sub / add 両方で同じ `drained` 値を使う
      // ことで「HP が空から生まれる」(seed 側 HP < max/8 なのに相手が max/8
      // 加算する) 退化を構造的に防ぐ。`sub_hp_floor0` も内部で floor 0 する
      // ため不変だが、両側で同じ amount を渡す形を SSoT として明示する。
      //
      // ヘドロえき (Liquid Ooze) × Leech Seed (design note): Gen5+ mainline
      // では Liquid Ooze は「相手 (Liquid Ooze 持ち) から HP を吸収する効果」
      // をすべて反転させる — Drain 系技だけでなく Leech Seed の EOT 吸収にも
      // 適用される。これは Showdown が実装する競技標準挙動で、本家ゲーム内
      // テキストも同じ意味を持つ:
      //   pokedex.db `ability.json` "ヘドロえき" (Sun_Moon 以降):
      //     "ヘドロえき を すいとった あいて は きょうれつな あくしゅう で
      //      ダメージ を うけて HP を へらす"
      // すなわち Liquid Ooze 持ちから HP を「すいとった」側 (= Leech Seed の
      // 種を蒔いた seeder、または Drain 系の attacker) が damage を受ける。
      // 種付き側 (Liquid Ooze 持ち) の HP 減少は通常通り発生する。本実装は
      // この本家挙動に従い、tests Case L-8b / L-8c で観測値を pin する。
      let raw = my_max / 8
      let cur_hp = my_hps[state.my_active]
      let drained = if cur_hp < raw { cur_hp } else { raw }
      sub_hp_floor0(my_hps, state.my_active, drained)
      if ability_reverses_drain(my_team[state.my_active].ability) {
        sub_hp_floor0(opp_hps, state.opp_active, drained)
      } else {
        add_hp_capped(opp_hps, state.opp_active, drained, opp_max)
      }
    }
  }
  let opp_seeded = state.opp_active < state.opp_leech_seeded.length() &&
    state.opp_leech_seeded[state.opp_active]
  if opp_seeded && opp_hps[state.opp_active] > 0 {
    let defender_blocks = ability_blocks_leech_seed(
      opp_team[state.opp_active].ability,
    )
    if !defender_blocks {
      let raw = opp_max / 8
      let cur_hp = opp_hps[state.opp_active]
      let drained = if cur_hp < raw { cur_hp } else { raw }
      sub_hp_floor0(opp_hps, state.opp_active, drained)
      if ability_reverses_drain(opp_team[state.opp_active].ability) {
        sub_hp_floor0(my_hps, state.my_active, drained)
      } else {
        add_hp_capped(my_hps, state.my_active, drained, my_max)
      }
    }
  }

  // === Step 4: 状態異常 slip ===
  // Burn / Poison / BadPoison / Drowsy → Sleep の counter 遷移を含む。
  // `eot_slip_active` は HP<=0 で早期 return するので、Sand or Leech で HP=0
  // になったスロットは status slip を観測しない (= HP は不変、status counter
  // も不変)。これは mainline 挙動 (faint 後の status は燃え尽きない / Toxic
  // counter は death で凍結) と一致する。
  let (my_hp_new, my_st_new) = eot_slip_active(
    my_hps[state.my_active], my_max, my_status[state.my_active],
  )
  my_hps[state.my_active] = my_hp_new
  my_status[state.my_active] = my_st_new
  let (opp_hp_new, opp_st_new) = eot_slip_active(
    opp_hps[state.opp_active], opp_max, opp_status[state.opp_active],
  )
  opp_hps[state.opp_active] = opp_hp_new
  opp_status[state.opp_active] = opp_st_new

  // === Step 5: ねがいごと (Wish) tick + activate (atomic single block) ===
  // wish_turns は per-side の scalar (Int)。pkdx は single battle で各サイド
  // 常に 1 active のため、サイド毎に 1 値で表現する (= 長さ 1 の per-active-
  // slot 配列と観測上等価)。受け取りは「fire 時点の current active」が拾うため、
  // Wisher が Switch で控えに退いた後でも、交代先 active が回復する (mainline
  // Gen5+ "the replacement in that slot receives the Wish" と一致)。
  //
  //   `>0`  → -= 1 (tick)
  //   `==0` → 発動: 現在 active な slot の HP > 0 なら `add_hp_capped(hps,
  //           my_active, slot_max/2, slot_max)` で回復、HP=0 なら不変。
  //           発動の有無に関わらず -1 に idle 化 (Wish 自体は消費される)。
  //   `<0`  → idle 状態、不変 (fixpoint)。
  //
  // タイミング契約 (SSoT は SwitchingGameState の wish_turns docstring):
  // 使用ターン T の action phase で set=2 → 同 turn の EOT (tick: 2→1) →
  // 次 turn の EOT (tick: 1→0 → 発動) で発火。これは Bulbapedia Gen5+ の
  // "at the end of the next turn" に一致。end-to-end 契約 (turn-relative
  // タイミング) は `attempt_turn_with_cache` 経由の real-path 回帰テストで
  // pin する (switching_game_healing_wbtest の Wish real-path セクション
  // 参照)。
  let mut my_wish_turns_new = state.my_wish_turns
  if my_wish_turns_new > 0 {
    my_wish_turns_new = my_wish_turns_new - 1
  }
  if my_wish_turns_new == 0 {
    let active = state.my_active
    if active >= 0 && active < my_hps.length() && my_hps[active] > 0 {
      let slot_max = effective_hp(my_team[active])
      add_hp_capped(my_hps, active, slot_max / 2, slot_max)
    }
    my_wish_turns_new = -1
  }
  let mut opp_wish_turns_new = state.opp_wish_turns
  if opp_wish_turns_new > 0 {
    opp_wish_turns_new = opp_wish_turns_new - 1
  }
  if opp_wish_turns_new == 0 {
    let active = state.opp_active
    if active >= 0 && active < opp_hps.length() && opp_hps[active] > 0 {
      let slot_max = effective_hp(opp_team[active])
      add_hp_capped(opp_hps, active, slot_max / 2, slot_max)
    }
    opp_wish_turns_new = -1
  }

  // === Step 6: 天候カウンタ tick ===
  // `weather_turns_left > 0` ならデクリメント、`0` になった瞬間に
  // `Weather::None` へリセット。`weather == None` 状態では既に `turns_left=0`
  // が保たれているので no-op (fixpoint)。step 1 の Sand チップは tick 前の
  // state.weather を参照しているため、「カウンタが 0 になる EOT」も Sand
  // チップは入る (= 切れる前の "最後の Sand チップ" が成立する)。これは
  // 本家挙動と一致 (天候は EOT の最後にカウントが終了する)。
  let (next_weather, next_weather_turns) = if state.weather_turns_left > 0 {
    let dec = state.weather_turns_left - 1
    if dec <= 0 {
      (@model.Weather::None, 0)
    } else {
      (state.weather, dec)
    }
  } else {
    (state.weather, 0)
  }

  // === Step 7: フィールド (terrain) カウンタ tick ===
  // 天候 tick と完全対称: `field_turns_left > 0` ならデクリメント、`0` に
  // なった瞬間に `Field::None` へリセット。`field == None` 状態では既に
  // `turns_left=0` が保たれているので no-op (fixpoint)。Stage F / G で field
  // 連動の damage 倍率 / 回復 / status block 等を実装した際は、それらは tick
  // **前** の state.field を参照する (= weather と同じ「切れる前の最後の
  // 効果」が成立する)。Showdown の仕様では EOT は weather → field の順に
  // tick されるため、本実装もその順で書く (field は weather の後)。
  let (next_field, next_field_turns) = if state.field_turns_left > 0 {
    let dec = state.field_turns_left - 1
    if dec <= 0 {
      (@model.Field::None, 0)
    } else {
      (state.field, dec)
    }
  } else {
    (state.field, 0)
  }
  {
    my_active: state.my_active,
    opp_active: state.opp_active,
    my_hps,
    opp_hps,
    my_ranks: state.my_ranks.copy(),
    opp_ranks: state.opp_ranks.copy(),
    my_mega_used: state.my_mega_used,
    opp_mega_used: state.opp_mega_used,
    my_megaed: state.my_megaed.copy(),
    opp_megaed: state.opp_megaed.copy(),
    my_status,
    opp_status,
    my_must_recharge: state.my_must_recharge.copy(),
    opp_must_recharge: state.opp_must_recharge.copy(),
    my_item_consumed: state.my_item_consumed.copy(),
    opp_item_consumed: state.opp_item_consumed.copy(),
    my_moves_used: state.my_moves_used.copy(),
    opp_moves_used: state.opp_moves_used.copy(),
    weather: next_weather,
    weather_turns_left: next_weather_turns,
    my_leech_seeded: state.my_leech_seeded.copy(),
    opp_leech_seeded: state.opp_leech_seeded.copy(),
    my_wish_turns: my_wish_turns_new,
    opp_wish_turns: opp_wish_turns_new,
    // Stage E: field counter tick — `next_field` / `next_field_turns` は
    // step 7 で計算済み (weather tick と対称構造)。Stage F / G で field
    // 連動効果 (damage 倍率 / 回復 / status block 等) を実装する際は、
    // tick **前** の `state.field` を参照すること (= weather と同じ "切れる
    // 前の最後の効果" を成立させる)。
    field: next_field,
    field_turns_left: next_field_turns,
    turn: state.turn,
  }
}

///|
/// Step 2-bis of `apply_eot`. Apply Grassy field heal (max_hp / 16, capped at
/// max_hp) to the active slot when field is Grassy and the active Pokemon is
/// grounded. Mutates `hps[slot]` in place. The post-mega type/ability/item are
/// read via `effective_combatant` so a Pokemon mid-mega is evaluated against
/// its new grounded state (e.g. Mega Gengar — ふゆう vanishes post-mega).
/// HP=0 (fainted) slots are skipped (Grassy heal does not revive). Order
/// contract: this runs **after** `eot_leftovers_heal` and **before** leech
/// tick / status slip (Gen9 mainline residual order).
///
/// Grounded check delegates to `@damage.is_grounded` (Stage F-1 SSoT — single
/// source of truth for grounded semantics across damage and EOT paths).
pub fn apply_grassy_heal_active(
  active : Int,
  hps : Array[Int],
  team : Array[Combatant],
  megaed : Array[Bool],
  max_hp : Int,
  field : @model.Field,
) -> Unit {
  match field {
    @model.Field::Grassy => {
      if hps[active] <= 0 {
        return
      }
      let is_mega = active < megaed.length() && megaed[active]
      let eff = effective_combatant(team[active], is_mega)
      if !(@damage.is_grounded(
          type1=eff.pokemon.type1,
          type2=eff.pokemon.type2,
          ability=eff.ability,
          item=eff.item,
        )) {
        return
      }
      // max_hp / 16 を回復。整数除算で 0 になる low-max ケースは max(1, _) で
      // 最小 1 に持ち上げる (本家挙動: Grassy heal は alive 限定で常に
      // 「少なくとも 1 HP」を回復する)。
      let raw = max_hp / 16
      let amount = if raw < 1 { 1 } else { raw }
      add_hp_capped(hps, active, amount, max_hp)
    }
    _ => ()
  }
}

///|
/// Step 1 of `apply_eot`. Apply sandstorm chip damage (max_hp / 16, floor 0)
/// to the active slot when weather is Sand and the active Pokemon is neither
/// type-immune (はがね / いわ / じめん) nor ability-immune (delegated to
/// `ability_blocks_sand_damage`). Mutates `hps[slot]` in place. The post-mega
/// type pair is read via `effective_combatant`, so a Pokemon mid-mega is
/// evaluated against its new typing.
pub fn apply_sand_damage_active(
  active : Int,
  hps : Array[Int],
  team : Array[Combatant],
  megaed : Array[Bool],
  max_hp : Int,
  weather : @model.Weather,
) -> Unit {
  match weather {
    @model.Sand => {
      if hps[active] <= 0 {
        return
      }
      let is_mega = active < megaed.length() && megaed[active]
      let eff = effective_combatant(team[active], is_mega)
      // 即値カバレッジ: 単タイプは type2="" で素通り (空文字は どのタイプ名
      // とも一致しない)。テラスタル / うちおとす による空中浮遊解除等の動的
      // type 上書きは本 EOT chip では未対応 (Plan スコープ外)。
      if eff.pokemon.type1 == "はがね" ||
        eff.pokemon.type1 == "いわ" ||
        eff.pokemon.type1 == "じめん" {
        return
      }
      if eff.pokemon.type2 == "はがね" ||
        eff.pokemon.type2 == "いわ" ||
        eff.pokemon.type2 == "じめん" {
        return
      }
      if ability_blocks_sand_damage(eff.ability) {
        return
      }
      sub_hp_floor0(hps, active, max_hp / 16)
    }
    _ => ()
  }
}

///|
/// Update a switched-out slot's status per mainline switch-out rules:
/// - `BadPoison(n)`: keep the status but reset the counter to 0 (next tick
///   is 1/16 again).
/// - `Drowsy(_)`: clear entirely — あくびの予告は控えに下がると消える。
/// - Other conditions: carry over unchanged (burns / paralysis / sleep all
///   persist across switches in canonical rules).
pub fn reset_toxic_counter_on_switch(
  status : @model.StatusCondition,
) -> @model.StatusCondition {
  match status {
    @model.BadPoison(_) => @model.BadPoison(0)
    @model.Drowsy(_) => @model.None
    other => other
  }
}

///|
pub fn is_paralyzed(s : @model.StatusCondition) -> Bool {
  match s {
    @model.Paralyze => true
    _ => false
  }
}

///|
pub fn is_burned(s : @model.StatusCondition) -> Bool {
  match s {
    @model.Burn => true
    _ => false
  }
}

///|
/// Return the number of remaining unable-to-act turns if `s` is a `Sleep`
/// condition. `Some(n)` means the sufferer will skip this turn (n ≥ 1) or
/// wake up (n == 0). `None` means not asleep.
pub fn sleep_turns(s : @model.StatusCondition) -> Int? {
  match s {
    @model.Sleep(n) => Some(n)
    _ => None
  }
}

///|
/// In-place HP 加算 helper。`hps[slot]` に `amount` を加え、`max_hp` で上限
/// クランプする。`amount <= 0` は no-op (回復系の呼び出し側で「無効」を表現
/// するため 0 / 負値で早期 return)。`hps[slot]` が既に `max_hp` 以上のときも
/// 副作用なし (回復対象が満タンなら何もしない)。
///
/// 回復技 (`apply_healing`) の FixedFraction / WeatherDependent / Drain 等
/// と EOT 自動回復 (`eot_leftovers_heal`) の HP 増加部分を共通化するための
/// 最小単位。`sub_hp_floor0` (HP 減少クランプ) は段階 8 (Drain + ヘドロえき)
/// で同じファイルに追加予定。
pub fn add_hp_capped(
  hps : Array[Int],
  slot : Int,
  amount : Int,
  max_hp : Int,
) -> Unit {
  if amount <= 0 {
    return
  }
  let cur = hps[slot]
  if cur >= max_hp {
    return
  }
  let new_hp = cur + amount
  hps[slot] = if new_hp > max_hp { max_hp } else { new_hp }
}

///|
/// In-place HP 減算 helper。`hps[slot]` から `amount` を引き、0 未満には
/// 落とさない (= floor at 0)。`amount <= 0` は no-op (Drain 反転で
/// `max(1, _)` が常に正であることを呼び出し側が保証する前提だが、防衛的
/// に no-op で吸収)。
///
/// 段階 8 で Drain × ヘドロえき (Liquid Ooze) の反転 damage を表現するため
/// に導入する。`add_hp_capped` の対称形 (HP 増加 + max クランプ ↔ HP 減少
/// + 0 床)。ひんしスロット (HP=0) でも `amount > 0` なら HP=0 のまま変化
/// なし (`max(0, -amount)` で吸収)。
pub fn sub_hp_floor0(hps : Array[Int], slot : Int, amount : Int) -> Unit {
  if amount <= 0 {
    return
  }
  let new_hp = hps[slot] - amount
  hps[slot] = if new_hp < 0 { 0 } else { new_hp }
}

///|
/// HP 回復技を適用する。`mv.healing` が `None` であれば no-op。本段階では
/// `FixedFraction(n, d)` / `WeatherDependent(...)` / `Rest` バリアントを実装。
/// 残る `Drain` / `LeechSeed` / `PainSplit` / `Wish` は段階 8 以降で同じ
/// 関数を拡張する形で順次有効化する。未実装バリアントは `_ => ()` で
/// fall-through し、ランタイムは no-op (型は通るが効果は出ないので、段階
/// 移行中に CLI が落ちることはない)。
///
/// 引数 `weather` は `WeatherDependent` の倍率選択に使う。
/// FixedFraction / その他バリアントでは参照されない。段階 5 で
/// `SwitchingGameState.weather` を導入したことに対応し、本関数は呼び出し元
/// (`with_post_hit_effects`) から state.weather を抜き出して受け取る (state
/// 全体ではなく Weather 単体にしている理由: Drain は defender.ability、Wish
/// は wish_turns 配列など state の特定フィールドではなく別ロジックを使う
/// ため、共通の "state 全部渡し" にしても利点が薄い。最小拡張で意味論を
/// 表現することを優先する)。
///
/// 引数 `attacker_status` / `attacker_ability` は段階 7 (Rest) で追加。
/// Rest は HP を max まで戻すと同時に `attacker_status[active]` を
/// `Sleep(2)` に **上書き** する本家挙動を持つため、status fanout
/// (`maybe_apply_status_fanout`) を経由できない (fanout は既存 status が
/// `None` の場合のみ書き換える保護を持っている)。さらに `ふみん` /
/// `やるき` / `スイートベール` の Sleep 免疫がある attacker では Rest 自体
/// が失敗する (HP も status も不変)。ability immunity 判定は
/// `ability_blocks_status(ability, SleepKind)` に集約済み。本家挙動として
/// attacker HP が既に max のときも Rest は失敗する (「体力がいっぱいで
/// 眠れない」)。
///
/// 引数 `dmg` / `defender_ability` は段階 8 (Drain + ヘドロえき反転) で追加。
/// Drain は与えた damage の n/d を attacker が吸収する技群 (ギガドレイン /
/// メガドレイン / すいとる / きゅうけつ / ドレインキッス (3/4) /
/// パラボラチャージ / ドレインパンチ) で、`dmg > 0` の場合のみ
/// `max(1, dmg * n / d)` を回復する。`dmg` は **dealt** (defender HP で
/// クランプ済み、overkill 補正済み) を caller が渡すこと。defender ability
/// が `ヘドロえき` (Liquid Ooze) の場合は回復が damage に反転し、`sub_hp_floor0`
/// 経由で attacker HP=0 まで削れる。Magic Guard × Liquid Ooze の組合せ
/// (attacker_ability=マジックガード が反転 damage を防ぐか) は Plan に
/// 明記されておらず本段階では未対応 (デフォルトで反転して食らう)。
/// FixedFraction / WeatherDependent / Rest は `dmg` / `defender_ability` を
/// 参照しない。
///
/// 引数 `field` / `attacker_grounded` は Stage H (terrain × sleep) で追加。
/// エレキフィールド / ミストフィールド 下で grounded な使用者は Rest で
/// 眠れず失敗する (HP も status も不変) — `field_blocks_status(field,
/// SleepKind)` が阻止対象を判定し、`attacker_grounded` が grounded 条件を
/// 与える。grounded 判定は mega 後の type/ability/item を要するため caller が
/// 解決して渡す (apply_healing 内では mega 解決経路を再通しない)。Rest 以外の
/// バリアントは `field` / `attacker_grounded` を参照しない。両引数のデフォルト
/// (`Field::None` / `true`) では `field_blocks_status` が false を返すため
/// 既存挙動と完全に一致する (terrain を渡さない呼び出しは無影響)。
///
/// `with_post_hit_effects` の末尾、`self_ko` の手前で呼ばれる。`self_ko`
/// 側で attacker HP を 0 にする本家挙動を妨げないよう、必ず先に回復してから
/// `self_ko` が後勝ちで HP を 0 化する。
pub fn apply_healing(
  mv : @model.Move,
  attacker_active_slot : Int,
  attacker_hps : Array[Int],
  attacker_max : Int,
  weather : @model.Weather,
  attacker_status : Array[@model.StatusCondition],
  attacker_ability : String,
  dmg : Int,
  defender_ability : String,
  field~ : @model.Field = @model.Field::None,
  attacker_grounded~ : Bool = true,
) -> Unit {
  match mv.healing {
    None => ()
    Some(@model.FixedFraction(n, d)) => {
      // d == 0 / n <= 0 は data.json 側で発生し得ないが、防衛的に no-op。
      if d <= 0 || n <= 0 {
        return
      }
      let amount = attacker_max * n / d
      add_hp_capped(attacker_hps, attacker_active_slot, amount, attacker_max)
    }
    Some(
      @model.WeatherDependent(
        default_n,
        default_d,
        sunny_n,
        sunny_d,
        harsh_n,
        harsh_d,
      ),
    ) => {
      // weather に応じて 3 系統から (n, d) を選択する。
      //   Sun                → sunny (= 2/3 for moonlight family)
      //   Rain / Sand / Snow → harsh (= 1/4)
      //   None               → default (= 1/2)
      // Gen9 仕様。霧 / 強い晴れ / 強い雨 / 乱気流は本 PR ではモデル外
      // (Champions M-A は通常 4 天候 + 無天候のみ)。
      let (n, d) = match weather {
        @model.Weather::Sun => (sunny_n, sunny_d)
        @model.Weather::Rain | @model.Weather::Sand | @model.Weather::Snow =>
          (harsh_n, harsh_d)
        @model.Weather::None => (default_n, default_d)
      }
      // 防衛的: data.json が壊れて (0, 0) が来ても segfault しないよう no-op。
      if d <= 0 || n <= 0 {
        return
      }
      let amount = attacker_max * n / d
      add_hp_capped(attacker_hps, attacker_active_slot, amount, attacker_max)
    }
    Some(@model.Rest) => {
      // Sleep 免疫 ability (ふみん / やるき / スイートベール) を持つ attacker
      // が Rest を撃つと「ねむれない！」で失敗し、HP も status も不変。
      // Magic Guard は Sleep の付与を **阻止しない** (residual damage の
      // immunity であって status immunity ではない) ので、ability_blocks_status
      // の truth table から意図的に外している (ability_immunity.mbt 参照)。
      if ability_blocks_status(attacker_ability, @model.SleepKind) {
        return
      }
      // エレキフィールド / ミストフィールド 下で grounded な使用者は眠れない
      // ため Rest が「ねむれない！」で失敗し、HP も status も不変。grounded
      // 判定は caller が mega 後形態で解決して `attacker_grounded` で渡す。
      // field → kind の阻止表は `field_blocks_status` に集約しており、DP の
      // status fanout / MC の status roll と完全に同一 semantics になる。
      if attacker_grounded && field_blocks_status(field, @model.SleepKind) {
        return
      }
      // 本家挙動: HP が既に max のとき Rest は「体力がいっぱいで眠れない」で
      // 失敗。HP も status も不変。これを入れないと満タンの攻め手が Rest を
      // 状態異常解除目的で常時撃って Sleep(2) を上書きしてしまい payoff が
      // overvalued になる (Sleep フェーズの行動制限分を払わずに status を
      // 書き換えるため)。
      if attacker_hps[attacker_active_slot] >= attacker_max {
        return
      }
      // 既存 status を強制的に Sleep(2) で上書き (本家挙動 — Burn / Poison /
      // Para / 既存 Sleep(残ターン) を Rest が必ず書き換える)。
      // status fanout を経由せず直接書き込むのは、fanout が None 保護を
      // 持っているため (Rest はその保護を bypass する必要がある)。
      // HP も max まで強制リセット (`add_hp_capped` の早期 return を bypass
      // する必要があるため直接代入)。
      attacker_hps[attacker_active_slot] = attacker_max
      attacker_status[attacker_active_slot] = @model.Sleep(2)
    }
    Some(@model.Drain(n, d)) => {
      // Drain は dmg > 0 のときのみ発動。dmg=0 (タイプ免疫 / 0 ダメ) では
      // 回復も反転 damage も起こさない (= ヘドロえき も発火しない、本家挙動)。
      if dmg <= 0 {
        return
      }
      // 防衛的: data.json が壊れて (0, 0) が来ても segfault しないよう no-op。
      if d <= 0 || n <= 0 {
        return
      }
      // 回復量は `max(1, dmg * n / d)`。dmg=1 / n=1 / d=2 のとき整数除算で
      // 0 に丸まる境界を `max(1, _)` で最小 1 回復に持ち上げる (Showdown / Gen9
      // 仕様)。
      let raw = dmg * n / d
      let amount = if raw < 1 { 1 } else { raw }
      if ability_reverses_drain(defender_ability) {
        // ヘドロえき (Liquid Ooze): 回復が damage に反転。attacker は amount
        // と同じ量の damage を受ける。`sub_hp_floor0` で HP=0 を床。HP=max
        // でも反転 damage は発動する (add_hp_capped の早期 return とは
        // 独立経路)。Magic Guard × Liquid Ooze (attacker_ability=マジックガード
        // が反転 damage を防ぐか) は Plan に明記なく本段階では未対応 =
        // デフォルトで反転して食らう。
        sub_hp_floor0(attacker_hps, attacker_active_slot, amount)
      } else {
        add_hp_capped(
          attacker_hps, attacker_active_slot, amount, attacker_max,
        )
      }
    }
    // 他バリアントは段階 9 以降で順次実装。本段階ではランタイム no-op。
    _ => ()
  }
}
