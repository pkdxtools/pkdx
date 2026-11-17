///|
/// 技由来の相手ダウン (post-hit `stat_effects`, target = 1) に対する防御特性の
/// ブロック (Showdown `onTryBoost`)。
///
/// 仕様 (Showdown 準拠):
///   - クリアボディ / しろいけむり / メタルプロテクト は相手由来の負のブーストを全能力
///     で不発にする (同一 body)。かいりきバサミ は攻撃 (A)、はとむね は防御 (B) の
///     ダウンのみ不発にする。
///   - 不発のダウンは rank も反応 (まけんき / かちき) も変えない。
///   - 自己ダウン (target = 0) は不発にならない (Showdown は `target === source` で免除)。
///   - いかく 専用の防御特性 (どんかん / マイペース / せいしんりょく / きもったま) と
///     ばんけん (Guard Dog) は技由来のダウンを防がない。
///   - あまのじゃく は反転を先に行うので、反転後に上昇になるエントリはブロック判定の対象外。
///
/// helper: `mk_move` (switching_game_status_wbtest)、`im_pokemon` / `im_combatant` /
/// `im_state` / `im_tackle` / `with_post_hit_effects` 経路は switching_game_intimidate_wbtest。

///|
/// **Case 1 (クリアボディ × なきごえ)**: 相手の なきごえ (A-1) は クリアボディ で不発。
/// 相手ランクも自分のランクも変わらない。
test "クリアボディ: 相手のなきごえ (A-1) は不発で rank 不変" {
  let mv = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="クリアボディ",
  )
  for i in 0..<5 {
    @debug.assert_eq(opp_ranks[i], 0)
    @debug.assert_eq(self_ranks[i], 0)
  }
}

///|
/// **Case 2 (しろいけむり / メタルプロテクト)**: クリアボディと同一 body の 2 特性は、
/// なきごえ (A-1) と あまえる (A-2、多段ダウン) のどちらも不発にする。
test "しろいけむり / メタルプロテクト: なきごえ・あまえる のダウンは不発" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let charm = mk_move("あまえる", "フェアリー", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -2, target: 1 },
  ])
  for ability in ["しろいけむり", "メタルプロテクト"] {
    for mv in [growl, charm] {
      let opp_ranks = [0, 0, 0, 0, 0]
      apply_stat_effects(
        [0, 0, 0, 0, 0],
        opp_ranks,
        true,
        mv,
        attacker_ability="",
        defender_ability=ability,
      )
      for i in 0..<5 {
        @debug.assert_eq(opp_ranks[i], 0)
      }
    }
  }
}

///|
/// **Case 3 (かいりきバサミ / 攻撃のみ)**: くすぐる (A-1 / B-1) は A だけ不発、B は
/// 下がる。なみだめ (A-1 / C-1) も同様に C だけ下がる。
test "かいりきバサミ: 攻撃のダウンのみ不発、防御・特攻のダウンは通る" {
  let tickle = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let tickle_opp = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    tickle_opp,
    true,
    tickle,
    attacker_ability="",
    defender_ability="かいりきバサミ",
  )
  @debug.assert_eq(tickle_opp[0], 0)
  @debug.assert_eq(tickle_opp[1], -1)
  for i in 2..<5 {
    @debug.assert_eq(tickle_opp[i], 0)
  }
  let tearful = mk_move("なみだめ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 2, delta: -1, target: 1 },
  ])
  let tearful_opp = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    tearful_opp,
    true,
    tearful,
    attacker_ability="",
    defender_ability="かいりきバサミ",
  )
  @debug.assert_eq(tearful_opp[0], 0)
  @debug.assert_eq(tearful_opp[2], -1)
}

///|
/// **Case 4 (自己ダウンは不発にならない)**: 自己ダウン (target = 0) は、所持者が
/// クリアボディ / かいりきバサミ でも通る (Showdown は target === source で免除)。
test "自己ダウンは クリアボディ / かいりきバサミ でも不発にならない" {
  let close_combat = mk_move("インファイト", "かくとう", @model.Physical, 120, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 3, delta: -1, target: 0 },
  ])
  let cc_self = [0, 0, 0, 0, 0]
  apply_stat_effects(
    cc_self,
    [0, 0, 0, 0, 0],
    true,
    close_combat,
    attacker_ability="クリアボディ",
    defender_ability="",
  )
  @debug.assert_eq(cc_self[1], -1)
  @debug.assert_eq(cc_self[3], -1)
  // 自己 A-1 の架空技 (効果形のみを模した fixture)。かいりきバサミ は相手由来の
  // 攻撃ダウンだけを防ぐので、自分が撃つ自己 A-1 は通る。
  let self_attack_drop = mk_move("テスト用自己A-1技", "ノーマル", @model.Physical, 80, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 0 },
  ])
  let hc_self = [0, 0, 0, 0, 0]
  apply_stat_effects(
    hc_self,
    [0, 0, 0, 0, 0],
    true,
    self_attack_drop,
    attacker_ability="かいりきバサミ",
    defender_ability="",
  )
  @debug.assert_eq(hc_self[0], -1)
}

///|
/// **Case 5 (不発のダウンは反応も起こさない)**: くすぐる (A-1 / B-1) を クリアボディ が
/// 受けると、A も B も動かず、まけんき の反応 (攻撃 +2) も起きない。感度ガード: 同じ
/// 技を まけんき が受けると、A は 2 回の反応で +3 になる。
test "ブロックされたダウンは まけんき / かちき の反応を起こさない" {
  let tickle = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let blocked = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    blocked,
    true,
    tickle,
    attacker_ability="",
    defender_ability="クリアボディ",
  )
  for i in 0..<5 {
    @debug.assert_eq(blocked[i], 0)
  }
  let sensitive = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    sensitive,
    true,
    tickle,
    attacker_ability="",
    defender_ability="まけんき",
  )
  @debug.assert_eq(sensitive[0], 3)
}

///|
/// **Case 5a (不発 / かちき の特攻反応)**: なきごえ (A-1) を クリアボディ が受けると
/// 特攻 +2 の反応も起きない。感度ガード: かちき が受けると特攻は +2 になる。
test "ブロックされたダウンは かちき の特攻 +2 反応も起こさない" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let blocked = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    blocked,
    true,
    growl,
    attacker_ability="",
    defender_ability="クリアボディ",
  )
  for i in 0..<5 {
    @debug.assert_eq(blocked[i], 0)
  }
  let sensitive = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    sensitive,
    true,
    growl,
    attacker_ability="",
    defender_ability="かちき",
  )
  @debug.assert_eq(sensitive[0], -1)
  @debug.assert_eq(sensitive[2], 2)
}

///|
/// **Case 6 (いかく専用の防御特性 / ばんけん は技由来を防がない)**: どんかん /
/// マイペース / せいしんりょく / きもったま は いかく の A-1 だけを防ぐ。ばんけん
/// (Guard Dog) も いかく 専用。技由来のなきごえは通り、A は -1 のまま。
test "いかく専用の防御特性 / ばんけん は技由来のダウンを防がない" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  for ability in ["どんかん", "マイペース", "せいしんりょく", "きもったま", "ばんけん"] {
    let opp_ranks = [0, 0, 0, 0, 0]
    apply_stat_effects(
      [0, 0, 0, 0, 0],
      opp_ranks,
      true,
      growl,
      attacker_ability="",
      defender_ability=ability,
    )
    @debug.assert_eq(opp_ranks[0], -1)
  }
}

///|
/// **Case 7 (あまのじゃく は反転が先)**: なきごえ (A-1) は あまのじゃく で A +1 に
/// 反転する。反転後は上昇なのでブロック判定に掛からない (あまのじゃく 持ちは
/// ブロック特性を同時に持てないため、反転そのものだけを確かめれば足りる)。
test "あまのじゃく: 相手のなきごえは反転して A +1 (ブロック判定の対象外)" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let opp_ranks = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    opp_ranks,
    true,
    growl,
    attacker_ability="",
    defender_ability="あまのじゃく",
  )
  @debug.assert_eq(opp_ranks[0], 1)
}

///|
/// **Case 8 (DP 配線 / 変化技)**: `with_post_hit_effects` (DP の post-hit 入口) で、
/// 防御側の クリアボディ が なきごえ (A-1) を受けない。plain (特性なし) は A -1 のまま。
test "DP 配線: with_post_hit_effects で クリアボディ の相手は なきごえ を受けない" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let my_team = [im_combatant(im_pokemon("なきごえ使い"), [growl])]
  let block_team = [
    im_combatant(im_pokemon("クリアボディ持ち"), [im_tackle()], ability="クリアボディ"),
  ]
  let blocked = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    my_team,
    block_team,
    growl,
    0,
  )
  @debug.assert_eq(blocked.opp_ranks[0], 0)
  @debug.assert_eq(blocked.my_ranks[0], 0)
  let plain_team = [im_combatant(im_pokemon("ふつう"), [im_tackle()])]
  let plain = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    my_team,
    plain_team,
    growl,
    0,
  )
  @debug.assert_eq(plain.opp_ranks[0], -1)
}

///|
/// **Case 9 (DP 配線 / 攻撃技の相手ダウン)**: 威力のある技の相手ダウン (こごえるかぜ
/// 相当の S-1) も、ダメージ後の post-hit で クリアボディ にブロックされる。
test "DP 配線: 攻撃技の相手ダウン (S-1) も クリアボディ で不発" {
  let icy = mk_move("こごえるかぜ", "こおり", @model.Special, 55, stat_effects=[
    @model.StatEffect::{ stat: 4, delta: -1, target: 1 },
  ])
  let my_team = [im_combatant(im_pokemon("こごえる使い"), [icy])]
  let block_team = [
    im_combatant(im_pokemon("クリアボディ持ち"), [im_tackle()], ability="クリアボディ"),
  ]
  let blocked = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    my_team,
    block_team,
    icy,
    10,
  )
  @debug.assert_eq(blocked.opp_ranks[4], 0)
  let plain_team = [im_combatant(im_pokemon("ふつう"), [im_tackle()])]
  let plain = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    my_team,
    plain_team,
    icy,
    10,
  )
  @debug.assert_eq(plain.opp_ranks[4], -1)
}

///|
/// **Case 10 (DP 配線 / メガ後の特性で判定)**: メタグロス は クリアボディ だが、メガ進化
/// すると かたいツメ になる。メガ進化していなければ なきごえ を不発にし、メガ進化後
/// (`opp_megaed`) は実効特性で判定するので A -1 を受ける。
test "DP 配線: メガ後の実効特性で判定 — メガ進化後は クリアボディ を失う" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let my_team = [im_combatant(im_pokemon("なきごえ使い"), [growl])]
  let mega_form : @model.MegaForm = {
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    type1: "はがね",
    type2: "エスパー",
    ability: "かたいツメ",
    name_ja: "メガメタグロス",
  }
  let metagross = im_combatant(
    im_pokemon("メタグロス"),
    [im_tackle()],
    ability="クリアボディ",
    mega_form=Some(mega_form),
  )
  let team = [metagross]
  let state = im_state()
  let base = with_post_hit_effects(state, true, 0, 0, my_team, team, growl, 0)
  @debug.assert_eq(base.opp_ranks[0], 0)
  let mega_state = { ..state, opp_megaed: [true, false, false] }
  let mega = with_post_hit_effects(mega_state, true, 0, 0, my_team, team, growl, 0)
  @debug.assert_eq(mega.opp_ranks[0], -1)
}

///|
/// **Case 11 (はとむね / 防御のみ)**: しっぽをふる (B-1) と いやなおと (B-2) は不発。
/// くすぐる (A-1 / B-1) は A だけ下がり、B は残る。なきごえ (A-1) は通る。
/// Champions `TOKUSEIINFO_SYN_145`: 相手の技や特性で防御を下げられない。
test "はとむね: 防御のダウンのみ不発、攻撃のダウンは通る" {
  let tail = mk_move("しっぽをふる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let screech = mk_move("いやなおと", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -2, target: 1 },
  ])
  for mv in [tail, screech] {
    let opp_ranks = [0, 0, 0, 0, 0]
    apply_stat_effects(
      [0, 0, 0, 0, 0],
      opp_ranks,
      true,
      mv,
      attacker_ability="",
      defender_ability="はとむね",
    )
    for i in 0..<5 {
      @debug.assert_eq(opp_ranks[i], 0)
    }
  }
  let tickle = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let tickle_opp = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    tickle_opp,
    true,
    tickle,
    attacker_ability="",
    defender_ability="はとむね",
  )
  @debug.assert_eq(tickle_opp[0], -1)
  @debug.assert_eq(tickle_opp[1], 0)
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let growl_opp = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    growl_opp,
    true,
    growl,
    attacker_ability="",
    defender_ability="はとむね",
  )
  @debug.assert_eq(growl_opp[0], -1)
  @debug.assert_eq(growl_opp[1], 0)
}

///|
/// **Case 12 (はとむね / 自己ダウンは通る)**: インファイト の自己 B-1 / D-1 と
/// ばかぢから相当の自己 A-1 / B-1 は、所持者が はとむね でも下がる。
test "はとむね: インファイト / 自己防御ダウンは不発にならない" {
  let close_combat = mk_move("インファイト", "かくとう", @model.Physical, 120, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 3, delta: -1, target: 0 },
  ])
  let cc_self = [0, 0, 0, 0, 0]
  apply_stat_effects(
    cc_self,
    [0, 0, 0, 0, 0],
    true,
    close_combat,
    attacker_ability="はとむね",
    defender_ability="",
  )
  @debug.assert_eq(cc_self[1], -1)
  @debug.assert_eq(cc_self[3], -1)
  let superpower = mk_move("ばかぢから", "かくとう", @model.Physical, 120, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
  ])
  let sp_self = [0, 0, 0, 0, 0]
  apply_stat_effects(
    sp_self,
    [0, 0, 0, 0, 0],
    true,
    superpower,
    attacker_ability="はとむね",
    defender_ability="",
  )
  @debug.assert_eq(sp_self[0], -1)
  @debug.assert_eq(sp_self[1], -1)
}

///|
/// **Case 13 (はとむねで不発の防御ダウンは反応しない)**: しっぽをふる (B-1) を
/// はとむね が受けるとランクは全部 0 のまま (まけんき の攻撃 +2 も起きない)。
/// 同じ技を まけんき が受けると B は下がり、下がった能力 1 つで攻撃 +2 する。
test "はとむね: 防いだ防御ダウンは まけんき の反応を起こさない" {
  let tail = mk_move("しっぽをふる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let blocked = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    blocked,
    true,
    tail,
    attacker_ability="",
    defender_ability="はとむね",
  )
  for i in 0..<5 {
    @debug.assert_eq(blocked[i], 0)
  }
  let sensitive = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    sensitive,
    true,
    tail,
    attacker_ability="",
    defender_ability="まけんき",
  )
  @debug.assert_eq(sensitive[0], 2)
  @debug.assert_eq(sensitive[1], -1)
}

///|
/// **Case 14 (DP 配線 / 攻撃技の防御ダウン)**: 威力のある技の相手 B-1
/// (かみくだく相当の確定ダウン) も post-hit で はとむね にブロックされる。
test "DP 配線: 攻撃技の防御ダウンは はとむね で不発" {
  let crunch = mk_move("かみくだく", "あく", @model.Physical, 80, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let my_team = [im_combatant(im_pokemon("かみくだく使い"), [crunch])]
  let block_team = [
    im_combatant(im_pokemon("はとむね持ち"), [im_tackle()], ability="はとむね"),
  ]
  let blocked = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    my_team,
    block_team,
    crunch,
    20,
  )
  @debug.assert_eq(blocked.opp_ranks[1], 0)
  let plain_team = [im_combatant(im_pokemon("ふつう"), [im_tackle()])]
  let plain = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    my_team,
    plain_team,
    crunch,
    20,
  )
  @debug.assert_eq(plain.opp_ranks[1], -1)
}

///|
/// **Case 15 (吸収の上昇は相手ダウンではない)**: そうしょく がくさ技を吸収すると
/// 攻撃 +1 だけが残り、技に載っていた相手 A-1 / B-1 は当たらない。+1 は吸収の
/// 上昇であり、まけんき の +2 は乗らない。ひらいしん も同じで、特攻 +1 だけ。
test "そうしょく / ひらいしん: 吸収の上昇は相手ダウンを消すので まけんき は誘発しない" {
  let grass = mk_move("くさダウン", "くさ", @model.Special, 90, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let sap = sap_one_leaf(
    im_state(),
    true,
    sap_team(grass),
    [im_combatant(im_pokemon("そうしょく持ち"), [im_tackle()], ability="そうしょく")],
    grass,
    40,
  )
  @debug.assert_eq(sap.opp_ranks[0], 1)
  @debug.assert_eq(sap.opp_ranks[1], 0)
  @debug.assert_eq(sap.opp_hps[0], 100)
  let bolt = mk_move("でんきダウン", "でんき", @model.Special, 90, stat_effects=[
    @model.StatEffect::{ stat: 2, delta: -1, target: 1 },
  ])
  let rod = sap_one_leaf(
    im_state(),
    true,
    sap_team(bolt),
    [im_combatant(im_pokemon("ひらいしん持ち"), [im_tackle()], ability="ひらいしん")],
    bolt,
    40,
  )
  @debug.assert_eq(rod.opp_ranks[2], 1)
  for i in [0, 1, 3, 4] {
    @debug.assert_eq(rod.opp_ranks[i], 0)
  }
  @debug.assert_eq(rod.opp_hps[0], 100)
}

///|
/// **フラワーベール (くさ)**: クリアボディと同じ `apply_stat_effects` 経路。
/// 所持者自身がくさ (type1 または type2) のとき、相手由来の負のランクは全能力で不発。
/// フェアリー (Champions のフラワーベール種) とタイプ未指定は通る。自己ダウンは通る。
test "フラワーベール: 自分がくさのとき相手ダウンは不発、自己ダウンと非くさは通る" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let tickle = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  let grass = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    grass,
    true,
    tickle,
    attacker_ability="",
    defender_ability="フラワーベール",
    defender_type1="くさ",
  )
  for i in 0..<5 {
    @debug.assert_eq(grass[i], 0)
  }
  let dual = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    dual,
    true,
    growl,
    attacker_ability="",
    defender_ability="フラワーベール",
    defender_type1="フェアリー",
    defender_type2="くさ",
  )
  @debug.assert_eq(dual[0], 0)
  let fairy = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    fairy,
    true,
    growl,
    attacker_ability="",
    defender_ability="フラワーベール",
    defender_type1="フェアリー",
  )
  @debug.assert_eq(fairy[0], -1)
  let omitted = [0, 0, 0, 0, 0]
  apply_stat_effects(
    [0, 0, 0, 0, 0],
    omitted,
    true,
    growl,
    attacker_ability="",
    defender_ability="フラワーベール",
  )
  @debug.assert_eq(omitted[0], -1)
  // ばかぢから: 自分の攻撃・防御 -1。くさのフラワーベールでも通る。
  let superpower = mk_move("ばかぢから", "かくとう", @model.Physical, 120, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
  ])
  let self_ranks = [0, 0, 0, 0, 0]
  apply_stat_effects(
    self_ranks,
    [0, 0, 0, 0, 0],
    true,
    superpower,
    attacker_ability="フラワーベール",
    defender_ability="",
    defender_type1="くさ",
  )
  @debug.assert_eq(self_ranks[0], -1)
  @debug.assert_eq(self_ranks[1], -1)
}

///|
/// **DP 配線**: `with_post_hit_effects` が防御側のタイプを渡す。くさはなきごえと
/// 攻撃技の S-1 を受けない。フェアリーはなきごえを受ける。メガ後にフェアリーへ
/// 変わると (特性はフラワーベールのまま) ブロックが外れる。
test "DP 配線: フラワーベールはメガ後の実効タイプがくさのときだけ相手ダウンを防ぐ" {
  let growl = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  let icy = mk_move("こごえるかぜ", "こおり", @model.Special, 55, stat_effects=[
    @model.StatEffect::{ stat: 4, delta: -1, target: 1 },
  ])
  let my_team = [im_combatant(im_pokemon("なきごえ使い"), [growl])]
  let grass_poke = { ..im_pokemon("くさベール"), type1: "くさ" }
  let grass_team = [
    im_combatant(grass_poke, [im_tackle()], ability="フラワーベール"),
  ]
  let blocked = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    my_team,
    grass_team,
    growl,
    0,
  )
  @debug.assert_eq(blocked.opp_ranks[0], 0)
  let icy_team = [im_combatant(im_pokemon("こごえる使い"), [icy])]
  let blocked_spe = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    icy_team,
    grass_team,
    icy,
    10,
  )
  @debug.assert_eq(blocked_spe.opp_ranks[4], 0)
  let fairy_poke = { ..im_pokemon("フェアリーベール"), type1: "フェアリー" }
  let fairy_team = [
    im_combatant(fairy_poke, [im_tackle()], ability="フラワーベール"),
  ]
  let fairy = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    my_team,
    fairy_team,
    growl,
    0,
  )
  @debug.assert_eq(fairy.opp_ranks[0], -1)
  let mega_form : @model.MegaForm = {
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    type1: "フェアリー",
    type2: "",
    ability: "フラワーベール",
    name_ja: "メガフェアリー",
  }
  let mega_mon = im_combatant(
    grass_poke,
    [im_tackle()],
    ability="フラワーベール",
    mega_form=Some(mega_form),
  )
  let base = with_post_hit_effects(
    im_state(),
    true,
    0,
    0,
    my_team,
    [mega_mon],
    growl,
    0,
  )
  @debug.assert_eq(base.opp_ranks[0], 0)
  let mega_state = { ..im_state(), opp_megaed: [true, false, false] }
  let mega = with_post_hit_effects(
    mega_state,
    true,
    0,
    0,
    my_team,
    [mega_mon],
    growl,
    0,
  )
  @debug.assert_eq(mega.opp_ranks[0], -1)
}
