///|
test "available_regulations: contains M-C" {
  let regs = available_regulations()
  assert_true(regs.contains("M-C"))
}

///|
test "canonicalize_regulation: accepts lowercase 'm-c'" {
  assert_true(canonicalize_regulation("m-c") == Some("M-C"))
}

///|
test "canonicalize_regulation: accepts canonical 'M-C'" {
  assert_true(canonicalize_regulation("M-C") == Some("M-C"))
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

///|
test "canonicalize_regulation: rejects retired M-B" {
  // M-B は M-C 移行に伴い退役。`pkdx regulation set M-B` は弾く。
  assert_true(canonicalize_regulation("M-B") == None)
}
