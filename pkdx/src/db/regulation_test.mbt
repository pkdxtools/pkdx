test "is_available: M-A accepts listed pokemon" {
  // ガブリアス (globalNo 0445) は M-A 参戦
  assert_true(is_available("0445", "M-A"))
}

test "is_available: M-A rejects unlisted pokemon" {
  assert_false(is_available("9999", "M-A"))
}

test "is_available: empty regulation accepts all" {
  assert_true(is_available("0445", ""))
}

test "is_available: unknown regulation accepts all" {
  assert_true(is_available("0445", "UNKNOWN"))
}

test "available_regulations: contains M-A" {
  let regs = available_regulations()
  assert_true(regs.contains("M-A"))
}
