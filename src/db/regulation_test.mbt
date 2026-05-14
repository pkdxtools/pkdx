test "available_regulations: contains M-A" {
  let regs = available_regulations()
  assert_true(regs.contains("M-A"))
}

test "canonicalize_regulation: accepts lowercase 'm-a' (PR test plan)" {
  assert_true(canonicalize_regulation("m-a") == Some("M-A"))
}

test "canonicalize_regulation: accepts canonical 'M-A'" {
  assert_true(canonicalize_regulation("M-A") == Some("M-A"))
}

test "canonicalize_regulation: rejects unknown names" {
  assert_true(canonicalize_regulation("M-Z") == None)
}
