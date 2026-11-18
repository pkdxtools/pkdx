///|
/// かたやぶりは技の解決中だけ、受け手の breakable な特性を無視する。
/// 攻撃側がかたやぶりでないときは既存の経路と同じ結果になる。
/// helper: `mk_move` / `im_pokemon` / `im_combatant` / `im_state` /
/// `imm_attacker` / `imm_defender` / `imm_one`。

///|
fn mb_quake() -> @model.Move {
  mk_move("じしん", "じめん", @model.Physical, 100)
}

///|
fn mb_growl() -> @model.Move {
  mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
}

///|
fn mb_mean(own : Combatant, opp : Combatant, mv : @model.Move, atk_rank : Int) -> Int {
  compute_damage_variants(own, opp, mv, atk_rank, 0)[0].mean_damage
}

///|
fn mb_disguise_state(
  own : Combatant,
  opp : Combatant,
  mv : @model.Move,
) -> SwitchingGameState {
  let intact = disguise_intact_of(
    im_state(),
    true,
    [opp],
    0,
    attacker_ability=own.ability,
  )
  let outcomes = compute_damage_variants(
    own, opp, mv, 0, 0, def_disguise_intact=intact,
  )
  let outs = apply_damage_variants_fanout(
    im_state(),
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[own],
    defender_team=[opp],
    pre_dmg_defender_hp=100,
  )
  if outs.length() != 1 {
    abort("mb_disguise_state: expected a single leaf")
  }
  outs[0].1
}

///|
test "DP: ふゆうはじしんを無効にし、かたやぶりは通す" {
  let mv = mb_quake()
  let opp = imm_defender("ノーマル", ability="ふゆう")
  let blocked = imm_one(imm_attacker(mv), opp, mv)
  @debug.assert_eq(blocked.opp_hps[0], 100)
  let broken = imm_one(imm_attacker(mv, ability="かたやぶり"), opp, mv)
  assert_true(broken.opp_hps[0] < 100)
}

///|
test "DP: クリアボディはなきごえを止め、かたやぶりは A-1 にする" {
  let mv = mb_growl()
  let opp = imm_defender("ノーマル", ability="クリアボディ")
  let blocked = imm_one(imm_attacker(mv), opp, mv)
  @debug.assert_eq(blocked.opp_ranks[0], 0)
  let broken = imm_one(imm_attacker(mv, ability="かたやぶり"), opp, mv)
  @debug.assert_eq(broken.opp_ranks[0], -1)
}

///|
test "DP: メタルプロテクトはかたやぶりでもなきごえを止める" {
  let mv = mb_growl()
  let opp = imm_defender("ノーマル", ability="メタルプロテクト")
  let s = imm_one(imm_attacker(mv, ability="かたやぶり"), opp, mv)
  @debug.assert_eq(s.opp_ranks[0], 0)
}

///|
test "DP: あまのじゃくの反転をかたやぶりは外す" {
  let mv = mb_growl()
  let opp = imm_defender("ノーマル", ability="あまのじゃく")
  let flipped = imm_one(imm_attacker(mv), opp, mv)
  @debug.assert_eq(flipped.opp_ranks[0], 1)
  let broken = imm_one(imm_attacker(mv, ability="かたやぶり"), opp, mv)
  @debug.assert_eq(broken.opp_ranks[0], -1)
}

///|
test "DP: まけんきはかたやぶりでも反応する" {
  let mv = mb_growl()
  let opp = imm_defender("ノーマル", ability="まけんき")
  let plain = imm_one(imm_attacker(mv), opp, mv)
  let broken = imm_one(imm_attacker(mv, ability="かたやぶり"), opp, mv)
  @debug.assert_eq(plain.opp_ranks[0], 1)
  @debug.assert_eq(broken.opp_ranks[0], 1)
}

///|
test "DP: くさのフラワーベールはかたやぶりでなきごえを通す" {
  let mv = mb_growl()
  let opp = imm_defender("くさ", ability="フラワーベール")
  let blocked = imm_one(imm_attacker(mv), opp, mv)
  @debug.assert_eq(blocked.opp_ranks[0], 0)
  let broken = imm_one(imm_attacker(mv, ability="かたやぶり"), opp, mv)
  @debug.assert_eq(broken.opp_ranks[0], -1)
}

///|
test "DP: マルチスケイルの軽減をかたやぶりは外し、特性なしと同じダメージ" {
  let mv = mb_quake()
  let plain = imm_defender("ノーマル")
  let scale = imm_defender("ノーマル", ability="マルチスケイル")
  let own = imm_attacker(mv)
  let d_plain = mb_mean(own, plain, mv, 0)
  let d_scale = mb_mean(own, scale, mv, 0)
  let d_break = mb_mean(imm_attacker(mv, ability="かたやぶり"), scale, mv, 0)
  assert_true(d_plain > d_scale)
  @debug.assert_eq(d_break, d_plain)
}

///|
test "DP: プリズムアーマーの抜群軽減はかたやぶりでも残る" {
  let mv = mk_move("10まんボルト", "でんき", @model.Special, 90)
  let plain = imm_defender("みず")
  let prism = imm_defender("みず", ability="プリズムアーマー")
  let own = imm_attacker(mv)
  let d_plain = mb_mean(own, plain, mv, 0)
  let d_prism = mb_mean(own, prism, mv, 0)
  let d_break = mb_mean(imm_attacker(mv, ability="かたやぶり"), prism, mv, 0)
  assert_true(d_plain > d_prism)
  @debug.assert_eq(d_break, d_prism)
}

///|
test "DP: てんねんのランク無視をかたやぶりは外す" {
  let mv = mb_quake()
  let plain = imm_defender("ノーマル")
  let unaware = imm_defender("ノーマル", ability="てんねん")
  let own = imm_attacker(mv)
  let d_rank = mb_mean(own, plain, mv, 2)
  let d_ignored = mb_mean(own, unaware, mv, 2)
  let d_zero = mb_mean(own, plain, mv, 0)
  let d_break = mb_mean(imm_attacker(mv, ability="かたやぶり"), unaware, mv, 2)
  @debug.assert_eq(d_ignored, d_zero)
  @debug.assert_eq(d_break, d_rank)
  assert_true(d_rank > d_zero)
}

///|
test "DP: ヘドロえきのドレイン反転はかたやぶりでも残る" {
  let mv = {
    ..mk_move("ギガドレイン", "くさ", @model.Special, 75),
    healing: Some(@model.HealingEffect::Drain(1, 2)),
  }
  let ooze = imm_defender("ノーマル", ability="ヘドロえき")
  let plain = imm_one(imm_attacker(mv), imm_defender("ノーマル"), mv)
  let flipped = imm_one(imm_attacker(mv), ooze, mv)
  let broken = imm_one(imm_attacker(mv, ability="かたやぶり"), ooze, mv)
  assert_true(plain.my_hps[0] > 100)
  assert_true(flipped.my_hps[0] < 100)
  @debug.assert_eq(broken.my_hps[0], flipped.my_hps[0])
}

///|
test "DP: ばけのかわはかたやぶりで割れず、ダメージが通る" {
  let mv = mb_quake()
  let opp = imm_defender("ノーマル", ability="ばけのかわ")
  let blocked = mb_disguise_state(imm_attacker(mv), opp, mv)
  assert_true(blocked.opp_hps[0] < 100)
  assert_true(blocked.opp_disguise_busted[0])
  let broken = mb_disguise_state(imm_attacker(mv, ability="かたやぶり"), opp, mv)
  assert_true(broken.opp_hps[0] < blocked.opp_hps[0])
  assert_true(!broken.opp_disguise_busted[0])
}

///|
test "DP: ぼうじんはねむりごなを止め、かたやぶりは止めない" {
  let mv = mk_move(
    "ねむりごな",
    "くさ",
    @model.Status,
    0,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let opp = imm_defender("ノーマル", ability="ぼうじん")
  match status_move_fail_state(
    im_state(), true, 0, 0, [imm_attacker(mv)], [opp], mv, 100,
  ) {
    Some(_) => ()
    None => abort("overcoat should reject spore")
  }
  match status_move_fail_state(
    im_state(),
    true,
    0,
    0,
    [imm_attacker(mv, ability="かたやぶり")],
    [opp],
    mv,
    100,
  ) {
    Some(_) => abort("mold breaker should not reject spore")
    None => ()
  }
}

///|
test "DP: じゅうなんのでんじはをかたやぶりは付与する" {
  let mv = mk_move(
    "でんじは",
    "でんき",
    @model.Status,
    0,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
  let opp = imm_defender("ノーマル", ability="じゅうなん")
  let blocked = maybe_apply_status_fanout(im_state(), false, 0, [opp], mv)
  @debug.assert_eq(blocked[0].1.opp_status[0], @model.None)
  let broken = maybe_apply_status_fanout(
    im_state(), false, 0, [opp], mv, attacker_ability="かたやぶり",
  )
  @debug.assert_eq(broken[0].1.opp_status[0], @model.Paralyze)
}

///|
test "DP: せいしんりょくのかみつきをかたやぶりはひるませる" {
  let mv = { ..mk_move("かみつく", "あく", @model.Physical, 60), flinch_chance: 100 }
  let opp = imm_defender("ノーマル", ability="せいしんりょく")
  let blocked = maybe_apply_flinch_fanout(im_state(), false, 0, [opp], mv)
  assert_true(!blocked[0].1.opp_flinched)
  let broken = maybe_apply_flinch_fanout(
    im_state(), false, 0, [opp], mv, attacker_ability="かたやぶり",
  )
  assert_true(broken[0].1.opp_flinched)
}

///|
test "DP: サイコフィールドはふゆうを通し、かたやぶりは優先度を止める" {
  let flyer = imm_defender("ノーマル", ability="ふゆう")
  let flying = imm_defender("ひこう")
  assert_true(
    !psychic_blocks_priority(@model.Field::Psychic, 1, flyer, false),
  )
  assert_true(
    psychic_blocks_priority(
      @model.Field::Psychic, 1, flyer, false, attacker_ability="かたやぶり",
    ),
  )
  assert_true(
    !psychic_blocks_priority(
      @model.Field::Psychic, 1, flying, false, attacker_ability="かたやぶり",
    ),
  )
}
