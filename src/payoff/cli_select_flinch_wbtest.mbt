///|
/// `pkdx select` の JSON 入力 (moves[].flinch_chance) の読み取り。省略は 0 (ひるみなし)。
/// DB 経路の値は move_meta.flinch_chance (m019) から入るので、JSON 入力は手動の指定に限る。
test "parse_move_json: flinch_chance is read as the per-hit percentage (absent -> 0)" {
  let with_flinch = @json.parse(
    "{\"name\":\"かみつく\",\"power\":60,\"flinch_chance\":30}",
  ) catch {
    _ => fail("json parse failed")
  }
  let without = @json.parse("{\"name\":\"たいあたり\",\"power\":40}") catch {
    _ => fail("json parse failed")
  }
  let mv1 = parse_move_json(with_flinch, "moves[0]") catch {
    _ => fail("parse_move_json failed")
  }
  let mv2 = parse_move_json(without, "moves[1]") catch {
    _ => fail("parse_move_json failed")
  }
  assert_true(mv1.flinch_chance == 30)
  assert_true(mv2.flinch_chance == 0)
}
