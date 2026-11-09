///|
/// Bit-exact round trip of the shard matrix wire:
/// `format_shard_cell` → JSON parse → `decode_shard_json_cell`.
/// Cells are IEEE-754 bits as 16 hex digits, because `Double.to_string`
/// prints `-0.0` as `0`. Bits are compared with `reinterpret_as_uint64`.

///|
fn shard_bits_mismatch(label : String, x : Double) -> String raise PayoffError {
  let y = parse_shard_cell(format_shard_cell(x))
  let xb = x.reinterpret_as_uint64()
  let yb = y.reinterpret_as_uint64()
  if xb == yb {
    ""
  } else {
    label +
    " bits diverged: in=" +
    xb.to_string() +
    " out=" +
    yb.to_string() +
    " token=" +
    format_shard_cell(x)
  }
}

///|
fn rt_pair() -> (Array[Combatant], Array[Combatant]) {
  let mk = fn(name : String, hp : Int, spe : Int) -> Combatant {
    mk_combatant(
      mk_pokemon(name, "ノーマル", "", hp, 100, 80, 70, 75, spe),
      [mk_move("のしかかり", "ノーマル", @model.Physical, 85)],
    )
  }
  (
    [mk("A0", 100, 120), mk("A1", 110, 100), mk("A2", 90, 80)],
    [mk("B0", 105, 110), mk("B1", 95, 90), mk("B2", 130, 70)],
  )
}

///|
test "shard double wire roundtrip preserves bits" {
  let (own, opp) = rt_pair()
  let own2 = [own[2], own[0], own[1]]
  let opp2 = [opp[1], opp[2], opp[0]]
  let checks = [
    ("0.1", 0.1),
    ("1/3", 1.0 / 3.0),
    ("-0.0", -0.0),
    ("+0.0", 0.0),
    ("1e-300", 1.0e-300),
    ("1e300", 1.0e300),
    ("subnormal-min", (1UL).reinterpret_as_double()),
    ("subnormal-max", (0x000FFFFFFFFFFFFFUL).reinterpret_as_double()),
    (
      "mc-cell-0",
      team_monte_carlo_value(own, opp, 24, 7UL, turn_limit=2),
    ),
    (
      "mc-cell-1",
      team_monte_carlo_value(own, opp, 24, 99UL, turn_limit=3),
    ),
    (
      "mc-cell-2",
      team_monte_carlo_value(own2, opp2, 16, 12345UL, turn_limit=2),
    ),
    ("dp-cell-0", switching_game_winrate(own, opp, 2)),
    ("dp-cell-1", switching_game_winrate(own2, opp2, 2)),
    ("dp-cell-2", switching_game_winrate(opp, own, 1)),
  ]
  let mut bad = ""
  for pair in checks {
    let (label, x) = pair
    let msg = shard_bits_mismatch(label, x)
    if msg.length() > 0 {
      if bad.length() > 0 {
        bad = bad + "\n"
      }
      bad = bad + msg
    }
  }
  if bad.length() > 0 {
    abort(bad)
  }
}

///|
/// True when `parse_shard_cell` raises for `token`.
fn shard_cell_rejects(token : String) -> Bool {
  let mut rejected = false
  let _ = try parse_shard_cell(token) catch {
    _ => {
      rejected = true
      0.0
    }
  }
  rejected
}

///|
test "shard double wire keeps NaN and inf bits and rejects malformed cells" {
  let checks = [
    ("qNaN", (0x7FF8000000000000UL).reinterpret_as_double()),
    ("qNaN-payload", (0x7FF8000000000001UL).reinterpret_as_double()),
    ("-qNaN", (0xFFF8000000000000UL).reinterpret_as_double()),
    ("+inf", (0x7FF0000000000000UL).reinterpret_as_double()),
    ("-inf", (0xFFF0000000000000UL).reinterpret_as_double()),
  ]
  let mut bad = ""
  for pair in checks {
    let (label, x) = pair
    let msg = shard_bits_mismatch(label, x)
    if msg.length() > 0 {
      if bad.length() > 0 {
        bad = bad + "\n"
      }
      bad = bad + msg
    }
  }
  if bad.length() > 0 {
    abort(bad)
  }
  // Only a 16-digit JSON string is a cell. Numbers, wrong lengths and
  // non-hex digits must all raise instead of decoding to some value.
  let malformed = [
    "0.5",
    "\"\"",
    "\"3ff000000000000\"",
    "\"3ff00000000000000\"",
    "\"3ff000000000000g\"",
  ]
  for token in malformed {
    @debug.assert_eq(shard_cell_rejects(token), true)
  }
  // Uppercase hex is accepted and decodes to 1.0.
  @debug.assert_eq(shard_cell_rejects("\"3FF0000000000000\""), false)
}
