///|
/// ガブリアス (108/130/95/80/85/102) ドラゴン/じめん
fn fixture_garchomp() -> @model.Pokemon {
  mk_pokemon_typed(
    "ガブリアス", "ドラゴン", "じめん", 108, 130, 95, 80, 85, 102,
  )
}

///|
/// じしん (じめん, 物理, 威力100) — STAB for ガブリアス
fn fixture_earthquake() -> @model.Move {
  mk_move("じしん", "じめん", @model.Physical, 100)
}

///|
test "calc_damage: baseline (no rank)" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content="84")
}

///|
test "calc_damage: atk_rank +2 doubles damage" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=2,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content="166")
}

///|
test "calc_damage: def_rank +2 halves damage" {
  let input = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=2,
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content="43")
}

///|
test "calc_damage: crit ignores atk negative rank" {
  let with_neg = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=-2,
    critical=true,
  )
  let without_neg = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_neg)
  let r2 = calc_damage(without_neg)
  inspect(r1.max_damage == r2.max_damage, content="true")
}

///|
test "calc_damage: crit ignores def positive rank" {
  let with_pos = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=2,
    critical=true,
  )
  let without_pos = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_pos)
  let r2 = calc_damage(without_pos)
  inspect(r1.max_damage == r2.max_damage, content="true")
}

///|
test "calc_damage: crit preserves atk positive rank" {
  let with_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=2,
    critical=true,
  )
  let without_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_rank)
  let r2 = calc_damage(without_rank)
  inspect(r1.max_damage != r2.max_damage, content="true")
}

///|
test "calc_damage: crit preserves def negative rank" {
  let with_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=-2,
    critical=true,
  )
  let without_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    def_rank=0,
    critical=true,
  )
  let r1 = calc_damage(with_rank)
  let r2 = calc_damage(without_rank)
  inspect(r1.max_damage != r2.max_damage, content="true")
}

///|
test "calc_damage: override ignores rank" {
  let with_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_stat_override=200,
    atk_rank=2,
  )
  let without_rank = mk_damage_input(
    fixture_garchomp(),
    fixture_garchomp(),
    fixture_earthquake(),
    atk_stat_override=200,
    atk_rank=0,
  )
  let r1 = calc_damage(with_rank)
  let r2 = calc_damage(without_rank)
  inspect(r1.max_damage == r2.max_damage, content="true")
}

///|
test "calc_damage: rank order matters with ability (ちからもち + rank +1)" {
  let atk = {
    ..fixture_garchomp(),
    ability1: "ちからもち",
  }
  let input = mk_damage_input(
    atk,
    fixture_garchomp(),
    fixture_earthquake(),
    atk_rank=1,
    atk_ability="ちからもち",
  )
  let result = calc_damage(input)
  inspect(result.max_damage, content="247")
}
