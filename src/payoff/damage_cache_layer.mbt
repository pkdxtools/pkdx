///|
/// Cache key for memoized mean damage. `my_attacker` distinguishes which
/// side's team the attacker/defender indices reference — without it my_team[0]
/// and opp_team[0] would collide. Ranks are stored pre-resolved (already
/// dispatched by move category in `mean_damage_cached`), so the key contains
/// only the values that change the damage output.
pub(all) struct DamageKey {
  my_attacker : Bool
  atk_idx : Int
  def_idx : Int
  mv_idx : Int
  atk_rank : Int
  def_rank : Int
  // Mega form resolved flags. `atk_idx` / `my_attacker` identify the slot, and
  // the slot → mega_form mapping is fixed for a single switching-game run, so
  // 1 bit per side is enough to disambiguate base vs mega stats/type/ability
  // in the cache (no collisions across different mega species).
  atk_mega : Bool
  def_mega : Bool
  // Whether the attacker is burned. Only physical moves are affected (halved),
  // but including the flag for all categories keeps the cache key uniform; the
  // reducer silently no-ops for special / status moves.
  atk_burn : Bool
  // P5 (#97): held-item consumption flags for both sides. When true the
  // mean_damage_cached caller has detected a prior berry / sash trigger
  // and the engine should see `item = ""` instead of the original held
  // item, so resist berries don't double-halve the second hit.
  atk_item_consumed : Bool
  def_item_consumed : Bool
  // Stage B (healing-moves plan): battle weather. Sun / Rain / Sand / Snow
  // produce different damage values for weather-sensitive moves (fire /
  // water 1.5x under Sun / Rain, Snow's Ice-type SpD boost, Sand's Rock
  // SpD boost, WeatherBall typing/power). Without weather in the key,
  // a single matchup cached pre-weather-change would shadow every
  // post-weather-change lookup for the rest of the switching-game run.
  weather : @model.Weather
  // Stage F (healing-moves plan): battle field (terrain). Electric / Grassy
  // / Misty / Psychic field flip damage multipliers for grounded combatants
  // (1.3x on type match, 0.5x on Grassy じしん / Misty ドラゴン). Without
  // field in the key, a matchup cached pre-terrain-change would shadow
  // every post-terrain-change lookup for the rest of the run, silently
  // suppressing the field bonus / debuff.
  field : @model.Field
} derive(Eq, Hash)

///|
/// Memoized mean-damage cache for a single SwitchingGame evaluation. Stores
/// `DamageKey → Int` (mean damage) and tracks hit/miss counts for
/// observability.
///
/// Lifetime is one `switching_game_winrate*` call: teams / abilities / items /
/// stat_system / tera_type are all fixed across the recursion, so the cache
/// stays valid. Reusing the same cache across calls with different teams
/// would be unsound (indices rebind).
pub(all) struct DamageCache {
  data : @hashmap.HashMap[DamageKey, Int]
  // Phase 2-E (#91): variants table cache. Mirrors `data` keyed by the same
  // `DamageKey` shape, but stores the per-variant `DamageOutcome` list so
  // `apply_damage_variants_fanout` can replay the chance-node leaf expansion
  // without re-invoking `@damage.calc_damage`. Decoupled from `data` so the
  // scalar `mean_damage_cached` path (used by Monte Carlo / select / nash
  // graph CLIs) keeps the smaller Int payload while only the in-game tree
  // search pays the larger payload cost.
  variants_data : @hashmap.HashMap[DamageKey, Array[@model.DamageOutcome]]
  // Optional L2 layer backed by SQLite. Populated across sessions — a
  // previous nash solve's 16-roll tables are reused on L1 miss so a
  // slightly-perturbed team doesn't re-pay the damage-engine cost for
  // matchups already seen.
  disk : @damage_cache.DamageDiskCache?
  mut hits : Int
  mut misses : Int
  mut disk_hits : Int
  mut disk_misses : Int
}

///|
/// Construct a fresh L1 damage cache. Pass `disk~=Some(...)` to wire an
/// L2 SQLite-backed layer underneath for cross-session reuse — typical
/// CLI entry points (`pkdx select`, `pkdx meta-divergence`, `pkdx nash
/// graph`) should; tests and short-lived paths leave it defaulted to
/// `None` and the disk is never touched.
pub fn new_damage_cache(
  disk~ : @damage_cache.DamageDiskCache? = None,
) -> DamageCache {
  {
    data: @hashmap.HashMap([]),
    variants_data: @hashmap.HashMap([]),
    disk,
    hits: 0,
    misses: 0,
    disk_hits: 0,
    disk_misses: 0,
  }
}

///|
/// Materialize a `CacheKeyInput` for the L2 cache from the resolved
/// (post-mega) Combatant pair. Matches the CLI `pkdx damage` key schema
/// so disk entries written by the CLI and the payoff layer share
/// identity.
///
/// Completeness argument — every field of `DamageCalcInput` that
/// `compute_mean_damage` feeds into `@damage.calc_damage` is either
/// (a) encoded below, (b) canonicalized to a constant because payoff never
/// varies it, or (c) determined by an encoded field. Mapping by
/// `DamageCalcInput` member:
///
///   * `attacker` / `defender` (`Pokemon`) — keyed by `name_ja`, which is
///     the canonical species+form+mega identifier in pokedex.db (mega
///     variants carry distinct `m.name_ja` via `effective_combatant`, and
///     alt-form rows have distinct Japanese names). Types / base stats /
///     weight therefore follow from the name.
///   * `move_` (`Move`) — keyed by `mv.name`. Move rows are 1:1 with name
///     per version, so power / type / category / accuracy follow.
///   * `atk_ability` / `def_ability` / `atk_item` / `def_item` — encoded.
///   * `weather` / `field` — canonicalized to "": payoff always passes
///     `Weather::None` / `Field::None` via `build_input_with_ranks`.
///   * `tera_type` — encoded (attacker only; `calc_damage` does not read a
///     defender tera, so there is no `def_tera` to encode).
///   * `critical` — always false in payoff (we model expected damage, not
///     crit rolls); canonicalized to false.
///   * `atk_nature` / `def_nature` — encoded as `name_ja`, which uniquely
///     identifies the `Nature` row (name → stat modifiers are 1:1).
///   * `atk_stat_override` / `def_stat_override` / `def_hp_override` —
///     encoded via `build_input_with_ranks`. When these are 0 the engine
///     falls back to `pokemon.base_stat + stat_system`, and both of those
///     are already keyed (species name + `version_str`).
///   * `atk_rank` / `def_rank` — encoded.
///   * `fainted_count` — canonicalized to 0: payoff does not model
///     last-respects / rage-fist.
///   * `is_double` — canonicalized to false: payoff only solves singles.
///   * `stat_system` — encoded via `version_str` ("champions" vs
///     "scarlet_violet"); both arms of the enum produce distinct strings.
///
/// `cache_key_completeness_test.mbt` asserts that toggling every one of
/// these factors (ability, item, tera, ranks, stat overrides, nature, move
/// name, species name, stat_system) changes the key, and that the
/// canonicalized fields are never threaded through.
fn combatant_to_cache_key_input(
  atk : Combatant,
  dfn : Combatant,
  mv : @model.Move,
  atk_rank : Int,
  def_rank : Int,
  weather~ : @model.Weather = @model.Weather::None,
  field~ : @model.Field = @model.Field::None,
) -> @damage_cache.CacheKeyInput {
  let input = build_input_with_ranks(
    atk, dfn, mv, atk_rank, def_rank, weather~, field~,
  )
  let version_str = match atk.stat_system {
    @model.Champions => "champions"
    @model.Standard => "scarlet_violet"
  }
  // Use the canonical Japanese weather labels already stored in pokedex.db
  // (`local_waza_weather`) so L2 disk entries written by `pkdx damage`
  // (which feeds the same labels via the CLI) and by the payoff layer
  // share identity. `Weather::None` collapses to "" so legacy v3 disk
  // entries (pre-Stage B, written under `weather=""`) remain readable for
  // weatherless matchups.
  let weather_str = match weather {
    @model.Weather::None => ""
    @model.Weather::Sun => "はれ"
    @model.Weather::Rain => "あめ"
    @model.Weather::Sand => "すなあらし"
    @model.Weather::Snow => "ゆき"
  }
  // Stage F-4: encode field with the same jp-label shape weather uses so
  // L2 disk entries written by `pkdx damage` and the payoff layer share
  // identity. `Field::None` collapses to "" so pre-Stage-F disk entries
  // (which carried `field=""`) remain readable for terrainless matchups.
  let field_str = field_to_cache_key(field)
  let atk_nature_str = match atk.nature {
    Some(n) => n.name_ja
    None => ""
  }
  let def_nature_str = match dfn.nature {
    Some(n) => n.name_ja
    None => ""
  }
  {
    version: version_str,
    regulation: "",
    attacker: atk.pokemon.name_ja,
    defender: dfn.pokemon.name_ja,
    move_name: mv.name,
    atk_ability: atk.ability,
    def_ability: dfn.ability,
    atk_item: atk.item,
    def_item: dfn.item,
    weather: weather_str,
    field: field_str,
    tera_type: atk.tera_type,
    critical: false,
    is_double: false,
    atk_stat: input.atk_stat_override,
    def_stat: input.def_stat_override,
    def_hp: input.def_hp_override,
    atk_nature: atk_nature_str,
    def_nature: def_nature_str,
    atk_rank,
    def_rank,
    fainted_count: 0,
    // rev2: payoff never varies any of these. Defaults keep pre-rev2 cache
    // semantics for disk entries recomputed under the extended key.
    wall: "",
    screen_pierce: false,
    atk_status: "",
    def_status: "",
    atk_rank_up_count: 0,
    def_rank_up_count: 0,
    atk_hp_num: 0,
    atk_hp_den: 0,
    def_item_removable: false,
    multi_hit_mode: "",
    disguise_active: false,
    incoming_attacker: "",
    incoming_move: "",
    incoming_atk_ability: "",
    incoming_atk_item: "",
    incoming_atk_nature: "",
    incoming_atk_rank: 0,
    incoming_atk_stat: 0,
    incoming_atk_status: "",
    incoming_atk_rank_up_count: 0,
    incoming_atk_hp_num: 0,
    incoming_atk_hp_den: 0,
    incoming_tera_type: "",
    incoming_critical: false,
  }
}

///|
/// L2 lookup / populate for a resolved matchup. Returns the mean damage,
/// burn already applied via `apply_burn_to_mean` so callers never need to
/// re-apply it — this keeps the L1-only and L2-backed paths semantically
/// identical. The L2 stored value remains the raw pre-burn 16-roll table,
/// so one disk entry still serves both burn and non-burn callers.
///
/// #91: must read `variants[]` (not the legacy top-level `damages` field)
/// so the disk-backed scalar matches `compute_mean_damage`'s probability-
/// weighted mean for multi-hit moves. The top-level `damages` is the
/// most-likely variant's roll table — using it would silently regress
/// Triple Axel / Random2to5 / PopulationBomb on every L2 hit. v3 schema
/// already invalidates older rows, so any row reaching this code embeds
/// `variants[]`; absence triggers a recompute rather than a silent
/// fallback to the legacy field.
///
/// Never raises: key-build errors, JSON parse failures, and `put` errors
/// all fall back to a direct compute so an unusable L2 never blocks the
/// actual calculation.
fn mean_damage_via_disk(
  cache : DamageCache,
  attacker : Combatant,
  defender : Combatant,
  mv : @model.Move,
  atk_rank : Int,
  def_rank : Int,
  atk_burn~ : Bool = false,
  atk_ranks_full~ : Array[Int]? = None,
  def_ranks_full~ : Array[Int]? = None,
  weather~ : @model.Weather = @model.Weather::None,
  field~ : @model.Field = @model.Field::None,
) -> Int {
  // 反射技は L2 disk を経由しない。@damage.calc_damage に incoming=None で
  // 渡すと反射 fallback が走り 0 ダメージの JSON が書き込まれてしまうため、
  // この cache key で zero を読み返す経路を恒久的に poison させない。
  // compute_mean_damage は compute_damage_variants 経由で reflect_damage_
  // outcomes に到達し、フル rank 配列を使って Step1 を正しく評価する。
  if @damage.is_reflect_move(mv.name) is Some(_) {
    return compute_mean_damage(
      attacker, defender, mv, atk_rank, def_rank,
      atk_burn=atk_burn,
      atk_ranks_full~,
      def_ranks_full~,
      weather~,
      field~,
    )
  }
  let disk = match cache.disk {
    Some(d) => d
    None =>
      return compute_mean_damage(
        attacker, defender, mv, atk_rank, def_rank, atk_burn=atk_burn,
        weather~,
        field~,
      )
  }
  let key_input = combatant_to_cache_key_input(
    attacker, defender, mv, atk_rank, def_rank, weather~, field~,
  )
  let key = match @damage_cache.build_cache_key(key_input) {
    Ok(k) => k
    Err(_) =>
      return compute_mean_damage(
        attacker, defender, mv, atk_rank, def_rank, atk_burn=atk_burn,
        weather~,
        field~,
      )
  }
  match @damage_cache.get(disk, key) {
    Some(json) =>
      match @damage_cache.parse_variants_from_json(json) {
        Some(parsed) => {
          cache.disk_hits = cache.disk_hits + 1
          weighted_mean_floor(
            outcomes_from_parsed(parsed, mv.category, atk_burn),
          )
        }
        None => {
          // No variants[] (legacy entry that survived the schema bump,
          // or malformed JSON) → recompute and overwrite with v3 payload.
          cache.disk_misses = cache.disk_misses + 1
          compute_and_populate_disk(
            disk, key, attacker, defender, mv, atk_rank, def_rank,
            atk_burn=atk_burn,
            weather~,
            field~,
          )
        }
      }
    None => {
      cache.disk_misses = cache.disk_misses + 1
      compute_and_populate_disk(
        disk, key, attacker, defender, mv, atk_rank, def_rank,
        atk_burn=atk_burn,
        weather~,
        field~,
      )
    }
  }
}

///|
/// Run the damage engine, store the v3 JSON (variants[] embedded) in L2,
/// and return the mean damage with burn applied so the return value
/// matches `compute_mean_damage` exactly — even for multi-hit moves.
///
/// #91: reduce through `r.variants[]` via `outcomes_from_calc_result` +
/// `weighted_mean_floor` (the same pair `compute_damage_variants` /
/// `compute_mean_damage` use) rather than the legacy `r.damages` field
/// which holds only the most-likely variant. Sharing the helper keeps L2
/// populate and read paths bit-identical to the L1 path.
fn compute_and_populate_disk(
  disk : @damage_cache.DamageDiskCache,
  key : String,
  attacker : Combatant,
  defender : Combatant,
  mv : @model.Move,
  atk_rank : Int,
  def_rank : Int,
  atk_burn~ : Bool = false,
  weather~ : @model.Weather = @model.Weather::None,
  field~ : @model.Field = @model.Field::None,
) -> Int {
  let input = build_input_with_ranks(
    attacker, defender, mv, atk_rank, def_rank, weather~, field~,
  )
  let r = @damage.calc_damage(input)
  let json_format = @cli.parse_output_format("json")
  let json = @cli.format_damage(r, input, json_format)
  // put errors are swallowed — they'd just force next invocation to
  // recompute, which is harmless.
  let _ = @damage_cache.put(disk, key, json)
  if r.is_immune {
    return 0
  }
  weighted_mean_floor(outcomes_from_calc_result(r, mv.category, atk_burn))
}

///|
/// Front portion shared by `mean_damage_cached` and `damage_variants_cached`:
/// resolve the raw attacker/defender (with item-consumed swap), bail out on
/// non-damaging moves, dispatch atk_rank / def_rank by move category, and
/// build the DamageKey.
///
/// Returns a 5-tuple instead of an Option to dodge a heap allocation per call
/// on the chance-node hot path. The leading `Bool` is `true` when the caller
/// should short-circuit (mv.power <= 0); the rest of the tuple is filled with
/// usable values regardless so the caller still has the move/raw combatants
/// for any cleanup it does on the early-return path.
fn prepare_damage_lookup(
  my_attacker : Bool,
  atk_idx : Int,
  atk_ranks : Array[Int],
  def_idx : Int,
  def_ranks : Array[Int],
  mv_idx : Int,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  atk_mega : Bool,
  def_mega : Bool,
  atk_burn : Bool,
  atk_item_consumed : Bool,
  def_item_consumed : Bool,
  weather : @model.Weather,
  field : @model.Field,
) -> (Bool, DamageKey, Combatant, Combatant, @model.Move) {
  let raw_attacker_full = if my_attacker {
    my_team[atk_idx]
  } else {
    opp_team[atk_idx]
  }
  let raw_defender_full = if my_attacker {
    opp_team[def_idx]
  } else {
    my_team[def_idx]
  }
  // Swap to itemless combatant copies once a berry / sash has been consumed
  // so the engine doesn't apply the item effect (resist berry halving,
  // choice band Atk x1.5 etc.) a second time.
  let raw_attacker = if atk_item_consumed {
    { ..raw_attacker_full, item: "" }
  } else {
    raw_attacker_full
  }
  let raw_defender = if def_item_consumed {
    { ..raw_defender_full, item: "" }
  } else {
    raw_defender_full
  }
  // Move list is identical across mega / base — read the move from the base
  // combatant so the post-mega synthetic view (which reuses `moves`) is not
  // required here.
  let mv = raw_attacker.moves[mv_idx]
  if mv.power <= 0 {
    let dummy_key : DamageKey = {
      my_attacker,
      atk_idx,
      def_idx,
      mv_idx,
      atk_rank: 0,
      def_rank: 0,
      atk_mega,
      def_mega,
      atk_burn,
      atk_item_consumed,
      def_item_consumed,
      weather,
      field,
    }
    return (true, dummy_key, raw_attacker, raw_defender, mv)
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
  let key : DamageKey = {
    my_attacker,
    atk_idx,
    def_idx,
    mv_idx,
    atk_rank,
    def_rank,
    atk_mega,
    def_mega,
    atk_burn,
    atk_item_consumed,
    def_item_consumed,
    weather,
    field,
  }
  (false, key, raw_attacker, raw_defender, mv)
}

///|
/// Cached mean-damage lookup. `my_attacker = true` means the attacker is in
/// `my_team` (and defender in `opp_team`); swap otherwise. `atk_ranks` /
/// `def_ranks` are the 5-slot rank vectors of the attacker / defender side
/// respectively. Public so external tests can observe cache counters.
pub fn mean_damage_cached(
  cache : DamageCache,
  my_attacker : Bool,
  atk_idx : Int,
  atk_ranks : Array[Int],
  def_idx : Int,
  def_ranks : Array[Int],
  mv_idx : Int,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  atk_mega~ : Bool = false,
  def_mega~ : Bool = false,
  atk_burn~ : Bool = false,
  atk_item_consumed~ : Bool = false,
  def_item_consumed~ : Bool = false,
  weather~ : @model.Weather = @model.Weather::None,
  field~ : @model.Field = @model.Field::None,
) -> Int {
  let (early, key, raw_attacker, raw_defender, mv) = prepare_damage_lookup(
    my_attacker,
    atk_idx,
    atk_ranks,
    def_idx,
    def_ranks,
    mv_idx,
    my_team,
    opp_team,
    atk_mega,
    def_mega,
    atk_burn,
    atk_item_consumed,
    def_item_consumed,
    weather,
    field,
  )
  if early {
    return 0
  }
  match cache.data.get(key) {
    Some(v) => {
      cache.hits = cache.hits + 1
      v
    }
    None => {
      cache.misses = cache.misses + 1
      let attacker = effective_combatant(raw_attacker, atk_mega)
      let defender = effective_combatant(raw_defender, def_mega)
      // Both branches reduce through `apply_burn_to_mean`, so the L2-backed
      // path is guaranteed bit-identical to the L1-only path for the same
      // matchup — the disk still stores only pre-burn 16-roll tables.
      let v = match cache.disk {
        Some(_) =>
          mean_damage_via_disk(
            cache,
            attacker,
            defender,
            mv,
            key.atk_rank,
            key.def_rank,
            atk_burn=atk_burn,
            atk_ranks_full=Some(atk_ranks),
            def_ranks_full=Some(def_ranks),
            weather~,
            field~,
          )
        None =>
          compute_mean_damage(
            attacker,
            defender,
            mv,
            key.atk_rank,
            key.def_rank,
            atk_burn=atk_burn,
            atk_ranks_full=Some(atk_ranks),
            def_ranks_full=Some(def_ranks),
            weather~,
            field~,
          )
      }
      cache.data[key] = v
      v
    }
  }
}

///|
/// Phase 2-E (#91): variants-table cache wrapper, mirroring
/// `mean_damage_cached`'s key shape. Returns the per-variant
/// `Array[DamageOutcome]` for the resolved matchup. Used by attack sites
/// (resolve_attacker_leg / transition_with_cache attack arms /
/// partial_act_outcomes) so the chance-node leaf expansion done by
/// `apply_damage_variants_fanout` reuses the engine's variant table
/// rather than recomputing it every recursion.
///
/// Key shape is identical to `mean_damage_cached` so the two caches stay
/// in lockstep — the same `DamageKey` resolves to a scalar mean in
/// `cache.data` and a variants list in `cache.variants_data`. Hit/miss
/// counters share with the scalar cache (the call site is unique per
/// (matchup, mv_idx, ranks, mega, burn, item_consumed) tuple).
fn damage_variants_cached(
  cache : DamageCache,
  my_attacker : Bool,
  atk_idx : Int,
  atk_ranks : Array[Int],
  def_idx : Int,
  def_ranks : Array[Int],
  mv_idx : Int,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  atk_mega~ : Bool = false,
  def_mega~ : Bool = false,
  atk_burn~ : Bool = false,
  atk_item_consumed~ : Bool = false,
  def_item_consumed~ : Bool = false,
  weather~ : @model.Weather = @model.Weather::None,
  field~ : @model.Field = @model.Field::None,
) -> Array[@model.DamageOutcome] {
  let (early, key, raw_attacker, raw_defender, mv) = prepare_damage_lookup(
    my_attacker,
    atk_idx,
    atk_ranks,
    def_idx,
    def_ranks,
    mv_idx,
    my_team,
    opp_team,
    atk_mega,
    def_mega,
    atk_burn,
    atk_item_consumed,
    def_item_consumed,
    weather,
    field,
  )
  if early {
    return [{ probability: 1.0, mean_damage: 0, hits_count: 1, hit_steps: [] }]
  }
  match cache.variants_data.get(key) {
    Some(v) => {
      cache.hits = cache.hits + 1
      v
    }
    None => {
      cache.misses = cache.misses + 1
      let attacker = effective_combatant(raw_attacker, atk_mega)
      let defender = effective_combatant(raw_defender, def_mega)
      let v = compute_damage_variants(
        attacker,
        defender,
        mv,
        key.atk_rank,
        key.def_rank,
        atk_burn=atk_burn,
        atk_ranks_full=Some(atk_ranks),
        def_ranks_full=Some(def_ranks),
        weather~,
        field~,
      )
      cache.variants_data[key] = v
      // Touch the L2 disk cache so cross-session damage entries stay
      // populated. The disk payload is the engine's pre-burn 16-roll
      // table (scalar), reused by mean_damage_cached callers (Monte
      // Carlo / select / nash graph). Variants serialisation to disk
      // is deferred — see open question on hit_steps fallback. Reflect
      // moves are short-circuited inside `mean_damage_via_disk` so the
      // L2 entry is never populated with the engine's zero fallback.
      match cache.disk {
        Some(_) => {
          let _ = mean_damage_via_disk(
            cache,
            attacker,
            defender,
            mv,
            key.atk_rank,
            key.def_rank,
            atk_burn=atk_burn,
            atk_ranks_full=Some(atk_ranks),
            def_ranks_full=Some(def_ranks),
            weather~,
            field~,
          )
        }
        None => ()
      }
      v
    }
  }
}

///|
/// Stage F-4: convert a `Field` enum to the L2 cache jp label, mirroring
/// the inline weather → jp label match in `combatant_to_cache_key_input`.
/// Centralized as a helper so the CLI / payoff / tests share the same
/// encoding. `Field::None` collapses to "" so disk entries written before
/// Stage F (which carried `field=""`) remain readable for terrainless
/// matchups.
pub fn field_to_cache_key(field : @model.Field) -> String {
  match field {
    @model.Field::None => ""
    @model.Field::Electric => "エレキ"
    @model.Field::Grassy => "グラス"
    @model.Field::Misty => "ミスト"
    @model.Field::Psychic => "サイコ"
  }
}
