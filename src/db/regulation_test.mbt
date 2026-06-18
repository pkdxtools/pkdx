///|
test "available_regulations: contains M-B" {
  let regs = available_regulations()
  assert_true(regs.contains("M-B"))
}

///|
test "canonicalize_regulation: accepts lowercase 'm-b'" {
  assert_true(canonicalize_regulation("m-b") == Some("M-B"))
}

///|
test "canonicalize_regulation: accepts canonical 'M-B'" {
  assert_true(canonicalize_regulation("M-B") == Some("M-B"))
}

///|
test "canonicalize_regulation: rejects unknown names" {
  assert_true(canonicalize_regulation("M-Z") == None)
}

///|
test "canonicalize_regulation: rejects retired M-A" {
  // M-A は M-B 移行に伴い退役。`pkdx regulation set M-A` は弾く。
  assert_true(canonicalize_regulation("M-A") == None)
}
