///|
/// もらいび状態の MC。吸収で slot が立ち、炎技の実ダメージだけ 1.5 倍。
/// 非炎は同じロール。rollout では先に吸収したターンの炎技が後攻より大きい。

///|
fn ffmc_mon(
  moves : Array[@model.Move],
  hp : Int,
  spe : Int,
  ability : String,
  type1 : String,
) -> Combatant {
  let c = crash_mon("M", moves, hp, type1~, spe~, ability~)
  { ..c, pokemon: { ..c.pokemon, hp } }
}

///|
fn ffmc_post(ability : String, mv : @model.Move, defender_hp : Int) -> Array[Bool] {
  let flags = [false]
  team_apply_post_hit(
    [200],
    0,
    [0, 0, 0, 0, 0],
    [false],
    [@model.None],
    [-1],
    [crash_mon("Atk", [mv], 200)],
    [defender_hp],
    0,
    [0, 0, 0, 0, 0],
    [false],
    [crash_mon("Holder", [im_tackle()], 200, ability=ability)],
    [false],
    [@model.Weather::None],
    [0],
    [@model.Field::None],
    [0],
    mv,
    60,
    defender_flash_fire=flags,
  )
  flags
}

///|
test "MC: もらいびは炎を吸収すると状態になり、瀕死とにほんばれではならない" {
  let fire = mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)
  @debug.assert_eq(ffmc_post("もらいび", fire, 100), [true])
  @debug.assert_eq(ffmc_post("もらいび", fire, 0), [false])
  @debug.assert_eq(ffmc_post("ちくでん", fire, 100), [false])
  let sun = {
    ..mk_move("にほんばれ", "ほのお", @model.Status, 0),
    weather_set: Some(@model.Sun),
  }
  @debug.assert_eq(ffmc_post("もらいび", sun, 100), [false])
}

///|
test "MC: もらいび状態の炎技だけダメージが増え、たいあたりは同じロール" {
  let fire = mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)
  let tackle = im_tackle()
  let atk = crash_mon("FF", [fire, tackle], 500, ability="もらいび")
  let dfn = crash_mon("Foe", [tackle], 500, type1="くさ")
  let ranks = [0, 0, 0, 0, 0]
  let (hp_off, _, _, immune_off) = team_perform_attack(
    atk, dfn, 500, fire, seeded_rng(7UL), ranks, ranks, atk_flash_fire=false,
  )
  let (hp_on, _, _, immune_on) = team_perform_attack(
    atk, dfn, 500, fire, seeded_rng(7UL), ranks, ranks, atk_flash_fire=true,
  )
  @debug.assert_eq(immune_off, false)
  @debug.assert_eq(immune_on, false)
  assert_true(hp_on < hp_off)
  let (t_off, _, _, _) = team_perform_attack(
    atk, dfn, 500, tackle, seeded_rng(7UL), ranks, ranks, atk_flash_fire=false,
  )
  let (t_on, _, _, _) = team_perform_attack(
    atk, dfn, 500, tackle, seeded_rng(7UL), ranks, ranks, atk_flash_fire=true,
  )
  @debug.assert_eq(t_off, t_on)
}

///|
test "MC: 相手の炎を先に受けると、同じロールでも rollout の与ダメージが大きい" {
  let fire = mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)
  let slow = ffmc_mon([fire], 800, 50, "もらいび", "ほのお")
  let fast = ffmc_mon([fire], 800, 200, "もらいび", "ほのお")
  let foe_slow = ffmc_mon([fire], 800, 200, "", "くさ")
  let foe_fast = ffmc_mon([fire], 800, 50, "", "くさ")
  // 自分が遅い: 相手の炎を先に吸収し、1 ターン目から 1.5 倍。
  let boosted = team_rollout(
    [slow], [foe_slow], seeded_rng(3UL), turn_limit=2, epsilon=0.0,
  )
  // 自分が速い: 1 ターン目は未発動のまま撃ち、2 ターン目から 1.5 倍。
  let partial = team_rollout(
    [fast], [foe_fast], seeded_rng(3UL), turn_limit=2, epsilon=0.0,
  )
  assert_true(boosted > partial)
}
