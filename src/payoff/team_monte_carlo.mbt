///|
/// Team-level Monte Carlo rollout used by the Screened pipeline. Simulates
/// 3v3-style battles with switching as a cheap pre-screening signal for
/// `team_payoff_matrix_screened`.
///
/// Returned value is in `[-1, +1]` (own-side utility): +1 = own sweeps,
/// -1 = own swept, otherwise the HP-ratio difference clamped to that range
/// when the rollout hits `turn_limit`. Mega evolution is intentionally
/// ignored — this is a rough screening pass; precise refinement is the
/// job of the SwitchingGame DP downstream.

///|
/// Switch hysteresis threshold: only switch when the best alternative slot's
/// expected damage / opp_hp exceeds the current active's value by more than
/// this. Keeps the rollout from thrashing on marginal matchups.
const SWITCH_HYSTERESIS : Double = 0.05

///|
/// Compute the best avg-damage move a given attacker can land on the given
/// defender with the given ranks. Returns `0.0` when all moves are immune or
/// non-damaging. Cheap wrapper around `pick_best_move` used by the greedy
/// heuristic — the returned scalar is not the move index but the expected
/// damage scalar.
fn best_expected_damage(
  atk : Combatant,
  dfn : Combatant,
  atk_ranks : Array[Int],
  def_ranks : Array[Int],
  weather? : @model.Weather = @model.Weather::None,
  field? : @model.Field = @model.Field::None,
  atk_protean_locked? : String = "",
  def_protean_locked? : String = "",
) -> Double {
  // Stage 7 (Protean / Libero MC parity): override attacker / defender combatant
  // 経由で Protean ロックを適用する。MC は mega を未モデルなので is_mega=false
  // 固定で DP 側 `effective_combatant` を再利用する (SSoT 共有)。`protean_locked`
  // が "" のときは override 無し (= 元 combatant そのまま、bit-exact)。
  // `protean_consumed = (locked != "")` を build_input_with_ranks に渡し、ロック中は
  // engine の Protean STAB gate を止める (override 済み type1 で通常 STAB 経路を
  // 通す)。team_perform_attack と同一の override をここでも掛けることで greedy
  // 選択と実ダメージの乖離を防ぐ。
  let atk_eff = effective_combatant(
    atk,
    false,
    protean_locked=atk_protean_locked,
  )
  let dfn_eff = effective_combatant(
    dfn,
    false,
    protean_locked=def_protean_locked,
  )
  let atk_consumed = atk_protean_locked != ""
  let mut best = 0.0
  for i in 0..<atk.moves.length() {
    let mv = atk.moves[i]
    if mv.power <= 0 {
      continue
    }
    // Psychic Terrain priority block (DP/MC parity): grounded defender 下では
    // priority>0 の damage 期待値を 0 として評価する。これが無いと greedy が
    // 無効化される priority 技を選び続け、resolution 側で `mc_psychic_priority_
    // blocked` により毎ターン no-effect になって MC value が DP と乖離する。
    if mc_psychic_priority_blocked(mv, field, dfn) {
      continue
    }
    let ar = match mv.category {
      @model.Physical => atk_ranks[0]
      @model.Special => atk_ranks[2]
      @model.Status => 0
    }
    let dr = match mv.category {
      @model.Physical => def_ranks[1]
      @model.Special => def_ranks[3]
      @model.Status => 0
    }
    let r = @damage.calc_damage(
      build_input_with_ranks(
        atk_eff,
        dfn_eff,
        mv,
        ar,
        dr,
        weather~,
        field~,
        protean_consumed=atk_consumed,
      ),
    )
    let avg = avg_damage(r)
    if avg > best {
      best = avg
    }
  }
  best
}

///|
/// Team action chosen for one rollout turn: `UseMove(mv_idx)` or
/// `Switch(slot_idx)`. Simpler than `ActionKind` in `switching_game.mbt` —
/// no Mega support in the screening rollout.
priv enum TeamAction {
  TmUseMove(Int)
  TmSwitch(Int)
}

///|
/// Pick a TeamAction for the given side under a stay-vs-best-switch greedy
/// policy with ε-greedy exploration. When `active` is KO-d, returns the
/// best forced switch (or `None` if the entire side has fainted).
///
/// When `must_recharge` is true the whole turn is forfeit (mainline Hyper
/// Beam / Giga Impact behaviour); we emit a `TmUseMove(0)` placeholder that
/// the caller will short-circuit to `acts=false`.
///
/// Stage H: `weather~ / field~` を受け取り、`best_expected_damage` /
/// `pick_best_move` の damage 評価に thread する。DP 側 `value` が state.weather
/// / state.field を渡しているのと対称な配線。これが無いと「Sun で でんき
/// vs ほのお のうち greedy が ほのお を選ぶ」「Electric Terrain で でんき
/// vs ほのお のうち greedy が でんき を選ぶ」といった field 依存の選択が
/// MC で起きず DP / MC parity が崩れる。
fn greedy_team_action(
  active : Int,
  my_team : Array[Combatant],
  my_hps : Array[Int],
  my_ranks : Array[Int],
  opp_active : Int,
  opp_team : Array[Combatant],
  opp_ranks : Array[Int],
  rng : @random.Rand,
  epsilon : Double,
  must_recharge? : Bool = false,
  weather? : @model.Weather = @model.Weather::None,
  field? : @model.Field = @model.Field::None,
  my_protean_locked? : Array[String] = [],
  opp_protean_locked? : Array[String] = [],
) -> TeamAction? {
  // Stage 7 (Protean / Libero MC parity): per-slot ロックを greedy 評価に
  // 渡すための helper。slot が範囲外 / 配列未指定 (テスト用 default [] ) のとき
  // "" を返す (= override 無し)。
  fn locked_of(arr : Array[String], slot : Int) -> String {
    if slot >= 0 && slot < arr.length() {
      arr[slot]
    } else {
      ""
    }
  }
  if must_recharge && my_hps[active] > 0 {
    return Some(TmUseMove(0))
  }
  let alive_slots : Array[Int] = []
  for i in 0..<my_hps.length() {
    if my_hps[i] > 0 {
      alive_slots.push(i)
    }
  }
  if alive_slots.length() == 0 {
    return None
  }
  // active KO → forced switch (only switch actions are legal)
  if my_hps[active] <= 0 {
    let mut best = alive_slots[0]
    let mut best_score = -1.0
    let zero_ranks = [0, 0, 0, 0, 0]
    let opp_locked = locked_of(opp_protean_locked, opp_active)
    for s in alive_slots {
      let score = best_expected_damage(
        my_team[s],
        opp_team[opp_active],
        zero_ranks,
        opp_ranks,
        weather~,
        field~,
        atk_protean_locked=locked_of(my_protean_locked, s),
        def_protean_locked=opp_locked,
      )
      if score > best_score {
        best_score = score
        best = s
      }
    }
    return Some(TmSwitch(best))
  }
  // ε-greedy: uniform over all legal actions (UseMove for every move + Switch
  // for every alive teammate other than `active`).
  let n_moves = my_team[active].moves.length()
  let n_switch = {
    let mut c = 0
    for s in alive_slots {
      if s != active {
        c = c + 1
      }
    }
    c
  }
  let total_actions = n_moves + n_switch
  if total_actions == 0 {
    return None
  }
  let draw = rng.int(limit=1000000).to_double() / 1000000.0
  if draw < epsilon {
    let idx = rng.int(limit=total_actions)
    if idx < n_moves {
      return Some(TmUseMove(idx))
    }
    // find the idx-n_moves-th switch slot in alive_slots order
    let mut k = idx - n_moves
    for s in alive_slots {
      if s == active {
        continue
      }
      if k == 0 {
        return Some(TmSwitch(s))
      }
      k = k - 1
    }
    return Some(TmUseMove(0))
  }
  // Greedy: stay vs best-switch comparison, normalised by opp active max HP.
  let opp_hp_denom = {
    let h = opp_team[opp_active].pokemon.hp
    if h > 0 {
      h.to_double()
    } else {
      1.0
    }
  }
  let opp_locked = locked_of(opp_protean_locked, opp_active)
  let active_locked = locked_of(my_protean_locked, active)
  let stay_value = best_expected_damage(
      my_team[active],
      opp_team[opp_active],
      my_ranks,
      opp_ranks,
      weather~,
      field~,
      atk_protean_locked=active_locked,
      def_protean_locked=opp_locked,
    ) /
    opp_hp_denom
  let mut best_switch = -1
  let mut best_switch_value = 0.0
  let zero_ranks = [0, 0, 0, 0, 0]
  for s in alive_slots {
    if s == active {
      continue
    }
    let v = best_expected_damage(
        my_team[s],
        opp_team[opp_active],
        zero_ranks,
        opp_ranks,
        weather~,
        field~,
        atk_protean_locked=locked_of(my_protean_locked, s),
        def_protean_locked=opp_locked,
      ) /
      opp_hp_denom
    if v > best_switch_value {
      best_switch_value = v
      best_switch = s
    }
  }
  if best_switch >= 0 && best_switch_value > stay_value + SWITCH_HYSTERESIS {
    return Some(TmSwitch(best_switch))
  }
  // UseMove: greedy max-damage move. Fall back to move 0 if no damaging move.
  // Stage 7: ロック中の Protean 個体は active_locked / opp_locked を渡して
  // 実ダメージ (`team_perform_attack`) と同じ override で move を選ぶ。
  match
    pick_best_move(
      my_team[active],
      opp_team[opp_active],
      atk_ranks=my_ranks,
      def_ranks=opp_ranks,
      weather~,
      field~,
      atk_protean_locked=active_locked,
      def_protean_locked=opp_locked,
    ) {
    Some(i) => Some(TmUseMove(i))
    None => Some(TmUseMove(0))
  }
}

///|
/// Apply team-level post-hit side effects after a `team_perform_attack`
/// call. Mirrors `resolve_post_hit_effects` + `with_post_hit_effects` in
/// the DP layer so the two resolvers agree on post-hit semantics.
///
/// Order matches the DP helper:
///   1. `stat_effects` (self + opp-target with opp_alive gating)
///   2. recoil (attacker HP loss)
///   3. apply_healing (HealingEffect: FixedFraction / WeatherDependent /
///      Drain / Rest / LeechSeed planting / PainSplit / Wish setting)
///   4. self_ko (attacker HP forced to 0, post-heal — self_ko wins ordering)
///   5. recharge (set only if attacker is still alive after 4)
///   6. weather_set (にほんばれ / あまごい / すなあらし / ゆきげしき)
///
/// Stage 13 (healing parity): Stage 12 まで MC 側は recoil / self_ko / recharge
/// しか resolve していなかったため、回復技 (じこさいせい等) や 天候設定技を
/// MC で打っても完全に無視され、ScreenedSwitchingGame の MC phase と DP phase
/// が割れていた。本関数は DP 側 `with_post_hit_effects` の意味論を移植し、
/// `apply_healing` / LeechSeed planting / PainSplit / Wish set / 天候設定の
/// 経路を MC でも有効化する。
///
/// `weather_state` / `weather_turns_state` は 1-element 配列 (out-param) で
/// 渡し、天候設定技ヒット時に書き換える。`attacker_team` / `defender_team` は
/// `apply_healing` の defender_ability 解決と LeechSeed のくさタイプ判定に必要。
/// `defender_leech_seeded` は LeechSeed 植え付け先 (defender 側) を書き換える。
/// attacker 側の leech_seeded は post-hit では触らない (剥がしは Switch arm
/// 側で行う)。`attacker_wish_turns` は per-side scalar の Wish counter
/// (1-element 配列で mutable に渡す)。Wish 使用で `[0]` に 2 を書き、EOT で
/// `tick_and_fire_wish_inplace` が active slot へ向けて発動する。DP 側
/// (`SwitchingGameState.my_wish_turns : Int`) と同じ slot-bound 仕様。
/// `attacker_status` は Rest が `Sleep(2)` を上書きするために必要。
/// `defender_megaed` は LeechSeed くさ判定の mega 後 type 解決に渡す
/// (MC では常に false 固定の dummy 配列だが、シグネチャは DP 側
/// `effective_combatant` 経路と整合)。MC は attacker mega を解決しないため
/// attacker_megaed は受け取らない (現状の MC は mega 未モデル、`apply_healing`
/// 側は attacker_ability を raw に読むので mega 後 ability の解決も不要)。
///
/// `applied for both damaging and status moves` — `team_perform_attack` は
/// status moves で damage を返さないが、本関数の全 phase (stat_effects 〜
/// weather_set) は damage の有無に依存せず適用される。
fn team_apply_post_hit(
  attacker_hps : Array[Int],
  attacker_active : Int,
  attacker_ranks : Array[Int],
  attacker_must_recharge : Array[Bool],
  attacker_status : Array[@model.StatusCondition],
  attacker_wish_turns : Array[Int],
  attacker_team : Array[Combatant],
  defender_hps : Array[Int],
  defender_active : Int,
  defender_ranks : Array[Int],
  defender_leech_seeded : Array[Bool],
  defender_team : Array[Combatant],
  defender_megaed : Array[Bool],
  weather_state : Array[@model.Weather],
  weather_turns_state : Array[Int],
  field_state : Array[@model.Field],
  field_turns_state : Array[Int],
  mv : @model.Move,
  dmg : Int,
) -> Unit {
  let opp_alive = defender_hps[defender_active] > 0
  apply_stat_effects(attacker_ranks, defender_ranks, opp_alive, mv)
  if mv.recoil_num > 0 && dmg > 0 {
    let raw = dmg * mv.recoil_num / mv.recoil_den
    let recoil = if raw < 1 { 1 } else { raw }
    let new_hp = attacker_hps[attacker_active] - recoil
    attacker_hps[attacker_active] = if new_hp < 0 { 0 } else { new_hp }
  }
  // Stage 13: 回復技 (HealingEffect) を self_ko の **手前** で適用。じばく系 +
  // healing の組合せは現状ゲーム内には無いが、ある場合は self_ko 側 (HP=0 強制
  // 上書き) が後勝ち、という DP 側の順序契約を MC でも維持する。
  let attacker_max = effective_hp(attacker_team[attacker_active])
  let attacker_ability = attacker_team[attacker_active].ability
  let defender_ability = defender_team[defender_active].ability
  let weather = weather_state[0]
  // Stage H (terrain × sleep): Rest がエレキ / ミストフィールド下で grounded
  // 使用者に失敗する DP 挙動を MC でも再現する。MC は mega を模さないため raw
  // combatant で grounded を解く (DP の `effective_combatant(_, false)` に相当
  // — mc_psychic_priority_blocked と同方針)。field は現在の field_state[0]。
  let attacker_c = attacker_team[attacker_active]
  let attacker_grounded = @damage.is_grounded(
    type1=attacker_c.pokemon.type1,
    type2=attacker_c.pokemon.type2,
    ability=attacker_c.ability,
    item=attacker_c.item,
  )
  apply_healing(
    mv,
    attacker_active,
    attacker_hps,
    attacker_max,
    weather,
    attacker_status,
    attacker_ability,
    dmg,
    defender_ability,
    field=field_state[0],
    attacker_grounded~,
  )
  // Stage 13: LeechSeed 植え付け (apply_healing は attacker 側バッファしか
  // 触れない設計なので、defender_leech_seeded への書き込みは専用パス)。
  //   - defender が くさタイプ (mega 後 effective type) なら失敗
  //   - すでに seeded な相手にもう一度撃っても観測上 no-op (true 上書きは無害)
  //   - Magic Guard は植え付け自体は許容する (EOT tick 側で 0 化される)
  match mv.healing {
    Some(@model.LeechSeed) => {
      let def_megaed = if defender_active < defender_megaed.length() {
        defender_megaed[defender_active]
      } else {
        false
      }
      let defender_eff = effective_combatant(
        defender_team[defender_active],
        def_megaed,
      )
      let is_grass = defender_eff.pokemon.type1 == "くさ" ||
        defender_eff.pokemon.type2 == "くさ"
      if !is_grass && defender_active < defender_leech_seeded.length() {
        defender_leech_seeded[defender_active] = true
      }
    }
    // PainSplit: 双方の HP を平均化し、各 max でクランプ。`apply_healing` は
    // attacker バッファしか書けないため LeechSeed と同様に専用パス。
    Some(@model.PainSplit) => {
      let defender_max = effective_hp(defender_team[defender_active])
      let attacker_cur = attacker_hps[attacker_active]
      let defender_cur = defender_hps[defender_active]
      let avg = (attacker_cur + defender_cur) / 2
      let new_attacker = if avg > attacker_max { attacker_max } else { avg }
      let new_defender = if avg > defender_max { defender_max } else { avg }
      attacker_hps[attacker_active] = new_attacker
      defender_hps[defender_active] = new_defender
    }
    // Wish: per-side scalar (1-element 配列) `[0]` を 2 にセット (DP 側と
    // 同じ後着優先の上書き semantics)。`attacker_active` は不要 — per-side
    // 1 wish counter のため。発動は EOT 側 (`tick_and_fire_wish_inplace`)。
    Some(@model.Wish) =>
      if attacker_wish_turns.length() > 0 {
        attacker_wish_turns[0] = 2
      }
    _ => ()
  }
  if mv.self_ko {
    attacker_hps[attacker_active] = 0
  }
  if mv.recharge && attacker_hps[attacker_active] > 0 {
    attacker_must_recharge[attacker_active] = true
  }
  // Stage 13: 天候設定技 (Move.weather_set) の効果を out-param に反映する。
  // Gen9 base の 5 ターン (天候石なし) を固定値とする。DP 側 `with_post_hit_effects`
  // 末尾の処理と整合。
  match mv.weather_set {
    Some(w) => {
      weather_state[0] = w
      weather_turns_state[0] = 5
    }
    None => ()
  }
  // Stage H: フィールド設定技 (Move.field_set) の効果を out-param に反映する。
  // Gen9 base の 5 ターン (Terrain Extender なし) を固定値とする。DP 側
  // `with_post_hit_effects` の `mv.field_set` 処理と semantics 一致 (later-wins
  // 上書き、turns=5 リセット)。weather_set と完全対称な処理パス。
  match mv.field_set {
    Some(f) => {
      field_state[0] = f
      field_turns_state[0] = 5
    }
    None => ()
  }
}

///|
/// In-place Wish tick + activate (per-side scalar、1-element 配列で mutable
/// に渡す)。
///   - `wish_turns[0] > 0`: -= 1 (tick).
///   - tick 後 `wish_turns[0] == 0`: fire — `hps[active] > 0` なら
///     `effective_hp(team[active]) / 2` ぶん回復 (max クランプ)。HP=0 受け手
///     には発動扱いだが HP は不変 (蘇生しない、本家挙動)。発動の有無に関わらず
///     `wish_turns[0] = -1` で idle 化、Wish 自体は消費される。
///   - `wish_turns[0] < 0` (idle, sentinel `-1`): no-op (fixpoint).
///
/// per-side scalar 設計のため、Wisher が Switch で控えに退いた後でも、Wish
/// は active slot に残り、交代先で受け取る (mainline と一致)。MC 側の EOT
/// block (`team_rollout` の Step 4.5) と wbtest 双方から同じ実装を呼ぶことで
/// helper 二重化を防ぐ — DP 側 `apply_eot` Step 5 と semantics 一致。
pub fn tick_and_fire_wish_inplace(
  wish_turns : Array[Int],
  hps : Array[Int],
  active : Int,
  team : Array[Combatant],
) -> Unit {
  if wish_turns.length() == 0 {
    return
  }
  if wish_turns[0] > 0 {
    wish_turns[0] = wish_turns[0] - 1
  }
  if wish_turns[0] == 0 {
    if active >= 0 && active < hps.length() && hps[active] > 0 {
      let slot_max = effective_hp(team[active])
      add_hp_capped(hps, active, slot_max / 2, slot_max)
    }
    wish_turns[0] = -1
  }
}

///|
/// Apply one pre-selected attack in the team rollout. Mirrors
/// `perform_attack_with` in `monte_carlo.mbt` but free-standing so the team
/// rollout stays self-contained.
fn team_perform_attack(
  attacker : Combatant,
  defender : Combatant,
  defender_hp : Int,
  mv : @model.Move,
  rng : @random.Rand,
  atk_ranks : Array[Int],
  def_ranks : Array[Int],
  atk_burn? : Bool = false,
  weather? : @model.Weather = @model.Weather::None,
  field? : @model.Field = @model.Field::None,
  atk_protean_locked? : String = "",
  def_protean_locked? : String = "",
) -> Int {
  if mv.power <= 0 {
    // Status moves: no damage and no in-place stat mutation. The caller
    // applies `stat_effects` (with opp_alive gating) via
    // `team_apply_post_hit` so both branches share one resolver.
    return defender_hp
  }
  let atk_rank = match mv.category {
    @model.Physical => atk_ranks[0]
    @model.Special => atk_ranks[2]
    @model.Status => 0
  }
  let def_rank = match mv.category {
    @model.Physical => def_ranks[1]
    @model.Special => def_ranks[3]
    @model.Status => 0
  }
  // Stage 7 (Protean / Libero MC parity): 実ダメージ解決も greedy 選択
  // (`best_expected_damage` / `pick_best_move`) と **同一の** Protean override を
  // 適用する。片側だけ override すると greedy と実ダメージが乖離して DP / MC
  // parity が崩れる (過去類似バグ)。MC は mega 未モデルなので is_mega=false 固定で
  // `effective_combatant` を再利用 (SSoT)。"" のときは override 無しで bit-exact。
  let attacker_eff = effective_combatant(
    attacker,
    false,
    protean_locked=atk_protean_locked,
  )
  let defender_eff = effective_combatant(
    defender,
    false,
    protean_locked=def_protean_locked,
  )
  let atk_consumed = atk_protean_locked != ""
  let r = @damage.calc_damage(
    build_input_with_ranks(
      attacker_eff,
      defender_eff,
      mv,
      atk_rank,
      def_rank,
      weather~,
      field~,
      protean_consumed=atk_consumed,
    ),
  )
  if r.is_immune {
    return defender_hp
  }
  let raw = r.damages[rng.int(limit=16)]
  // やけど + 物理: ダメージ半減。
  let dmg = if atk_burn {
    match mv.category {
      @model.Physical => raw / 2
      _ => raw
    }
  } else {
    raw
  }
  // overkill 分が `before - new_hp` で過大計上されてドレイン / 反動を膨らませる
  // のを防ぐため 0 床でクランプ。caller は `before - new_hp` を dealt として
  // team_apply_post_hit に渡すので、ここで HP を 0 にすればその差分は actual
  // dealt (= min(dmg, before)) に一致する。
  let new_hp = defender_hp - dmg
  if new_hp < 0 {
    0
  } else {
    new_hp
  }
}

///|
/// Sample a Bernoulli outcome with success probability `p` in [0, 1] using
/// `rng.int(limit=N)` quantised at 1/1_000_000 granularity.
fn rand_bool(rng : @random.Rand, p : Double) -> Bool {
  if p <= 0.0 {
    return false
  }
  if p >= 1.0 {
    return true
  }
  rng.int(limit=1000000).to_double() / 1000000.0 < p
}

///|
/// Resolve a single attack attempt for `me` in the MC rollout, respecting
/// paralysis (12.5% failure), sleep (skip + counter decrement / wake-up),
/// and move accuracy. Returns the new status of `me` and whether the action
/// executes this turn.
fn mc_resolve_attempt(
  status : @model.StatusCondition,
  mv_acc : Int,
  rng : @random.Rand,
) -> (@model.StatusCondition, Bool) {
  match status {
    @model.Sleep(n) => {
      if n > 0 {
        return (@model.Sleep(n - 1), false)
      }
      // Sleep(0): wake up and act subject to accuracy below.
      let acts = rand_bool(rng, mv_acc.to_double() / 100.0)
      (@model.None, acts)
    }
    @model.Paralyze => {
      if rand_bool(rng, PARALYZE_SKIP_RATE) {
        return (@model.Paralyze, false)
      }
      let acts = rand_bool(rng, mv_acc.to_double() / 100.0)
      (@model.Paralyze, acts)
    }
    other => {
      let acts = rand_bool(rng, mv_acc.to_double() / 100.0)
      (other, acts)
    }
  }
}

///|
/// MC rollout variant of `maybe_apply_status_fanout` — samples the chance
/// roll directly. Mutates `defender_status_arr[defender_slot]` in place when
/// the status lands (ignored when already statused, type immune, fainted, or
/// the chance roll fails).
///
/// Stage H parity: `field` を受け取り、DP 側 `maybe_apply_status_fanout` の
/// Misty Terrain block (switching_game_effects.mbt Stage G-2) を移植する。
/// ミストフィールド下で grounded な defender には major status + confusion +
/// freeze-dry の凍りが付与されない。grounded SSoT は `@damage.is_grounded`。
/// MC は mega を未モデルなので raw combatant をそのまま読む (= DP の
/// `effective_combatant(c, false)` と一致)。これが無いと ScreenedSwitchingGame
/// の MC screening phase が Misty 下で status 技を過大評価し、DP refine phase と
/// payoff が割れる。
fn mc_try_apply_status(
  rng : @random.Rand,
  mv : @model.Move,
  defender_team : Array[Combatant],
  defender_hps : Array[Int],
  defender_status_arr : Array[@model.StatusCondition],
  defender_slot : Int,
  field? : @model.Field = @model.Field::None,
) -> Unit {
  let eff = match mv.status_effect {
    None => return
    Some(x) => x
  }
  let (kind, chance) = eff
  if chance <= 0 {
    return
  }
  if defender_hps[defender_slot] <= 0 {
    return
  }
  if defender_status_arr[defender_slot] != @model.None {
    return
  }
  let c = defender_team[defender_slot]
  if @model.immune_to_status(kind, c.pokemon.type1, c.pokemon.type2) {
    return
  }
  // Stage H: terrain (Misty / Electric) は grounded defender への状態異常付与を
  // 阻止する (DP `maybe_apply_status_fanout` Stage G-2 / H と semantics 一致)。
  // 阻止対象 kind は `field_blocks_status` に集約: Misty は全状態、Electric は
  // ねむり / あくび予告 のみ。MC は mega を模さないため raw combatant で判定。
  if field_blocks_status(field, kind) {
    if @damage.is_grounded(
        type1=c.pokemon.type1,
        type2=c.pokemon.type2,
        ability=c.ability,
        item=c.item,
      ) {
      return
    }
  }
  if !rand_bool(rng, chance.to_double() / 100.0) {
    return
  }
  defender_status_arr[defender_slot] = @model.inflict_status(kind)
}

///|
/// MC variant of the DP Psychic-terrain priority block (switching_game_turn.mbt
/// Stage G-3). Returns `true` when `mv` has priority > 0 and the grounded
/// `defender` is under Psychic Terrain — the attack is fully negated (no
/// damage / post-hit / status), matching the DP single-leaf no-effect branch.
/// MC does not model mega, so the raw combatant is read directly (= DP's
/// `effective_combatant(defender, false)`). Without this gate the MC screening
/// phase overvalues priority moves under Psychic Terrain vs the DP refine phase.
fn mc_psychic_priority_blocked(
  mv : @model.Move,
  field : @model.Field,
  defender : Combatant,
) -> Bool {
  if mv.priority <= 0 {
    return false
  }
  match field {
    @model.Field::Psychic =>
      @damage.is_grounded(
        type1=defender.pokemon.type1,
        type2=defender.pokemon.type2,
        ability=defender.ability,
        item=defender.item,
      )
    _ => false
  }
}

// Stage 13: `mc_eot_slip` は削除。MC rollout の EOT 状態異常 slip は DP 側
// `eot_slip_active` (switching_game_effects.mbt) を直接呼ぶようになったため、
// 重複定義 (semantics 一致だがコピー実装) を廃止し SSoT を保つ。挙動は
// pre-Stage-13 と完全一致 (関数本体が同じ).

///|
/// Stage 7 (Protean / Libero MC parity): 攻撃が解決した直後に attacker スロットへ
/// Protean ロックを記録する。DP 側 `with_post_hit_effects` の記録条件と semantics
/// 一致:
///   - 実効特性が へんげんじざい / リベロ (MC は mega 未モデルなので raw ability)
///   - tera_type == "" (テラス中は型固定で Protean 非発動)
///   - 当該 slot が未ロック ("") — once per switch-in
/// 記録値は `mv.type_`。status 技でもカテゴリゲートなしで発動する。
fn record_protean_lock(
  locked : Array[String],
  active : Int,
  attacker : Combatant,
  mv : @model.Move,
) -> Unit {
  if active < 0 || active >= locked.length() {
    return
  }
  if locked[active] != "" {
    return
  }
  if attacker.tera_type != "" {
    return
  }
  if attacker.ability == "へんげんじざい" ||
    attacker.ability == "リベロ" {
    locked[active] = mv.type_
  }
}

///|
/// Run a single team rollout trial. Returns own-side value in `[-1, +1]`:
///
/// - `+1.0` when all opponents are KO'd
/// - `-1.0` when all own Pokemon are KO'd
/// - `own_team_hp_ratio - opp_team_hp_ratio` clamped to `[-1, +1]` when `turn_limit`
///   elapses with both sides still alive
///
/// Mega evolution is not modelled here (screening heuristic).
pub fn team_rollout(
  own : Array[Combatant],
  opp : Array[Combatant],
  rng : @random.Rand,
  turn_limit? : Int = MC_TURN_LIMIT,
  epsilon? : Double = default_rollout_epsilon,
  weather? : @model.Weather = @model.Weather::None,
  field? : @model.Field = @model.Field::None,
) -> Double {
  let own_hps = Array::make(own.length(), 0)
  let opp_hps = Array::make(opp.length(), 0)
  for i in 0..<own.length() {
    own_hps[i] = own[i].pokemon.hp
  }
  for i in 0..<opp.length() {
    opp_hps[i] = opp[i].pokemon.hp
  }
  let own_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let own_status : Array[@model.StatusCondition] = Array::make(
    own.length(),
    @model.None,
  )
  let opp_status : Array[@model.StatusCondition] = Array::make(
    opp.length(),
    @model.None,
  )
  // Per-slot recharge flag. Set by a recharge move (Hyper Beam etc.) landing;
  // consumed next turn by forcing a skipped UseMove. Switching is blocked
  // during recharge (matches mainline), so the flag only clears at end-of-
  // turn after the forced skip.
  let own_must_recharge : Array[Bool] = Array::make(own.length(), false)
  let opp_must_recharge : Array[Bool] = Array::make(opp.length(), false)
  // Stage 13: 回復技 / 天候設定 / LeechSeed / Wish 用の state を追加。
  // DP 側 `SwitchingGameState` の対応フィールドと同じ semantics:
  //   - weather / weather_turns_left: 1-element 配列で out-param スタイル
  //     (Bool の 1 要素配列に値を流す)
  //   - *_leech_seeded[i]: i 番スロットがやどりぎ tick を受けるか
  //   - *_wish_turns: per-side scalar (1-element 配列で mutable に渡す)。
  //     active slot に貼り付く Wish を表現する (DP 側 Int と同 semantics)。
  // mega は MC では未モデル化 (screening 用) なので megaed は false 固定の
  // dummy 配列を用意 (effective_combatant + LeechSeed くさ判定で使う)。
  // Stage H: caller-provided initial weather / field を seed して MC を回す。
  // 既存 default (Weather::None / Field::None + turns=0) 動作は引数省略時に
  // bit-exact 維持される。caller が `Sun` を渡せば、Sun の効果が damage 計算 +
  // greedy 選択 + EOT (Sand chip / Sun heal 倍率) に反映される。`turns=999` の
  // 大きな値で初期化することで、テスト用に DP horizon 内で weather/field が
  // 切れないように引き受ける (DP 側 `b4_state_from_weather` の `999` と同じ
  // 設計)。weather が None / field が None で渡された場合は turns=0 を保ち、
  // EOT tick が weather/field を立てない無害な状態にする。
  let init_weather_turns = if weather.is_active() { 999 } else { 0 }
  let init_field_turns = if field.is_active() { 999 } else { 0 }
  let weather_state : Array[@model.Weather] = [weather]
  let weather_turns_state : Array[Int] = [init_weather_turns]
  let field_state : Array[@model.Field] = [field]
  let field_turns_state : Array[Int] = [init_field_turns]
  let own_leech_seeded : Array[Bool] = Array::make(own.length(), false)
  let opp_leech_seeded : Array[Bool] = Array::make(opp.length(), false)
  // per-side scalar Wish counter (DP 側 `SwitchingGameState.my_wish_turns : Int`
  // と同じ slot-bound 仕様)。Mutability のため 1-element 配列で持つ。
  let own_wish_turns : Array[Int] = [-1]
  let opp_wish_turns : Array[Int] = [-1]
  let own_megaed : Array[Bool] = Array::make(own.length(), false)
  let opp_megaed : Array[Bool] = Array::make(opp.length(), false)
  // Stage 7 (Protean / Libero MC parity): per-slot ロックタイプ。へんげんじざい /
  // リベロ 使用者が初手で撃った技のタイプを記録し、以降の攻撃 STAB / 被弾相性に
  // override で効かせる (DP 側 `SwitchingGameState.{my,opp}_protean_locked` と同じ
  // slot-bound semantics)。"" = 未ロック。switch-out で "" に戻る (once per
  // switch-in)。MC は mega 未モデルなので mega リセットは無い。
  let own_protean_locked : Array[String] = Array::make(own.length(), "")
  let opp_protean_locked : Array[String] = Array::make(opp.length(), "")
  let mut own_active = 0
  let mut opp_active = 0
  for _ in 0..<turn_limit {
    let a_own = greedy_team_action(
      own_active,
      own,
      own_hps,
      own_ranks,
      opp_active,
      opp,
      opp_ranks,
      rng,
      epsilon,
      must_recharge=own_must_recharge[own_active],
      weather=weather_state[0],
      field=field_state[0],
      my_protean_locked=own_protean_locked,
      opp_protean_locked~,
    )
    let a_opp = greedy_team_action(
      opp_active,
      opp,
      opp_hps,
      opp_ranks,
      own_active,
      own,
      own_ranks,
      rng,
      epsilon,
      must_recharge=opp_must_recharge[opp_active],
      weather=weather_state[0],
      field=field_state[0],
      my_protean_locked=opp_protean_locked,
      opp_protean_locked=own_protean_locked,
    )
    match (a_own, a_opp) {
      (None, _) => return -1.0
      (_, None) => return 1.0
      (Some(ao), Some(ap)) => {
        let own_switches = match ao {
          TmSwitch(_) => true
          _ => false
        }
        let opp_switches = match ap {
          TmSwitch(_) => true
          _ => false
        }
        // Capture turn-start active indices + recharge flags. Consumed at
        // turn end only for the *start-of-turn* slot (keyed off the captured
        // index, not the post-switch `*_active`) so a mid-turn switch can't
        // clear a freshly-set flag on the switched-in Pokemon. Mirrors
        // `clear_consumed_recharge` in the DP layer.
        let own_start_active = own_active
        let opp_start_active = opp_active
        let own_start_recharging = own_must_recharge[own_start_active]
        let opp_start_recharging = opp_must_recharge[opp_start_active]
        // Step 1: resolve status-phase attempts for move attempts (switches are
        // always successful and bypass sleep / paralyze). Recharge short-
        // circuits UseMove to `acts=false` regardless of status.
        let mut own_attempt_acts = true
        let mut opp_attempt_acts = true
        match ao {
          TmUseMove(mi) =>
            if own_start_recharging {
              own_attempt_acts = false
            } else {
              let (st, acts) = mc_resolve_attempt(
                own_status[own_active],
                own[own_active].moves[mi].accuracy,
                rng,
              )
              own_status[own_active] = st
              own_attempt_acts = acts
            }
          _ => ()
        }
        match ap {
          TmUseMove(mi) =>
            if opp_start_recharging {
              opp_attempt_acts = false
            } else {
              let (st, acts) = mc_resolve_attempt(
                opp_status[opp_active],
                opp[opp_active].moves[mi].accuracy,
                rng,
              )
              opp_status[opp_active] = st
              opp_attempt_acts = acts
            }
          _ => ()
        }
        // Step 2: apply switches. Reset toxic counter on the switched-out
        // slot. (Switches are never chosen while must_recharge is set, so
        // there is no recharge flag to clear here.) Stage 13: LeechSeed は
        // switched-out slot で剥がれる (mainline: ordinary switch で seed が
        // 消える)。Wish はスロットに残るため触らない (= 受け手は交代後の
        // Pokemon、DP 側 SwitchingGame の Switch arm と同じ semantics)。
        match ao {
          TmSwitch(i) => {
            own_status[own_active] = reset_toxic_counter_on_switch(
              own_status[own_active],
            )
            if own_active < own_leech_seeded.length() {
              own_leech_seeded[own_active] = false
            }
            // Stage 7: switch-out で出ていくスロットの Protean ロックを解除
            // (DP 側 transition_with_cache / partial_act_outcomes の Switch arm と
            // 同 semantics)。leech_seeded と同じ index・同じタイミング。
            if own_active < own_protean_locked.length() {
              own_protean_locked[own_active] = ""
            }
            own_active = i
            reset_ranks(own_ranks)
          }
          _ => ()
        }
        match ap {
          TmSwitch(i) => {
            opp_status[opp_active] = reset_toxic_counter_on_switch(
              opp_status[opp_active],
            )
            if opp_active < opp_leech_seeded.length() {
              opp_leech_seeded[opp_active] = false
            }
            if opp_active < opp_protean_locked.length() {
              opp_protean_locked[opp_active] = ""
            }
            opp_active = i
            reset_ranks(opp_ranks)
          }
          _ => ()
        }
        // Step 3: resolve moves honouring paralysis speed halving and skips.
        if !own_switches && !opp_switches {
          let mi_own = match ao {
            TmUseMove(i) => i
            _ => -1
          }
          let mi_opp = match ap {
            TmUseMove(i) => i
            _ => -1
          }
          let mv_own = own[own_active].moves[mi_own]
          let mv_opp = opp[opp_active].moves[mi_opp]
          let base_spe_own = effective_speed(
            own[own_active].pokemon.spe,
            own_ranks[4],
          )
          let base_spe_opp = effective_speed(
            opp[opp_active].pokemon.spe,
            opp_ranks[4],
          )
          let eff_spe_own = if is_paralyzed(own_status[own_active]) {
            base_spe_own / 2
          } else {
            base_spe_own
          }
          let eff_spe_opp = if is_paralyzed(opp_status[opp_active]) {
            base_spe_opp / 2
          } else {
            base_spe_opp
          }
          let s = turn_order_sign(
            own[own_active],
            mv_own.priority,
            eff_spe_own,
            opp[opp_active],
            mv_opp.priority,
            eff_spe_opp,
          )
          let own_first = if s > 0 {
            true
          } else if s < 0 {
            false
          } else {
            rng.boolean()
          }
          // Pre-first-leg statuses. Captured so the second leg can detect a
          // mid-turn sleep (Spore/Hypnosis) that locks the target out and read
          // the post-first-leg burn (Will-O-Wisp halving physical damage).
          let own_pre_status = own_status[own_active]
          let opp_pre_status = opp_status[opp_active]
          if own_first {
            let mut opp_blocked_mid_turn = false
            // Stage H: Psychic Terrain priority block — own の priority>0 技は
            // grounded な opp に対し無効化 (DP resolve 側 Stage G-3 と一致)。
            if own_attempt_acts &&
              !mc_psychic_priority_blocked(
                mv_own,
                field_state[0],
                opp[opp_active],
              ) {
              let before = opp_hps[opp_active]
              opp_hps[opp_active] = team_perform_attack(
                own[own_active],
                opp[opp_active],
                before,
                mv_own,
                rng,
                own_ranks,
                opp_ranks,
                atk_burn=is_burned(own_pre_status),
                weather=weather_state[0],
                field=field_state[0],
                atk_protean_locked=own_protean_locked[own_active],
                def_protean_locked=opp_protean_locked[opp_active],
              )
              team_apply_post_hit(
                own_hps,
                own_active,
                own_ranks,
                own_must_recharge,
                own_status,
                own_wish_turns,
                own,
                opp_hps,
                opp_active,
                opp_ranks,
                opp_leech_seeded,
                opp,
                opp_megaed,
                weather_state,
                weather_turns_state,
                field_state,
                field_turns_state,
                mv_own,
                before - opp_hps[opp_active],
              )
              record_protean_lock(
                own_protean_locked,
                own_active,
                own[own_active],
                mv_own,
              )
              mc_try_apply_status(
                rng,
                mv_own,
                opp,
                opp_hps,
                opp_status,
                opp_active,
                field=field_state[0],
              )
              if all_ko(own_hps) {
                return -1.0
              }
              if all_ko(opp_hps) {
                return 1.0
              }
              if action_blocked_by_fresh_status(
                  opp_pre_status,
                  opp_status[opp_active],
                ) {
                opp_blocked_mid_turn = true
              }
            }
            if opp_hps[opp_active] > 0 &&
              own_hps[own_active] > 0 &&
              opp_attempt_acts &&
              !opp_blocked_mid_turn &&
              !mc_psychic_priority_blocked(
                mv_opp,
                field_state[0],
                own[own_active],
              ) {
              // Read burn *after* first leg's status fan-out so a fresh burn
              // from own's move halves opp's physical damage this turn.
              let opp_burn_now = is_burned(opp_status[opp_active])
              let before = own_hps[own_active]
              own_hps[own_active] = team_perform_attack(
                opp[opp_active],
                own[own_active],
                before,
                mv_opp,
                rng,
                opp_ranks,
                own_ranks,
                atk_burn=opp_burn_now,
                weather=weather_state[0],
                field=field_state[0],
                atk_protean_locked=opp_protean_locked[opp_active],
                def_protean_locked=own_protean_locked[own_active],
              )
              team_apply_post_hit(
                opp_hps,
                opp_active,
                opp_ranks,
                opp_must_recharge,
                opp_status,
                opp_wish_turns,
                opp,
                own_hps,
                own_active,
                own_ranks,
                own_leech_seeded,
                own,
                own_megaed,
                weather_state,
                weather_turns_state,
                field_state,
                field_turns_state,
                mv_opp,
                before - own_hps[own_active],
              )
              record_protean_lock(
                opp_protean_locked,
                opp_active,
                opp[opp_active],
                mv_opp,
              )
              mc_try_apply_status(
                rng,
                mv_opp,
                own,
                own_hps,
                own_status,
                own_active,
                field=field_state[0],
              )
              if all_ko(own_hps) {
                return -1.0
              }
              if all_ko(opp_hps) {
                return 1.0
              }
            }
          } else {
            let mut own_blocked_mid_turn = false
            // Stage H: Psychic Terrain priority block — opp の priority>0 技は
            // grounded な own に対し無効化 (DP resolve 側 Stage G-3 と一致)。
            if opp_attempt_acts &&
              !mc_psychic_priority_blocked(
                mv_opp,
                field_state[0],
                own[own_active],
              ) {
              let before = own_hps[own_active]
              own_hps[own_active] = team_perform_attack(
                opp[opp_active],
                own[own_active],
                before,
                mv_opp,
                rng,
                opp_ranks,
                own_ranks,
                atk_burn=is_burned(opp_pre_status),
                weather=weather_state[0],
                field=field_state[0],
                atk_protean_locked=opp_protean_locked[opp_active],
                def_protean_locked=own_protean_locked[own_active],
              )
              team_apply_post_hit(
                opp_hps,
                opp_active,
                opp_ranks,
                opp_must_recharge,
                opp_status,
                opp_wish_turns,
                opp,
                own_hps,
                own_active,
                own_ranks,
                own_leech_seeded,
                own,
                own_megaed,
                weather_state,
                weather_turns_state,
                field_state,
                field_turns_state,
                mv_opp,
                before - own_hps[own_active],
              )
              record_protean_lock(
                opp_protean_locked,
                opp_active,
                opp[opp_active],
                mv_opp,
              )
              mc_try_apply_status(
                rng,
                mv_opp,
                own,
                own_hps,
                own_status,
                own_active,
                field=field_state[0],
              )
              if all_ko(own_hps) {
                return -1.0
              }
              if all_ko(opp_hps) {
                return 1.0
              }
              if action_blocked_by_fresh_status(
                  own_pre_status,
                  own_status[own_active],
                ) {
                own_blocked_mid_turn = true
              }
            }
            if own_hps[own_active] > 0 &&
              opp_hps[opp_active] > 0 &&
              own_attempt_acts &&
              !own_blocked_mid_turn &&
              !mc_psychic_priority_blocked(
                mv_own,
                field_state[0],
                opp[opp_active],
              ) {
              let own_burn_now = is_burned(own_status[own_active])
              let before = opp_hps[opp_active]
              opp_hps[opp_active] = team_perform_attack(
                own[own_active],
                opp[opp_active],
                before,
                mv_own,
                rng,
                own_ranks,
                opp_ranks,
                atk_burn=own_burn_now,
                weather=weather_state[0],
                field=field_state[0],
                atk_protean_locked=own_protean_locked[own_active],
                def_protean_locked=opp_protean_locked[opp_active],
              )
              team_apply_post_hit(
                own_hps,
                own_active,
                own_ranks,
                own_must_recharge,
                own_status,
                own_wish_turns,
                own,
                opp_hps,
                opp_active,
                opp_ranks,
                opp_leech_seeded,
                opp,
                opp_megaed,
                weather_state,
                weather_turns_state,
                field_state,
                field_turns_state,
                mv_own,
                before - opp_hps[opp_active],
              )
              record_protean_lock(
                own_protean_locked,
                own_active,
                own[own_active],
                mv_own,
              )
              mc_try_apply_status(
                rng,
                mv_own,
                opp,
                opp_hps,
                opp_status,
                opp_active,
                field=field_state[0],
              )
              if all_ko(own_hps) {
                return -1.0
              }
              if all_ko(opp_hps) {
                return 1.0
              }
            }
          }
        } else if !own_switches {
          let mi_own = match ao {
            TmUseMove(i) => i
            _ => -1
          }
          let mv_own = own[own_active].moves[mi_own]
          let own_burn = is_burned(own_status[own_active])
          // Stage H: Psychic Terrain priority block (DP resolve Stage G-3 と一致)。
          if own_attempt_acts &&
            !mc_psychic_priority_blocked(
              mv_own,
              field_state[0],
              opp[opp_active],
            ) {
            let before = opp_hps[opp_active]
            opp_hps[opp_active] = team_perform_attack(
              own[own_active],
              opp[opp_active],
              before,
              mv_own,
              rng,
              own_ranks,
              opp_ranks,
              atk_burn=own_burn,
              weather=weather_state[0],
              field=field_state[0],
              atk_protean_locked=own_protean_locked[own_active],
              def_protean_locked=opp_protean_locked[opp_active],
            )
            team_apply_post_hit(
              own_hps,
              own_active,
              own_ranks,
              own_must_recharge,
              own_status,
              own_wish_turns,
              own,
              opp_hps,
              opp_active,
              opp_ranks,
              opp_leech_seeded,
              opp,
              opp_megaed,
              weather_state,
              weather_turns_state,
              field_state,
              field_turns_state,
              mv_own,
              before - opp_hps[opp_active],
            )
            record_protean_lock(
              own_protean_locked,
              own_active,
              own[own_active],
              mv_own,
            )
            mc_try_apply_status(
              rng,
              mv_own,
              opp,
              opp_hps,
              opp_status,
              opp_active,
              field=field_state[0],
            )
            if all_ko(own_hps) {
              return -1.0
            }
            if all_ko(opp_hps) {
              return 1.0
            }
          }
        } else if !opp_switches {
          let mi_opp = match ap {
            TmUseMove(i) => i
            _ => -1
          }
          let mv_opp = opp[opp_active].moves[mi_opp]
          let opp_burn = is_burned(opp_status[opp_active])
          // Stage H: Psychic Terrain priority block (DP resolve Stage G-3 と一致)。
          if opp_attempt_acts &&
            !mc_psychic_priority_blocked(
              mv_opp,
              field_state[0],
              own[own_active],
            ) {
            let before = own_hps[own_active]
            own_hps[own_active] = team_perform_attack(
              opp[opp_active],
              own[own_active],
              before,
              mv_opp,
              rng,
              opp_ranks,
              own_ranks,
              atk_burn=opp_burn,
              weather=weather_state[0],
              field=field_state[0],
              atk_protean_locked=opp_protean_locked[opp_active],
              def_protean_locked=own_protean_locked[own_active],
            )
            team_apply_post_hit(
              opp_hps,
              opp_active,
              opp_ranks,
              opp_must_recharge,
              opp_status,
              opp_wish_turns,
              opp,
              own_hps,
              own_active,
              own_ranks,
              own_leech_seeded,
              own,
              own_megaed,
              weather_state,
              weather_turns_state,
              field_state,
              field_turns_state,
              mv_opp,
              before - own_hps[own_active],
            )
            record_protean_lock(
              opp_protean_locked,
              opp_active,
              opp[opp_active],
              mv_opp,
            )
            mc_try_apply_status(
              rng,
              mv_opp,
              own,
              own_hps,
              own_status,
              own_active,
              field=field_state[0],
            )
            if all_ko(own_hps) {
              return -1.0
            }
            if all_ko(opp_hps) {
              return 1.0
            }
          }
        }
        // Clear recharge flag for the slot that entered the turn already
        // recharging — one-turn penalty is paid. Keyed off the captured
        // start-of-turn index so a mid-turn switch + fresh recharge hit
        // on the switched-in slot is not mistakenly cleared.
        if own_start_recharging &&
          own_start_active >= 0 &&
          own_start_active < own_must_recharge.length() {
          own_must_recharge[own_start_active] = false
        }
        if opp_start_recharging &&
          opp_start_active >= 0 &&
          opp_start_active < opp_must_recharge.length() {
          opp_must_recharge[opp_start_active] = false
        }
        // Step 4: end-of-turn — Gen9 公式順序で適用する。DP 側 `apply_eot`
        // (switching_game_effects.mbt) と同じ順序を保つことで、MC と DP の
        // 意味論 parity を保証する。順序:
        //   1. 天候ダメ (Sand chip)
        //   2. アイテム回復 (たべのこし)
        //   3. やどりぎのタネ tick
        //   4. 状態異常 slip
        //   5. ねがいごと発動 (atomic tick + activate)
        //   6. 天候カウンタ tick
        //   7. wish_turns カウンタ tick (Stage 12 SSoT: atomic と組み合わせ済み)
        //
        // DP 側のヘルパー (`apply_sand_damage_active` / `eot_leftovers_heal` /
        // `eot_slip_active` / `add_hp_capped` / `sub_hp_floor0`) を直接呼び、
        // 二重実装の乖離リスクを排除する (= 単一ソース)。
        let own_max = effective_hp(own[own_active])
        let opp_max = effective_hp(opp[opp_active])

        // === Step 4.1: 天候ダメ (Sand chip) ===
        apply_sand_damage_active(
          own_active,
          own_hps,
          own,
          own_megaed,
          own_max,
          weather_state[0],
        )
        apply_sand_damage_active(
          opp_active,
          opp_hps,
          opp,
          opp_megaed,
          opp_max,
          weather_state[0],
        )

        // === Step 4.2: アイテム回復 (たべのこし) ===
        // eot_leftovers_heal は HP<=0 で early return するので、Sand チップで
        // KO されたあとは heal が発火しない (DP 側と整合)。
        own_hps[own_active] = eot_leftovers_heal(
          own_hps[own_active],
          own_max,
          own[own_active].item,
        )
        opp_hps[opp_active] = eot_leftovers_heal(
          opp_hps[opp_active],
          opp_max,
          opp[opp_active].item,
        )

        // === Step 4.2-bis: グラスフィールド回復 (Stage H parity) ===
        // field == Grassy で active が grounded なら HP += max(1, max/16)。
        // leftovers (Step 4.2) の **後**、leech tick (Step 4.3) の **前** に
        // 走る (Gen9 mainline residual order)。DP 側 `apply_eot` Step 2-bis
        // (`apply_grassy_heal_active`) を直接呼び SSoT を共有する。これが無いと
        // ScreenedSwitchingGame の MC screening phase が Grassy 回復を無視し、
        // DP refine phase と payoff が割れる。
        apply_grassy_heal_active(
          own_active,
          own_hps,
          own,
          own_megaed,
          own_max,
          field_state[0],
        )
        apply_grassy_heal_active(
          opp_active,
          opp_hps,
          opp,
          opp_megaed,
          opp_max,
          field_state[0],
        )

        // === Step 4.3: やどりぎのタネ tick ===
        // 種付き側 HP -= max/8、相手 active HP += 同量。Magic Guard は seed
        // 側 tick を完全スキップ (HP 不変 + 相手側加算も 0)。HP<=0 (faint 後) は
        // tick skip (faint 後の二度発火抑止)。my → opp の固定順序で逐次適用。
        let own_seeded = own_active < own_leech_seeded.length() &&
          own_leech_seeded[own_active]
        if own_seeded && own_hps[own_active] > 0 {
          if !ability_blocks_leech_seed(own[own_active].ability) {
            // 種付き側 HP が max/8 未満なら実際に吸えた分しか相手に渡らない
            // (本家挙動: actual drained を基準とし overkill 分を回復に
            // 転用しない)。DP 側 `apply_eot` と同じ semantics。sub / add 両側で
            // 同じ `drained` を渡し、Issue #4 の「HP が空から生まれる」退化を
            // 構造的に防ぐ。
            //
            // ヘドロえき (Liquid Ooze) × Leech Seed: Gen5+ mainline では
            // Liquid Ooze は HP 吸収効果を反転させ、Drain 系技だけでなく
            // Leech Seed の EOT 吸収にも適用される (Showdown 競技標準 +
            // pokedex.db `ability.json` "ヘドロえき" の Sun_Moon 以降のテキスト
            // と一致)。DP 側 `apply_eot` Step 3 と semantics 完全一致。詳細
            // citation は switching_game_effects.mbt の同 step を参照。
            let raw = own_max / 8
            let cur_hp = own_hps[own_active]
            let drained = if cur_hp < raw { cur_hp } else { raw }
            sub_hp_floor0(own_hps, own_active, drained)
            if ability_reverses_drain(own[own_active].ability) {
              sub_hp_floor0(opp_hps, opp_active, drained)
            } else {
              add_hp_capped(opp_hps, opp_active, drained, opp_max)
            }
          }
        }
        let opp_seeded = opp_active < opp_leech_seeded.length() &&
          opp_leech_seeded[opp_active]
        if opp_seeded && opp_hps[opp_active] > 0 {
          if !ability_blocks_leech_seed(opp[opp_active].ability) {
            let raw = opp_max / 8
            let cur_hp = opp_hps[opp_active]
            let drained = if cur_hp < raw { cur_hp } else { raw }
            sub_hp_floor0(opp_hps, opp_active, drained)
            if ability_reverses_drain(opp[opp_active].ability) {
              sub_hp_floor0(own_hps, own_active, drained)
            } else {
              add_hp_capped(own_hps, own_active, drained, own_max)
            }
          }
        }

        // === Step 4.4: 状態異常 slip ===
        // DP 側 `eot_slip_active` を直接呼ぶ (MC ローカル `mc_eot_slip` と
        // semantics 完全一致だが、SSoT 化のため DP 側を共有)。Stage 12 で確立
        // した eot_slip_active を MC でも reuse することで両者の乖離を防ぐ。
        let (new_own_hp, new_own_st) = eot_slip_active(
          own_hps[own_active],
          own_max,
          own_status[own_active],
        )
        own_hps[own_active] = new_own_hp
        own_status[own_active] = new_own_st
        let (new_opp_hp, new_opp_st) = eot_slip_active(
          opp_hps[opp_active],
          opp_max,
          opp_status[opp_active],
        )
        opp_hps[opp_active] = new_opp_hp
        opp_status[opp_active] = new_opp_st

        // === Step 4.5: ねがいごと (Wish) 発動 (atomic tick + activate) ===
        // 共通 helper `tick_and_fire_wish_inplace` に集約 (DP 側 `apply_eot`
        // Step 5 と semantics 一致)。テスト (`_wbtest.mbt`) からも同じ helper
        // を呼んで HP の実加算を直接観測できる。
        tick_and_fire_wish_inplace(own_wish_turns, own_hps, own_active, own)
        tick_and_fire_wish_inplace(opp_wish_turns, opp_hps, opp_active, opp)

        // === Step 4.6: 天候カウンタ tick ===
        // weather_turns_left > 0 ならデクリメント、0 になった瞬間に
        // Weather::None へリセット。Step 4.1 の Sand チップは tick 前の
        // weather を参照するため、「カウンタが 0 になる EOT」も Sand チップは
        // 入る (= 切れる前の最後の Sand チップが成立、本家挙動)。
        if weather_turns_state[0] > 0 {
          let dec = weather_turns_state[0] - 1
          if dec <= 0 {
            weather_state[0] = @model.Weather::None
            weather_turns_state[0] = 0
          } else {
            weather_turns_state[0] = dec
          }
        }

        // === Step 4.7: フィールドカウンタ tick (Stage H) ===
        // weather と完全対称: `field_turns_left > 0` ならデクリメント、0 に
        // なった瞬間に Field::None へリセット。DP 側 `apply_eot` の field tick
        // (switching_game_effects.mbt) と semantics 一致。Step 4.2-bis の Grassy
        // heal は tick **前** の field_state[0] を読むため、heal とリセットの
        // 順序整合は EOT 順序内で確保される (= 切れる前の最後の Grassy 回復が
        // 成立する、本家挙動)。
        if field_turns_state[0] > 0 {
          let dec = field_turns_state[0] - 1
          if dec <= 0 {
            field_state[0] = @model.Field::None
            field_turns_state[0] = 0
          } else {
            field_turns_state[0] = dec
          }
        }

        if all_ko(own_hps) {
          return -1.0
        }
        if all_ko(opp_hps) {
          return 1.0
        }
      }
    }
  }
  // Turn limit hit: return HP ratio difference clamped to [-1, +1].
  let own_ratio = team_hp_ratio(own, own_hps)
  let opp_ratio = team_hp_ratio(opp, opp_hps)
  let v = own_ratio - opp_ratio
  if v > 1.0 {
    1.0
  } else if v < -1.0 {
    -1.0
  } else {
    v
  }
}

///|
/// Aggregate team rollout result over `trials` seeded runs. Returns value in
/// `[-1, +1]`. `trials <= 0` returns `0.0` (neutral prior).
pub fn team_monte_carlo_value(
  own : Array[Combatant],
  opp : Array[Combatant],
  trials : Int,
  seed : UInt64,
  turn_limit? : Int = MC_TURN_LIMIT,
  weather? : @model.Weather = @model.Weather::None,
  field? : @model.Field = @model.Field::None,
) -> Double {
  if trials <= 0 {
    return 0.0
  }
  let rng = seeded_rng(seed)
  let mut total = 0.0
  for _ in 0..<trials {
    total += team_rollout(own, opp, rng, turn_limit~, weather~, field~)
  }
  total / trials.to_double()
}

///|
fn reset_ranks(ranks : Array[Int]) -> Unit {
  for i in 0..<ranks.length() {
    ranks[i] = 0
  }
}

///|
fn all_ko(hps : Array[Int]) -> Bool {
  for h in hps {
    if h > 0 {
      return false
    }
  }
  true
}

///|
/// Sum of `(hp_i / max_hp_i)` divided by team size.
fn team_hp_ratio(team : Array[Combatant], hps : Array[Int]) -> Double {
  let mut total = 0.0
  for i in 0..<team.length() {
    let max_hp = team[i].pokemon.hp
    if max_hp > 0 {
      let h = if hps[i] > 0 { hps[i] } else { 0 }
      total += h.to_double() / max_hp.to_double()
    }
  }
  total / team.length().to_double()
}
