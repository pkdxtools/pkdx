///|
/// Handler logic for `pkdx select` — the selection-optimisation command.
///
/// Input JSON schema (simplified team-cache shape):
/// ```
/// {
///   "team":     [<combatant>, ...],
///   "opponent": [<combatant>, ...],
///   "format":   "single" | "double",
///   "stat_system": "champions" | "standard",  // default: "champions"
///   "team_payoff_model": "switching_game" | "screened_switching_game:..."
/// }
///
/// <combatant> = {
///   "name":    String,
///   "type1":   String, "type2": String,
///   "hp":      Int, "atk":  Int, "def": Int,
///   "spa":     Int, "spd":  Int, "spe": Int,
///   "ability": String, "item": String, "tera": String,
///   "mega_form": {"atk":Int, "def":Int, "spa":Int, "spd":Int, "spe":Int,
///                 "type1":String, "type2":String, "ability":String,
///                 "name_ja":String}?,  // optional; present if mega-capable
///   "moves":   [{"name":..., "type":..., "category":"物理"|"特殊"|"変化",
///                "power":Int, "priority":Int?, "stat_effects":[[Int,Int], ...]?}, ...]
/// }
/// ```
///
/// Output JSON schema:
/// ```
/// {
///   "format": String,
///   "value":  Double,
///   "exploitability": Double,
///   "selections": [
///     {"indices": [Int], "names": [String], "probability": Double}, ...
///   ],
///   "opponent_selections": [...]
/// }
/// ```

///|
fn parse_move_json(j : Json, ctx : String) -> @model.Move raise NashCliError {
  match j {
    Object(m) => {
      let name = match m.get("name") {
        Some(x) => json_string(x, ctx + ".name")
        None => raise MissingField(ctx + ".name")
      }
      let type_ = match m.get("type") {
        Some(x) => json_string(x, ctx + ".type")
        None => ""
      }
      let category = match m.get("category") {
        Some(String(s)) => @model.category_from_jp(s)
        _ => @model.Physical
      }
      let power = match m.get("power") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let priority = match m.get("priority") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let stat_effects = match m.get("stat_effects") {
        Some(Array(arr)) => parse_stat_effects_array(arr)
        _ => []
      }
      let accuracy = match m.get("accuracy") {
        Some(Number(n, ..)) => n.to_int()
        _ => 100
      }
      let status_effect = match m.get("status_effect") {
        Some(Object(se)) => parse_status_effect_object(se)
        _ => None
      }
      let recoil_num = match m.get("recoil_num") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let recoil_den = match m.get("recoil_den") {
        Some(Number(n, ..)) => {
          let v = n.to_int()
          // Guard against zero denominator upstream; treat as no-recoil.
          if v <= 0 { 1 } else { v }
        }
        _ => 1
      }
      let self_ko = match m.get("self_ko") {
        Some(True) => true
        _ => false
      }
      let recharge = match m.get("recharge") {
        Some(True) => true
        _ => false
      }
      {
        name,
        type_,
        category,
        power,
        accuracy,
        pp: 10,
        learn_method: "",
        priority,
        stat_effects,
        status_effect,
        recoil_num,
        recoil_den,
        self_ko,
        recharge,
      }
    }
    _ => raise InvalidJson(ctx + " must be an object")
  }
}

///|
/// Parse `{"kind": "まひ" | "やけど" | ...,"chance": 100}` into a
/// `(StatusKind, Int)` tuple. Missing or unknown kind yields `None`; a
/// missing `chance` defaults to 100.
fn parse_status_effect_object(
  m : Map[String, Json],
) -> (@model.StatusKind, Int)? {
  let kind = match m.get("kind") {
    Some(String(s)) => @model.status_kind_from_jp(s)
    _ => None
  }
  match kind {
    None => None
    Some(k) => {
      let chance = match m.get("chance") {
        Some(Number(n, ..)) => n.to_int()
        _ => 100
      }
      Some((k, chance))
    }
  }
}

///|
/// Parse a JSON array of stat-effect entries. Accepts two shapes so existing
/// `pkdx moves` output keeps working while the new 3-element form flows
/// through:
///
/// - 2-element `[stat, delta]` — legacy; `target` defaults to `0` (self)
/// - 3-element `[stat, delta, target]` — `target` 0=self, 1=opp
///
/// Non-conforming entries (wrong arity, non-numeric members) are silently
/// skipped; a malformed JSON that still parsed as an Array yields an empty
/// effect list rather than raising.
fn parse_stat_effects_array(arr : Array[Json]) -> Array[@model.StatEffect] {
  let out : Array[@model.StatEffect] = []
  for item in arr {
    match item {
      Array(triple) => {
        let len = triple.length()
        if len == 2 || len == 3 {
          let a = match triple[0] {
            Number(n, ..) => Some(n.to_int())
            _ => None
          }
          let b = match triple[1] {
            Number(n, ..) => Some(n.to_int())
            _ => None
          }
          let t = if len == 3 {
            match triple[2] {
              Number(n, ..) => n.to_int()
              _ => 0
            }
          } else {
            0
          }
          match (a, b) {
            (Some(ai), Some(bi)) =>
              out.push(@model.StatEffect::{ stat: ai, delta: bi, target: t })
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  out
}

///|
fn parse_int_field(
  m : Map[String, Json],
  key : String,
  ctx : String,
) -> Int raise NashCliError {
  match m.get(key) {
    Some(Number(n, ..)) => n.to_int()
    Some(_) => raise InvalidJson(ctx + "." + key + " must be a number")
    None => raise MissingField(ctx + "." + key)
  }
}

///|
fn parse_str_field(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn parse_int_field_or(
  m : Map[String, Json],
  key : String,
  default : Int,
) -> Int {
  match m.get(key) {
    Some(Number(n, ..)) => n.to_int()
    _ => default
  }
}

///|
fn parse_types_field(m : Map[String, Json]) -> (String, String) {
  match m.get("types") {
    Some(Array(arr)) => {
      let t1 = match arr.get(0) {
        Some(String(s)) => s
        _ => ""
      }
      let t2 = match arr.get(1) {
        Some(String(s)) => s
        _ => ""
      }
      (t1, t2)
    }
    _ => (parse_str_field(m, "type1"), parse_str_field(m, "type2"))
  }
}

///|
fn parse_stats_fields(
  m : Map[String, Json],
  ctx : String,
) -> (Int, Int, Int, Int, Int, Int) raise NashCliError {
  match m.get("base_stats") {
    Some(Object(bs)) => (
      parse_int_field_or(bs, "h", 0),
      parse_int_field_or(bs, "a", 0),
      parse_int_field_or(bs, "b", 0),
      parse_int_field_or(bs, "c", 0),
      parse_int_field_or(bs, "d", 0),
      parse_int_field_or(bs, "s", 0),
    )
    _ =>
      match m.get("hp") {
        Some(_) => (
          parse_int_field(m, "hp", ctx),
          parse_int_field(m, "atk", ctx),
          parse_int_field(m, "def", ctx),
          parse_int_field(m, "spa", ctx),
          parse_int_field(m, "spd", ctx),
          parse_int_field(m, "spe", ctx),
        )
        None =>
          raise MissingField(
            ctx + ": either 'hp/atk/def/spa/spd/spe' or 'base_stats' required",
          )
      }
  }
}

///|
fn parse_combatant_json(
  j : Json,
  ctx : String,
  stat_system? : @model.StatSystem = @model.Champions,
) -> Combatant raise NashCliError {
  match j {
    Object(m) => {
      let name = match m.get("name") {
        Some(String(s)) => s
        _ => raise MissingField(ctx + ".name")
      }
      let (type1, type2) = parse_types_field(m)
      let (hp, atk, def_, spa, spd, spe) = parse_stats_fields(m, ctx)
      let poke : @model.Pokemon = {
        global_no: "0000",
        name_ja: name,
        name_en: name,
        type1,
        type2,
        hp,
        atk,
        def_,
        spa,
        spd,
        spe,
        bst: hp + atk + def_ + spa + spd + spe,
        ability1: "",
        ability2: "",
        dream_ability: "",
        weight: 0.0,
      }
      let moves : Array[@model.Move] = match m.get("moves") {
        Some(Array(arr)) => {
          let out = Array::make(arr.length(), @model.Move::{
            name: "",
            type_: "",
            category: @model.Physical,
            power: 0,
            accuracy: 100,
            pp: 10,
            learn_method: "",
            priority: 0,
            stat_effects: [],
            status_effect: None,
            recoil_num: 0,
            recoil_den: 1,
            self_ko: false,
            recharge: false,
          })
          for i in 0..<arr.length() {
            out[i] = parse_move_json(
              arr[i], ctx + ".moves[" + i.to_string() + "]",
            )
          }
          out
        }
        _ => raise MissingField(ctx + ".moves")
      }
      let mega_form = match m.get("mega_form") {
        Some(mj) => Some(parse_mega_form_json(mj, ctx + ".mega_form"))
        None => None
      }
      {
        pokemon: poke,
        moves,
        ability: parse_str_field(m, "ability"),
        item: parse_str_field(m, "item"),
        tera_type: parse_str_field(m, "tera"),
        stat_system,
        mega_form,
      }
    }
    _ => raise InvalidJson(ctx + " must be an object")
  }
}

///|
/// Parse the optional `mega_form` object attached to a combatant JSON. Fields
/// mirror `@model.MegaForm`: post-mega atk/def/spa/spd/spe + type1/type2 +
/// ability. `hp` is intentionally not carried because mega evolution does not
/// change HP (max or current).
fn parse_mega_form_json(
  j : Json,
  ctx : String,
) -> @model.MegaForm raise NashCliError {
  match j {
    Object(m) => {
      let atk = parse_int_field(m, "atk", ctx)
      let def_ = parse_int_field(m, "def", ctx)
      let spa = parse_int_field(m, "spa", ctx)
      let spd = parse_int_field(m, "spd", ctx)
      let spe = parse_int_field(m, "spe", ctx)
      let type1 = parse_str_field(m, "type1")
      let type2 = parse_str_field(m, "type2")
      let ability = parse_str_field(m, "ability")
      let name_ja = parse_str_field(m, "name_ja")
      { atk, def_, spa, spd, spe, type1, type2, ability, name_ja }
    }
    _ => raise InvalidJson(ctx + " must be an object")
  }
}

///|
pub fn parse_team_array(
  j : Json,
  ctx : String,
  stat_system? : @model.StatSystem = @model.Champions,
) -> Array[Combatant] raise NashCliError {
  match j {
    Array(arr) => {
      let out = Array::make(arr.length(), mk_empty_combatant())
      for i in 0..<arr.length() {
        out[i] = parse_combatant_json(
          arr[i], ctx + "[" + i.to_string() + "]",
          stat_system=stat_system,
        )
      }
      out
    }
    _ => raise InvalidJson(ctx + " must be an array")
  }
}

///|
fn mk_empty_combatant() -> Combatant {
  {
    pokemon: {
      global_no: "0000",
      name_ja: "",
      name_en: "",
      type1: "",
      type2: "",
      hp: 0,
      atk: 0,
      def_: 0,
      spa: 0,
      spd: 0,
      spe: 0,
      bst: 0,
      ability1: "",
      ability2: "",
      dream_ability: "",
      weight: 0.0,
    },
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Champions,
    mega_form: None,
  }
}

///|
fn parse_format(s : String) -> BattleFormat raise NashCliError {
  match s {
    "single" => Single
    "double" => Double
    _ => raise InvalidJson("format must be 'single' or 'double'")
  }
}

///|
/// Parse `team_payoff_model` string:
/// - `"switching_game"` → `SwitchingGame` (turn_limit = `DP_TURN_LIMIT`)
/// - `"screened_switching_game:<trials>:<seed>:<keep_top>"` → `ScreenedSwitchingGame`
///   (MC turn_limit = `MC_TURN_LIMIT`, refine turn_limit = `DP_TURN_LIMIT`)
fn parse_team_payoff_model(s : String) -> TeamPayoffModel raise NashCliError {
  if s == "switching_game" {
    return SwitchingGame(DP_TURN_LIMIT)
  }
  match s.strip_prefix("switching_game:") {
    Some(rest) => {
      let turn_limit = try @strconv.parse_int(rest.to_string()) catch {
        _ =>
          raise InvalidJson(
            "switching_game turn_limit must be a positive integer",
          )
      }
      if turn_limit <= 0 {
        raise InvalidJson(
          "switching_game turn_limit must be a positive integer",
        )
      }
      return SwitchingGame(turn_limit)
    }
    None => ()
  }
  match s.strip_prefix("screened_switching_game:") {
    Some(rest) => parse_screened_spec(rest.to_string())
    None =>
      raise InvalidJson(
        "team_payoff_model must be 'switching_game' or 'screened_switching_game:<trials>:<seed>:<keep_top>'",
      )
  }
}

///|
/// Parse `"<trials>:<seed>:<keep_top>"` or `"<trials>:<seed>:<keep_top>:<turn_limit>"`
/// into a `ScreenedSwitchingGame` variant. When `turn_limit` is omitted,
/// `DP_TURN_LIMIT` is used. Enforces `trials > 0` and `0 < keep_top <= 1`.
fn parse_screened_spec(rest : String) -> TeamPayoffModel raise NashCliError {
  let (trials_str, after_trials) = match rest.split_once(":") {
    Some((a, b)) => (a.to_string(), b.to_string())
    None =>
      raise InvalidJson(
        "screened_switching_game must be 'screened_switching_game:<trials>:<seed>:<keep_top>'",
      )
  }
  let (seed_str, keep_top_and_maybe_tl) = match after_trials.view().split_once(":") {
    Some((a, b)) => (a.to_string(), b.to_string())
    None =>
      raise InvalidJson(
        "screened_switching_game must be 'screened_switching_game:<trials>:<seed>:<keep_top>'",
      )
  }
  let (keep_top_str, opt_tl_str) = match keep_top_and_maybe_tl.view().split_once(":") {
    Some((a, b)) => (a.to_string(), Some(b.to_string()))
    None => (keep_top_and_maybe_tl, None)
  }
  let trials = try @strconv.parse_int(trials_str) catch {
    _ =>
      raise InvalidJson("screened_switching_game trials must be a positive integer")
  }
  if trials <= 0 {
    raise InvalidJson("screened_switching_game trials must be a positive integer")
  }
  let seed = try @strconv.parse_uint64(seed_str) catch {
    _ => raise InvalidJson("screened_switching_game seed must be a UInt64 literal")
  }
  let keep_top = try @strconv.parse_double(keep_top_str) catch {
    _ =>
      raise InvalidJson(
        "screened_switching_game keep_top_quantile must be a number in (0, 1]",
      )
  }
  if keep_top <= 0.0 || keep_top > 1.0 {
    raise InvalidJson(
      "screened_switching_game keep_top_quantile must be in (0, 1]",
    )
  }
  let refine_tl = match opt_tl_str {
    Some(s) => {
      let tl = try @strconv.parse_int(s) catch {
        _ =>
          raise InvalidJson(
            "screened_switching_game turn_limit must be a positive integer",
          )
      }
      if tl <= 0 {
        raise InvalidJson(
          "screened_switching_game turn_limit must be a positive integer",
        )
      }
      tl
    }
    None => DP_TURN_LIMIT
  }
  ScreenedSwitchingGame(trials, seed, keep_top, refine_tl)
}

///|
/// `SwitchingGame(N)` で N が閾値以上なら `ScreenedSwitchingGame` に自動昇格する。
/// ユーザーが `screened_switching_game:...` を明示したケースは match されず
/// そのまま通る。閾値・既定 MC パラメータは `semantics.mbt` の定数に集約。
fn auto_upgrade_team_model(m : TeamPayoffModel) -> TeamPayoffModel {
  match m {
    SwitchingGame(n) if n >= AUTO_SCREEN_TURN_LIMIT =>
      ScreenedSwitchingGame(
        AUTO_SCREEN_TRIALS, AUTO_SCREEN_SEED, AUTO_SCREEN_KEEP_TOP, n,
      )
    _ => m
  }
}

///|
/// Selection result: distribution over k-selections for both sides, plus
/// game value and exploitability.
pub(all) struct SelectResult {
  format : BattleFormat
  value : Double
  exploitability : Double
  team_size : Int
  opp_size : Int
  selections : Array[Array[Int]]
  selection_names : Array[Array[String]]
  opp_selections : Array[Array[Int]]
  opp_selection_names : Array[Array[String]]
  row_strategy : Array[Double]
  col_strategy : Array[Double]
}

///|
fn selection_names(
  team : Array[Combatant],
  indices : Array[Int],
) -> Array[String] {
  let out = Array::make(indices.length(), "")
  for i in 0..<indices.length() {
    out[i] = team[indices[i]].pokemon.name_ja
  }
  out
}

///|
/// Compute the selection-level Nash distribution for `team` vs `opponent`
/// under a full `TeamPayoffModel` (Phase 13 entry point).
pub fn compute_select_with_team_model(
  team : Array[Combatant],
  opponent : Array[Combatant],
  format : BattleFormat,
  team_model : TeamPayoffModel,
) -> SelectResult raise NashCliError {
  let k = match format {
    Single => 3
    Double => 4
  }
  if team.length() < k || opponent.length() < k {
    raise InvalidJson(
      "team and opponent must each have at least " + k.to_string() + " members",
    )
  }
  let (matrix, retained_rows, retained_cols) = match team_model {
    ScreenedSwitchingGame(trials, seed, keep_top, refine_tl) => {
      let (m, rows, cols) = try team_payoff_matrix_screened(
          team, opponent, format, trials, seed, keep_top,
          refine_turn_limit=refine_tl,
        ) catch {
        err => raise InnerError(err.to_string())
      }
      (m, Some(rows), Some(cols))
    }
    _ => {
      let m = try team_payoff_matrix_with_team_model(
          team, opponent, format, team_model,
        ) catch {
        err => raise InnerError(err.to_string())
      }
      (m, None, None)
    }
  }
  build_select_result(
    format, team, opponent, matrix, retained_rows, retained_cols,
  )
}

///|
/// Build a `SelectResult` from the payoff matrix by solving the zero-sum
/// Nash equilibrium. When `retained_rows` / `retained_cols` are `Some`, the
/// matrix rows / columns index into `combinations(|team|, k)` via the given
/// index arrays (used by the screened pipeline). When both are `None`, the
/// full Cartesian enumeration is used (plain `SwitchingGame` path).
fn build_select_result(
  format : BattleFormat,
  team : Array[Combatant],
  opponent : Array[Combatant],
  matrix : @nash.FiniteMatrix,
  retained_rows : Array[Int]?,
  retained_cols : Array[Int]?,
) -> SelectResult raise NashCliError {
  let k = match format {
    Single => 3
    Double => 4
  }
  let lp = try @nash.solve_zero_sum(matrix) catch {
    err => raise InnerError(err.to_string())
  }
  let (value, p, q) = match lp {
    Optimal(value~, row_strategy~, col_strategy~) =>
      (value, strategy_to_array(row_strategy), strategy_to_array(col_strategy))
    Infeasible => raise InfeasibleGame
    Unbounded => raise UnboundedGame
  }
  let expl = match lp {
    Optimal(row_strategy~, col_strategy~, ..) =>
      @nash.exploitability(matrix, row_strategy, col_strategy)
    _ => 0.0
  }
  let all_team = combinations(team.length(), k)
  let all_opp = combinations(opponent.length(), k)
  let team_indices = match retained_rows {
    Some(idx) => idx
    None => {
      let r = Array::make(all_team.length(), 0)
      for i in 0..<all_team.length() {
        r[i] = i
      }
      r
    }
  }
  let opp_indices = match retained_cols {
    Some(idx) => idx
    None => {
      let r = Array::make(all_opp.length(), 0)
      for j in 0..<all_opp.length() {
        r[j] = j
      }
      r
    }
  }
  let sel_team = Array::make(team_indices.length(), ([] : Array[Int]))
  let sel_team_names = Array::make(team_indices.length(), ([] : Array[String]))
  for i in 0..<team_indices.length() {
    sel_team[i] = all_team[team_indices[i]]
    sel_team_names[i] = selection_names(team, all_team[team_indices[i]])
  }
  let sel_opp = Array::make(opp_indices.length(), ([] : Array[Int]))
  let sel_opp_names = Array::make(opp_indices.length(), ([] : Array[String]))
  for j in 0..<opp_indices.length() {
    sel_opp[j] = all_opp[opp_indices[j]]
    sel_opp_names[j] = selection_names(opponent, all_opp[opp_indices[j]])
  }
  {
    format,
    value,
    exploitability: expl,
    team_size: team.length(),
    opp_size: opponent.length(),
    selections: sel_team,
    selection_names: sel_team_names,
    opp_selections: sel_opp,
    opp_selection_names: sel_opp_names,
    row_strategy: p,
    col_strategy: q,
  }
}

///|
fn fmt_int_2d(xs : Array[Array[Int]]) -> String {
  fmt_json_array(xs, fmt_int_array)
}

///|
fn fmt_string_2d(xs : Array[Array[String]]) -> String {
  fmt_json_array(xs, fmt_string_array)
}

///|
fn format_label(f : BattleFormat) -> String {
  match f {
    Single => "single"
    Double => "double"
  }
}

///|
/// Parse `stat_system` field: `"champions"` (default) or `"standard"`.
fn parse_stat_system_field(s : String) -> @model.StatSystem raise NashCliError {
  match s {
    "champions" | "Champions" => @model.Champions
    "standard" | "Standard" => @model.Standard
    _ =>
      raise InvalidJson(
        "stat_system must be 'champions' or 'standard' (got '" + s + "')",
      )
  }
}

///|
/// Run `pkdx select`. Returns a JSON string with the Nash-equilibrium
/// distribution over k-selections. Move priority / stat-boost metadata rides
/// on each move's JSON entry (`priority`, `stat_effects`) — skills should
/// take the fields straight from `pkdx moves` output, which JOINs
/// `move_meta` and emits them.
pub fn run_select(input_json : String) -> String raise NashCliError {
  let root = try @json.parse(input_json) catch {
    err => raise InvalidJson(err.to_string())
  }
  let obj = match root {
    Object(m) => m
    _ => raise InvalidJson("top-level must be an object")
  }
  let stat_system = match obj.get("stat_system") {
    Some(String(s)) => parse_stat_system_field(s)
    Some(_) => raise InvalidJson("stat_system must be a string")
    None => @model.Champions
  }
  let team = match obj.get("team") {
    Some(j) => parse_team_array(j, "team", stat_system=stat_system)
    None => raise MissingField("team")
  }
  let opp = match obj.get("opponent") {
    Some(j) => parse_team_array(j, "opponent", stat_system=stat_system)
    None => raise MissingField("opponent")
  }
  let format = match obj.get("format") {
    Some(String(s)) => parse_format(s)
    _ => Single
  }
  let raw_team_model = match obj.get("team_payoff_model") {
    Some(String(s)) => parse_team_payoff_model(s)
    Some(_) => raise InvalidJson("team_payoff_model must be a string")
    None => SwitchingGame(DP_TURN_LIMIT)
  }
  let team_model = auto_upgrade_team_model(raw_team_model)
  match (format, team_model) {
    (Double, SwitchingGame(_)) =>
      raise InvalidJson(
        "switching_game does not support double format (single-active model only)",
      )
    (Double, ScreenedSwitchingGame(_, _, _, _)) =>
      raise InvalidJson(
        "screened_switching_game does not support double format (single-active model only)",
      )
    _ => ()
  }
  let r = compute_select_with_team_model(team, opp, format, team_model)
  let mut out = "{"
  out = out + "\"format\":\"" + format_label(r.format) + "\""
  out = out + ",\"value\":" + r.value.to_string()
  out = out + ",\"exploitability\":" + r.exploitability.to_string()
  out = out + ",\"selections\":" + fmt_int_2d(r.selections)
  out = out + ",\"selection_names\":" + fmt_string_2d(r.selection_names)
  out = out + ",\"opp_selections\":" + fmt_int_2d(r.opp_selections)
  out = out + ",\"opp_selection_names\":" + fmt_string_2d(r.opp_selection_names)
  out = out + ",\"row_strategy\":" + fmt_double_array(r.row_strategy)
  out = out + ",\"col_strategy\":" + fmt_double_array(r.col_strategy)
  out + "}"
}

///|
/// Build a Markdown selection report from a `SelectResult`. Suitable for
/// writing under `box/teams/` as a companion to the team build doc.
pub fn render_select_markdown(r : SelectResult) -> String {
  let mut s = "# Selection Report\n\n"
  s = s + "- format: " + format_label(r.format) + "\n"
  s = s + "- value: " + r.value.to_string() + "\n"
  s = s + "- exploitability: " + r.exploitability.to_string() + "\n\n"
  s = s + "## Row-player selection distribution\n\n"
  s = s + "| probability | members |\n| --- | --- |\n"
  for i in 0..<r.selections.length() {
    if r.row_strategy[i] > 1.0e-6 {
      s = s + "| " + r.row_strategy[i].to_string() + " | "
      for j in 0..<r.selection_names[i].length() {
        if j > 0 {
          s = s + ", "
        }
        s = s + r.selection_names[i][j]
      }
      s = s + " |\n"
    }
  }
  s
}
