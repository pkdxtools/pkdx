///|
/// まけんき (Defiant) / かちき (Competitive) の単体・DP 配線テスト。
///
/// 仕様 (Showdown 準拠):
///   - 相手由来の能力ダウンイベント (いかく 1 回 / 1 つの技) につき 1 回、まけんきは
///     攻撃 +2、かちきは特攻 +2（上限 +6）。イベント内で実際に下がった能力が 1 つ
///     以上あれば発動し、能力ごとには発動しない (くすぐる で 2 能力下がっても 1 回)。
///   - 自分の技の自己ダウン (target = 0) では発動しない。
///   - ブロック (クリアボディ等) された、または既に下限でランクが変わらなかった
///     ダウンは不発。
///
/// 所持者のランクは実機どおり ±6 で追跡する (`clamp_rank_for`)。それ以外の特性
/// の ±2 reduced range は従来どおり（既存テストが pin している）。
///
/// helper: `mk_move` (switching_game_status_wbtest)、`im_pokemon` / `im_combatant`
/// / `im_state` / `im_tackle` (switching_game_intimidate_wbtest)。

///|
/// **Case 1 (まけんき: いかく で攻撃 +1 の純増)**: A は -1 され、そのダウンが
/// 適用されたので攻撃 +2。実効 A は +1。他の能力・entrant は不変。
test "まけんき: いかくで A -1 のあと攻撃 +2 (実効 A +1)、他ランクは不変" {
  let target = [0, 0, 0, 0, 0]
  let entrant = [0, 0, 0, 0, 0]
  apply_intimidate_on_entry("いかく", "まけんき", target, entrant)
  @debug.assert_eq(target[0], 1)
  for i in 1..<5 {
    @debug.assert_eq(target[i], 0)
  }
  for i in 0..<5 {
    @debug.assert_eq(entrant[i], 0)
  }
}

///|
/// **Case 2 (かちき: 特攻 +2 のみ)**: A は -1 のまま、反応は特攻 (index 2) に出る。
test "かちき: いかくで A -1 のまま、特攻 +2 (index 2)" {
  let target = [0, 0, 0, 0, 0]
  let entrant = [0, 0, 0, 0, 0]
  apply_intimidate_on_entry("いかく", "かちき", target, entrant)
  @debug.assert_eq(target[0], -1)
  @debug.assert_eq(target[1], 0)
  @debug.assert_eq(target[2], 2)
  @debug.assert_eq(target[3], 0)
  @debug.assert_eq(target[4], 0)
}

///|
/// **Case 3 (まけんき: 上限 +6)**: 1 回ごとに「-1 → +2」で純増 +1。6 回目で
/// 上限 +6 に達し、以降は据え置き。
test "まけんき: 上限 +6 — いかくを繰り返しても A は 6 で止まる" {
  let target = [0, 0, 0, 0, 0]
  let entrant = [0, 0, 0, 0, 0]
  let expected = [1, 2, 3, 4, 5, 6, 6, 6]
  for i in 0..<expected.length() {
    apply_intimidate_on_entry("いかく", "まけんき", target, entrant)
    @debug.assert_eq(target[0], expected[i])
  }
}

///|
/// **Case 4 (かちき: 上限 +6 + 所持者の下限 -6)**: A は毎回 -1 され (下がる)、
/// 特攻は毎回 +2。特攻は 3 回目で +6 に達する。A は -6 まで下がり、以降の
/// ダウンは適用されないので特攻は据え置き。
test "かちき: 上限 +6 — 特攻は 6 で止まり、A は下限 -6 まで下がる" {
  let target = [0, 0, 0, 0, 0]
  let entrant = [0, 0, 0, 0, 0]
  let expected_a = [-1, -2, -3, -4, -5, -6, -6, -6]
  let expected_c = [2, 4, 6, 6, 6, 6, 6, 6]
  for i in 0..<expected_a.length() {
    apply_intimidate_on_entry("いかく", "かちき", target, entrant)
    @debug.assert_eq(target[0], expected_a[i])
    @debug.assert_eq(target[2], expected_c[i])
  }
}

///|
/// **Case 5 (下限: 既に -6 では不発)**: ダウンが適用されない (ランク不変) ので
/// 反応もない。まけんき は攻撃 +2 が起きず、かちき は特攻 +2 が起きない。
test "下限: 既に -6 のまけんき / かちき はダウンが適用されず反応もしない" {
  let defiant = [-6, 0, 0, 0, 0]
  apply_intimidate_on_entry("いかく", "まけんき", defiant, [0, 0, 0, 0, 0])
  @debug.assert_eq(defiant[0], -6)
  for i in 1..<5 {
    @debug.assert_eq(defiant[i], 0)
  }
  let competitive = [-6, 0, 0, 0, 0]
  apply_intimidate_on_entry("いかく", "かちき", competitive, [0, 0, 0, 0, 0])
  @debug.assert_eq(competitive[0], -6)
  @debug.assert_eq(competitive[2], 0)
}

///|
/// **Case 6 (防がれたダウンは不発)**: クリアボディ (ブロック) では対象のランクも
/// 反応も変わらない。ミラーアーマーは反射で entrant の A -1 のみ、target は不変。
test "防がれたダウン (クリアボディ / ミラーアーマー) は対象のランクも反応も変えない" {
  let blocked = [0, 0, 0, 0, 0]
  apply_intimidate_on_entry("いかく", "クリアボディ", blocked, [0, 0, 0, 0, 0])
  for i in 0..<5 {
    @debug.assert_eq(blocked[i], 0)
  }
  let target = [0, 0, 0, 0, 0]
  let reflected = [0, 0, 0, 0, 0]
  apply_intimidate_on_entry("いかく", "ミラーアーマー", target, reflected)
  @debug.assert_eq(reflected[0], -1)
  for i in 0..<5 {
    @debug.assert_eq(target[i], 0)
  }
}

///|
/// **Case 7 (自傷不発 / かちき)**: オーバーヒートの自己特攻 -2 では +2 されない。
test "自傷不発 (かちき): オーバーヒートの自己特攻 -2 では +2 されない" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("オーバーヒート", "ほのお", @model.Special, 130, stat_effects=[
    @model.StatEffect::{ stat: 2, delta: -2, target: 0 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="かちき",
    defender_ability="",
  )
  @debug.assert_eq(self_ranks[2], -2)
  for i in 0..<5 {
    @debug.assert_eq(opp_ranks[i], 0)
  }
}

///|
/// **Case 8 (自傷不発 / まけんき)**: インファイトの自己 B-1 / D-1 では攻撃は上がらない。
test "自傷不発 (まけんき): インファイトの自己 B-1 / D-1 では攻撃は上がらない" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("インファイト", "かくとう", @model.Physical, 120, stat_effects=[
    @model.StatEffect::{ stat: 1, delta: -1, target: 0 },
    @model.StatEffect::{ stat: 3, delta: -1, target: 0 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="まけんき",
    defender_ability="",
  )
  @debug.assert_eq(self_ranks[0], 0)
  @debug.assert_eq(self_ranks[1], -1)
  @debug.assert_eq(self_ranks[3], -1)
  for i in 0..<5 {
    @debug.assert_eq(opp_ranks[i], 0)
  }
}

///|
/// **Case 9 (相手ダウン技 / まけんき)**: あまえる (相手 A-2) は A -2 のあと攻撃
/// +2 で実効 0。
test "まけんき: 相手ダウン技 あまえる (A-2) で A -2 のあと +2 → 実効 0" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("あまえる", "フェアリー", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -2, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="まけんき",
  )
  @debug.assert_eq(opp_ranks[0], 0)
  for i in 0..<5 {
    @debug.assert_eq(self_ranks[i], 0)
  }
}

///|
/// **Case 10 (相手ダウン技 / かちき)**: なきごえ (相手 A-1) で特攻 +2、攻撃は -1 のまま。
test "かちき: 相手ダウン技 なきごえ (A-1) で特攻 +2、攻撃は -1 のまま" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="かちき",
  )
  @debug.assert_eq(opp_ranks[0], -1)
  @debug.assert_eq(opp_ranks[2], 2)
  for i in 0..<5 {
    @debug.assert_eq(self_ranks[i], 0)
  }
}

///|
/// **Case 11 (同時に 2 能力を下げる技 / まけんき)**: くすぐる (相手 A-1 / B-1) は
/// 1 回の技なので、両方のダウンを適用してから反応を 1 回だけ行う。A: -1 (適用) →
/// 攻撃 +2 で +1。B は反応の対象外なので -1 のまま。能力ごとに反応する実装なら A は +3。
test "まけんき: くすぐる (A-1/B-1 相手) は 1 回の技で 1 回だけ発動し A は +1" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="まけんき",
  )
  @debug.assert_eq(opp_ranks[0], 1)
  @debug.assert_eq(opp_ranks[1], -1)
  @debug.assert_eq(opp_ranks[2], 0)
}

///|
/// **Case 12 (同時に 2 能力を下げる技 / かちき)**: なみだめ (相手 A-1 / C-1) は
/// 1 回の技なので、両方のダウンを適用してから特攻 +2 を 1 回だけ行う。C: -1 (適用)
/// → +2 で +1。A は反応の対象外なので -1 のまま。能力ごとに反応する実装なら C は 3。
test "かちき: なみだめ (A-1/C-1 相手) は 1 回の技で 1 回だけ特攻 +2 — C = 1, A = -1" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("なみだめ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 2, delta: -1, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="かちき",
  )
  @debug.assert_eq(opp_ranks[0], -1)
  @debug.assert_eq(opp_ranks[2], 1)
}

///|
/// **Case 12a (複数ダウン / 片方だけ下限 / まけんき)**: A が既に -6 (下限) の まけんき に
/// くすぐる。A-1 は適用されず (ランク不変)、B-1 だけが適用される。下がった能力は 1 つ
/// あるので反応は 1 回: A = -6 + 2 = -4。下がらなかった A-1 では反応しない (試行ごとに
/// 反応する実装なら A は -2 になる)。
test "まけんき: くすぐる で A が下限なら A-1 は不適用、B だけ下がって反応は 1 回 (A = -4)" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [-6, 0, 0, 0, 0]
  let mv = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="まけんき",
  )
  @debug.assert_eq(opp_ranks[0], -4)
  @debug.assert_eq(opp_ranks[1], -1)
  @debug.assert_eq(opp_ranks[2], 0)
}

///|
/// **Case 12b (複数ダウン / 片方だけ下限 / かちき)**: C が既に -6 (下限) の かちき に
/// なみだめ。C-1 は適用されず、A-1 だけが適用される。反応は 1 回: 特攻 = -6 + 2 = -4。
test "かちき: なみだめ で C が下限なら C-1 は不適用、A だけ下がって反応は 1 回 (C = -4)" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, -6, 0, 0]
  let mv = mk_move("なみだめ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 2, delta: -1, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="かちき",
  )
  @debug.assert_eq(opp_ranks[0], -1)
  @debug.assert_eq(opp_ranks[2], -4)
}

///|
/// **Case 12c (複数ダウン / 全部下限で不発)**: 下げられる能力がすべて既に -6 のとき、
/// どのダウンも適用されず反応もしない。まけんき の A / B も、かちき の A / C も -6 のまま。
test "複数ダウンが全部下限なら不発: まけんき / かちき とも反応しない" {
  let self_ranks = [0, 0, 0, 0, 0]
  let defiant = [-6, -6, 0, 0, 0]
  let kugu = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    defiant,
    true,
    kugu,
    attacker_ability="",
    defender_ability="まけんき",
  )
  @debug.assert_eq(defiant[0], -6)
  @debug.assert_eq(defiant[1], -6)
  @debug.assert_eq(defiant[2], 0)
  let competitive = [-6, 0, -6, 0, 0]
  let namida = mk_move("なみだめ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 2, delta: -1, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    competitive,
    true,
    namida,
    attacker_ability="",
    defender_ability="かちき",
  )
  @debug.assert_eq(competitive[0], -6)
  @debug.assert_eq(competitive[2], -6)
  for i in 0..<5 {
    @debug.assert_eq(self_ranks[i], 0)
  }
}

///|
/// **Case 12d (反応は技ごと)**: くすぐる を 2 回受けると、技ごとに 1 回ずつ反応する。
/// 1 回目: A -1 → 反応 +2 で +1。2 回目: A +1 → 0 → 反応 +2 で +2。B は -2。
test "まけんき: くすぐるを 2 回受けると技ごとに 1 回ずつ反応 (A = +2, B = -2)" {
  let self_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move("くすぐる", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
    @model.StatEffect::{ stat: 1, delta: -1, target: 1 },
  ])
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="まけんき",
  )
  @debug.assert_eq(opp_ranks[0], 1)
  apply_stat_effects(
    self_ranks,
    opp_ranks,
    true,
    mv,
    attacker_ability="",
    defender_ability="まけんき",
  )
  @debug.assert_eq(opp_ranks[0], 2)
  @debug.assert_eq(opp_ranks[1], -2)
}

///|
/// `apply_opp_stat_drop` は反応を行わず、ランクが実際に変わったかどうかだけを返す。
/// 下限 (-6) で動かなければ false。反応 (+2) はここでは起きない。
test "apply_opp_stat_drop: 実際に下がったときだけ true、下限では false (反応しない)" {
  let ranks = [0, 0, 0, 0, 0]
  assert_true(apply_opp_stat_drop("まけんき", ranks, 0, -1))
  @debug.assert_eq(ranks[0], -1)
  let floor = [-6, 0, 0, 0, 0]
  assert_true(!apply_opp_stat_drop("まけんき", floor, 0, -1))
  @debug.assert_eq(floor[0], -6)
}

///|
/// **Case 13 (上限 +6 / 技の上昇)**: 所持者の攻撃 +4 に つるぎのまい (+2) を積むと
/// +6 まで上がる (reduced range の ±2 飽和を受けない)。
test "上限 +6: まけんき の A +4 に つるぎのまい で +6 (±2 飽和を受けない)" {
  let self_ranks = [4, 0, 0, 0, 0]
  let mv = mk_move("つるぎのまい", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: 2, target: 0 },
  ])
  apply_stat_effects(
    self_ranks,
    [0, 0, 0, 0, 0],
    true,
    mv,
    attacker_ability="まけんき",
    defender_ability="",
  )
  @debug.assert_eq(self_ranks[0], 6)
}

///|
/// **Case 14 (非所持者は従来の reduced range)**: 同じ つるぎのまい で A +1 の
/// 非所持者は +2 で ±2 に飽和する (従来挙動の pin)。
test "非所持者の技ランクは従来どおり ±2 で飽和 (reduced range)" {
  let self_ranks = [1, 0, 0, 0, 0]
  let mv = mk_move("つるぎのまい", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: 2, target: 0 },
  ])
  apply_stat_effects(
    self_ranks,
    [0, 0, 0, 0, 0],
    true,
    mv,
    attacker_ability="",
    defender_ability="",
  )
  @debug.assert_eq(self_ranks[0], 2)
}

///|
/// 特性述語と clamp の真理値表。
test "ability_boosts_on_opp_drop: まけんき / かちき のみ true" {
  assert_true(ability_boosts_on_opp_drop("まけんき"))
  assert_true(ability_boosts_on_opp_drop("かちき"))
  assert_true(!ability_boosts_on_opp_drop("いかく"))
  assert_true(!ability_boosts_on_opp_drop("あまのじゃく"))
  assert_true(!ability_boosts_on_opp_drop(""))
}

///|
test "clamp_rank_for: 所持者が まけんき / かちき なら ±6、それ以外は ±2" {
  @debug.assert_eq(clamp_rank_for("まけんき", 9), 6)
  @debug.assert_eq(clamp_rank_for("かちき", -9), -6)
  @debug.assert_eq(clamp_rank_for("いかく", 3), 2)
  @debug.assert_eq(clamp_rank_for("", -3), -2)
}

///|
/// **DP 配線 1 (まけんき / 交代いかく)**: 相手 active (まけんき) へ my の
/// いかく持ちが交代で入る。(Switch, UseMove) の順で entry 時に A -1 → 攻撃 +2。
test "まけんき: DP 交代いかく (Switch,UseMove) で相手の攻撃ランクが +1" {
  let mv = im_tackle()
  let intimidator = im_combatant(
    im_pokemon("いかく持ち", hp=300),
    [mv],
    ability="いかく",
  )
  let plain = im_combatant(im_pokemon("ふつう", hp=300), [mv])
  let receiver = im_combatant(
    im_pokemon("まけんき持ち", hp=300),
    [mv],
    ability="まけんき",
  )
  let my_team = [plain, intimidator, plain]
  let opp_team = [receiver, receiver, receiver]
  let outs = transition_with_cache(
    im_state(my_hps=[300, 300, 300], opp_hps=[300, 300, 300]),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  @debug.assert_eq(s.opp_ranks[0], 1)
}

///|
/// **DP 配線 2 (かちき / 交代いかく)**: 同じ配線で かちき 側は特攻 +2、A は -1。
test "かちき: DP 交代いかく (Switch,UseMove) で 相手は A -1 / 特攻 +2" {
  let mv = im_tackle()
  let intimidator = im_combatant(
    im_pokemon("いかく持ち", hp=300),
    [mv],
    ability="いかく",
  )
  let plain = im_combatant(im_pokemon("ふつう", hp=300), [mv])
  let receiver = im_combatant(
    im_pokemon("かちき持ち", hp=300),
    [mv],
    ability="かちき",
  )
  let my_team = [plain, intimidator, plain]
  let opp_team = [receiver, receiver, receiver]
  let outs = transition_with_cache(
    im_state(my_hps=[300, 300, 300], opp_hps=[300, 300, 300]),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  @debug.assert_eq(s.opp_ranks[0], -1)
  @debug.assert_eq(s.opp_ranks[2], 2)
}

///|
/// **DP 配線 3 (連続交代の累積 + 退場リセット)**: まけんき の攻撃は 2 回目の
/// 交代いかくで +2 に積み上がる。その後 まけんき 本人が交代で退場すると、
/// 所持者のランクは switch-out で 0 に戻る。
test "まけんき: 連続交代いかくで A は積み上がり、交代退場で 0 に戻る" {
  let mv = im_tackle()
  let intimidator = im_combatant(
    im_pokemon("いかく持ち", hp=300),
    [mv],
    ability="いかく",
  )
  let plain = im_combatant(im_pokemon("ふつう", hp=300), [mv])
  let receiver = im_combatant(
    im_pokemon("まけんき持ち", hp=300),
    [mv],
    ability="まけんき",
  )
  let my_team = [intimidator, intimidator, intimidator]
  let opp_team = [receiver, plain, plain]
  let s0 = im_state(my_hps=[300, 300, 300], opp_hps=[300, 300, 300])
  let outs1 = transition_with_cache(
    s0,
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (_, s1) = outs1[0]
  @debug.assert_eq(s1.opp_ranks[0], 1)
  let outs2 = transition_with_cache(
    s1,
    ActionKind::Switch(2),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (_, s2) = outs2[0]
  @debug.assert_eq(s2.opp_ranks[0], 2)
  // 相手が まけんき を交代で退場させる (my は技)。switch-out で相手ランクは 0。
  let outs3 = transition_with_cache(
    s2,
    ActionKind::UseMove(0),
    ActionKind::Switch(1),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (_, s3) = outs3[0]
  @debug.assert_eq(s3.opp_active, 1)
  for i in 0..<5 {
    @debug.assert_eq(s3.opp_ranks[i], 0)
  }
}
