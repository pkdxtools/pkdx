///|
test "is_reflect_move identifies all four reflect moves" {
  @debug.debug_inspect(is_reflect_move("カウンター"), content="Some(Counter)")
  @debug.debug_inspect(is_reflect_move("ミラーコート"), content="Some(MirrorCoat)")
  @debug.debug_inspect(is_reflect_move("メタルバースト"), content="Some(MetalBurst)")
  @debug.debug_inspect(is_reflect_move("ほうふく"), content="Some(Revenge)")
}

///|
test "is_reflect_move returns None for non-reflect moves" {
  @debug.debug_inspect(is_reflect_move("じしん"), content="None")
  @debug.debug_inspect(is_reflect_move("ハイドロポンプ"), content="None")
  @debug.debug_inspect(is_reflect_move(""), content="None")
}

///|
test "reflect_multiplier integer fractions" {
  @debug.debug_inspect(reflect_multiplier(Counter), content="(2, 1)")
  @debug.debug_inspect(reflect_multiplier(MirrorCoat), content="(2, 1)")
  @debug.debug_inspect(reflect_multiplier(MetalBurst), content="(3, 2)")
  @debug.debug_inspect(reflect_multiplier(Revenge), content="(3, 2)")
}

///|
test "reflect_move_type returns the move's own type" {
  @debug.debug_inspect(reflect_move_type(Counter), content="\"かくとう\"")
  @debug.debug_inspect(reflect_move_type(MirrorCoat), content="\"エスパー\"")
  @debug.debug_inspect(reflect_move_type(MetalBurst), content="\"はがね\"")
  @debug.debug_inspect(reflect_move_type(Revenge), content="\"あく\"")
}

///|
test "reflect_accepts_category: Counter is physical only" {
  @debug.debug_inspect(
    reflect_accepts_category(Counter, @model.Physical),
    content="true",
  )
  @debug.debug_inspect(
    reflect_accepts_category(Counter, @model.Special),
    content="false",
  )
  @debug.debug_inspect(
    reflect_accepts_category(Counter, @model.Status),
    content="false",
  )
}

///|
test "reflect_accepts_category: MirrorCoat is special only" {
  @debug.debug_inspect(
    reflect_accepts_category(MirrorCoat, @model.Physical),
    content="false",
  )
  @debug.debug_inspect(
    reflect_accepts_category(MirrorCoat, @model.Special),
    content="true",
  )
  @debug.debug_inspect(
    reflect_accepts_category(MirrorCoat, @model.Status),
    content="false",
  )
}

///|
test "reflect_accepts_category: MetalBurst / Revenge accept both physical and special" {
  for kind in [MetalBurst, Revenge] {
    @debug.debug_inspect(
      reflect_accepts_category(kind, @model.Physical),
      content="true",
    )
    @debug.debug_inspect(
      reflect_accepts_category(kind, @model.Special),
      content="true",
    )
    @debug.debug_inspect(
      reflect_accepts_category(kind, @model.Status),
      content="false",
    )
  }
}
