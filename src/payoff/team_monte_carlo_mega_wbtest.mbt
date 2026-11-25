///|
/// Monte Carlo / screening のメガシンカ。
///
/// 発動は DP と同じ: サイド 1 回、生存かつ `mega_form = Some`、技の命中より前、
/// メガ後の素早さ。方策は既存の与ダメージ貪欲で、メガ後の期待ダメージが
/// 厳密に大きいときだけ `TmMega` を選ぶ。

///|
fn mcg_move(
  name : String,
  type_ : String,
  power : Int,
  accuracy? : Int = 100,
) -> @model.Move {
  mk_move(name, type_, @model.Physical, power, accuracy~)
}

///|
fn mcg_mon(
  name : String,
  hp : Int,
  atk : Int,
  def_ : Int,
  spe : Int,
  type1 : String,
  moves : Array[@model.Move],
  mega? : @model.MegaForm? = None,
) -> Combatant {
  {
    pokemon: mk_pokemon(name, type1, "", hp, atk, def_, 100, 100, spe),
    moves,
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: mega,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
    gender: Gender::Unknown,
  }
}

///|
fn mcg_mega(
  atk : Int,
  spe : Int,
  type1? : String = "ノーマル",
) -> @model.MegaForm {
  {
    atk,
    def_: 100,
    spa: 100,
    spd: 100,
    spe,
    type1,
    type2: "",
    ability: "",
    name_ja: "メガテスト",
  }
}

///|
fn mcg_zero() -> Array[Int] {
  [0, 0, 0, 0, 0]
}

///|
fn mcg_pick(
  mine : Combatant,
  foe : Combatant,
  epsilon : Double,
  seed : UInt64,
  must_recharge? : Bool = false,
  two_turn_lock? : Int = -1,
  mega_used? : Bool = false,
) -> TeamAction? {
  greedy_team_action(
    0,
    [mine],
    [mine.pokemon.hp],
    mcg_zero(),
    0,
    [foe],
    mcg_zero(),
    seeded_rng(seed),
    epsilon,
    must_recharge~,
    two_turn_lock~,
    mega_used~,
  )
}

///|
test "mc mega greedy: メガが無いときは強い技の UseMove" {
  let weak = mcg_move("ひっかく", "ノーマル", 40)
  let strong = mcg_move("はかいこうせん", "ノーマル", 150)
  let mine = mcg_mon("a", 120, 100, 100, 100, "ノーマル", [weak, strong])
  let foe = mcg_mon("b", 120, 50, 100, 50, "ノーマル", [weak])
  match mcg_pick(mine, foe, 0.0, 1UL) {
    Some(TmUseMove(1)) => ()
    _ => abort("expected UseMove(1)")
  }
}

///|
test "mc mega greedy: メガ後の与ダメが大きいとき TmMega" {
  let mv = mcg_move("たいあたり", "ノーマル", 40)
  let mine = mcg_mon(
    "a",
    120,
    20,
    100,
    80,
    "ノーマル",
    [mv],
    mega=Some(mcg_mega(250, 80)),
  )
  let foe = mcg_mon("b", 120, 50, 100, 50, "ノーマル", [mv])
  match mcg_pick(mine, foe, 0.0, 2UL) {
    Some(TmMega(0)) => ()
    _ => abort("expected Mega(0)")
  }
}

///|
test "mc mega greedy: メガ後の与ダメが同じなら UseMove" {
  let mv = mcg_move("たいあたり", "ノーマル", 40)
  let mine = mcg_mon(
    "a",
    120,
    100,
    100,
    100,
    "ノーマル",
    [mv],
    mega=Some(mcg_mega(100, 100)),
  )
  let foe = mcg_mon("b", 120, 50, 100, 50, "ノーマル", [mv])
  match mcg_pick(mine, foe, 0.0, 3UL) {
    Some(TmUseMove(0)) => ()
    _ => abort("expected UseMove(0)")
  }
}

///|
test "mc mega greedy: ノーマル STAB を失うだけのメガは選ばない" {
  let mv = mcg_move("たいあたり", "ノーマル", 80)
  let mine = mcg_mon(
    "a",
    120,
    120,
    100,
    100,
    "ノーマル",
    [mv],
    mega=Some(mcg_mega(120, 100, type1="ゴースト")),
  )
  let foe = mcg_mon("b", 200, 50, 100, 50, "ノーマル", [mv])
  match mcg_pick(mine, foe, 0.0, 4UL) {
    Some(TmUseMove(0)) => ()
    _ => abort("expected UseMove(0)")
  }
}

///|
test "mc mega greedy: 使用済みとリチャージではメガしない" {
  let mv = mcg_move("たいあたり", "ノーマル", 40)
  let mine = mcg_mon(
    "a",
    120,
    20,
    100,
    80,
    "ノーマル",
    [mv],
    mega=Some(mcg_mega(250, 200)),
  )
  let foe = mcg_mon("b", 120, 50, 100, 50, "ノーマル", [mv])
  match mcg_pick(mine, foe, 0.0, 5UL, mega_used=true) {
    Some(TmUseMove(0)) => ()
    _ => abort("expected UseMove after mega_used")
  }
  match mcg_pick(mine, foe, 0.0, 6UL, must_recharge=true) {
    Some(TmUseMove(0)) => ()
    _ => abort("expected recharge placeholder")
  }
}

///|
test "mc mega greedy: 溜め中はメガ後ダメが厳密に大きいときだけ Mega" {
  let mv = mcg_move("はかいこうせん", "ノーマル", 150)
  let boosted = mcg_mon(
    "a",
    120,
    20,
    100,
    80,
    "ノーマル",
    [mv],
    mega=Some(mcg_mega(250, 80)),
  )
  let same = mcg_mon(
    "a",
    120,
    100,
    100,
    100,
    "ノーマル",
    [mv],
    mega=Some(mcg_mega(100, 100)),
  )
  let foe = mcg_mon("b", 120, 50, 100, 50, "ノーマル", [mv])
  match mcg_pick(boosted, foe, 0.0, 7UL, two_turn_lock=0) {
    Some(TmMega(0)) => ()
    _ => abort("expected Mega during two-turn")
  }
  match mcg_pick(same, foe, 0.0, 8UL, two_turn_lock=0) {
    Some(TmUseMove(0)) => ()
    _ => abort("expected UseMove during two-turn")
  }
}

///|
test "mc mega greedy: ε はメガ持ちだけ Mega を一様に含む" {
  let mv = mcg_move("たいあたり", "ノーマル", 40)
  let mega = mcg_mon(
    "a",
    120,
    100,
    100,
    100,
    "ノーマル",
    [mv],
    mega=Some(mcg_mega(100, 100)),
  )
  let plain = mcg_mon("a", 120, 100, 100, 100, "ノーマル", [mv])
  let foe = mcg_mon("b", 120, 50, 100, 50, "ノーマル", [mv])
  let mut saw_move = false
  let mut saw_mega = false
  for i in 0..<40 {
    match mcg_pick(mega, foe, 1.0, i.to_uint64()) {
      Some(TmUseMove(_)) => saw_move = true
      Some(TmMega(_)) => saw_mega = true
      _ => abort("epsilon drew a switch")
    }
    match mcg_pick(plain, foe, 1.0, i.to_uint64()) {
      Some(TmUseMove(_)) => ()
      _ => abort("non-mega epsilon drew Mega")
    }
  }
  assert_true(saw_move && saw_mega)
}

///|
test "mc mega rollout: メガ後の素早さで先に倒す" {
  let mv = mcg_move("はかいこうせん", "ノーマル", 100)
  let slow = mcg_mon(
    "slow",
    80,
    1,
    100,
    10,
    "ノーマル",
    [mv],
    mega=Some(mcg_mega(250, 200)),
  )
  let fast = mcg_mon("fast", 80, 250, 100, 100, "ノーマル", [mv])
  let with_mega = team_rollout(
    [slow],
    [fast],
    seeded_rng(11UL),
    turn_limit=1,
    epsilon=0.0,
  )
  let no_mega = team_rollout(
    [mcg_mon("slow", 80, 1, 100, 10, "ノーマル", [mv])],
    [fast],
    seeded_rng(11UL),
    turn_limit=1,
    epsilon=0.0,
  )
  @debug.assert_eq(with_mega, 1.0)
  @debug.assert_eq(no_mega, -1.0)
  @debug.assert_eq(slow.pokemon.spe, 10)
  match slow.mega_form {
    Some(_) => ()
    None => abort("rollout mutated the caller")
  }
}

///|
test "mc mega rollout: 外してもメガ後ゴーストでノーマルを受けない" {
  let hit = mcg_move("たいあたり", "ノーマル", 80)
  let miss = mcg_move("はずす", "ノーマル", 80, accuracy=0)
  let own = mcg_mon("own", 80, 250, 100, 150, "ノーマル", [hit])
  let ghost = mcg_mon(
    "ghost",
    80,
    1,
    100,
    1,
    "ノーマル",
    [miss],
    mega=Some(mcg_mega(250, 1, type1="ゴースト")),
  )
  let plain = mcg_mon("ghost", 80, 1, 100, 1, "ノーマル", [miss])
  let mega_v = team_rollout(
    [own], [ghost], seeded_rng(12UL), turn_limit=1, epsilon=0.0,
  )
  let plain_v = team_rollout(
    [own], [plain], seeded_rng(12UL), turn_limit=1, epsilon=0.0,
  )
  @debug.assert_eq(mega_v, 0.0)
  @debug.assert_eq(plain_v, 1.0)
}

///|
test "mc mega rollout: サイドのメガは 1 回" {
  let lead_mv = mcg_move("たいあたり", "ノーマル", 40)
  let bench_mv = mcg_move("はかいこうせん", "ノーマル", 100)
  let opp_mv = mcg_move("かみつく", "あく", 80)
  let bench = mcg_mon(
    "bench",
    400,
    1,
    200,
    1,
    "ノーマル",
    [bench_mv],
    mega=Some(mcg_mega(500, 300)),
  )
  let opp = mcg_mon("opp", 160, 120, 120, 100, "ノーマル", [opp_mv])
  let lead_mega = mcg_mon(
    "lead",
    1,
    1,
    1,
    1,
    "ノーマル",
    [lead_mv],
    mega=Some(mcg_mega(80, 1)),
  )
  let lead_plain = mcg_mon("lead", 1, 1, 1, 1, "ノーマル", [lead_mv])
  let used = team_rollout(
    [lead_mega, bench],
    [opp],
    seeded_rng(13UL),
    turn_limit=3,
    epsilon=0.0,
  )
  let open = team_rollout(
    [lead_plain, bench],
    [opp],
    seeded_rng(13UL),
    turn_limit=3,
    epsilon=0.0,
  )
  assert_true(used < 0.0)
  @debug.assert_eq(open, 1.0)
}

///|
test "mc mega screening: screen_one_cell がメガ後の無効を見る" {
  let hit = mcg_move("たいあたり", "ノーマル", 80)
  let miss = mcg_move("はずす", "ノーマル", 80, accuracy=0)
  let own = mcg_mon("own", 80, 250, 100, 150, "ノーマル", [hit])
  let ghost = mcg_mon(
    "ghost",
    80,
    1,
    100,
    1,
    "ノーマル",
    [miss],
    mega=Some(mcg_mega(250, 1, type1="ゴースト")),
  )
  let plain = mcg_mon("ghost", 80, 1, 100, 1, "ノーマル", [miss])
  let mega_v = screen_one_cell([own], [ghost], [0], [0], 1, 12UL, 0, 1)
  let plain_v = screen_one_cell([own], [plain], [0], [0], 1, 12UL, 0, 1)
  @debug.assert_eq(mega_v, 0.0)
  @debug.assert_eq(plain_v, 1.0)
}
