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
test "select golden: 6v6 single, balanced same-speed teams" {
  let speeds = [100, 100, 100, 100, 100, 100]
  let out = run_select(build_select_input(speeds, speeds))
  inspect(out, content=(
    #|{"format":"single","value":0,"exploitability":0,"selections":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,3,4],[2,3,5],[2,4,5],[3,4,5]],"selection_names":[["T0","T1","T2"],["T0","T1","T3"],["T0","T1","T4"],["T0","T1","T5"],["T0","T2","T3"],["T0","T2","T4"],["T0","T2","T5"],["T0","T3","T4"],["T0","T3","T5"],["T0","T4","T5"],["T1","T2","T3"],["T1","T2","T4"],["T1","T2","T5"],["T1","T3","T4"],["T1","T3","T5"],["T1","T4","T5"],["T2","T3","T4"],["T2","T3","T5"],["T2","T4","T5"],["T3","T4","T5"]],"opp_selections":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,3,4],[2,3,5],[2,4,5],[3,4,5]],"opp_selection_names":[["O0","O1","O2"],["O0","O1","O3"],["O0","O1","O4"],["O0","O1","O5"],["O0","O2","O3"],["O0","O2","O4"],["O0","O2","O5"],["O0","O3","O4"],["O0","O3","O5"],["O0","O4","O5"],["O1","O2","O3"],["O1","O2","O4"],["O1","O2","O5"],["O1","O3","O4"],["O1","O3","O5"],["O1","O4","O5"],["O2","O3","O4"],["O2","O3","O5"],["O2","O4","O5"],["O3","O4","O5"]],"row_strategy":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"col_strategy":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}
  ))
}

///|
test "select golden: 6v6 single, team faster than opponent" {
  let team_speeds = [120, 115, 110, 105, 100, 95]
  let opp_speeds = [80, 75, 70, 65, 60, 55]
  let out = run_select(build_select_input(team_speeds, opp_speeds))
  inspect(out, content=(
    #|{"format":"single","value":0,"exploitability":0,"selections":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,3,4],[2,3,5],[2,4,5],[3,4,5]],"selection_names":[["T0","T1","T2"],["T0","T1","T3"],["T0","T1","T4"],["T0","T1","T5"],["T0","T2","T3"],["T0","T2","T4"],["T0","T2","T5"],["T0","T3","T4"],["T0","T3","T5"],["T0","T4","T5"],["T1","T2","T3"],["T1","T2","T4"],["T1","T2","T5"],["T1","T3","T4"],["T1","T3","T5"],["T1","T4","T5"],["T2","T3","T4"],["T2","T3","T5"],["T2","T4","T5"],["T3","T4","T5"]],"opp_selections":[[0,1,2],[0,1,3],[0,1,4],[0,1,5],[0,2,3],[0,2,4],[0,2,5],[0,3,4],[0,3,5],[0,4,5],[1,2,3],[1,2,4],[1,2,5],[1,3,4],[1,3,5],[1,4,5],[2,3,4],[2,3,5],[2,4,5],[3,4,5]],"opp_selection_names":[["O0","O1","O2"],["O0","O1","O3"],["O0","O1","O4"],["O0","O1","O5"],["O0","O2","O3"],["O0","O2","O4"],["O0","O2","O5"],["O0","O3","O4"],["O0","O3","O5"],["O0","O4","O5"],["O1","O2","O3"],["O1","O2","O4"],["O1","O2","O5"],["O1","O3","O4"],["O1","O3","O5"],["O1","O4","O5"],["O2","O3","O4"],["O2","O3","O5"],["O2","O4","O5"],["O3","O4","O5"]],"row_strategy":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"col_strategy":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}
  ))
}
