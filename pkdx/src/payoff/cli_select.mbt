///|
/// Handler logic for `pkdx select` — the selection-optimisation command.
///
/// Input JSON schema (simplified team-cache shape):
/// ```
/// {
///   "team":     [<combatant>, ...],
///   "opponent": [<combatant>, ...],
///   "format":   "single" | "double",
///   "payoff_model": "best1v1" | "nash_responses"  // default: best1v1
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
      {
        name,
        type_,
        category,
        power,
        accuracy: 100,
        pp: 10,
        learn_method: "",
        priority,
        stat_effects,
      }
    }
    _ => raise InvalidJson(ctx + " must be an object")
  }
}

///|
/// Parse a JSON array of `[stat_index, delta]` pairs. Non-conforming entries
/// are silently skipped (e.g. wrong arity, non-numeric members); a malformed
/// JSON that parsed as an Array still yields an empty effect list rather than
/// raising.
fn parse_stat_effects_array(arr : Array[Json]) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  for item in arr {
    match item {
      Array(pair) =>
        if pair.length() == 2 {
          let a = match pair[0] {
            Number(n, ..) => Some(n.to_int())
            _ => None
          }
          let b = match pair[1] {
            Number(n, ..) => Some(n.to_int())
            _ => None
          }
          match (a, b) {
            (Some(ai), Some(bi)) => out.push((ai, bi))
            _ => ()
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
fn parse_combatant_json(
  j : Json,
  ctx : String,
) -> Combatant raise NashCliError {
  match j {
    Object(m) => {
      let name = match m.get("name") {
        Some(String(s)) => s
        _ => raise MissingField(ctx + ".name")
      }
      let hp = parse_int_field(m, "hp", ctx)
      let atk = parse_int_field(m, "atk", ctx)
      let def_ = parse_int_field(m, "def", ctx)
      let spa = parse_int_field(m, "spa", ctx)
      let spd = parse_int_field(m, "spd", ctx)
      let spe = parse_int_field(m, "spe", ctx)
      let poke : @model.Pokemon = {
        global_no: "0000",
        name_ja: name,
        name_en: name,
        type1: parse_str_field(m, "type1"),
        type2: parse_str_field(m, "type2"),
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
        stat_system: @model.Standard,
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
) -> Array[Combatant] raise NashCliError {
  match j {
    Array(arr) => {
      let out = Array::make(arr.length(), mk_empty_combatant())
      for i in 0..<arr.length() {
        out[i] = parse_combatant_json(
          arr[i], ctx + "[" + i.to_string() + "]",
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
    stat_system: @model.Standard,
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
fn parse_model(s : String) -> PayoffModel raise NashCliError {
  match s {
    "best1v1" => Best1v1
    "nash_responses" => NashResponses
    _ =>
      match s.strip_prefix("monte_carlo:") {
        Some(rest) => parse_monte_carlo_spec(rest.to_string())
        None =>
          raise InvalidJson(
            "payoff_model must be 'best1v1', 'nash_responses', or 'monte_carlo:<trials>:<seed>'",
          )
      }
  }
}

///|
fn parse_team_payoff_model(s : String) -> TeamPayoffModel raise NashCliError {
  match s.strip_prefix("pairwise:") {
    Some(rest) => Pairwise(parse_model(rest.to_string()))
    None =>
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
          SwitchingGame(turn_limit)
        }
        None =>
          raise InvalidJson(
            "team_payoff_model must be 'pairwise:<model>' or 'switching_game:<turn_limit>'",
          )
      }
  }
}

///|
fn parse_monte_carlo_spec(rest : String) -> PayoffModel raise NashCliError {
  let (trials_str, seed_str) = match rest.split_once(":") {
    Some((t, s)) => (t.to_string(), s.to_string())
    None =>
      raise InvalidJson(
        "monte_carlo model must be 'monte_carlo:<trials>:<seed>'",
      )
  }
  let trials = try @strconv.parse_int(trials_str) catch {
    _ => raise InvalidJson("monte_carlo trials must be a positive integer")
  }
  if trials <= 0 {
    raise InvalidJson("monte_carlo trials must be a positive integer")
  }
  let seed = try @strconv.parse_uint64(seed_str) catch {
    _ => raise InvalidJson("monte_carlo seed must be a UInt64 literal")
  }
  MonteCarloSim(trials, seed)
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
  let m = try team_payoff_matrix_with_team_model(
      team, opponent, format, team_model,
    ) catch {
    err => raise InnerError(err.to_string())
  }
  let lp = try @nash.solve_zero_sum(m) catch {
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
      @nash.exploitability(m, row_strategy, col_strategy)
    _ => 0.0
  }
  let sel_team = combinations(team.length(), k)
  let sel_opp = combinations(opponent.length(), k)
  let sel_team_names = Array::make(sel_team.length(), ([] : Array[String]))
  for i in 0..<sel_team.length() {
    sel_team_names[i] = selection_names(team, sel_team[i])
  }
  let sel_opp_names = Array::make(sel_opp.length(), ([] : Array[String]))
  for i in 0..<sel_opp.length() {
    sel_opp_names[i] = selection_names(opponent, sel_opp[i])
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
/// Legacy entry: delegate to `compute_select_with_team_model(..., Pairwise(model))`.
pub fn compute_select(
  team : Array[Combatant],
  opponent : Array[Combatant],
  format : BattleFormat,
  model : PayoffModel,
) -> SelectResult raise NashCliError {
  compute_select_with_team_model(team, opponent, format, Pairwise(model))
}

///|
fn fmt_int_2d(xs : Array[Array[Int]]) -> String {
  let mut s = "["
  for i in 0..<xs.length() {
    if i > 0 {
      s = s + ","
    }
    s = s + fmt_int_array(xs[i])
  }
  s + "]"
}

///|
fn fmt_string_2d(xs : Array[Array[String]]) -> String {
  let mut s = "["
  for i in 0..<xs.length() {
    if i > 0 {
      s = s + ","
    }
    s = s + fmt_string_array(xs[i])
  }
  s + "]"
}

///|
fn format_label(f : BattleFormat) -> String {
  match f {
    Single => "single"
    Double => "double"
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
  let team = match obj.get("team") {
    Some(j) => parse_team_array(j, "team")
    None => raise MissingField("team")
  }
  let opp = match obj.get("opponent") {
    Some(j) => parse_team_array(j, "opponent")
    None => raise MissingField("opponent")
  }
  let format = match obj.get("format") {
    Some(String(s)) => parse_format(s)
    _ => Single
  }
  // JSON compatibility: `team_payoff_model` (Phase 13) takes precedence over
  // the legacy `payoff_model` field. If only `payoff_model` is present it is
  // wrapped in `Pairwise`. If neither is present the default is `Pairwise(Best1v1)`.
  let team_model = match obj.get("team_payoff_model") {
    Some(String(s)) => parse_team_payoff_model(s)
    Some(_) => raise InvalidJson("team_payoff_model must be a string")
    None =>
      match obj.get("payoff_model") {
        Some(String(s)) => Pairwise(parse_model(s))
        Some(_) => raise InvalidJson("payoff_model must be a string")
        None => Pairwise(Best1v1)
      }
  }
  match (format, team_model) {
    (Double, SwitchingGame(_)) =>
      raise InvalidJson(
        "switching_game does not support double format (single-active model only)",
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
