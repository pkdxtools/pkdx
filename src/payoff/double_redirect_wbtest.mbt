///|
fn de_mon(
  name : String,
  type1 : String,
  hp : Int,
  atk : Int,
  def_ : Int,
  spa : Int,
  spd : Int,
  spe : Int,
  mv : @model.Move,
  ability? : String = "",
) -> Combatant {
  {
    pokemon: mk_pokemon(name, type1, "", hp, atk, def_, spa, spd, spe),
    moves: [mv],
    ability,
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
    gender: Gender::Unknown,
  }
}

///|
fn de_four(
  a : Combatant,
  b : Combatant,
  c : Combatant,
  d : Combatant,
) -> Array[Combatant] {
  [a, b, c, d]
}

///|
fn de_splash() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
fn de_field(
  my : Array[Combatant],
  opp : Array[Combatant],
  my_t : Array[Array[Int]],
  opp_t : Array[Array[Int]],
  my_left : @doubles.DoubleAction?,
  my_right : @doubles.DoubleAction?,
  opp_left : @doubles.DoubleAction?,
  opp_right : @doubles.DoubleAction?,
) -> DoubleFieldHp {
  let (_, field) = scripted_turn_field(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    my_left,
    my_right,
    opp_left,
    opp_right,
    [],
  )
  field
}

///|
test "follow me pulls a chosen foe move onto the user" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let follow = mk_move("このゆびとまれ", "ノーマル", @model.Status, 0, priority=2)
  let frail = de_mon("Frail", "ノーマル", 220, 40, 80, 40, 80, 20, de_splash())
  let user = de_mon("User", "ノーマル", 260, 40, 90, 40, 90, 30, follow)
  let foe = de_mon("Foe", "ノーマル", 200, 170, 80, 40, 80, 80, hit)
  let dead = dg_dead()
  let my = de_four(frail, user, dead, dead)
  let opp = dg_side(foe)
  let field = de_field(
    my,
    opp,
    [[7], [7], [7], [7]],
    dg_targets([0]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let dmg = double_move_mean(foe, user, hit)
  assert_true(dmg > 0)
  assert_true(field.my_hp[0] == 220)
  assert_true(field.my_hp[1] == 260 - dmg)
}

///|
test "spread moves are not pulled by follow me" {
  let hit = mk_move("じしん", "じめん", @model.Physical, 90)
  let follow = mk_move("このゆびとまれ", "ノーマル", @model.Status, 0, priority=2)
  let left = de_mon("Left", "ノーマル", 300, 40, 100, 40, 100, 20, de_splash())
  let user = de_mon("User", "ノーマル", 300, 40, 100, 40, 100, 25, follow)
  let foe = de_mon("Foe", "じめん", 240, 160, 90, 40, 90, 70, hit)
  let dead = dg_dead()
  let field = de_field(
    de_four(left, user, dead, dead),
    dg_side(foe),
    [[7], [7], [7], [7]],
    dg_targets([4]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    None,
  )
  let on_left = double_move_mean(foe, left, hit)
  let on_user = double_move_mean(foe, user, hit)
  assert_true(on_left > 0 && on_user > 0)
  assert_true(field.my_hp[0] == 300 - on_left)
  assert_true(field.my_hp[1] == 300 - on_user)
}

///|
test "rage powder ignores grass and overcoat and pulls everyone else" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 70)
  let rage = mk_move("いかりのこな", "むし", @model.Status, 0, priority=2)
  let user = de_mon("User", "むし", 240, 40, 80, 40, 80, 30, rage)
  let frail = de_mon("Frail", "ノーマル", 240, 40, 80, 40, 80, 15, de_splash())
  let dead = dg_dead()
  let my = de_four(frail, user, dead, dead)
  let plain = de_mon("Plain", "ノーマル", 200, 150, 80, 40, 80, 60, hit)
  let grass = de_mon("Grass", "くさ", 200, 150, 80, 40, 80, 60, hit)
  let coat = de_mon("Coat", "ノーマル", 200, 150, 80, 40, 80, 60, hit, ability="ぼうじん")
  let dmg_user = double_move_mean(plain, user, hit)
  let pulled = de_field(
    my,
    dg_side(plain),
    [[7], [7], [7], [7]],
    dg_targets([0]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(pulled.my_hp[0] == 240)
  assert_true(pulled.my_hp[1] == 240 - dmg_user)
  for foe in [grass, coat] {
    let skipped = de_field(
      my,
      dg_side(foe),
      [[7], [7], [7], [7]],
      dg_targets([0]),
      Some(@doubles.Use(0)),
      Some(@doubles.Use(0)),
      Some(@doubles.UseOn(0, @doubles.MyLeft)),
      None,
    )
    let dealt = double_move_mean(foe, frail, hit)
    assert_true(dealt > 0 && dealt < 240)
    assert_true(skipped.my_hp[0] == 240 - dealt)
    assert_true(skipped.my_hp[1] == 240)
  }
}

///|
test "the later redirect wins and powder immunity falls back to follow me" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 60)
  let follow = mk_move("このゆびとまれ", "ノーマル", @model.Status, 0, priority=2)
  let rage = mk_move("いかりのこな", "むし", @model.Status, 0, priority=2)
  let fast = de_mon("Fast", "ノーマル", 220, 40, 80, 40, 80, 120, follow)
  let slow = de_mon("Slow", "むし", 220, 40, 80, 40, 80, 40, rage)
  let dead = dg_dead()
  let my = de_four(fast, slow, dead, dead)
  let plain = de_mon("Plain", "ノーマル", 180, 140, 70, 40, 70, 30, hit)
  let grass = de_mon("Grass", "くさ", 180, 140, 70, 40, 70, 30, hit)
  let on_slow = double_move_mean(plain, slow, hit)
  let on_fast_grass = double_move_mean(grass, fast, hit)
  let normal = de_field(
    my,
    dg_side(plain),
    [[7], [7], [7], [7]],
    dg_targets([0]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(normal.my_hp[0] == 220)
  assert_true(normal.my_hp[1] == 220 - on_slow)
  let immune = de_field(
    my,
    dg_side(grass),
    [[7], [7], [7], [7]],
    dg_targets([0]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(immune.my_hp[0] == 220 - on_fast_grass)
  assert_true(immune.my_hp[1] == 220)
}

///|
test "a higher priority hit lands before follow me is set" {
  let hit = mk_move("ねこだまし", "ノーマル", @model.Physical, 40, priority=3)
  let follow = mk_move("このゆびとまれ", "ノーマル", @model.Status, 0, priority=2)
  let frail = de_mon("Frail", "ノーマル", 200, 40, 70, 40, 70, 10, de_splash())
  let user = de_mon("User", "ノーマル", 200, 40, 70, 40, 70, 90, follow)
  let foe = de_mon("Foe", "ノーマル", 180, 160, 70, 40, 70, 20, hit)
  let dead = dg_dead()
  let field = de_field(
    de_four(frail, user, dead, dead),
    dg_side(foe),
    [[7], [7], [7], [7]],
    dg_targets([0]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let dmg = double_move_mean(foe, frail, hit)
  assert_true(dmg > 0)
  assert_true(field.my_hp[0] == 200 - dmg)
  assert_true(field.my_hp[1] == 200)
}

///|
test "fainting the follow me user ends the redirect" {
  let spread = mk_move("じしん", "じめん", @model.Physical, 140)
  let single = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  let follow = mk_move("このゆびとまれ", "ノーマル", @model.Status, 0, priority=2)
  let partner = de_mon("Partner", "ノーマル", 500, 40, 140, 40, 140, 10, de_splash())
  let user = de_mon("User", "ノーマル", 40, 40, 40, 40, 40, 15, follow)
  let fast = de_mon("Fast", "じめん", 220, 180, 80, 40, 80, 130, spread)
  let slow = de_mon("Slow", "ノーマル", 220, 130, 80, 40, 80, 40, single)
  let dead = dg_dead()
  let spread_user = double_move_mean(fast, user, spread)
  let spread_partner = double_move_mean(fast, partner, spread)
  let single_partner = double_move_mean(slow, partner, single)
  assert_true(spread_user >= 40)
  assert_true(spread_partner > 0 && spread_partner < 500)
  assert_true(single_partner > 0)
  let field = de_field(
    de_four(partner, user, dead, dead),
    de_four(fast, slow, dead, dead),
    [[7], [7], [7], [7]],
    [[4], [0], [7], [7]],
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
  )
  assert_true(field.my_hp[1] == 0)
  assert_true(field.my_hp[0] == 500 - spread_partner - single_partner)
}

///|
test "leaf prune keeps follow me and rage powder and drops a worse hit" {
  let weak = mk_move("たいあたり", "ノーマル", @model.Physical, 30)
  let strong = mk_move("たいあたり", "ノーマル", @model.Physical, 110)
  let follow = mk_move("このゆびとまれ", "ノーマル", @model.Status, 0, priority=2)
  let rage = mk_move("いかりのこな", "むし", @model.Status, 0, priority=2)
  let endure = mk_move("こらえる", "ノーマル", @model.Status, 0, priority=4)
  let mon = mk_combatant(
    mk_pokemon("Both", "ノーマル", "", 180, 160, 80, 40, 80, 90),
    [weak, strong, follow, rage, endure],
  )
  let foe = de_mon("Foe", "ノーマル", 200, 40, 80, 40, 80, 40, strong)
  let targets = [0, 0, 7, 7, 7]
  let actions : Array[@doubles.DoubleAction] = [
    @doubles.Use(0),
    @doubles.Use(1),
    @doubles.Use(2),
    @doubles.Use(3),
    @doubles.Use(4),
  ]
  let leaf = prune_slot_actions(
    new_double_eval(),
    mon,
    targets,
    actions,
    [foe],
    [],
    true,
  )
  let names = dg_names(mon, leaf)
  assert_true(dg_has(names, "このゆびとまれ"))
  assert_true(dg_has(names, "いかりのこな"))
  assert_true(dg_has(names, "たいあたり"))
  assert_true(!dg_has(names, "こらえる"))
  let mut saw_weak = false
  let mut saw_strong = false
  for action in leaf {
    match double_slot_move(mon, action) {
      Some(mv) =>
        if mv.power == 30 {
          saw_weak = true
        } else if mv.power == 110 {
          saw_strong = true
        }
      None => ()
    }
  }
  assert_true(saw_strong && !saw_weak)
}

///|
test "a dominated single target stays dominated beside follow me" {
  let weak = mk_move("たいあたり", "ノーマル", @model.Physical, 25)
  let strong = mk_move("たいあたり", "ノーマル", @model.Physical, 100)
  let follow = mk_move("このゆびとまれ", "ノーマル", @model.Status, 0, priority=2)
  let endure = mk_move("こらえる", "ノーマル", @model.Status, 0, priority=4)
  let with_weak = mk_combatant(
    mk_pokemon("Rich", "ノーマル", "", 280, 40, 180, 40, 160, 30),
    [weak, strong, follow],
  )
  let thin_mon = mk_combatant(
    mk_pokemon("Rich", "ノーマル", "", 280, 40, 180, 40, 160, 30),
    [strong, follow],
  )
  let no_draw = mk_combatant(
    mk_pokemon("Rich", "ノーマル", "", 280, 40, 180, 40, 160, 30),
    [strong, endure],
  )
  let finisher = mk_move("たいあたり", "ノーマル", @model.Physical, 140)
  let ally = de_mon("Ally", "ノーマル", 90, 240, 40, 40, 40, 50, finisher)
  let smasher = de_mon("Smash", "ノーマル", 160, 220, 80, 40, 80, 120, strong)
  let dead = dg_dead()
  let opp = de_four(smasher, dead, dead, dead)
  let opp_t = dg_targets([0])
  let cache = new_double_eval()
  let config = NashSolverConfig::default()
  let smash_ally = double_move_mean(smasher, ally, strong)
  let smash_user = double_move_mean(smasher, with_weak, strong)
  let reply = double_move_mean(ally, smasher, finisher)
  let chip = double_move_mean(with_weak, smasher, strong)
  assert_true(smash_ally >= 90)
  assert_true(smash_user > 0 && smash_user < 280)
  assert_true(reply >= 160)
  assert_true(chip > 0 && chip < 160)
  let rich = double_dp_cell(
    cache,
    de_four(with_weak, ally, dead, dead),
    opp,
    [[0, 0, 7], [0], [7], [7]],
    opp_t,
    config,
    2,
  )
  let thin = double_dp_cell(
    cache,
    de_four(thin_mon, ally, dead, dead),
    opp,
    [[0, 7], [0], [7], [7]],
    opp_t,
    config,
    2,
  )
  let blank = double_dp_cell(
    cache,
    de_four(no_draw, ally, dead, dead),
    opp,
    [[0, 7], [0], [7], [7]],
    opp_t,
    config,
    2,
  )
  assert_true(dg_gap(rich, thin) < 1.0e-9)
  assert_true(dg_gap(rich, blank) > 1.0e-4)
}

///|
test "lead intimidate drops both foes and only physical damage" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let special = mk_move("はかいこうせん", "ノーマル", @model.Special, 40)
  let splash = de_splash()
  let intim = de_mon("Intim", "ノーマル", 220, 40, 90, 40, 90, 20, splash, ability="いかく")
  let partner = de_mon("Mate", "ノーマル", 220, 40, 90, 40, 90, 15, splash)
  let physical = de_mon("Phys", "ノーマル", 200, 150, 80, 40, 80, 50, hit)
  let caster = de_mon("Spec", "ノーマル", 200, 40, 80, 150, 80, 45, special)
  let dead = dg_dead()
  let field = de_field(
    de_four(intim, partner, dead, dead),
    de_four(physical, caster, dead, dead),
    [[7], [7], [7], [7]],
    [[0], [0], [7], [7]],
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyRight)),
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
  )
  let physical_drop = double_move_mean(physical, partner, hit, stage=-1)
  let physical_open = double_move_mean(physical, partner, hit, stage=0)
  let special_open = double_move_mean(caster, intim, special, stage=0)
  assert_true(physical_drop > 0 && physical_drop < physical_open && physical_drop < 220)
  assert_true(special_open > 0 && special_open < 220)
  assert_true(field_rank(field, 2, 0) == -1)
  assert_true(field_rank(field, 3, 0) == -1)
  assert_true(field_rank(field, 3, 2) == 0)
  assert_true(field.my_hp[1] == 220 - physical_drop)
  assert_true(field.my_hp[0] == 220 - special_open)
  let stacked = de_field(
    de_four(intim, intim, dead, dead),
    de_four(physical, caster, dead, dead),
    [[7], [7], [7], [7]],
    [[0], [7], [7], [7]],
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyRight)),
    Some(@doubles.Use(0)),
  )
  let twice = double_move_mean(physical, intim, hit, stage=-2)
  assert_true(twice > 0 && twice < physical_drop)
  assert_true(field_rank(stacked, 2, 0) == -2)
  assert_true(field_rank(stacked, 3, 0) == -2)
  assert_true(stacked.my_hp[1] == 220 - twice)
}

///|
test "intimidate blockers and attack reactions match the singles helper" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 70)
  let special = mk_move("はかいこうせん", "ノーマル", @model.Special, 20)
  let splash = de_splash()
  let intim = de_mon("Intim", "ノーマル", 200, 40, 80, 40, 80, 40, splash, ability="いかく")
  let opp = dg_side(intim)
  let blockers = [
    "クリアボディ", "どんかん", "マイペース", "せいしんりょく", "きもったま", "かいりきバサミ",
    "しろいけむり",
  ]
  for ability in blockers {
    let mon = de_mon("Wall", "ノーマル", 180, 150, 80, 40, 80, 20, hit, ability~)
    let field = de_field(
      dg_side(mon),
      opp,
      dg_targets([0]),
      dg_targets([7]),
      Some(@doubles.UseOn(0, @doubles.FoeLeft)),
      None,
      Some(@doubles.Use(0)),
      None,
    )
    let dmg = double_move_mean(mon, intim, hit, stage=0)
    assert_true(field_rank(field, 0, 0) == 0)
    assert_true(field.opp_hp[0] == 200 - dmg)
  }
  let raised = ["ばんけん", "あまのじゃく", "まけんき"]
  for ability in raised {
    let mon = de_mon("Up", "ノーマル", 180, 150, 80, 40, 80, 20, hit, ability~)
    let field = de_field(
      dg_side(mon),
      opp,
      dg_targets([0]),
      dg_targets([7]),
      Some(@doubles.UseOn(0, @doubles.FoeLeft)),
      None,
      Some(@doubles.Use(0)),
      None,
    )
    let dmg = double_move_mean(mon, intim, hit, stage=1)
    assert_true(field_rank(field, 0, 0) == 1)
    assert_true(field.opp_hp[0] == 200 - dmg)
  }
  let comp = de_mon("Comp", "ノーマル", 180, 40, 80, 170, 80, 20, special, ability="かちき")
  let comp_field = de_field(
    dg_side(comp),
    opp,
    dg_targets([0]),
    dg_targets([7]),
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    None,
    Some(@doubles.Use(0)),
    None,
  )
  let boosted = double_move_mean(comp, intim, special, stage=2)
  let unboosted = double_move_mean(comp, intim, special, stage=0)
  assert_true(boosted > unboosted && boosted < 200)
  assert_true(field_rank(comp_field, 0, 0) == -1)
  assert_true(field_rank(comp_field, 0, 2) == 2)
  assert_true(comp_field.opp_hp[0] == 200 - boosted)
  let mirror = de_mon("Mirror", "はがね", 190, 140, 100, 40, 100, 20, hit, ability="ミラーアーマー")
  let mirror_field = de_field(
    dg_side(intim),
    dg_side(mirror),
    dg_targets([7]),
    dg_targets([0]),
    Some(@doubles.Use(0)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  let bounced = double_move_mean(mirror, intim, hit, stage=-1)
  let untouched = double_move_mean(mirror, intim, hit, stage=0)
  assert_true(bounced < untouched && untouched < 200)
  assert_true(field_rank(mirror_field, 0, 0) == -1)
  assert_true(field_rank(mirror_field, 2, 0) == 0)
  assert_true(mirror_field.my_hp[0] == 200 - untouched)
}

///|
test "rattled outspeeds after intimidate and moves first" {
  let mine = mk_move("たいあたり", "ノーマル", @model.Physical, 200)
  let theirs = mk_move("はかいこうせん", "ノーマル", @model.Special, 200)
  let me = de_mon("Me", "ノーマル", 90, 220, 40, 40, 40, 100, mine, ability="いかく")
  let rattled = de_mon("Rat", "ノーマル", 90, 40, 40, 220, 40, 70, theirs, ability="びびり")
  let immune = de_mon("Obl", "ノーマル", 90, 40, 40, 220, 40, 70, theirs, ability="どんかん")
  assert_true(double_move_mean(me, rattled, mine) >= 90)
  assert_true(double_move_mean(rattled, me, theirs) >= 90)
  let fast = de_field(
    dg_side(me),
    dg_side(rattled),
    dg_targets([0]),
    dg_targets([0]),
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(fast.my_hp[0] == 0)
  assert_true(fast.opp_hp[0] > 0)
  assert_true(field_rank(fast, 2, 4) == 1)
  let slow = de_field(
    dg_side(me),
    dg_side(immune),
    dg_targets([0]),
    dg_targets([0]),
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(slow.opp_hp[0] == 0)
  assert_true(slow.my_hp[0] > 0)
  assert_true(field_rank(slow, 2, 4) == 0)
}

///|
test "flower veil on a grass ally blocks intimidate" {
  let splash = de_splash()
  let grass = de_mon("Grass", "くさ", 180, 120, 80, 40, 80, 20, splash)
  let veil = de_mon("Veil", "フェアリー", 180, 80, 80, 40, 80, 15, splash, ability="フラワーベール")
  let intim = de_mon("Intim", "ノーマル", 180, 40, 80, 40, 80, 40, splash, ability="いかく")
  let dead = dg_dead()
  let field = de_field(
    de_four(grass, veil, dead, dead),
    dg_side(intim),
    [[7], [7], [7], [7]],
    dg_targets([7]),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    None,
  )
  assert_true(field_rank(field, 0, 0) == 0)
  assert_true(field_rank(field, 1, 0) == -1)
}

///|
test "a turn-1 switch stacks on the lead intimidate and clears a received drop" {
  let splash = de_splash()
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let lead = de_mon("Lead", "ノーマル", 200, 40, 80, 40, 80, 30, splash, ability="いかく")
  let bench = de_mon("Bench", "ノーマル", 200, 40, 80, 40, 80, 25, splash, ability="いかく")
  let plain = de_mon("Plain", "ノーマル", 200, 40, 80, 40, 80, 20, splash)
  let foe = de_mon("Foe", "ノーマル", 220, 160, 90, 40, 90, 40, hit)
  let dead = dg_dead()
  let stacked = de_field(
    de_four(lead, plain, bench, dead),
    dg_side(foe),
    [[7], [7], [7], [7]],
    dg_targets([0]),
    Some(@doubles.BenchTo(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.UseOn(0, @doubles.MyRight)),
    None,
  )
  let dropped = double_move_mean(foe, plain, hit, stage=-2)
  assert_true(field_rank(stacked, 2, 0) == -2)
  assert_true(stacked.my_hp[1] == 200 - dropped)
  let stayed = de_mon("Stay", "ノーマル", 180, 100, 80, 40, 80, 20, splash)
  let cleared = de_field(
    de_four(stayed, plain, plain, dead),
    dg_side(lead),
    [[7], [7], [7], [7]],
    dg_targets([7]),
    Some(@doubles.BenchTo(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    None,
  )
  assert_true(field_rank(cleared, 0, 0) == 0)
  assert_true(field_rank(cleared, 1, 0) == -1)
}

///|
test "faint replacement intimidate is applied before the next hit" {
  let splash = de_splash()
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 90)
  let lead = de_mon("Lead", "ノーマル", 160, 40, 70, 40, 70, 20, splash)
  let bench = de_mon("Bench", "ノーマル", 160, 40, 70, 40, 70, 30, splash, ability="いかく")
  let foe = de_mon("Foe", "ノーマル", 200, 170, 80, 40, 80, 50, hit)
  let dead = dg_dead()
  let my = de_four(lead, lead, bench, dead)
  let opp = dg_side(foe)
  let state = fresh_field(my, opp)
  set_hp(state, @doubles.MyLeft, 0)
  replace_fainted(
    new_double_eval(),
    state,
    [[7], [7], [7], [7]],
    dg_targets([0]),
    my,
    opp,
  )
  fire_entry_intimidate(state, my, opp)
  assert_true(field_rank(state, 2, 0) == -1)
  assert_true(state.pos[0] == 2)
  let actor : DoubleActor = {
    is_me: false,
    squad: 0,
    slot: @doubles.FoeLeft,
    move_idx: 0,
    target_code: 0,
    chosen: Some(@doubles.MyRight),
    priority: 0,
    speed: 50,
  }
  resolve_actor_sampled(
    new_double_eval(),
    state,
    actor,
    seeded_rng(1),
    my,
    opp,
  )
  let dmg = double_move_mean(foe, lead, hit, stage=-1)
  assert_true(dmg < double_move_mean(foe, lead, hit, stage=0))
  assert_true(state.my_hp[1] == 160 - dmg)
}

///|
test "double dp at one turn matches the joint value under intimidate" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let splash = de_splash()
  let me = de_mon("Me", "ノーマル", 200, 140, 90, 40, 90, 80, hit)
  let mate = de_mon("Mate", "ノーマル", 200, 40, 90, 40, 90, 70, splash)
  let pad = de_mon("Pad", "ノーマル", 180, 40, 80, 40, 80, 40, splash)
  let intim = de_mon("Intim", "ノーマル", 200, 40, 100, 40, 100, 50, splash, ability="いかく")
  let wall = de_mon("Wall", "ノーマル", 200, 40, 100, 40, 100, 45, splash)
  let my = de_four(me, mate, pad, pad)
  let opp = de_four(intim, wall, pad, pad)
  let open_team = de_four(wall, wall, pad, pad)
  let my_t = [[0], [7], [7], [7]]
  let opp_t = [[7], [7], [7], [7]]
  let cache = new_double_eval()
  let config = NashSolverConfig::default()
  let dp = double_dp_cell(cache, my, opp, my_t, opp_t, config, 1)
  let joint = joint_matrix_value(cache, my, opp, my_t, opp_t, config)
  let open = double_dp_cell(cache, my, open_team, my_t, opp_t, config, 1)
  assert_true(dg_gap(dp, joint) < 1.0e-9)
  assert_true(dg_gap(dp, open) > 1.0e-4)
  let rolled = double_scripted_rollout(
    cache,
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    seeded_rng(3),
    1,
    1,
    0.0,
  )
  let (scripted, _, _) = scripted_value_and_hp(
    cache,
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
  )
  assert_true(dg_gap(rolled, scripted) < 1.0e-9)
}
