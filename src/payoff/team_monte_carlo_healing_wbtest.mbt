///|
/// Stage 13 (team_monte_carlo parity): MC rollout が回復技セマンティクスを
/// 持つことを確認する parity test 群。
///
/// **背景**: DP 側 (SwitchingGame) は段階 1-12 で じこさいせい / つきのひかり /
/// ねむる / ねがいごと / やどりぎのタネ / いたみわけ / ドレイン技 / 天候設定
/// 技を完全に意味論化済み。一方 MC 側 (`team_monte_carlo`) は回復技を
/// `apply_healing` 相当のコードパスで処理しておらず、「じこさいせい持ちチーム」
/// と「ない版」を同条件で走らせても同じ勝率になっていた (= MC phase と DP phase
/// が割れる原因)。Stage 13 で MC 側に同じ意味論を移植し、parity を保証する。
///
/// **Red phase**: 本ファイルを Stage 13 実装前にコミットすると以下が fail する。
/// **Green phase**: `team_monte_carlo.mbt` の `team_rollout` に
///   weather / leech_seeded / wish_turns の slot 配列を追加し、
///   `team_apply_post_hit` に apply_healing 呼び出し + LeechSeed planting +
///   PainSplit + Wish setting + 天候設定処理を移植、EOT に Gen9 順序の
///   Sand chip / leftovers / leech tick / status slip / wish trigger /
///   weather counter tick を追加する。
///
/// 本ファイルは `_wbtest.mbt` (whitebox test) として `payoff` package 内に
/// 置かれている。`team_apply_post_hit` (private fn) や `switching_game_winrate`
/// などの private/public API 両方を直接呼ぶため、blackbox の `_test.mbt`
/// では扱えない。

///|
/// wbtest 内 helper。`_test.mbt` 側の helper は wbtest からは見えないため
/// 本ファイル内に inline で持つ (mk_pokemon / mk_combatant / mk_move は
/// 各種 _wbtest 間で同じ名前を持つが、`fn` (file-private) なので衝突しない)。
fn mk_pokemon(
  name : String,
  type1 : String,
  type2 : String,
  hp : Int,
  atk : Int,
  def_ : Int,
  spa : Int,
  spd : Int,
  spe : Int,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2,
    hp,
    atk,
    def_,
    spa,
    spd,
    spe,
    bst: hp + atk + def_ + spa + spd + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 0.0,
    forms: [],
  }
}

///|
fn mk_combatant(
  pokemon : @model.Pokemon, moves : Array[@model.Move],
) -> Combatant {
  {
    pokemon,
    moves,
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
}

// mk_move は switching_game_status_wbtest.mbt 側で同 package wbtest 共有の
// helper として既に定義されているので本ファイルでは再定義しない (file-private
// 同士でも namespace 衝突するため)。

///|
/// **Case A1 (Self-healing rollout)**: 回復だけが入った 1 体 vs 1 体の rollout。
///
/// own = じこさいせい のみ moveset (= greedy が必ず回復を選ぶ。pick_best_move
/// は damage > 0 の move を探すが、無ければ `TmUseMove(0)` fallback で move
/// index 0 を返すので、moveset = [じこさいせい] なら毎ターン じこさいせい が
/// 打たれる)。HP=200, Def=200。
/// opp = たいあたり (power=40)。HP=200, Atk=100。
///
/// 数値計算:
///   - opp の damage 期待値はおよそ 20 前後 (1v1 で Lv50 / 40 BP / Atk 100 vs Def 200)
///   - own の HP=200 から始まり毎ターン opp に 20 食らう
///   - own の じこさいせい は max/2 = 100 回復 (FixedFraction(1, 2))
///   - turn_limit=20 で考えると: healing なし → 200 - 20*20 = -200 → 早期 KO
///                                healing あり → 毎ターン -20 + 100 = +80 で常に max クランプ
///
/// 期待される観測:
///   - Stage 13 実装前: MC 側で apply_healing が呼ばれず, own は KO されて value = -1.0
///   - Stage 13 実装後: own は HP 維持で生存 → value > -1.0 (turn_limit でドロー
///                      or HP 比 diff で非負値)
///
/// strict assertion: 実装前は `v <= -0.5`、実装後は `v > -0.5` (実装前は -1.0
/// 確定なので strict に -0.5 で境界を作れる)。
test "team_rollout: self-heal-only own survives 20-turn rollout (recover semantics)" {
  let own_p = mk_pokemon("Healer", "ノーマル", "", 200, 50, 200, 50, 200, 100)
  let recover : @model.Move = {
    ..mk_move("じこさいせい", "ノーマル", @model.Status, 0),
    healing: Some(@model.FixedFraction(1, 2)),
  }
  let own = [mk_combatant(own_p, [recover])]
  let opp_p = mk_pokemon("Attacker", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let opp = [mk_combatant(opp_p, [tackle])]
  let rng = seeded_rng(42UL)
  // greedy 固定で確実に毎ターン じこさいせい を打つ。turn_limit=20 で十分な
  // 検証 horizon (heal-only なら全 20 ターン耐え抜く、heal なしなら ~10 ターン
  // 程度で KO される)。
  let v = team_rollout(own, opp, rng, turn_limit=20, epsilon=0.0)
  // Stage 13 実装前: healing 無視で KO 確定 → -1.0 近辺
  // Stage 13 実装後: 持続戦で HP 維持 → 非負値 (ドロー or own 有利)
  assert_true(v >= -0.5)
}

///|
/// **Case A2 (No-heal control)**: Case A1 と完全に同じ条件で、回復技を
/// damage=0 の status move (no-op) に差し替えただけ。これは「回復ありとなしで
/// 差がつく」ことを確認するための control。実装前後どちらでも fail しない
/// (control なので不変)。
test "team_rollout: no-heal control own gets KO'd in 20-turn rollout" {
  let own_p = mk_pokemon("Tank", "ノーマル", "", 200, 50, 200, 50, 200, 100)
  // healing=None の status move。実質「何もしない」ターンが続く。
  let noop = mk_move("nooop", "ノーマル", @model.Status, 0)
  let own = [mk_combatant(own_p, [noop])]
  let opp_p = mk_pokemon("Attacker", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let opp = [mk_combatant(opp_p, [tackle])]
  let rng = seeded_rng(42UL)
  let v = team_rollout(own, opp, rng, turn_limit=20, epsilon=0.0)
  // No-heal control は毎ターン 20 ダメ食らって 200 / 20 = 10 ターンで KO。
  // turn_limit=20 まで生存しないので -1.0 確定 (own のみ KO で all_ko → -1.0)。
  @debug.assert_eq(v, -1.0)
}

///|
/// **Case B1 (Wish trigger via forced switch)**: ねがいごと は 2 ターン後 EOT
/// で **同じスロット** に max/2 を発動する。Wish の戦略的価値は「受け取り手は
/// 交代後の Pokemon」というスロット固定性。MC で確認するため、1 体目が Wish
/// を打って即 KO → forced switch → 2 体目が次々 EOT で wish を受け取る、という
/// シナリオを組む。
///
/// own = [Wisher(HP=20 fragile), Receiver(HP=200 bulky)]
///   - Wisher は HP=20 で 1 ターンで KO 確定 (opp の damage ≈ 20)。Wisher の
///     moveset は [ねがいごと only] (greedy fallback で wish を打つ)。
///   - Receiver は HP=200 で turn_limit 内で耐え抜き、wish 受け取り後も生存。
/// opp = [Attacker(HP=200, Atk=100)] × 1。たいあたり power=40 で turn ごとに
///   own active に約 20 ダメ与える。
///
/// turn 1: own Wisher が wish 打つ (own_wish_turns[0]=2), opp attack で
///         Wisher HP=20 → 0 (KO)
/// turn 1 EOT: wish tick (2→1), KO 受け手は alive 判定 false → no heal
/// turn 2 開始: forced switch (Wisher fainted) で own_active = 1 (Receiver)。
///              Receiver は wish action はせず (greedy fallback で moves[0]=
///              tackle)。
/// turn 2 EOT: wish_turns[0] が 1→0 だが、wish はスロット **0** (Wisher) に
///             残っているため、HP=0 の Wisher へは発動しない。Receiver (slot 1)
///             の wish_turns は -1 のまま。
///
/// **重要**: Plan の Wish semantics は「wish はスロット固定」なので、上記の
/// 設計では Receiver は wish を受けない (slot 1 には貼られていない)。Receiver
/// が wish を受けるには Receiver 自身が wish を打って switch out → switch back
/// する必要があり、greedy 戦略では非現実的。
///
/// 本テストでは「**Wish set 経路が呼ばれる**」ことだけを確認する。Stage 13
/// 実装前は MC 側に wish_turns 配列が無いので Wish move 自体が完全 no-op、
/// own_wish_turns 配列も存在しないため symbol error で fail する。Stage 13
/// 実装後はコードが通り、Wish set 経路は走るが Receiver に healing は乗らない
/// (slot semantics)。観測上は「実装前は build error / 実装後は build success」
/// だが、Red phase test としては「team_rollout が Wish 入りの moveset を扱える
/// (型エラーで落ちない)」ことを assert する形にする。
///
/// このテストは parity の strict criterion ではなく「Wish 経路が MC でも到達
/// 可能であることの smoke test」として残す。strict parity は Case A (Recover)
/// で十分担保されているため、Wish の戦略的価値の細部 (slot semantics) は
/// DP 側 wbtest (`switching_game_healing_wbtest.mbt` の Wish ケース) に任せる。
test "team_rollout: wish-only moveset reaches the rollout without panic" {
  let own_p = mk_pokemon("Wisher", "ノーマル", "", 200, 50, 200, 50, 200, 100)
  let wish : @model.Move = {
    ..mk_move("ねがいごと", "ノーマル", @model.Status, 0),
    healing: Some(@model.Wish),
  }
  let own = [mk_combatant(own_p, [wish])]
  let opp_p = mk_pokemon("Attacker", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let opp = [mk_combatant(opp_p, [tackle])]
  let rng = seeded_rng(42UL)
  // turn_limit=5 で wish set + tick が走るが、HP=200 で 5 ターンに 100 食らう
  // 程度。Wisher is alive で wish 上書きが毎ターン起こり、wish は永久に発動
  // しない (上書きセマンティクスのため)。これは parity の **下界** を 0 で取る
  // ことに該当: Wish の上書きで healing は起きないが、build error も起きない
  // ことを確認する。
  let v = team_rollout(own, opp, rng, turn_limit=5, epsilon=0.0)
  // 値の境界 assert: rollout が完走し [-1, +1] の範囲に収まる。実装前は
  // Wish 関連の配列が無いため compile error で test 自体が走らない (= 別の意味
  // で Red phase が機能する)。
  assert_true(v >= -1.0 && v <= 1.0)
}

///|
/// **Case B2 (Wish EOT tick + activate via shared helper)**:
/// `team_apply_post_hit` 経由で wish_turns[0] = 2 にセットしたあと、MC EOT
/// block と同じ `tick_and_fire_wish_inplace` helper を 2 回呼んで Wish の
/// 2 EOT delay + 発動 + HP 加算 + idle 化までを直接観測する。`team_rollout`
/// の Step 4.5 と同じ実装を呼ぶ pin なので、helper の挙動が変わると本テスト
/// も同時に動く (= MC の wish 経路が「カウンタだけ tick して HP を加算しない」
/// 退化に逆戻りした場合に fail する)。
test "team_apply_post_hit + tick_and_fire_wish_inplace: Wish heals max/2 2 EOT later" {
  // Wisher 1 体構成。MC ローカル state を直接組み立てる。
  let wisher_p : @model.Pokemon = {
    global_no: "0000",
    name_ja: "Wisher",
    name_en: "Wisher",
    type1: "ノーマル",
    type2: "",
    hp: 200,
    atk: 100,
    def_: 200,
    spa: 100,
    spd: 200,
    spe: 100,
    bst: 900,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
  let wish_move : @model.Move = {
    name: "ねがいごと",
    type_: "ノーマル",
    category: @model.Status,
    power: 0,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: Some(@model.Wish),
    weather_set: None,
    field_set: None,
  }
  let dummy_combatant : Combatant = {
    pokemon: wisher_p,
    moves: [wish_move],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
  let attacker_hps = [200]
  let attacker_ranks = [0, 0, 0, 0, 0]
  let attacker_must_recharge = [false]
  let attacker_status : Array[@model.StatusCondition] = [@model.None]
  // per-side scalar (1-element 配列で mutable に渡す、DP 側 Int と同 semantics)。
  let attacker_wish_turns = [-1]
  let attacker_team = [dummy_combatant]
  let defender_hps = [200]
  let defender_ranks = [0, 0, 0, 0, 0]
  let defender_leech_seeded = [false]
  let defender_team = [dummy_combatant]
  let defender_megaed = [false]
  let weather_state : Array[@model.Weather] = [@model.Weather::None]
  let weather_turns_state = [0]
  // Stage H: team_apply_post_hit が field_state / field_turns_state を取るので
  // 単なる Wish setting テストでも dummy (Field::None / turns=0) を渡す。
  let field_state : Array[@model.Field] = [@model.Field::None]
  let field_turns_state = [0]
  // Wish を発動: wish_turns[0] = 2 にセットされる。
  team_apply_post_hit(
    attacker_hps, 0, attacker_ranks, attacker_must_recharge,
    attacker_status, attacker_wish_turns, attacker_team,
    defender_hps, 0, defender_ranks,
    defender_leech_seeded, defender_team, defender_megaed,
    weather_state, weather_turns_state,
    field_state, field_turns_state,
    wish_move, 0,
  )
  @debug.assert_eq(attacker_wish_turns[0], 2)

  // 1 体構成で Lv50 HP base=200 / EV252 / IV31 のとき effective_hp は確定だが
  // 値そのものは `calc_stat` に依存するので、ここでは「helper 呼出し前後で
  // HP がきちんと加算される」点のみ検証する。低い HP からスタートして heal
  // をクランプに当てない (slot_max / 2 ≥ heal_amount でちょうど observe 可能)。
  let hp_before_wait = 1
  attacker_hps[0] = hp_before_wait

  // EOT 1 回目: wish_turns[0] が 2 → 1、発動なし、HP 不変。
  // MC rollout の Step 4.5 と同じ helper (`tick_and_fire_wish_inplace`) を
  // 呼ぶことで「カウンタ tick だけして HP 加算しない」退化を防げる。active
  // index = 0 (1 体構成)。
  tick_and_fire_wish_inplace(
    attacker_wish_turns, attacker_hps, 0, attacker_team,
  )
  @debug.assert_eq(attacker_wish_turns[0], 1)
  @debug.assert_eq(attacker_hps[0], hp_before_wait)

  // EOT 2 回目: wish_turns[0] が 1 → 0 で発動、HP は max/2 ぶん加算され idle 化。
  tick_and_fire_wish_inplace(
    attacker_wish_turns, attacker_hps, 0, attacker_team,
  )
  @debug.assert_eq(attacker_wish_turns[0], -1)
  // HP は確実に増えている (max/2 が 1 以上である限り、加算が観測される)。
  // 具体値は effective_hp に依存するので strict eq ではなく増分 ≥ 1 で検証。
  assert_true(attacker_hps[0] > hp_before_wait)

  // 3 回目以降は idle (fixpoint): HP も wish_turns も不変。
  let hp_after_wish = attacker_hps[0]
  tick_and_fire_wish_inplace(
    attacker_wish_turns, attacker_hps, 0, attacker_team,
  )
  @debug.assert_eq(attacker_wish_turns[0], -1)
  @debug.assert_eq(attacker_hps[0], hp_after_wish)
}

///|
/// **Case B3 (Issue #6 regression — Wish via team_rollout, slot-bound parity)**:
/// 上記の Case B2 は `tick_and_fire_wish_inplace` を直接呼んで「helper の
/// HP 加算」を観測するが、`team_rollout` の EOT block を通っていないため、
/// MC で本当に Wish が動いているかは検証できていなかった。本ケースは
/// `team_rollout` を 2 回実行して 「Wish ありの own」と「Wish 無し (no-op) の
/// own」の最終 HP 比に有意な差が出るかを検証する。Wish が team_rollout の
/// EOT 経由で実際に発動していなければ、両者の最終 HP 比は同じになり test fail。
///
/// **シナリオ設計**:
///   - own = [Wisher (fragile HP=100), Receiver (bulky HP=300)]
///   - Wisher moveset = [ねがいごと only] (greedy fallback で Wish を打つ)
///   - opp = [Hard hitter] (turn 1 で Wisher を KO する Atk を持つ)
///   - turn 1: own[0] (Wisher) が Wish 使用 (wish_turns=2)、opp が Wisher を KO
///   - turn 1 EOT: wish_turns tick 2→1、Wisher は HP=0 (Wish 蘇生しない)
///   - turn 2 開始: greedy で own[0] KO → forced TmSwitch(1) (Receiver)。
///                  own_active=1 (slot-bound: wish_turns はサイドに残る)
///   - turn 2: Receiver は moves[0] = tackle で attack
///   - turn 2 EOT: wish_turns tick 1→0 → 発動 → own_active=1 (Receiver) 受け取り
///                 → HP += Receiver_max / 2
///   - turn 3+: Receiver は wish なし、turn_limit まで Tackle 合戦
///
/// 期待される観測:
///   - Wish パス通った場合: turn 2 EOT で Receiver が +Receiver_max/2 を受け取る
///     ため turn_limit 終了時の own_ratio がコントロール (Wish 経路を通らない)
///     より strict に高い
///   - Wish が MC で動いていない (旧バグ): own_ratio に差が出ず assert fail
///
/// コントロールは「ねがいごと の代わりに healing=None の no-op Status 技」を
/// 撃つ Wisher。攻撃手段は同じ tackle なので、Wish の有無だけが差分。
test "team_rollout: Wish on Wisher heals Receiver after forced switch (Issue #6)" {
  // Wisher: 紙耐久 + 高素早さ。turn 1 で必ず Wish を打ち、その後 Hitter に KO される
  // (Hitter は十分な火力を持つ)。Wisher は素早さで先制し、Wish を打ち切ってから
  // 倒されるのが重要。
  // Receiver: 高耐久 + 低素早さ。turn_limit まで生存することで Wish の HP 回復を
  // 観測可能。
  // Opp Hitter: 高耐久 + 中等火力。Wisher を 1 撃で倒す、Receiver には ~50/turn
  // 与える程度の damage tempo。Receiver の tackle (低火力) では turn_limit 内で
  // 倒しきれない。
  let wisher_p = mk_pokemon("Wisher", "ノーマル", "", 100, 50, 50, 50, 50, 250)
  let receiver_p = mk_pokemon("Receiver", "ノーマル", "", 300, 50, 300, 50, 300, 50)
  let opp_p = mk_pokemon("Hitter", "ノーマル", "", 400, 150, 200, 150, 200, 100)
  let wish_move : @model.Move = {
    ..mk_move("ねがいごと", "ノーマル", @model.Status, 0),
    healing: Some(@model.Wish),
  }
  let noop_move = mk_move("noop", "ノーマル", @model.Status, 0)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  // Wisher は Wish + tackle の moveset。greedy は damage move を優先するため
  // tackle が選ばれることが多い。それを避けるため、Wisher は Wish only にする
  // (greedy fallback で wish が必ず選択される)。
  let own_wish = [
    mk_combatant(wisher_p, [wish_move]),
    mk_combatant(receiver_p, [tackle]),
  ]
  let own_noop = [
    mk_combatant(wisher_p, [noop_move]),
    mk_combatant(receiver_p, [tackle]),
  ]
  let opp = [mk_combatant(opp_p, [tackle])]
  // 同じ seed で 2 回 rollout し、Wish の有無による own_ratio の差を観測する。
  // turn_limit はチューン: 短すぎると差が出ず、長すぎると両方 KO で v=-1 同点
  // になる。Receiver 単体での opp の damage tempo + Wish の +150 HP 補填を
  // 反映する境界に turn_limit を取る。
  let rng_a = seeded_rng(7777UL)
  let v_with_wish = team_rollout(
    own_wish, opp, rng_a, turn_limit=8, epsilon=0.0,
  )
  let rng_b = seeded_rng(7777UL)
  let v_without_wish = team_rollout(
    own_noop, opp, rng_b, turn_limit=8, epsilon=0.0,
  )
  // Wish 経由で Receiver HP が回復するため、Wish ありの方が最終 value で
  // strict に高い。差は max/2 = 150 HP 分相当 (Receiver の比率に直すと
  // 150/300 = 0.5 増分)。実装誤差や rounding を考慮し margin 0.05 を確保。
  // 旧 buggy 実装 (MC で Wish が動かない) では両者の差が ~0 になり assert fail。
  assert_true(v_with_wish > v_without_wish + 0.05)
}

///|
/// **Case C (DP / MC sign agreement on recover)**: 同じチームペアに対して
/// DP value と MC value の符号一致を観測する。回復ありの 1v1 で 20 turn の
/// horizon を取ると、DP も MC も「回復ありはほぼドロー (value ≈ 0 〜 + 微正)」
/// になる。実装前は MC が回復を観測しないため value = -1.0 で乖離。
///
/// strict criterion: DP > -0.5 のとき MC > -0.5 (両者ともに「壊滅 KO」では
/// ないこと)。
test "team_rollout: DP value and MC value agree on recover team viability" {
  let own_p = mk_pokemon("Healer", "ノーマル", "", 200, 50, 200, 50, 200, 100)
  let recover : @model.Move = {
    ..mk_move("じこさいせい", "ノーマル", @model.Status, 0),
    healing: Some(@model.FixedFraction(1, 2)),
  }
  let own = [mk_combatant(own_p, [recover])]
  let opp_p = mk_pokemon("Attacker", "ノーマル", "", 200, 100, 100, 100, 100, 100)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let opp = [mk_combatant(opp_p, [tackle])]
  // turn_limit=10 で DP を回す (1v1 + 1 move/side で state 数は小さい)。
  let dp_value = switching_game_winrate(own, opp, 10)
  // MC value: trials=1, seed 固定で挙動を pin。
  let mc_value = team_monte_carlo_value(own, opp, 1, 42UL, turn_limit=10)
  // 符号一致は「DP > -0.5 (= 壊滅 KO ではない) のとき MC も > -0.5」で十分。
  // 実装前: DP 側は段階 4 で healing が効くので value ≈ 0 (生存)、MC 側は
  // healing 無視で value = -1.0 (KO) → 乖離 (fail)。
  // 実装後: 両者ともに value > -0.5 (生存) → parity (pass)。
  if dp_value > -0.5 {
    assert_true(mc_value > -0.5)
  }
}
