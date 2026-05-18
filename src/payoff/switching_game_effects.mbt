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
fn eot_leftovers_heal(current_hp : Int, max_hp : Int, item : String) -> Int {
  if current_hp <= 0 {
    return current_hp
  }
  if current_hp >= max_hp {
    return current_hp
  }
  if item != "たべのこし" {
    return current_hp
  }
  let heal = max_hp / 16
  let new_hp = current_hp + heal
  if new_hp > max_hp { max_hp } else { new_hp }
}

///|
/// Apply end-of-turn slip damage and counter updates to both actives of
/// `state` in place on fresh copies; returns the updated state. Only the
/// active slot receives EOT — bench Pokemon don't tick. Called at the end of
/// every turn resolution in `attempt_turn_with_cache`.
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
  // Mainline EOT 順: たべのこし 等のアイテム回復 → 状態異常のスリップダメージ。
  // (Gen9 公式順では item heal が status damage より先にティックする。)
  // 持ち物消費フラグは消費系 berry 用で、たべのこし はそもそも非消費アイテム
  // なので item_consumed の影響を受けない。
  let my_hp_after_heal = eot_leftovers_heal(
    my_hps[state.my_active], my_max, my_team[state.my_active].item,
  )
  let opp_hp_after_heal = eot_leftovers_heal(
    opp_hps[state.opp_active], opp_max, opp_team[state.opp_active].item,
  )
  let (my_hp_new, my_st_new) = eot_slip_active(
    my_hp_after_heal, my_max, my_status[state.my_active],
  )
  my_hps[state.my_active] = my_hp_new
  my_status[state.my_active] = my_st_new
  let (opp_hp_new, opp_st_new) = eot_slip_active(
    opp_hp_after_heal, opp_max, opp_status[state.opp_active],
  )
  opp_hps[state.opp_active] = opp_hp_new
  opp_status[state.opp_active] = opp_st_new
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
    turn: state.turn,
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
