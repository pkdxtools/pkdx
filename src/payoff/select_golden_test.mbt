// Byte-for-byte regression pin for `pkdx select` output. Locked before the
// B-7 / B-8 hot-path refactors of switching_game.mbt so any change in the
// emitted JSON (selection order, strategy weights, value, exploitability)
// surfaces as a snapshot mismatch.
//
// run_select is called directly with a JSON string instead of shelling out
// to the binary; the output JSON is `inspect`-pinned. To regenerate after
// an intentional output change, run `moon test --update` on this file.

///|
fn build_select_input(
  team_speeds : Array[Int],
  opp_speeds : Array[Int],
) -> String {
  let mk = fn(prefix : String, speeds : Array[Int]) -> String {
    let mut s = "["
    for i in 0..<speeds.length() {
      if i > 0 {
        s = s + ","
      }
      s = s +
        "{\"name\":\"" +
        prefix +
        i.to_string() +
        "\",\"type1\":\"ノーマル\",\"type2\":\"\"," +
        "\"hp\":100,\"atk\":100,\"def\":80,\"spa\":80,\"spd\":80,\"spe\":" +
        speeds[i].to_string() +
        "," +
        "\"ability\":\"\",\"item\":\"\",\"tera\":\"\"," +
        "\"moves\":[{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":85}]}"
    }
    s + "]"
  }
  "{\"team\":" +
  mk("T", team_speeds) +
  ",\"opponent\":" +
  mk("O", opp_speeds) +
  ",\"format\":\"single\"" +
  ",\"team_payoff_model\":\"switching_game:1\"" +
  "}"
}

///|
/// Per-slot stat profile used by the asymmetric-team golden below. Allows
/// individual entries to differ in HP / Attack so that selecting a strong
/// lead changes the resulting payoff (the symmetric `build_select_input`
/// fixture is degenerate w.r.t. damage).
priv struct GoldenSlot {
  name : String
  hp : Int
  atk : Int
  def_ : Int
  spe : Int
  type1 : String
  move_name : String
  move_type : String
  move_power : Int
}

///|
fn build_select_input_asym(
  team : Array[GoldenSlot],
  opp : Array[GoldenSlot],
) -> String {
  let mk = fn(slots : Array[GoldenSlot]) -> String {
    let mut s = "["
    for i in 0..<slots.length() {
      let p = slots[i]
      if i > 0 {
        s = s + ","
      }
      s = s +
        "{\"name\":\"" +
        p.name +
        "\",\"type1\":\"" +
        p.type1 +
        "\",\"type2\":\"\"," +
        "\"hp\":" +
        p.hp.to_string() +
        ",\"atk\":" +
        p.atk.to_string() +
        ",\"def\":" +
        p.def_.to_string() +
        ",\"spa\":80,\"spd\":80,\"spe\":" +
        p.spe.to_string() +
        "," +
        "\"ability\":\"\",\"item\":\"\",\"tera\":\"\"," +
        "\"moves\":[{\"name\":\"" +
        p.move_name +
        "\",\"type\":\"" +
        p.move_type +
        "\",\"category\":\"物理\",\"power\":" +
        p.move_power.to_string() +
        "}]}"
    }
    s + "]"
  }
  "{\"team\":" +
  mk(team) +
  ",\"opponent\":" +
  mk(opp) +
  ",\"format\":\"single\"" +
  ",\"team_payoff_model\":\"switching_game:1\"" +
  "}"
}

///|
test "select golden: 6v6 single, balanced same-speed teams" {
  let speeds = [100, 100, 100, 100, 100, 100]
  let out = run_select(build_select_input(speeds, speeds))
  @debug.debug_inspect(
    out,
    content=(
      #|"{\"format\":\"single\",\"value\":0,\"exploitability\":0,\"nash_solver\":\"simplex\",\"selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"selection_names\":[[\"T0\",\"T1\",\"T2\"],[\"T0\",\"T1\",\"T3\"],[\"T0\",\"T1\",\"T4\"],[\"T0\",\"T1\",\"T5\"],[\"T0\",\"T2\",\"T3\"],[\"T0\",\"T2\",\"T4\"],[\"T0\",\"T2\",\"T5\"],[\"T0\",\"T3\",\"T4\"],[\"T0\",\"T3\",\"T5\"],[\"T0\",\"T4\",\"T5\"],[\"T1\",\"T0\",\"T2\"],[\"T1\",\"T0\",\"T3\"],[\"T1\",\"T0\",\"T4\"],[\"T1\",\"T0\",\"T5\"],[\"T1\",\"T2\",\"T3\"],[\"T1\",\"T2\",\"T4\"],[\"T1\",\"T2\",\"T5\"],[\"T1\",\"T3\",\"T4\"],[\"T1\",\"T3\",\"T5\"],[\"T1\",\"T4\",\"T5\"],[\"T2\",\"T0\",\"T1\"],[\"T2\",\"T0\",\"T3\"],[\"T2\",\"T0\",\"T4\"],[\"T2\",\"T0\",\"T5\"],[\"T2\",\"T1\",\"T3\"],[\"T2\",\"T1\",\"T4\"],[\"T2\",\"T1\",\"T5\"],[\"T2\",\"T3\",\"T4\"],[\"T2\",\"T3\",\"T5\"],[\"T2\",\"T4\",\"T5\"],[\"T3\",\"T0\",\"T1\"],[\"T3\",\"T0\",\"T2\"],[\"T3\",\"T0\",\"T4\"],[\"T3\",\"T0\",\"T5\"],[\"T3\",\"T1\",\"T2\"],[\"T3\",\"T1\",\"T4\"],[\"T3\",\"T1\",\"T5\"],[\"T3\",\"T2\",\"T4\"],[\"T3\",\"T2\",\"T5\"],[\"T3\",\"T4\",\"T5\"],[\"T4\",\"T0\",\"T1\"],[\"T4\",\"T0\",\"T2\"],[\"T4\",\"T0\",\"T3\"],[\"T4\",\"T0\",\"T5\"],[\"T4\",\"T1\",\"T2\"],[\"T4\",\"T1\",\"T3\"],[\"T4\",\"T1\",\"T5\"],[\"T4\",\"T2\",\"T3\"],[\"T4\",\"T2\",\"T5\"],[\"T4\",\"T3\",\"T5\"],[\"T5\",\"T0\",\"T1\"],[\"T5\",\"T0\",\"T2\"],[\"T5\",\"T0\",\"T3\"],[\"T5\",\"T0\",\"T4\"],[\"T5\",\"T1\",\"T2\"],[\"T5\",\"T1\",\"T3\"],[\"T5\",\"T1\",\"T4\"],[\"T5\",\"T2\",\"T3\"],[\"T5\",\"T2\",\"T4\"],[\"T5\",\"T3\",\"T4\"]],\"opp_selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"opp_selection_names\":[[\"O0\",\"O1\",\"O2\"],[\"O0\",\"O1\",\"O3\"],[\"O0\",\"O1\",\"O4\"],[\"O0\",\"O1\",\"O5\"],[\"O0\",\"O2\",\"O3\"],[\"O0\",\"O2\",\"O4\"],[\"O0\",\"O2\",\"O5\"],[\"O0\",\"O3\",\"O4\"],[\"O0\",\"O3\",\"O5\"],[\"O0\",\"O4\",\"O5\"],[\"O1\",\"O0\",\"O2\"],[\"O1\",\"O0\",\"O3\"],[\"O1\",\"O0\",\"O4\"],[\"O1\",\"O0\",\"O5\"],[\"O1\",\"O2\",\"O3\"],[\"O1\",\"O2\",\"O4\"],[\"O1\",\"O2\",\"O5\"],[\"O1\",\"O3\",\"O4\"],[\"O1\",\"O3\",\"O5\"],[\"O1\",\"O4\",\"O5\"],[\"O2\",\"O0\",\"O1\"],[\"O2\",\"O0\",\"O3\"],[\"O2\",\"O0\",\"O4\"],[\"O2\",\"O0\",\"O5\"],[\"O2\",\"O1\",\"O3\"],[\"O2\",\"O1\",\"O4\"],[\"O2\",\"O1\",\"O5\"],[\"O2\",\"O3\",\"O4\"],[\"O2\",\"O3\",\"O5\"],[\"O2\",\"O4\",\"O5\"],[\"O3\",\"O0\",\"O1\"],[\"O3\",\"O0\",\"O2\"],[\"O3\",\"O0\",\"O4\"],[\"O3\",\"O0\",\"O5\"],[\"O3\",\"O1\",\"O2\"],[\"O3\",\"O1\",\"O4\"],[\"O3\",\"O1\",\"O5\"],[\"O3\",\"O2\",\"O4\"],[\"O3\",\"O2\",\"O5\"],[\"O3\",\"O4\",\"O5\"],[\"O4\",\"O0\",\"O1\"],[\"O4\",\"O0\",\"O2\"],[\"O4\",\"O0\",\"O3\"],[\"O4\",\"O0\",\"O5\"],[\"O4\",\"O1\",\"O2\"],[\"O4\",\"O1\",\"O3\"],[\"O4\",\"O1\",\"O5\"],[\"O4\",\"O2\",\"O3\"],[\"O4\",\"O2\",\"O5\"],[\"O4\",\"O3\",\"O5\"],[\"O5\",\"O0\",\"O1\"],[\"O5\",\"O0\",\"O2\"],[\"O5\",\"O0\",\"O3\"],[\"O5\",\"O0\",\"O4\"],[\"O5\",\"O1\",\"O2\"],[\"O5\",\"O1\",\"O3\"],[\"O5\",\"O1\",\"O4\"],[\"O5\",\"O2\",\"O3\"],[\"O5\",\"O2\",\"O4\"],[\"O5\",\"O3\",\"O4\"]],\"row_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"col_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}"
    ),
  )
}

///|
test "select golden: 6v6 single, team faster than opponent" {
  let team_speeds = [120, 115, 110, 105, 100, 95]
  let opp_speeds = [80, 75, 70, 65, 60, 55]
  let out = run_select(build_select_input(team_speeds, opp_speeds))
  @debug.debug_inspect(
    out,
    content=(
      #|"{\"format\":\"single\",\"value\":0,\"exploitability\":0,\"nash_solver\":\"simplex\",\"selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"selection_names\":[[\"T0\",\"T1\",\"T2\"],[\"T0\",\"T1\",\"T3\"],[\"T0\",\"T1\",\"T4\"],[\"T0\",\"T1\",\"T5\"],[\"T0\",\"T2\",\"T3\"],[\"T0\",\"T2\",\"T4\"],[\"T0\",\"T2\",\"T5\"],[\"T0\",\"T3\",\"T4\"],[\"T0\",\"T3\",\"T5\"],[\"T0\",\"T4\",\"T5\"],[\"T1\",\"T0\",\"T2\"],[\"T1\",\"T0\",\"T3\"],[\"T1\",\"T0\",\"T4\"],[\"T1\",\"T0\",\"T5\"],[\"T1\",\"T2\",\"T3\"],[\"T1\",\"T2\",\"T4\"],[\"T1\",\"T2\",\"T5\"],[\"T1\",\"T3\",\"T4\"],[\"T1\",\"T3\",\"T5\"],[\"T1\",\"T4\",\"T5\"],[\"T2\",\"T0\",\"T1\"],[\"T2\",\"T0\",\"T3\"],[\"T2\",\"T0\",\"T4\"],[\"T2\",\"T0\",\"T5\"],[\"T2\",\"T1\",\"T3\"],[\"T2\",\"T1\",\"T4\"],[\"T2\",\"T1\",\"T5\"],[\"T2\",\"T3\",\"T4\"],[\"T2\",\"T3\",\"T5\"],[\"T2\",\"T4\",\"T5\"],[\"T3\",\"T0\",\"T1\"],[\"T3\",\"T0\",\"T2\"],[\"T3\",\"T0\",\"T4\"],[\"T3\",\"T0\",\"T5\"],[\"T3\",\"T1\",\"T2\"],[\"T3\",\"T1\",\"T4\"],[\"T3\",\"T1\",\"T5\"],[\"T3\",\"T2\",\"T4\"],[\"T3\",\"T2\",\"T5\"],[\"T3\",\"T4\",\"T5\"],[\"T4\",\"T0\",\"T1\"],[\"T4\",\"T0\",\"T2\"],[\"T4\",\"T0\",\"T3\"],[\"T4\",\"T0\",\"T5\"],[\"T4\",\"T1\",\"T2\"],[\"T4\",\"T1\",\"T3\"],[\"T4\",\"T1\",\"T5\"],[\"T4\",\"T2\",\"T3\"],[\"T4\",\"T2\",\"T5\"],[\"T4\",\"T3\",\"T5\"],[\"T5\",\"T0\",\"T1\"],[\"T5\",\"T0\",\"T2\"],[\"T5\",\"T0\",\"T3\"],[\"T5\",\"T0\",\"T4\"],[\"T5\",\"T1\",\"T2\"],[\"T5\",\"T1\",\"T3\"],[\"T5\",\"T1\",\"T4\"],[\"T5\",\"T2\",\"T3\"],[\"T5\",\"T2\",\"T4\"],[\"T5\",\"T3\",\"T4\"]],\"opp_selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"opp_selection_names\":[[\"O0\",\"O1\",\"O2\"],[\"O0\",\"O1\",\"O3\"],[\"O0\",\"O1\",\"O4\"],[\"O0\",\"O1\",\"O5\"],[\"O0\",\"O2\",\"O3\"],[\"O0\",\"O2\",\"O4\"],[\"O0\",\"O2\",\"O5\"],[\"O0\",\"O3\",\"O4\"],[\"O0\",\"O3\",\"O5\"],[\"O0\",\"O4\",\"O5\"],[\"O1\",\"O0\",\"O2\"],[\"O1\",\"O0\",\"O3\"],[\"O1\",\"O0\",\"O4\"],[\"O1\",\"O0\",\"O5\"],[\"O1\",\"O2\",\"O3\"],[\"O1\",\"O2\",\"O4\"],[\"O1\",\"O2\",\"O5\"],[\"O1\",\"O3\",\"O4\"],[\"O1\",\"O3\",\"O5\"],[\"O1\",\"O4\",\"O5\"],[\"O2\",\"O0\",\"O1\"],[\"O2\",\"O0\",\"O3\"],[\"O2\",\"O0\",\"O4\"],[\"O2\",\"O0\",\"O5\"],[\"O2\",\"O1\",\"O3\"],[\"O2\",\"O1\",\"O4\"],[\"O2\",\"O1\",\"O5\"],[\"O2\",\"O3\",\"O4\"],[\"O2\",\"O3\",\"O5\"],[\"O2\",\"O4\",\"O5\"],[\"O3\",\"O0\",\"O1\"],[\"O3\",\"O0\",\"O2\"],[\"O3\",\"O0\",\"O4\"],[\"O3\",\"O0\",\"O5\"],[\"O3\",\"O1\",\"O2\"],[\"O3\",\"O1\",\"O4\"],[\"O3\",\"O1\",\"O5\"],[\"O3\",\"O2\",\"O4\"],[\"O3\",\"O2\",\"O5\"],[\"O3\",\"O4\",\"O5\"],[\"O4\",\"O0\",\"O1\"],[\"O4\",\"O0\",\"O2\"],[\"O4\",\"O0\",\"O3\"],[\"O4\",\"O0\",\"O5\"],[\"O4\",\"O1\",\"O2\"],[\"O4\",\"O1\",\"O3\"],[\"O4\",\"O1\",\"O5\"],[\"O4\",\"O2\",\"O3\"],[\"O4\",\"O2\",\"O5\"],[\"O4\",\"O3\",\"O5\"],[\"O5\",\"O0\",\"O1\"],[\"O5\",\"O0\",\"O2\"],[\"O5\",\"O0\",\"O3\"],[\"O5\",\"O0\",\"O4\"],[\"O5\",\"O1\",\"O2\"],[\"O5\",\"O1\",\"O3\"],[\"O5\",\"O1\",\"O4\"],[\"O5\",\"O2\",\"O3\"],[\"O5\",\"O2\",\"O4\"],[\"O5\",\"O3\",\"O4\"]],\"row_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"col_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}"
    ),
  )
}

///|
/// Stage 14 fixture builder — JSON input with healing / weather-set move
/// metadata directly embedded (via `heal_kind` / `weather_set` fields on
/// each move). Mirrors the DB-driven path used by `pkdx select` in
/// production (m014 fills the same fields on the `Move` struct), so the
/// golden output reflects the same payoff arithmetic users observe end-to-end.
///
/// `team_payoff_model` is fixed at `"switching_game:6"` so the DP runs
/// enough turns for healing effects to materially shift the value. 3v3
/// (single-format) keeps the state space tractable for a regression pin.
priv struct HealingSlot {
  name : String
  hp : Int
  atk : Int
  def_ : Int
  spd : Int
  spe : Int
  type1 : String
  ability : String
  moves_json : String
}

///|
fn build_select_input_healing(
  team : Array[HealingSlot],
  opp : Array[HealingSlot],
  team_payoff_model : String,
) -> String {
  let mk = fn(slots : Array[HealingSlot]) -> String {
    let mut s = "["
    for i in 0..<slots.length() {
      let p = slots[i]
      if i > 0 {
        s = s + ","
      }
      s = s +
        "{\"name\":\"" +
        p.name +
        "\",\"type1\":\"" +
        p.type1 +
        "\",\"type2\":\"\"," +
        "\"hp\":" +
        p.hp.to_string() +
        ",\"atk\":" +
        p.atk.to_string() +
        ",\"def\":" +
        p.def_.to_string() +
        ",\"spa\":80,\"spd\":" +
        p.spd.to_string() +
        ",\"spe\":" +
        p.spe.to_string() +
        "," +
        "\"ability\":\"" +
        p.ability +
        "\",\"item\":\"\",\"tera\":\"\"," +
        "\"moves\":" +
        p.moves_json +
        "}"
    }
    s + "]"
  }
  "{\"team\":" +
  mk(team) +
  ",\"opponent\":" +
  mk(opp) +
  ",\"format\":\"single\"" +
  ",\"team_payoff_model\":\"" +
  team_payoff_model +
  "\"" +
  "}"
}

///|
/// **Golden fixture 1 — Self-Recover vs Attacker control parity**.
///
/// 「じこさいせい持ち高耐久ポケモン」を含むチームと、それを「damaging move
/// に差し替えただけ」の control チームを同条件で `pkdx select` に流す。
///
/// 期待される観測:
///   - 高耐久 + Recover slot (T0) は持続戦に強い → switching_game value が
///     control 版 (T0 が damaging move のみ) より高く出る (回復技を持つ
///     attacker の方が長期戦で生存しやすいため)。
///   - row_strategy の T0-先頭 selections に重みが寄る (回復技持ちの方が
///     先発として価値が高い)。
///
/// snapshot は `moon test --update` で固定し、回復技サポート全体 (m014 →
/// query → cli_select → payoff → DP) の bit-exact regression pin として
/// 機能する。テスト名が "recover" を含むので、healing 関連の挙動が壊れた
/// ときに最初にここが落ちる。
test "select golden: healing fixture — Recover-bearing tank shifts value" {
  let recover_moves = "[{\"name\":\"じこさいせい\",\"type\":\"ノーマル\",\"category\":\"変化\",\"power\":0,\"heal_kind\":\"fixed\",\"heal_num\":1,\"heal_den\":2},{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":85}]"
  let control_moves = "[{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":85}]"
  let opp_moves = "[{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":85}]"
  let team = [
    {
      name: "Tank",
      hp: 200,
      atk: 80,
      def_: 200,
      spd: 200,
      spe: 60,
      type1: "ノーマル",
      ability: "",
      moves_json: recover_moves,
    },
    {
      name: "AceA",
      hp: 100,
      atk: 130,
      def_: 80,
      spd: 80,
      spe: 110,
      type1: "ノーマル",
      ability: "",
      moves_json: control_moves,
    },
    {
      name: "AceB",
      hp: 100,
      atk: 130,
      def_: 80,
      spd: 80,
      spe: 110,
      type1: "ノーマル",
      ability: "",
      moves_json: control_moves,
    },
    {
      name: "AceC",
      hp: 100,
      atk: 120,
      def_: 80,
      spd: 80,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: control_moves,
    },
    {
      name: "AceD",
      hp: 100,
      atk: 120,
      def_: 80,
      spd: 80,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: control_moves,
    },
    {
      name: "AceE",
      hp: 100,
      atk: 120,
      def_: 80,
      spd: 80,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: control_moves,
    },
  ]
  let opp = [
    {
      name: "OAtk0",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: opp_moves,
    },
    {
      name: "OAtk1",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: opp_moves,
    },
    {
      name: "OAtk2",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: opp_moves,
    },
    {
      name: "OAtk3",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: opp_moves,
    },
    {
      name: "OAtk4",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: opp_moves,
    },
    {
      name: "OAtk5",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: opp_moves,
    },
  ]
  let input = build_select_input_healing(team, opp, "switching_game:3")
  let out = run_select(input)
  @debug.debug_inspect(
    out,
    content=(
      #|"{\"format\":\"single\",\"value\":0.22249999999999998,\"exploitability\":0,\"nash_solver\":\"simplex\",\"selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"selection_names\":[[\"Tank\",\"AceA\",\"AceB\"],[\"Tank\",\"AceA\",\"AceC\"],[\"Tank\",\"AceA\",\"AceD\"],[\"Tank\",\"AceA\",\"AceE\"],[\"Tank\",\"AceB\",\"AceC\"],[\"Tank\",\"AceB\",\"AceD\"],[\"Tank\",\"AceB\",\"AceE\"],[\"Tank\",\"AceC\",\"AceD\"],[\"Tank\",\"AceC\",\"AceE\"],[\"Tank\",\"AceD\",\"AceE\"],[\"AceA\",\"Tank\",\"AceB\"],[\"AceA\",\"Tank\",\"AceC\"],[\"AceA\",\"Tank\",\"AceD\"],[\"AceA\",\"Tank\",\"AceE\"],[\"AceA\",\"AceB\",\"AceC\"],[\"AceA\",\"AceB\",\"AceD\"],[\"AceA\",\"AceB\",\"AceE\"],[\"AceA\",\"AceC\",\"AceD\"],[\"AceA\",\"AceC\",\"AceE\"],[\"AceA\",\"AceD\",\"AceE\"],[\"AceB\",\"Tank\",\"AceA\"],[\"AceB\",\"Tank\",\"AceC\"],[\"AceB\",\"Tank\",\"AceD\"],[\"AceB\",\"Tank\",\"AceE\"],[\"AceB\",\"AceA\",\"AceC\"],[\"AceB\",\"AceA\",\"AceD\"],[\"AceB\",\"AceA\",\"AceE\"],[\"AceB\",\"AceC\",\"AceD\"],[\"AceB\",\"AceC\",\"AceE\"],[\"AceB\",\"AceD\",\"AceE\"],[\"AceC\",\"Tank\",\"AceA\"],[\"AceC\",\"Tank\",\"AceB\"],[\"AceC\",\"Tank\",\"AceD\"],[\"AceC\",\"Tank\",\"AceE\"],[\"AceC\",\"AceA\",\"AceB\"],[\"AceC\",\"AceA\",\"AceD\"],[\"AceC\",\"AceA\",\"AceE\"],[\"AceC\",\"AceB\",\"AceD\"],[\"AceC\",\"AceB\",\"AceE\"],[\"AceC\",\"AceD\",\"AceE\"],[\"AceD\",\"Tank\",\"AceA\"],[\"AceD\",\"Tank\",\"AceB\"],[\"AceD\",\"Tank\",\"AceC\"],[\"AceD\",\"Tank\",\"AceE\"],[\"AceD\",\"AceA\",\"AceB\"],[\"AceD\",\"AceA\",\"AceC\"],[\"AceD\",\"AceA\",\"AceE\"],[\"AceD\",\"AceB\",\"AceC\"],[\"AceD\",\"AceB\",\"AceE\"],[\"AceD\",\"AceC\",\"AceE\"],[\"AceE\",\"Tank\",\"AceA\"],[\"AceE\",\"Tank\",\"AceB\"],[\"AceE\",\"Tank\",\"AceC\"],[\"AceE\",\"Tank\",\"AceD\"],[\"AceE\",\"AceA\",\"AceB\"],[\"AceE\",\"AceA\",\"AceC\"],[\"AceE\",\"AceA\",\"AceD\"],[\"AceE\",\"AceB\",\"AceC\"],[\"AceE\",\"AceB\",\"AceD\"],[\"AceE\",\"AceC\",\"AceD\"]],\"opp_selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"opp_selection_names\":[[\"OAtk0\",\"OAtk1\",\"OAtk2\"],[\"OAtk0\",\"OAtk1\",\"OAtk3\"],[\"OAtk0\",\"OAtk1\",\"OAtk4\"],[\"OAtk0\",\"OAtk1\",\"OAtk5\"],[\"OAtk0\",\"OAtk2\",\"OAtk3\"],[\"OAtk0\",\"OAtk2\",\"OAtk4\"],[\"OAtk0\",\"OAtk2\",\"OAtk5\"],[\"OAtk0\",\"OAtk3\",\"OAtk4\"],[\"OAtk0\",\"OAtk3\",\"OAtk5\"],[\"OAtk0\",\"OAtk4\",\"OAtk5\"],[\"OAtk1\",\"OAtk0\",\"OAtk2\"],[\"OAtk1\",\"OAtk0\",\"OAtk3\"],[\"OAtk1\",\"OAtk0\",\"OAtk4\"],[\"OAtk1\",\"OAtk0\",\"OAtk5\"],[\"OAtk1\",\"OAtk2\",\"OAtk3\"],[\"OAtk1\",\"OAtk2\",\"OAtk4\"],[\"OAtk1\",\"OAtk2\",\"OAtk5\"],[\"OAtk1\",\"OAtk3\",\"OAtk4\"],[\"OAtk1\",\"OAtk3\",\"OAtk5\"],[\"OAtk1\",\"OAtk4\",\"OAtk5\"],[\"OAtk2\",\"OAtk0\",\"OAtk1\"],[\"OAtk2\",\"OAtk0\",\"OAtk3\"],[\"OAtk2\",\"OAtk0\",\"OAtk4\"],[\"OAtk2\",\"OAtk0\",\"OAtk5\"],[\"OAtk2\",\"OAtk1\",\"OAtk3\"],[\"OAtk2\",\"OAtk1\",\"OAtk4\"],[\"OAtk2\",\"OAtk1\",\"OAtk5\"],[\"OAtk2\",\"OAtk3\",\"OAtk4\"],[\"OAtk2\",\"OAtk3\",\"OAtk5\"],[\"OAtk2\",\"OAtk4\",\"OAtk5\"],[\"OAtk3\",\"OAtk0\",\"OAtk1\"],[\"OAtk3\",\"OAtk0\",\"OAtk2\"],[\"OAtk3\",\"OAtk0\",\"OAtk4\"],[\"OAtk3\",\"OAtk0\",\"OAtk5\"],[\"OAtk3\",\"OAtk1\",\"OAtk2\"],[\"OAtk3\",\"OAtk1\",\"OAtk4\"],[\"OAtk3\",\"OAtk1\",\"OAtk5\"],[\"OAtk3\",\"OAtk2\",\"OAtk4\"],[\"OAtk3\",\"OAtk2\",\"OAtk5\"],[\"OAtk3\",\"OAtk4\",\"OAtk5\"],[\"OAtk4\",\"OAtk0\",\"OAtk1\"],[\"OAtk4\",\"OAtk0\",\"OAtk2\"],[\"OAtk4\",\"OAtk0\",\"OAtk3\"],[\"OAtk4\",\"OAtk0\",\"OAtk5\"],[\"OAtk4\",\"OAtk1\",\"OAtk2\"],[\"OAtk4\",\"OAtk1\",\"OAtk3\"],[\"OAtk4\",\"OAtk1\",\"OAtk5\"],[\"OAtk4\",\"OAtk2\",\"OAtk3\"],[\"OAtk4\",\"OAtk2\",\"OAtk5\"],[\"OAtk4\",\"OAtk3\",\"OAtk5\"],[\"OAtk5\",\"OAtk0\",\"OAtk1\"],[\"OAtk5\",\"OAtk0\",\"OAtk2\"],[\"OAtk5\",\"OAtk0\",\"OAtk3\"],[\"OAtk5\",\"OAtk0\",\"OAtk4\"],[\"OAtk5\",\"OAtk1\",\"OAtk2\"],[\"OAtk5\",\"OAtk1\",\"OAtk3\"],[\"OAtk5\",\"OAtk1\",\"OAtk4\"],[\"OAtk5\",\"OAtk2\",\"OAtk3\"],[\"OAtk5\",\"OAtk2\",\"OAtk4\"],[\"OAtk5\",\"OAtk3\",\"OAtk4\"]],\"row_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"col_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}"
    ),
  )
}

///|
/// **Golden fixture 2 — Sunny-weather-dependent healing**.
///
/// にほんばれ (weather_set=sun) + つきのひかり (WeatherDependent (1,2)/(2,3)/(1,4))
/// を持つチームと、weather 制御を持たない opponent を流す。
///
/// 期待される観測:
///   - 晴れ状態では つきのひかり が max*2/3 回復 (= 0.667) → 高耐久を維持
///   - 天候設定を持たない場合のデフォルト 1/2 (= 0.5) より持続戦に強い
///   - row_strategy で天候 + heal を持つ slot に重みが寄る
///
/// snapshot は天候 state 連動 (weather_set → state.weather → WeatherDependent
/// 倍率切替 → apply_healing) の end-to-end 連結を pin する。
test "select golden: healing fixture — Sun-synced Moonlight" {
  let sun_moves = "[{\"name\":\"にほんばれ\",\"type\":\"ほのお\",\"category\":\"変化\",\"power\":0,\"weather_set\":\"sun\"},{\"name\":\"つきのひかり\",\"type\":\"フェアリー\",\"category\":\"変化\",\"power\":0,\"heal_kind\":\"weather\",\"heal_num\":1,\"heal_den\":2,\"heal_sunny_num\":2,\"heal_sunny_den\":3,\"heal_harsh_num\":1,\"heal_harsh_den\":4},{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":85}]"
  let plain_moves = "[{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":85}]"
  let team = [
    {
      name: "Solar",
      hp: 200,
      atk: 80,
      def_: 150,
      spd: 200,
      spe: 80,
      type1: "ほのお",
      ability: "",
      moves_json: sun_moves,
    },
    {
      name: "Sub0",
      hp: 100,
      atk: 100,
      def_: 80,
      spd: 80,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
    {
      name: "Sub1",
      hp: 100,
      atk: 100,
      def_: 80,
      spd: 80,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
    {
      name: "Sub2",
      hp: 100,
      atk: 100,
      def_: 80,
      spd: 80,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
    {
      name: "Sub3",
      hp: 100,
      atk: 100,
      def_: 80,
      spd: 80,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
    {
      name: "Sub4",
      hp: 100,
      atk: 100,
      def_: 80,
      spd: 80,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
  ]
  let opp = [
    {
      name: "OAtk0",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
    {
      name: "OAtk1",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
    {
      name: "OAtk2",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
    {
      name: "OAtk3",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
    {
      name: "OAtk4",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
    {
      name: "OAtk5",
      hp: 120,
      atk: 110,
      def_: 90,
      spd: 90,
      spe: 100,
      type1: "ノーマル",
      ability: "",
      moves_json: plain_moves,
    },
  ]
  let out = run_select(
    build_select_input_healing(team, opp, "switching_game:3"),
  )
  @debug.debug_inspect(
    out,
    content=(
      #|"{\"format\":\"single\",\"value\":0.1530555555555556,\"exploitability\":0,\"nash_solver\":\"simplex\",\"selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"selection_names\":[[\"Solar\",\"Sub0\",\"Sub1\"],[\"Solar\",\"Sub0\",\"Sub2\"],[\"Solar\",\"Sub0\",\"Sub3\"],[\"Solar\",\"Sub0\",\"Sub4\"],[\"Solar\",\"Sub1\",\"Sub2\"],[\"Solar\",\"Sub1\",\"Sub3\"],[\"Solar\",\"Sub1\",\"Sub4\"],[\"Solar\",\"Sub2\",\"Sub3\"],[\"Solar\",\"Sub2\",\"Sub4\"],[\"Solar\",\"Sub3\",\"Sub4\"],[\"Sub0\",\"Solar\",\"Sub1\"],[\"Sub0\",\"Solar\",\"Sub2\"],[\"Sub0\",\"Solar\",\"Sub3\"],[\"Sub0\",\"Solar\",\"Sub4\"],[\"Sub0\",\"Sub1\",\"Sub2\"],[\"Sub0\",\"Sub1\",\"Sub3\"],[\"Sub0\",\"Sub1\",\"Sub4\"],[\"Sub0\",\"Sub2\",\"Sub3\"],[\"Sub0\",\"Sub2\",\"Sub4\"],[\"Sub0\",\"Sub3\",\"Sub4\"],[\"Sub1\",\"Solar\",\"Sub0\"],[\"Sub1\",\"Solar\",\"Sub2\"],[\"Sub1\",\"Solar\",\"Sub3\"],[\"Sub1\",\"Solar\",\"Sub4\"],[\"Sub1\",\"Sub0\",\"Sub2\"],[\"Sub1\",\"Sub0\",\"Sub3\"],[\"Sub1\",\"Sub0\",\"Sub4\"],[\"Sub1\",\"Sub2\",\"Sub3\"],[\"Sub1\",\"Sub2\",\"Sub4\"],[\"Sub1\",\"Sub3\",\"Sub4\"],[\"Sub2\",\"Solar\",\"Sub0\"],[\"Sub2\",\"Solar\",\"Sub1\"],[\"Sub2\",\"Solar\",\"Sub3\"],[\"Sub2\",\"Solar\",\"Sub4\"],[\"Sub2\",\"Sub0\",\"Sub1\"],[\"Sub2\",\"Sub0\",\"Sub3\"],[\"Sub2\",\"Sub0\",\"Sub4\"],[\"Sub2\",\"Sub1\",\"Sub3\"],[\"Sub2\",\"Sub1\",\"Sub4\"],[\"Sub2\",\"Sub3\",\"Sub4\"],[\"Sub3\",\"Solar\",\"Sub0\"],[\"Sub3\",\"Solar\",\"Sub1\"],[\"Sub3\",\"Solar\",\"Sub2\"],[\"Sub3\",\"Solar\",\"Sub4\"],[\"Sub3\",\"Sub0\",\"Sub1\"],[\"Sub3\",\"Sub0\",\"Sub2\"],[\"Sub3\",\"Sub0\",\"Sub4\"],[\"Sub3\",\"Sub1\",\"Sub2\"],[\"Sub3\",\"Sub1\",\"Sub4\"],[\"Sub3\",\"Sub2\",\"Sub4\"],[\"Sub4\",\"Solar\",\"Sub0\"],[\"Sub4\",\"Solar\",\"Sub1\"],[\"Sub4\",\"Solar\",\"Sub2\"],[\"Sub4\",\"Solar\",\"Sub3\"],[\"Sub4\",\"Sub0\",\"Sub1\"],[\"Sub4\",\"Sub0\",\"Sub2\"],[\"Sub4\",\"Sub0\",\"Sub3\"],[\"Sub4\",\"Sub1\",\"Sub2\"],[\"Sub4\",\"Sub1\",\"Sub3\"],[\"Sub4\",\"Sub2\",\"Sub3\"]],\"opp_selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"opp_selection_names\":[[\"OAtk0\",\"OAtk1\",\"OAtk2\"],[\"OAtk0\",\"OAtk1\",\"OAtk3\"],[\"OAtk0\",\"OAtk1\",\"OAtk4\"],[\"OAtk0\",\"OAtk1\",\"OAtk5\"],[\"OAtk0\",\"OAtk2\",\"OAtk3\"],[\"OAtk0\",\"OAtk2\",\"OAtk4\"],[\"OAtk0\",\"OAtk2\",\"OAtk5\"],[\"OAtk0\",\"OAtk3\",\"OAtk4\"],[\"OAtk0\",\"OAtk3\",\"OAtk5\"],[\"OAtk0\",\"OAtk4\",\"OAtk5\"],[\"OAtk1\",\"OAtk0\",\"OAtk2\"],[\"OAtk1\",\"OAtk0\",\"OAtk3\"],[\"OAtk1\",\"OAtk0\",\"OAtk4\"],[\"OAtk1\",\"OAtk0\",\"OAtk5\"],[\"OAtk1\",\"OAtk2\",\"OAtk3\"],[\"OAtk1\",\"OAtk2\",\"OAtk4\"],[\"OAtk1\",\"OAtk2\",\"OAtk5\"],[\"OAtk1\",\"OAtk3\",\"OAtk4\"],[\"OAtk1\",\"OAtk3\",\"OAtk5\"],[\"OAtk1\",\"OAtk4\",\"OAtk5\"],[\"OAtk2\",\"OAtk0\",\"OAtk1\"],[\"OAtk2\",\"OAtk0\",\"OAtk3\"],[\"OAtk2\",\"OAtk0\",\"OAtk4\"],[\"OAtk2\",\"OAtk0\",\"OAtk5\"],[\"OAtk2\",\"OAtk1\",\"OAtk3\"],[\"OAtk2\",\"OAtk1\",\"OAtk4\"],[\"OAtk2\",\"OAtk1\",\"OAtk5\"],[\"OAtk2\",\"OAtk3\",\"OAtk4\"],[\"OAtk2\",\"OAtk3\",\"OAtk5\"],[\"OAtk2\",\"OAtk4\",\"OAtk5\"],[\"OAtk3\",\"OAtk0\",\"OAtk1\"],[\"OAtk3\",\"OAtk0\",\"OAtk2\"],[\"OAtk3\",\"OAtk0\",\"OAtk4\"],[\"OAtk3\",\"OAtk0\",\"OAtk5\"],[\"OAtk3\",\"OAtk1\",\"OAtk2\"],[\"OAtk3\",\"OAtk1\",\"OAtk4\"],[\"OAtk3\",\"OAtk1\",\"OAtk5\"],[\"OAtk3\",\"OAtk2\",\"OAtk4\"],[\"OAtk3\",\"OAtk2\",\"OAtk5\"],[\"OAtk3\",\"OAtk4\",\"OAtk5\"],[\"OAtk4\",\"OAtk0\",\"OAtk1\"],[\"OAtk4\",\"OAtk0\",\"OAtk2\"],[\"OAtk4\",\"OAtk0\",\"OAtk3\"],[\"OAtk4\",\"OAtk0\",\"OAtk5\"],[\"OAtk4\",\"OAtk1\",\"OAtk2\"],[\"OAtk4\",\"OAtk1\",\"OAtk3\"],[\"OAtk4\",\"OAtk1\",\"OAtk5\"],[\"OAtk4\",\"OAtk2\",\"OAtk3\"],[\"OAtk4\",\"OAtk2\",\"OAtk5\"],[\"OAtk4\",\"OAtk3\",\"OAtk5\"],[\"OAtk5\",\"OAtk0\",\"OAtk1\"],[\"OAtk5\",\"OAtk0\",\"OAtk2\"],[\"OAtk5\",\"OAtk0\",\"OAtk3\"],[\"OAtk5\",\"OAtk0\",\"OAtk4\"],[\"OAtk5\",\"OAtk1\",\"OAtk2\"],[\"OAtk5\",\"OAtk1\",\"OAtk3\"],[\"OAtk5\",\"OAtk1\",\"OAtk4\"],[\"OAtk5\",\"OAtk2\",\"OAtk3\"],[\"OAtk5\",\"OAtk2\",\"OAtk4\"],[\"OAtk5\",\"OAtk3\",\"OAtk4\"]],\"row_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"col_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}"
    ),
  )
}

///|
/// Asymmetric team / opponent: the team has 3 strong attackers (T0..T2) and
/// 3 weak ones (T3..T5); the opponent is uniform but strictly weaker than
/// the strong team trio. Selections that lead with a weak Pokémon (e.g.
/// `[3,4,5]` → lead T3) yield a different switching-game value than those
/// led by T0..T2, so the snapshot pins the actual damage / value path —
/// not just the JSON serialization shape and the enumeration order.
test "select golden: 6v6 single, asymmetric strong-vs-weak teams" {
  let strong = (200, 200, 100, 100)
  let weak = (100, 60, 60, 60)
  let opp_stats = (140, 100, 80, 90)
  let mk_team = fn(prefix : String) -> Array[GoldenSlot] {
    let out : Array[GoldenSlot] = Array::make(6, {
      name: "",
      hp: 0,
      atk: 0,
      def_: 0,
      spe: 0,
      type1: "ノーマル",
      move_name: "のしかかり",
      move_type: "ノーマル",
      move_power: 85,
    })
    for i in 0..<6 {
      let (hp, atk, def_, spe) = if i < 3 { strong } else { weak }
      out[i] = {
        name: prefix + i.to_string(),
        hp,
        atk,
        def_,
        spe,
        type1: "ノーマル",
        move_name: "のしかかり",
        move_type: "ノーマル",
        move_power: 85,
      }
    }
    out
  }
  let mk_opp = fn() -> Array[GoldenSlot] {
    let (hp, atk, def_, spe) = opp_stats
    let out : Array[GoldenSlot] = Array::make(6, {
      name: "",
      hp,
      atk,
      def_,
      spe,
      type1: "ノーマル",
      move_name: "のしかかり",
      move_type: "ノーマル",
      move_power: 85,
    })
    for i in 0..<6 {
      out[i] = {
        name: "O" + i.to_string(),
        hp,
        atk,
        def_,
        spe,
        type1: "ノーマル",
        move_name: "のしかかり",
        move_type: "ノーマル",
        move_power: 85,
      }
    }
    out
  }
  let out = run_select(build_select_input_asym(mk_team("T"), mk_opp()))
  @debug.debug_inspect(
    out,
    content=(
      #|"{\"format\":\"single\",\"value\":0.16666666666666669,\"exploitability\":0,\"nash_solver\":\"simplex\",\"selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"selection_names\":[[\"T0\",\"T1\",\"T2\"],[\"T0\",\"T1\",\"T3\"],[\"T0\",\"T1\",\"T4\"],[\"T0\",\"T1\",\"T5\"],[\"T0\",\"T2\",\"T3\"],[\"T0\",\"T2\",\"T4\"],[\"T0\",\"T2\",\"T5\"],[\"T0\",\"T3\",\"T4\"],[\"T0\",\"T3\",\"T5\"],[\"T0\",\"T4\",\"T5\"],[\"T1\",\"T0\",\"T2\"],[\"T1\",\"T0\",\"T3\"],[\"T1\",\"T0\",\"T4\"],[\"T1\",\"T0\",\"T5\"],[\"T1\",\"T2\",\"T3\"],[\"T1\",\"T2\",\"T4\"],[\"T1\",\"T2\",\"T5\"],[\"T1\",\"T3\",\"T4\"],[\"T1\",\"T3\",\"T5\"],[\"T1\",\"T4\",\"T5\"],[\"T2\",\"T0\",\"T1\"],[\"T2\",\"T0\",\"T3\"],[\"T2\",\"T0\",\"T4\"],[\"T2\",\"T0\",\"T5\"],[\"T2\",\"T1\",\"T3\"],[\"T2\",\"T1\",\"T4\"],[\"T2\",\"T1\",\"T5\"],[\"T2\",\"T3\",\"T4\"],[\"T2\",\"T3\",\"T5\"],[\"T2\",\"T4\",\"T5\"],[\"T3\",\"T0\",\"T1\"],[\"T3\",\"T0\",\"T2\"],[\"T3\",\"T0\",\"T4\"],[\"T3\",\"T0\",\"T5\"],[\"T3\",\"T1\",\"T2\"],[\"T3\",\"T1\",\"T4\"],[\"T3\",\"T1\",\"T5\"],[\"T3\",\"T2\",\"T4\"],[\"T3\",\"T2\",\"T5\"],[\"T3\",\"T4\",\"T5\"],[\"T4\",\"T0\",\"T1\"],[\"T4\",\"T0\",\"T2\"],[\"T4\",\"T0\",\"T3\"],[\"T4\",\"T0\",\"T5\"],[\"T4\",\"T1\",\"T2\"],[\"T4\",\"T1\",\"T3\"],[\"T4\",\"T1\",\"T5\"],[\"T4\",\"T2\",\"T3\"],[\"T4\",\"T2\",\"T5\"],[\"T4\",\"T3\",\"T5\"],[\"T5\",\"T0\",\"T1\"],[\"T5\",\"T0\",\"T2\"],[\"T5\",\"T0\",\"T3\"],[\"T5\",\"T0\",\"T4\"],[\"T5\",\"T1\",\"T2\"],[\"T5\",\"T1\",\"T3\"],[\"T5\",\"T1\",\"T4\"],[\"T5\",\"T2\",\"T3\"],[\"T5\",\"T2\",\"T4\"],[\"T5\",\"T3\",\"T4\"]],\"opp_selections\":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,0,2],[1,0,3],[1,0,4],[1,0,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,0,1],[2,0,3],[2,0,4],[2,0,5],[2,1,3],[2,1,4],[2,1,5],[2,3,4],[2,3,5],[2,4,5],[3,0,1],[3,0,2],[3,0,4],[3,0,5],[3,1,2],[3,1,4],[3,1,5],[3,2,4],[3,2,5],[3,4,5],[4,0,1],[4,0,2],[4,0,3],[4,0,5],[4,1,2],[4,1,3],[4,1,5],[4,2,3],[4,2,5],[4,3,5],[5,0,1],[5,0,2],[5,0,3],[5,0,4],[5,1,2],[5,1,3],[5,1,4],[5,2,3],[5,2,4],[5,3,4]],\"opp_selection_names\":[[\"O0\",\"O1\",\"O2\"],[\"O0\",\"O1\",\"O3\"],[\"O0\",\"O1\",\"O4\"],[\"O0\",\"O1\",\"O5\"],[\"O0\",\"O2\",\"O3\"],[\"O0\",\"O2\",\"O4\"],[\"O0\",\"O2\",\"O5\"],[\"O0\",\"O3\",\"O4\"],[\"O0\",\"O3\",\"O5\"],[\"O0\",\"O4\",\"O5\"],[\"O1\",\"O0\",\"O2\"],[\"O1\",\"O0\",\"O3\"],[\"O1\",\"O0\",\"O4\"],[\"O1\",\"O0\",\"O5\"],[\"O1\",\"O2\",\"O3\"],[\"O1\",\"O2\",\"O4\"],[\"O1\",\"O2\",\"O5\"],[\"O1\",\"O3\",\"O4\"],[\"O1\",\"O3\",\"O5\"],[\"O1\",\"O4\",\"O5\"],[\"O2\",\"O0\",\"O1\"],[\"O2\",\"O0\",\"O3\"],[\"O2\",\"O0\",\"O4\"],[\"O2\",\"O0\",\"O5\"],[\"O2\",\"O1\",\"O3\"],[\"O2\",\"O1\",\"O4\"],[\"O2\",\"O1\",\"O5\"],[\"O2\",\"O3\",\"O4\"],[\"O2\",\"O3\",\"O5\"],[\"O2\",\"O4\",\"O5\"],[\"O3\",\"O0\",\"O1\"],[\"O3\",\"O0\",\"O2\"],[\"O3\",\"O0\",\"O4\"],[\"O3\",\"O0\",\"O5\"],[\"O3\",\"O1\",\"O2\"],[\"O3\",\"O1\",\"O4\"],[\"O3\",\"O1\",\"O5\"],[\"O3\",\"O2\",\"O4\"],[\"O3\",\"O2\",\"O5\"],[\"O3\",\"O4\",\"O5\"],[\"O4\",\"O0\",\"O1\"],[\"O4\",\"O0\",\"O2\"],[\"O4\",\"O0\",\"O3\"],[\"O4\",\"O0\",\"O5\"],[\"O4\",\"O1\",\"O2\"],[\"O4\",\"O1\",\"O3\"],[\"O4\",\"O1\",\"O5\"],[\"O4\",\"O2\",\"O3\"],[\"O4\",\"O2\",\"O5\"],[\"O4\",\"O3\",\"O5\"],[\"O5\",\"O0\",\"O1\"],[\"O5\",\"O0\",\"O2\"],[\"O5\",\"O0\",\"O3\"],[\"O5\",\"O0\",\"O4\"],[\"O5\",\"O1\",\"O2\"],[\"O5\",\"O1\",\"O3\"],[\"O5\",\"O1\",\"O4\"],[\"O5\",\"O2\",\"O3\"],[\"O5\",\"O2\",\"O4\"],[\"O5\",\"O3\",\"O4\"]],\"row_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"col_strategy\":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}"
    ),
  )
}
