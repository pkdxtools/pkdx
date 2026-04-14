///|
/// Move metadata consumed by the payoff layer (SwitchingGame / MonteCarloSim).
///
/// The canonical source is the `move_meta` table installed by
/// `pkdx_patch/006_move_meta` — queried once at payoff entry via
/// `db.query_move_meta` and cached in a `MoveMetaCache`. The hardcoded
/// curated table in this module (`move_priority_fallback` /
/// `stat_boost_effect_fallback`) exists only as a fallback for moves the DB
/// does not yet have. Production reads should go through `lookup_priority`
/// and `lookup_stat_effects`, which consult the cache first and fall back to
/// the curated table.
///
/// Stat indices used throughout the module (matches the order inside
/// `my_ranks` / `opp_ranks` in `SwitchingGameState`):
///
/// - 0: Attack (A)
/// - 1: Defense (B)
/// - 2: Special Attack (C)
/// - 3: Special Defense (D)
/// - 4: Speed (S)

///|
/// Parsed metadata for a single move. `priority` is the in-game priority
/// bucket; `stat_effects` is the list of `(stat_index, delta)` pairs the
/// move applies to its user on hit.
pub(all) struct MoveMeta {
  priority : Int
  stat_effects : Array[(Int, Int)]
} derive(Show, Eq)

///|
/// Run-scoped cache of move metadata. Populated at payoff entry via
/// `load_move_meta_from_rows` (DB path) or left empty (fallback-only path).
/// Lookups on a miss fall back to the curated table below.
pub(all) struct MoveMetaCache {
  data : @hashmap.HashMap[String, MoveMeta]
  mut hits : Int
  mut misses : Int
  mut fallbacks : Int
}

///|
pub fn new_move_meta_cache() -> MoveMetaCache {
  { data: @hashmap.HashMap::new(), hits: 0, misses: 0, fallbacks: 0 }
}

///|
/// Populate a cache from `(name, priority, stat_effects_json)` tuples as
/// returned by `db.query_move_meta`. `stat_effects_json` is parsed here
/// (the db module stays JSON-agnostic). Rows whose JSON is malformed are
/// silently treated as empty-effect entries so one bad entry does not break
/// a whole run; callers can inspect `cache.data` if they need strict
/// parsing.
pub fn load_move_meta_from_rows(
  cache : MoveMetaCache,
  rows : Array[(String, Int, String)],
) -> Unit {
  for row in rows {
    let (name, priority, effects_json) = row
    let effects = parse_stat_effects_json(effects_json)
    cache.data[name] = { priority, stat_effects: effects }
  }
}

///|
/// Parse a JSON-encoded array of `[stat, delta]` pairs (e.g. `"[[0,2]]"`)
/// into an `Array[(Int, Int)]`. Returns `[]` on any parse error or
/// non-conforming shape — the caller is responsible for treating
/// fallback-identical behaviour as non-fatal.
fn parse_stat_effects_json(raw : String) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let json = try @json.parse(raw) catch {
    _ => return out
  }
  match json {
    Array(arr) =>
      for item in arr {
        match item {
          Array(pair) =>
            if pair.length() == 2 {
              let a = json_to_int(pair[0])
              let b = json_to_int(pair[1])
              match (a, b) {
                (Some(ai), Some(bi)) => out.push((ai, bi))
                _ => ()
              }
            }
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
fn json_to_int(j : Json) -> Int? {
  match j {
    Number(n, ..) => Some(n.to_int())
    _ => None
  }
}

///|
/// Look up a move's priority, preferring the DB-sourced cache and falling
/// back to the curated table for unknown names. Updates `cache.hits` /
/// `cache.misses` / `cache.fallbacks` so callers (tests, diagnostics) can
/// verify DB coverage.
pub fn lookup_priority(cache : MoveMetaCache, name : String) -> Int {
  match cache.data.get(name) {
    Some(m) => {
      cache.hits = cache.hits + 1
      m.priority
    }
    None => {
      cache.misses = cache.misses + 1
      let p = move_priority_fallback(name)
      if p != 0 {
        cache.fallbacks = cache.fallbacks + 1
      }
      p
    }
  }
}

///|
/// Look up a move's self stat-boost effects from the DB-sourced cache,
/// falling back to the curated table. Returns an empty array for moves
/// that have no effect (damaging moves, unrecognised names).
pub fn lookup_stat_effects(
  cache : MoveMetaCache,
  name : String,
) -> Array[(Int, Int)] {
  match cache.data.get(name) {
    Some(m) => {
      cache.hits = cache.hits + 1
      m.stat_effects
    }
    None => {
      cache.misses = cache.misses + 1
      match stat_boost_effect_fallback(name) {
        Some(effs) => {
          cache.fallbacks = cache.fallbacks + 1
          effs
        }
        None => []
      }
    }
  }
}

///|
/// Curated fallback for `lookup_priority`. Retained for offline runs where
/// the `move_meta` table has not yet been installed (older DB snapshots,
/// tests bypassing the DB). Prefer `lookup_priority` in production paths.
pub fn move_priority_fallback(name : String) -> Int {
  match name {
    "しんそく" | "ファーストブラッド" => 2
    "バレットパンチ"
    | "こおりのつぶて"
    | "アクアジェット"
    | "かげうち"
    | "マッハパンチ"
    | "みずしゅりけん"
    | "でんこうせっか"
    | "しんくうは"
    | "ふいうち" => 1
    "ねこだまし" | "ファストガード" => 3
    "まもる" | "みきり" => 4
    _ => 0
  }
}

///|
/// Curated fallback for `lookup_stat_effects`. Retained for offline runs.
pub fn stat_boost_effect_fallback(name : String) -> Array[(Int, Int)]? {
  match name {
    "つるぎのまい" => Some([(0, 2)])
    "りゅうのまい" => Some([(0, 1), (4, 1)])
    "めいそう" => Some([(2, 1), (3, 1)])
    "わるだくみ" => Some([(2, 2)])
    "てっぺき" | "バリアー" => Some([(1, 2)])
    "ちょうのまい" => Some([(2, 1), (3, 1), (4, 1)])
    "からをやぶる" => Some([(0, 2), (2, 2), (4, 2), (1, -1), (3, -1)])
    "ロックカット" | "こうそくいどう" | "アジリティ" => Some([(4, 2)])
    "ビルドアップ" => Some([(0, 1), (1, 1)])
    _ => None
  }
}

///|
/// Deprecated: use `lookup_priority(cache, name)` instead. Retained for
/// callers that do not yet thread a `MoveMetaCache` through (tests, old
/// entry points). Equivalent to consulting only the curated fallback.
pub fn move_priority(name : String) -> Int {
  move_priority_fallback(name)
}

///|
/// Deprecated: use `lookup_stat_effects(cache, name)` instead. Retained as
/// a fallback-only convenience.
pub fn stat_boost_effect(name : String) -> Array[(Int, Int)]? {
  stat_boost_effect_fallback(name)
}

///|
/// Collect unique move names across two teams' combatants. Feeds
/// `db.query_move_meta` so that the cache is populated for every move that
/// can possibly be used during the run.
pub fn collect_move_names(
  team_a : Array[Combatant],
  team_b : Array[Combatant],
) -> Array[String] {
  let seen : @hashmap.HashMap[String, Bool] = @hashmap.HashMap::new()
  let out : Array[String] = []
  for c in team_a {
    for mv in c.moves {
      match seen.get(mv.name) {
        Some(_) => ()
        None => {
          seen[mv.name] = true
          out.push(mv.name)
        }
      }
    }
  }
  for c in team_b {
    for mv in c.moves {
      match seen.get(mv.name) {
        Some(_) => ()
        None => {
          seen[mv.name] = true
          out.push(mv.name)
        }
      }
    }
  }
  out
}

///|
/// Clamp a stat rank delta-sum into the payoff layer's reduced range
/// `[-2, +2]`. Abstracting the clamp here keeps `transition` readable and
/// ensures the same rounding rule is applied in every call site.
pub fn clamp_rank(r : Int) -> Int {
  if r > 2 {
    2
  } else if r < -2 {
    -2
  } else {
    r
  }
}

///|
/// Compare two combatants' turn order accounting for move priority. Returns
/// `+1` if `a` acts before `b`, `-1` if after, `0` on a full tie. Priority
/// dominates; speed is the tie-breaker (matches in-game rules).
pub fn turn_order_sign(
  a : Combatant,
  prio_a : Int,
  a_spe : Int,
  b : Combatant,
  prio_b : Int,
  b_spe : Int,
) -> Int {
  // `a` and `b` are kept in the signature for future extensions (ability-
  // based priority, e.g. プレッシャー / いたずらごころ). Currently unused
  // beyond the speed values the caller already resolved.
  let _ = a
  let _ = b
  if prio_a > prio_b {
    1
  } else if prio_a < prio_b {
    -1
  } else if a_spe > b_spe {
    1
  } else if a_spe < b_spe {
    -1
  } else {
    0
  }
}

///|
/// Effective speed of a combatant given a Speed rank `s_rank ∈ [-6, +6]`
/// (caller should already clamp to `[-2, +2]` for payoff-layer states).
/// Matches the in-game stage multiplier for non-HP stats: positive stages
/// scale by `(2 + s)/2`, negative by `2/(2 + |s|)`.
pub fn effective_speed(base_spe : Int, s_rank : Int) -> Int {
  if s_rank >= 0 {
    base_spe * (2 + s_rank) / 2
  } else {
    base_spe * 2 / (2 + -s_rank)
  }
}
