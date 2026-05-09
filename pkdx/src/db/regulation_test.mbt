test "available_regulations: contains M-A" {
  let regs = available_regulations()
  assert_true(regs.contains("M-A"))
}

test "canonicalize_regulation: accepts lowercase 'm-a' (PR test plan)" {
  debug_inspect(canonicalize_regulation("m-a"), content="Some(\"M-A\")")
}

test "canonicalize_regulation: accepts canonical 'M-A'" {
  debug_inspect(canonicalize_regulation("M-A"), content="Some(\"M-A\")")
}

test "canonicalize_regulation: rejects unknown names" {
  debug_inspect(canonicalize_regulation("M-Z"), content="None")
}
