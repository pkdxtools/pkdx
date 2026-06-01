///|
test "to_waza_version: champions maps to Champions" {
  @debug.debug_inspect(
    to_waza_version("champions"),
    content=(
      #|"Champions"
    ),
  )
}

///|
test "to_waza_version: scarlet_violet maps to Scarlet_Violet" {
  @debug.debug_inspect(
    to_waza_version("scarlet_violet"),
    content=(
      #|"Scarlet_Violet"
    ),
  )
}

///|
test "to_waza_version: legendsza maps to LegendsZA" {
  @debug.debug_inspect(
    to_waza_version("legendsza"),
    content=(
      #|"LegendsZA"
    ),
  )
}

///|
test "to_waza_version: unknown version passes through" {
  @debug.debug_inspect(
    to_waza_version("unknown_version"),
    content=(
      #|"unknown_version"
    ),
  )
}
