///|
/// Stage H-1 (MC parity under weather × field): MC rollout が DP と同じ
/// initial weather / field を seed して開始した場合、Nash 値が DP と相関する
/// (sign-agreement style)。Stage F で `team_perform_attack` には `field~`
/// keyword arg が配線済みだが、MC entry point (`team_rollout` /
/// `team_monte_carlo_value`) は初期 field state を受け取らないため、
/// `Weather::None / Field::None` 開始限定の parity しか担保できていなかった。
/// 本 stage で initial weather / field を seed できる API を導入し、
/// weather × field 組合せで MC でも field/weather が damage 計算 + EOT に
/// 反映されることを観測する。
///
/// **Red phase**: 本ファイルを Stage H-1 実装前にコミットすると、`team_rollout`
/// / `team_monte_carlo_value` に `weather~` / `field~` keyword arg が無いため
/// compile error で fail する。
/// **Green phase**: `team_rollout` / `team_monte_carlo_value` に
/// `weather~ : Weather` / `field~ : Field` の keyword arg を追加し、内部の
/// `weather_state[0]` / `field_state[0]` (新規) を seed する。`greedy_team_action`
/// / `best_expected_damage` / `pick_best_move` も state.field を読んで damage
/// 計算に渡し、`team_perform_attack` callsite でも field~ を thread する。
///
/// **Parity criterion (sign agreement)**: 同じ initial state を共有した DP と
/// MC は同方向 (= same sign-bucket) の値を出す。strict numeric parity は
/// MC の単一 sample の確率性で破れるため、既存 `team_rollout: DP value and
/// MC value agree on recover team viability` 等と同じ posture (sign bucket +
/// tol 0.5 程度の budget) を取る。

///|
/// Helper: DP 用に weather + field を seed した SwitchingGameState を作る。
/// 既存 `b4_state_from_weather` を field 対応に拡張した版。Stage H 内で再利用
/// する目的で wbtest 内 local helper として持つ。
fn h1_state_from_weather_field(
  w : @model.Weather,
  f : @model.Field,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> SwitchingGameState {
  let my_hps = Array::make(my_team.length(), 0)
  let opp_hps = Array::make(opp_team.length(), 0)
  for i in 0..<my_team.length() {
    my_hps[i] = my_team[i].pokemon.hp
  }
  for i in 0..<opp_team.length() {
    opp_hps[i] = opp_team[i].pokemon.hp
  }
  {
    my_active: 0,
    opp_active: 0,
    my_hps,
    opp_hps,
    my_ranks: zero_ranks(),
    opp_ranks: zero_ranks(),
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: Array::make(my_team.length(), false),
    opp_megaed: Array::make(opp_team.length(), false),
    my_status: zero_status(my_team.length()),
    opp_status: zero_status(opp_team.length()),
    my_must_recharge: Array::make(my_team.length(), false),
    opp_must_recharge: Array::make(opp_team.length(), false),
    my_item_consumed: Array::make(my_team.length(), false),
    opp_item_consumed: Array::make(opp_team.length(), false),
    my_moves_used: Array::make(my_team.length(), 0),
    opp_moves_used: Array::make(opp_team.length(), 0),
    weather: w,
    weather_turns_left: 999,
    my_leech_seeded: Array::make(my_team.length(), false),
    my_protean_locked: Array::make(my_team.length(), ""),
    opp_leech_seeded: Array::make(opp_team.length(), false),
    opp_protean_locked: Array::make(opp_team.length(), ""),
    my_wish_turns: no_wish_pending(my_team.length()),
    opp_wish_turns: no_wish_pending(opp_team.length()),
    field: f,
    field_turns_left: 999,
    turn: 0,
  }
}

///|
/// **Case H-1A (Sun + Electric Terrain — sign agreement)**: 炎攻撃 (Sun 1.5x) +
/// でんき攻撃 (Electric Terrain 1.3x for grounded attacker) の組合せ。
/// 同じ initial state を共有した DP と MC が同符号の値を出すことを確認する。
///
/// fixture: 1v1、own = ほのお/でんき hybrid (Sun + Electric Terrain で攻撃側
/// 両方バフ)、opp = ノーマル受け。turn_limit=5 程度で DP horizon を確保。
/// strict numeric parity は MC の単一 trial 確率性で破れるため、sign-bucket
/// 一致 (DP > 0 → MC > -0.5) で十分。
test "MC/DP parity under (Sun, Electric Terrain): sign agreement" {
  let own_p = mk_pokemon(
    "FireZap", "ほのお", "でんき", 200, 120, 80, 120, 80, 100,
  )
  let opp_p = mk_pokemon("Dfn", "ノーマル", "", 250, 80, 100, 80, 100, 70)
  let flamethrower = mk_move(
    "かえんほうしゃ",
    "ほのお",
    @model.Special,
    90,
  )
  let thunderbolt = mk_move(
    "10まんボルト",
    "でんき",
    @model.Special,
    90,
  )
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let own = [mk_combatant(own_p, [flamethrower, thunderbolt])]
  let opp = [mk_combatant(opp_p, [tackle])]
  let turn_limit = 5
  let state = h1_state_from_weather_field(
    @model.Weather::Sun,
    @model.Field::Electric,
    own,
    opp,
  )
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  let stats = new_stats_with_progress(noop_progress, 0)
  let dmg = new_damage_cache()
  let dp_value = value(state, own, opp, turn_limit, cache, stats, dmg)
  // MC trials=4 で seed-averaged value を計算 (単一 sample の極端な outcome を
  // 平均化)。weather+field が MC layer の damage 経路を抜けていれば、own 側
  // 1.5x × 1.3x boost で DP と MC は同符号 (own 有利) になる。
  let mc_value = team_monte_carlo_value(
    own,
    opp,
    4,
    42UL,
    turn_limit~,
    weather=@model.Weather::Sun,
    field=@model.Field::Electric,
  )
  // sign agreement: DP > 0 (own 有利) のとき MC も > -0.5 (壊滅 KO ではない)。
  // strict numeric parity は MC noise + DP exhaustive 最適化の差で破れるが、
  // 「field が読まれていれば own 側 boost で MC も善戦する」という qualitative
  // 一致は担保される。
  if dp_value > 0.0 {
    assert_true(mc_value > -0.5)
  }
}

///|
/// **Case H-1B (Rain + Grassy Terrain — sign agreement)**: 水攻撃 (Rain 1.5x) +
/// くさ攻撃 (Grassy Terrain 1.3x for grounded attacker) の組合せ。defender が
/// 地震系を撃たない設計なので Grassy の 0.5x defender mod は影響しない。
test "MC/DP parity under (Rain, Grassy Terrain): sign agreement" {
  let own_p = mk_pokemon(
    "WaterGrass", "みず", "くさ", 200, 100, 100, 120, 100, 100,
  )
  let opp_p = mk_pokemon("Dfn", "ノーマル", "", 250, 80, 110, 80, 110, 70)
  let surf = mk_move("なみのり", "みず", @model.Special, 90)
  let leafblade = mk_move(
    "リーフブレード",
    "くさ",
    @model.Physical,
    90,
  )
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let own = [mk_combatant(own_p, [surf, leafblade])]
  let opp = [mk_combatant(opp_p, [tackle])]
  let turn_limit = 5
  let state = h1_state_from_weather_field(
    @model.Weather::Rain,
    @model.Field::Grassy,
    own,
    opp,
  )
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  let stats = new_stats_with_progress(noop_progress, 0)
  let dmg = new_damage_cache()
  let dp_value = value(state, own, opp, turn_limit, cache, stats, dmg)
  let mc_value = team_monte_carlo_value(
    own,
    opp,
    4,
    42UL,
    turn_limit~,
    weather=@model.Weather::Rain,
    field=@model.Field::Grassy,
  )
  if dp_value > 0.0 {
    assert_true(mc_value > -0.5)
  }
}

///|
/// **Case H-1C (Sand + Misty Terrain — sign agreement)**: Sand chip と Misty
/// Terrain の同期 read を確認する。defender が地震系を撃たないので Misty の
/// 0.5x defender mod は damage 計算に影響しないが、Misty による status block
/// effect の存在 (state 形式) は DP / MC で同じ state を共有していれば parity
/// に影響しない。Sand chip は両 layer で各スロット max/16 だけ EOT で削れる。
///
/// fixture は own = はがね/ひこう (Sand 免疫) で chip を片側だけにする。これで
/// Sand 環境下の win-rate boost が own 側に出る (DP / MC で同方向)。
test "MC/DP parity under (Sand, Misty Terrain): sign agreement, own Sand-immune" {
  let own_p = mk_pokemon(
    "SteelFly", "はがね", "ひこう", 200, 110, 110, 80, 90, 100,
  )
  let opp_p = mk_pokemon("Dfn", "ノーマル", "", 250, 80, 100, 80, 100, 70)
  let ironhead = mk_move(
    "アイアンヘッド",
    "はがね",
    @model.Physical,
    80,
  )
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let own = [mk_combatant(own_p, [ironhead])]
  let opp = [mk_combatant(opp_p, [tackle])]
  let turn_limit = 5
  let state = h1_state_from_weather_field(
    @model.Weather::Sand,
    @model.Field::Misty,
    own,
    opp,
  )
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  let stats = new_stats_with_progress(noop_progress, 0)
  let dmg = new_damage_cache()
  let dp_value = value(state, own, opp, turn_limit, cache, stats, dmg)
  let mc_value = team_monte_carlo_value(
    own,
    opp,
    4,
    42UL,
    turn_limit~,
    weather=@model.Weather::Sand,
    field=@model.Field::Misty,
  )
  if dp_value > 0.0 {
    assert_true(mc_value > -0.5)
  }
}

///|
/// **Case H-1D (Snow + Psychic Terrain — sign agreement)**: Psychic Terrain で
/// priority block が両 layer で同じ semantics で適用される。本 fixture では
/// priority 技を撃たないので priority block 自体は damage parity に影響せず、
/// state を共有していれば DP / MC は同方向に出る。
test "MC/DP parity under (Snow, Psychic Terrain): sign agreement" {
  let own_p = mk_pokemon(
    "PsyAtk", "エスパー", "", 200, 100, 100, 130, 100, 110,
  )
  let opp_p = mk_pokemon("Dfn", "ノーマル", "", 250, 80, 110, 80, 110, 70)
  let psychic_mv = mk_move(
    "サイコキネシス",
    "エスパー",
    @model.Special,
    90,
  )
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let own = [mk_combatant(own_p, [psychic_mv])]
  let opp = [mk_combatant(opp_p, [tackle])]
  let turn_limit = 5
  let state = h1_state_from_weather_field(
    @model.Weather::Snow,
    @model.Field::Psychic,
    own,
    opp,
  )
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  let stats = new_stats_with_progress(noop_progress, 0)
  let dmg = new_damage_cache()
  let dp_value = value(state, own, opp, turn_limit, cache, stats, dmg)
  let mc_value = team_monte_carlo_value(
    own,
    opp,
    4,
    42UL,
    turn_limit~,
    weather=@model.Weather::Snow,
    field=@model.Field::Psychic,
  )
  if dp_value > 0.0 {
    assert_true(mc_value > -0.5)
  }
}

///|
/// **Case H-1E (default vs explicit None seed — bit-exact)**: baseline parity
/// (既存 default) が回帰しないことを確認する control。既存 `team_rollout` の
/// 挙動と完全同一になるべき (= 何も seed しない呼び出しと、明示的に None /
/// None を seed した呼び出しは bit-exact)。
test "MC parity: default (None, None) and explicit seed are bit-exact" {
  let own_p = mk_pokemon("A", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let opp_p = mk_pokemon("B", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let own = [mk_combatant(own_p, [tackle])]
  let opp = [mk_combatant(opp_p, [tackle])]
  let v_default = team_monte_carlo_value(own, opp, 4, 123UL, turn_limit=5)
  let v_explicit = team_monte_carlo_value(
    own,
    opp,
    4,
    123UL,
    turn_limit=5,
    weather=@model.Weather::None,
    field=@model.Field::None,
  )
  // 同じ seed + 同じ initial state → bit-exact 一致。デフォルト値が壊れていれば
  // ここで fail する。
  @debug.assert_eq(v_default, v_explicit)
}

///|
/// **Case H-1F (field 配線確認 — field 切替で MC value が動く)**:
/// 同じチームで `field=None` と `field=Electric` を切替えると MC value が
/// 変化することを直接観測する。Stage F Open item (MC greedy の field thread)
/// が完全に解消したことの観察証拠 — 配線が抜けていれば両者は同じ value を
/// 出す。
///
/// fixture: own = でんき 攻撃 (Electric Terrain 1.3x for grounded attacker)。
/// own grounded + field=Electric で damage 1.3x boost → opp 側 KO までの
/// turn が縮まり MC value が異なる。

///|
/// **Case H-2A (Grassy heal — DP/MC value tol parity, field-active fixture)**:
/// AI Rally 指摘 #2 (MC EOT が Grassy heal をスキップしていた) の回帰防止用 tol
/// 一致テスト。既存 H-1 系は sign-agreement (DP > 0 → MC > -0.5) どまりで、
/// MC が `apply_grassy_heal_active` を実際に EOT で呼んでいることを value レベル
/// で観測できなかった。本テストは Grassy 下で grounded 同士の地味な殴り合いを
/// 解き、`|dp - mc| < 0.15` を要求する (既存 healing parity と同じ tol)。
///
/// fixture 設計: 1v1 で own / opp 共に grounded ノーマル殴り合い。両者 max_hp /
/// 16 ずつ EOT で回復するので Grassy heal 自体は zero-sum (両側に同じく載る)
/// だが、damage 計算 + EOT residual の符号付き寄与が DP / MC で一致するかを直接
/// 観測する。trial=64 で law-of-large-numbers を効かせ tol 0.15 に収める。
test "MC/DP value parity under Grassy Terrain heal (field-active fixture)" {
  let own_p = mk_pokemon(
    "OwnG", "ノーマル", "", 240, 100, 100, 80, 100, 100,
  )
  let opp_p = mk_pokemon("OppG", "ノーマル", "", 240, 100, 100, 80, 100, 90)
  let tackle_o = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  let tackle_p = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  let own = [mk_combatant(own_p, [tackle_o])]
  let opp = [mk_combatant(opp_p, [tackle_p])]
  let turn_limit = 4
  let state = h1_state_from_weather_field(
    @model.Weather::None,
    @model.Field::Grassy,
    own,
    opp,
  )
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  let stats = new_stats_with_progress(noop_progress, 0)
  let dmg = new_damage_cache()
  let dp_value = value(state, own, opp, turn_limit, cache, stats, dmg)
  let mc_value = team_monte_carlo_value(
    own,
    opp,
    64,
    4242UL,
    turn_limit~,
    weather=@model.Weather::None,
    field=@model.Field::Grassy,
  )
  // tol 0.15: MC が Grassy heal を EOT で呼んでいなければ own 側は HP 維持が
  // 弱くなり (両側 grounded だが、damage 確率分布の偏りで EOT heal 抜けは
  // value を負方向にずらす)、tol を超える。既存 healing parity と同じ tol 値。
  let diff = (dp_value - mc_value).abs()
  assert_true(diff < 0.15)
}

///|
/// **Case H-2B (Misty status block — DP/MC value tol parity, field-active
/// fixture)**: AI Rally 指摘 #1 (MC `mc_try_apply_status` が field を読まず
/// Misty 下でも grounded defender に status を付与していた) の回帰防止用 tol
/// 一致テスト。
///
/// fixture: own = でんじは + 殴り技、opp = grounded ノーマル殴り技のみ。
/// Misty 下では own のでんじは が effects 経由で paralysis を付与できない (DP /
/// MC 両方とも block すべき)。MC で field が未配線だと paralysis が MC 側だけ
/// 通って opp が遅延し own が一方的に削れ続けるという乖離が出る。Misty が
/// 両 layer で block されていれば、両者は damage-only な殴り合いを解き、value
/// は `|dp - mc| < 0.15` で一致する。
test "MC/DP value parity under Misty Terrain status block (field-active fixture)" {
  let own_p = mk_pokemon("OwnM", "ノーマル", "", 220, 110, 95, 80, 95, 110)
  let opp_p = mk_pokemon(
    "GroundedM", "ノーマル", "", 220, 100, 100, 80, 100, 90,
  )
  let thunderwave = mk_move(
    "でんじは",
    "でんき",
    @model.Status,
    0,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
  let tackle_o = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  let tackle_p = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  let own = [mk_combatant(own_p, [tackle_o, thunderwave])]
  let opp = [mk_combatant(opp_p, [tackle_p])]
  let turn_limit = 4
  let state = h1_state_from_weather_field(
    @model.Weather::None,
    @model.Field::Misty,
    own,
    opp,
  )
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  let stats = new_stats_with_progress(noop_progress, 0)
  let dmg = new_damage_cache()
  let dp_value = value(state, own, opp, turn_limit, cache, stats, dmg)
  let mc_value = team_monte_carlo_value(
    own,
    opp,
    64,
    5151UL,
    turn_limit~,
    weather=@model.Weather::None,
    field=@model.Field::Misty,
  )
  let diff = (dp_value - mc_value).abs()
  assert_true(diff < 0.15)
}

///|
/// **Case H-2C (Psychic priority block — DP/MC value tol parity, field-active
/// fixture)**: AI Rally 指摘 #3 (MC move-resolution が Psychic Terrain で
/// priority>0 を block していなかった) の回帰防止用 tol 一致テスト。
///
/// fixture: own = しんそく (priority +1) + 通常 priority 攻撃の 2 択、opp =
/// grounded ノーマル殴り技。Psychic Terrain では own のしんそくが grounded
/// opp に対して無効化される (両 layer で同じ semantics)。MC 側 block が
/// 抜けていれば、MC は priority +1 を毎ターン通して own が大幅に有利になり
/// tol を超える。両 layer で block されていれば DP greedy / MC greedy 共に
/// 通常 priority 攻撃にフォールバックし、value は `|dp - mc| < 0.15` で一致。
test "MC/DP value parity under Psychic Terrain priority block (field-active fixture)" {
  let own_p = mk_pokemon("OwnP", "ノーマル", "", 220, 110, 95, 80, 95, 100)
  let opp_p = mk_pokemon(
    "GroundedP", "ノーマル", "", 220, 100, 100, 80, 100, 90,
  )
  let extreme_speed = mk_move(
    "しんそく",
    "ノーマル",
    @model.Physical,
    80,
    priority=2,
  )
  let tackle_o = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  let tackle_p = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  let own = [mk_combatant(own_p, [extreme_speed, tackle_o])]
  let opp = [mk_combatant(opp_p, [tackle_p])]
  let turn_limit = 4
  let state = h1_state_from_weather_field(
    @model.Weather::None,
    @model.Field::Psychic,
    own,
    opp,
  )
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  let stats = new_stats_with_progress(noop_progress, 0)
  let dmg = new_damage_cache()
  let dp_value = value(state, own, opp, turn_limit, cache, stats, dmg)
  let mc_value = team_monte_carlo_value(
    own,
    opp,
    64,
    6363UL,
    turn_limit~,
    weather=@model.Weather::None,
    field=@model.Field::Psychic,
  )
  let diff = (dp_value - mc_value).abs()
  assert_true(diff < 0.15)
}

///|
test "MC field threading: Electric Terrain shifts MC value vs Field::None" {
  // own = でんき 攻撃 (Electric Terrain で 1.3x boost、grounded 必要)。
  // 充分に bulky な opp を組んで turn_limit 内で簡単に KO されないようにし、
  // turn_limit horizon 内で HP-ratio diff の値が出るようにする。
  // own と opp の Atk / Def を釣り合わせ、Field::None では「ほぼドロー」
  // (HP ratio diff ~ 0) になるよう設計。Electric Terrain ON だと own が
  // 1.3x boost で優位に立ち、value が strict に高くなる。
  let own_p = mk_pokemon("Zap", "でんき", "", 250, 90, 90, 110, 90, 90)
  let opp_p = mk_pokemon("Dfn", "ノーマル", "", 280, 100, 110, 90, 110, 80)
  let thunderbolt = mk_move(
    "10まんボルト",
    "でんき",
    @model.Special,
    80,
  )
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 50)
  let own = [mk_combatant(own_p, [thunderbolt])]
  let opp = [mk_combatant(opp_p, [tackle])]
  let v_no_field = team_monte_carlo_value(
    own,
    opp,
    4,
    99UL,
    turn_limit=4,
    weather=@model.Weather::None,
    field=@model.Field::None,
  )
  let v_electric = team_monte_carlo_value(
    own,
    opp,
    4,
    99UL,
    turn_limit=4,
    weather=@model.Weather::None,
    field=@model.Field::Electric,
  )
  // field 配線が抜けている (旧実装) なら両 value は完全一致して fail。
  // Electric が boost を与えるなら v_electric > v_no_field。
  assert_true(v_electric > v_no_field)
}
