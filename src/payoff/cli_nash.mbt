///|
/// Handler logic for `pkdx nash solve` and `pkdx nash graph`.
///
/// Input JSON accepts either a direct payoff matrix or a list of characters
/// (monocycle (p, v) form). Exactly one must be supplied.
///
/// ```
/// {"matrix": [[0, 1, -1], [-1, 0, 1], [1, -1, 0]], "labels": ["A", "B", "C"]}
/// {"characters": [{"label": "A", "power": 0, "v": {"x": 2, "y": 0}}, ...]}
/// ```
///
/// Solve output JSON schema:
/// ```
/// {"value": 0.0, "row_strategy": [...], "col_strategy": [...],
///  "exploitability": 0.0, "support": {"row": [0,1,2], "col": [0,1,2]},
///  "labels": ["A","B","C"]}
/// ```

///|
pub suberror NashCliError {
  InvalidJson(String)
  MissingField(String)
  ConflictingInputs
  NonSquareMatrix(Int, Int)
  LabelCountMismatch(Int, Int)
  InfeasibleGame
  UnboundedGame
  InnerError(String)
} derive(Show)

///|
/// Parse one number (Double) from a Json node. `raise InvalidJson` if not a
/// number.
fn json_number(j : Json, ctx : String) -> Double raise NashCliError {
  match j {
    Number(n, ..) => n
    _ => raise InvalidJson("expected number at " + ctx)
  }
}

///|
fn json_string(j : Json, ctx : String) -> String raise NashCliError {
  match j {
    String(s) => s
    _ => raise InvalidJson("expected string at " + ctx)
  }
}

///|
fn parse_matrix_input(
  arr : Array[Json],
) -> Array[Array[Double]] raise NashCliError {
  let n = arr.length()
  if n == 0 {
    raise InvalidJson("matrix must be non-empty")
  }
  let data = Array::make(n, ([] : Array[Double]))
  for i in 0..<n {
    match arr[i] {
      Array(row_json) => {
        let row = Array::make(row_json.length(), 0.0)
        for j in 0..<row_json.length() {
          row[j] = json_number(
            row_json[j], "matrix[" + i.to_string() + "][" + j.to_string() + "]",
          )
        }
        data[i] = row
      }
      _ => raise InvalidJson("matrix[" + i.to_string() + "] must be an array")
    }
  }
  // Validate rectangular shape.
  let cols = data[0].length()
  for i in 1..<n {
    if data[i].length() != cols {
      raise NonSquareMatrix(n, data[i].length())
    }
  }
  if n != cols {
    raise NonSquareMatrix(n, cols)
  }
  data
}

///|
fn parse_characters_input(
  arr : Array[Json],
) -> Array[Character] raise NashCliError {
  let n = arr.length()
  if n == 0 {
    raise InvalidJson("characters must be non-empty")
  }
  let result : Array[Character] = []
  for i in 0..<n {
    let ctx = "characters[" + i.to_string() + "]"
    match arr[i] {
      Object(m) => {
        let label = match m.get("label") {
          Some(j) => json_string(j, ctx + ".label")
          None => raise MissingField(ctx + ".label")
        }
        let power = match m.get("power") {
          Some(j) => json_number(j, ctx + ".power")
          None => raise MissingField(ctx + ".power")
        }
        let v = match m.get("v") {
          Some(Object(vm)) => {
            let x = match vm.get("x") {
              Some(j) => json_number(j, ctx + ".v.x")
              None => raise MissingField(ctx + ".v.x")
            }
            let y = match vm.get("y") {
              Some(j) => json_number(j, ctx + ".v.y")
              None => raise MissingField(ctx + ".v.y")
            }
            MatchupVector::{ x, y }
          }
          _ => raise MissingField(ctx + ".v")
        }
        result.push(Character::{ label, power, v })
      }
      _ => raise InvalidJson(ctx + " must be an object")
    }
  }
  result
}

///|
fn parse_labels(
  obj : Map[String, Json],
  default_count : Int,
) -> Array[String] raise NashCliError {
  match obj.get("labels") {
    None => {
      let arr = Array::make(default_count, "")
      for i in 0..<default_count {
        arr[i] = i.to_string()
      }
      arr
    }
    Some(Array(arr)) => {
      if arr.length() != default_count {
        raise LabelCountMismatch(default_count, arr.length())
      }
      let result = Array::make(arr.length(), "")
      for i in 0..<arr.length() {
        result[i] = json_string(arr[i], "labels[" + i.to_string() + "]")
      }
      result
    }
    _ => raise InvalidJson("labels must be an array")
  }
}

///|
/// Parse the top-level nash-CLI input JSON into a matrix + labels. Rejects if
/// both `matrix` and `characters` are supplied, or neither is.
fn parse_nash_input(
  input_json : String,
) -> (@nash.FiniteMatrix, Array[String]) raise NashCliError {
  let root = try @json.parse(input_json) catch {
    err => raise InvalidJson(err.to_string())
  }
  let obj = match root {
    Object(m) => m
    _ => raise InvalidJson("top-level must be an object")
  }
  let has_matrix = obj.contains("matrix")
  let has_chars = obj.contains("characters")
  if has_matrix && has_chars {
    raise ConflictingInputs
  }
  if not(has_matrix) && not(has_chars) {
    raise MissingField("matrix or characters")
  }
  let (data, labels) = if has_matrix {
    match obj.get("matrix") {
      Some(Array(arr)) => {
        let d = parse_matrix_input(arr)
        let labels = parse_labels(obj, d.length())
        (d, labels)
      }
      _ => raise InvalidJson("matrix must be an array")
    }
  } else {
    match obj.get("characters") {
      Some(Array(arr)) => {
        let chars = parse_characters_input(arr)
        let m = try from_characters(chars) catch {
          err => raise InnerError(err.to_string())
        }
        let labels = Array::make(chars.length(), "")
        for i in 0..<chars.length() {
          labels[i] = chars[i].label
        }
        let d = Array::make(m.rows(), ([] : Array[Double]))
        for i in 0..<m.rows() {
          let row = Array::make(m.cols(), 0.0)
          for j in 0..<m.cols() {
            row[j] = m.at(i, j)
          }
          d[i] = row
        }
        (d, labels)
      }
      _ => raise InvalidJson("characters must be an array")
    }
  }
  let matrix = match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise InvalidJson("invalid matrix data")
  }
  (matrix, labels)
}

///|
/// Serialize `xs` as a JSON array, delegating per-element formatting
/// (including any escaping) to `fmt_one`. Shared by int / double / string /
/// 2-D variants across the payoff CLI.
fn[T] fmt_json_array(xs : Array[T], fmt_one : (T) -> String) -> String {
  let mut s = "["
  for i in 0..<xs.length() {
    if i > 0 {
      s = s + ","
    }
    s = s + fmt_one(xs[i])
  }
  s + "]"
}

///|
/// Format an `Array[Double]` as a JSON array string.
fn fmt_double_array(xs : Array[Double]) -> String {
  fmt_json_array(xs, fn(x) { x.to_string() })
}

///|
fn fmt_int_array(xs : Array[Int]) -> String {
  fmt_json_array(xs, fn(x) { x.to_string() })
}

///|
/// Escape a string for inclusion inside JSON string literals (RFC 8259 §7).
/// Quotes, backslashes, and ASCII control characters are replaced with the
/// appropriate escape sequence so that arbitrary labels / Pokemon names
/// produce valid JSON.
fn json_escape(s : String) -> String {
  let hex_digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e',
    'f',
  ]
  let mut out = ""
  for ch in s {
    let code = ch.to_int()
    if ch == '"' {
      out = out + "\\\""
    } else if ch == '\\' {
      out = out + "\\\\"
    } else if code == 0x08 {
      out = out + "\\b"
    } else if code == 0x09 {
      out = out + "\\t"
    } else if code == 0x0A {
      out = out + "\\n"
    } else if code == 0x0C {
      out = out + "\\f"
    } else if code == 0x0D {
      out = out + "\\r"
    } else if code < 0x20 {
      let hi = (code / 16) % 16
      let lo = code % 16
      out = out +
        "\\u00" +
        hex_digits[hi].to_string() +
        hex_digits[lo].to_string()
    } else {
      out = out + ch.to_string()
    }
  }
  out
}

///|
/// Escape a string for inclusion inside DOT `"..."` quoted identifiers.
/// Quotes and backslashes get backslash-escaped; literal newline/tab/carriage
/// return are converted to the two-character escape sequences (\n, \t, \r) so
/// labels containing raw control characters still produce syntactically valid
/// DOT. Other ASCII control characters below 0x20 are dropped.
fn dot_escape(s : String) -> String {
  let mut out = ""
  for ch in s {
    let code = ch.to_int()
    if ch == '"' {
      out = out + "\\\""
    } else if ch == '\\' {
      out = out + "\\\\"
    } else if code == 0x0A {
      out = out + "\\n"
    } else if code == 0x0D {
      out = out + "\\r"
    } else if code == 0x09 {
      out = out + "\\t"
    } else if code < 0x20 {
      continue
    } else {
      out = out + ch.to_string()
    }
  }
  out
}

///|
fn fmt_string_array(xs : Array[String]) -> String {
  fmt_json_array(xs, fn(x) { "\"" + json_escape(x) + "\"" })
}

///|
/// Support set: indices where `strategy[i] > threshold`.
fn support_indices(strategy : Array[Double], threshold : Double) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<strategy.length() {
    if strategy[i] > threshold {
      out.push(i)
    }
  }
  out
}

///|
fn strategy_to_array(s : @nash.MixedStrategy) -> Array[Double] {
  let out = Array::make(s.len(), 0.0)
  for i in 0..<s.len() {
    out[i] = s.at(i)
  }
  out
}

///|
/// Run `pkdx nash solve`. Returns a JSON string on success. Raises
/// `InfeasibleGame` / `UnboundedGame` for degenerate LPs so the caller can exit
/// non-zero.
pub fn run_nash_solve(input_json : String) -> String raise NashCliError {
  let (matrix, labels) = parse_nash_input(input_json)
  let lp = try @nash.solve_zero_sum(matrix) catch {
    err => raise InnerError(err.to_string())
  }
  match lp {
    Optimal(value~, row_strategy~, col_strategy~) => {
      let p = strategy_to_array(row_strategy)
      let q = strategy_to_array(col_strategy)
      let expl = @nash.exploitability(matrix, row_strategy, col_strategy)
      let sup_row = support_indices(p, 1.0e-6)
      let sup_col = support_indices(q, 1.0e-6)
      let mut out = "{"
      out = out + "\"value\":" + value.to_string()
      out = out + ",\"row_strategy\":" + fmt_double_array(p)
      out = out + ",\"col_strategy\":" + fmt_double_array(q)
      out = out + ",\"exploitability\":" + expl.to_string()
      out = out +
        ",\"support\":{\"row\":" +
        fmt_int_array(sup_row) +
        ",\"col\":" +
        fmt_int_array(sup_col) +
        "}"
      out = out + ",\"labels\":" + fmt_string_array(labels)
      out + "}"
    }
    Infeasible => raise InfeasibleGame
    Unbounded => raise UnboundedGame
  }
}

///|
/// Run `pkdx nash graph`. Emits a DOT digraph with one edge per entry whose
/// absolute value exceeds `threshold`.
///
/// Three input shapes are accepted:
/// - `{"matrix": [[...]], "labels": [...]?}` — legacy direct matrix
/// - `{"characters": [...]}` — monocycle (p, v) characters
/// - `{"team": [...], "opponent": [...], "stat_system"?, "turn_limit"?}` —
///   build pairwise matchup matrix from `pkdx select` style combatants
///
/// The team form is routed to `run_nash_graph_team`; matrix/characters keep
/// the legacy code path. The shared `parse_nash_input` is intentionally not
/// extended so `pkdx nash solve` continues to reject the team form.
pub fn run_nash_graph(
  input_json : String,
  threshold : Double,
) -> String raise NashCliError {
  let root = try @json.parse(input_json) catch {
    err => raise InvalidJson(err.to_string())
  }
  let obj = match root {
    Object(m) => m
    _ => raise InvalidJson("top-level must be an object")
  }
  if obj.contains("team") || obj.contains("opponent") {
    if not(obj.contains("opponent")) {
      raise MissingField("opponent")
    }
    if not(obj.contains("team")) {
      raise MissingField("team")
    }
    return run_nash_graph_team(obj, threshold)
  }
  let (matrix, labels) = parse_nash_input(input_json)
  let mut out = "digraph payoff {\n"
  for i in 0..<matrix.rows() {
    out = out + "  \"" + dot_escape(labels[i]) + "\";\n"
  }
  for i in 0..<matrix.rows() {
    for j in 0..<matrix.cols() {
      let v = matrix.at(i, j)
      if v.abs() > threshold {
        out = out +
          "  \"" +
          dot_escape(labels[i]) +
          "\" -> \"" +
          dot_escape(labels[j]) +
          "\" [label=\"" +
          dot_escape(v.to_string()) +
          "\"];\n"
      }
    }
  }
  out + "}"
}

///|
/// Team-form `pkdx nash graph` handler. Builds a `(n+m) × (n+m)`
/// antisymmetric pairwise score matrix:
///
/// ```
/// A[i][n+j]   =  pairwise_score(team[i], opp[j])
/// A[n+j][i]   = -A[i][n+j]
/// A[i][i']    =  0   (intra-side block; visualization-only placeholder)
/// ```
///
/// `turn_limit == 1` (default) uses the fast mean-damage ratio difference;
/// `turn_limit >= 2` routes through `switching_game_winrate([a], [b], n)`
/// for a full extensive-form 1v1 DP value. Intra-side zeros are NOT a real
/// payoff — the matrix is graph-only and must not flow into a generic
/// zero-sum solver.
fn run_nash_graph_team(
  obj : Map[String, Json],
  threshold : Double,
) -> String raise NashCliError {
  if obj.contains("matrix") || obj.contains("characters") {
    raise ConflictingInputs
  }
  if obj.contains("labels") {
    raise InvalidJson(
      "labels not allowed with team input; node labels are derived from member names",
    )
  }
  let stat_system = match obj.get("stat_system") {
    Some(String(s)) => parse_stat_system_field(s)
    Some(_) => raise InvalidJson("stat_system must be a string")
    None => @model.Champions
  }
  let team_json = match obj.get("team") {
    Some(j) => j
    None => raise MissingField("team")
  }
  let opp_json = match obj.get("opponent") {
    Some(j) => j
    None => raise MissingField("opponent")
  }
  let team = parse_team_array(team_json, "team", stat_system=stat_system)
  let opp = parse_team_array(opp_json, "opponent", stat_system=stat_system)
  let turn_limit = match obj.get("turn_limit") {
    Some(Number(n, ..)) => {
      let v = n.to_int()
      if v <= 0 {
        raise InvalidJson("turn_limit must be a positive integer")
      }
      v
    }
    Some(_) => raise InvalidJson("turn_limit must be a number")
    None => 1
  }
  let matrix = build_team_matchup_matrix(team, opp, turn_limit)
  emit_dot_team_form(matrix, team, opp, threshold)
}

///|
/// Build the antisymmetric pairwise score matrix described on
/// `run_nash_graph_team`. Intra-side cells stay at zero.
fn build_team_matchup_matrix(
  team : Array[Combatant],
  opp : Array[Combatant],
  turn_limit : Int,
) -> Array[Array[Double]] {
  let n = team.length()
  let m = opp.length()
  let size = n + m
  let matrix : Array[Array[Double]] = Array::make(size, ([] : Array[Double]))
  for i in 0..<size {
    matrix[i] = Array::make(size, 0.0)
  }
  for i in 0..<n {
    for j in 0..<m {
      let s = team_pairwise_score(team[i], opp[j], turn_limit)
      matrix[i][n + j] = s
      matrix[n + j][i] = -s
    }
  }
  matrix
}

///|
/// 1v1 pairwise score for `nash graph` team-form. `turn_limit == 1` uses the
/// fast mean-damage ratio difference; `turn_limit >= 2` routes through the
/// full extensive-form DP via `switching_game_winrate`.
fn team_pairwise_score(
  a : Combatant,
  b : Combatant,
  turn_limit : Int,
) -> Double {
  if turn_limit >= 2 {
    return switching_game_winrate([a], [b], turn_limit)
  }
  mean_damage_ratio(a, b) - mean_damage_ratio(b, a)
}

///|
/// Mean damage ratio of `a` hitting `d`, normalised by `d`'s effective max
/// HP. Averaged across `a`'s offensive moves (power > 0, non-status).
/// Returns 0.0 when `a` has no offensive move.
fn mean_damage_ratio(a : Combatant, d : Combatant) -> Double {
  let mut total = 0.0
  let mut count = 0
  for mv in a.moves {
    if mv.power <= 0 || mv.category == @model.Status {
      continue
    }
    let r = @damage.calc_damage(build_input_with_ranks(a, d, mv, 0, 0))
    total += avg_damage(r)
    count += 1
  }
  if count == 0 {
    return 0.0
  }
  let denom = effective_hp(d).to_double()
  if denom <= 0.0 {
    return 0.0
  }
  total / denom / count.to_double()
}

///|
/// Render the team-form payoff matrix as a DOT digraph with stable
/// `team_<i>` / `opp_<j>` identifiers and separate `label="..."` attributes.
/// Stable ids prevent name collisions when both sides include a Pokemon
/// with the same display name.
fn emit_dot_team_form(
  matrix : Array[Array[Double]],
  team : Array[Combatant],
  opp : Array[Combatant],
  threshold : Double,
) -> String {
  let n = team.length()
  let m = opp.length()
  let mut out = "digraph payoff {\n"
  for i in 0..<n {
    out = out +
      "  team_" +
      i.to_string() +
      " [label=\"" +
      dot_escape(team[i].pokemon.name_ja) +
      "\"];\n"
  }
  for j in 0..<m {
    out = out +
      "  opp_" +
      j.to_string() +
      " [label=\"" +
      dot_escape(opp[j].pokemon.name_ja) +
      "\"];\n"
  }
  for i in 0..<(n + m) {
    for j in 0..<(n + m) {
      let v = matrix[i][j]
      if v.abs() > threshold {
        out = out +
          "  " +
          team_form_node_id(i, n) +
          " -> " +
          team_form_node_id(j, n) +
          " [label=\"" +
          dot_escape(v.to_string()) +
          "\"];\n"
      }
    }
  }
  out + "}"
}

///|
fn team_form_node_id(idx : Int, n_team : Int) -> String {
  if idx < n_team {
    "team_" + idx.to_string()
  } else {
    "opp_" + (idx - n_team).to_string()
  }
}
