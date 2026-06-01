///|
/// Stage 4-5 (FixedFraction healing + 天候設定技) wbtest 群。
///
/// `apply_healing` 単体と `with_post_hit_effects` 経由 integration の双方で
/// HP 回復が観測されることを assert する。Stage 4 では `FixedFraction(n, d)`
/// バリアント、Stage 5 では天候設定技 (にほんばれ / あまごい / すなあらし /
/// ゆきげしき) と weather counter tick (`apply_eot`) を追加。残るバリアントは
/// 段階 6 以降で別 wbtest として加算していく。
///
/// Red phase で `apply_healing` を no-op スタブとして導入し本ファイルが
/// fail することを確認、Green phase で FixedFraction 分岐を実装して PASS
/// させる順序。`add_hp_capped` 共通化 (Refactor) で挙動が不変であることも
/// 既存 leftovers heal テストで担保される。

///|
/// Whitebox-local `mk_heal_move` helper. `switching_game_status_wbtest.mbt` と同
/// 流儀で healing / weather_set 既定値 `None` を許す。本ファイルは healing /
/// weather_set どちらかを使うテストが中心なので、必要に応じて渡す形になる。
fn mk_heal_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
  healing? : @model.HealingEffect? = None,
  weather_set? : @model.Weather? = None,
  priority? : Int = 0,
  stat_effects? : Array[@model.StatEffect] = [],
  status_effect? : (@model.StatusKind, Int)? = None,
  accuracy? : Int = 100,
  recoil_num? : Int = 0,
  recoil_den? : Int = 1,
  self_ko? : Bool = false,
  recharge? : Bool = false,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
    accuracy,
    pp: 10,
    learn_method: "",
    priority,
    stat_effects,
    status_effect,
    recoil_num,
    recoil_den,
    self_ko,
    recharge,
    healing,
    weather_set,
    field_set: None,
  }
}

///|
/// HP=1, max=100 のスロットに `FixedFraction(1, 2)` (じこさいせい相当) を
/// 適用すると max/2 = 50 が加算される。50 < 100 なので上限クランプは効かず
/// 1 + 50 = 51 になる。
test "apply_healing: FixedFraction(1/2) restores max/2 — HP=1 → 51" {
  let hps = [1, 100]
  let mv = mk_heal_move(
    "じこさいせい",
    "ノーマル",
    @model.Status,
    0,
    healing=Some(@model.FixedFraction(1, 2)),
  )
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None, @model.None],
    "",
    0,
    "",
  )
  @debug.assert_eq(hps[0], 51)
  // 非 active slot は触られない。
  @debug.assert_eq(hps[1], 100)
}

///|
/// HP=max のスロットに `FixedFraction(1, 2)` を適用しても満タンの上限で
/// クランプされ HP は不変。`add_hp_capped` が `cur >= max_hp` 早期 return
/// しているおかげで、`max + max/2 → max` の代入も発生しない (= identity)。
test "apply_healing: FixedFraction(1/2) no-op when already full — HP=max → max" {
  let hps = [100, 100]
  let mv = mk_heal_move(
    "じこさいせい",
    "ノーマル",
    @model.Status,
    0,
    healing=Some(@model.FixedFraction(1, 2)),
  )
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None, @model.None],
    "",
    0,
    "",
  )
  @debug.assert_eq(hps[0], 100)
  @debug.assert_eq(hps[1], 100)
}

///|
/// HP=60, max=100 で `FixedFraction(1, 2)` を打つと max/2 = 50 加算で 110
/// になるが max クランプで 100 に丸まる。境界の overflow ケース。
test "apply_healing: FixedFraction(1/2) clamps overflow at max — HP=60 → 100" {
  let hps = [60]
  let mv = mk_heal_move(
    "じこさいせい",
    "ノーマル",
    @model.Status,
    0,
    healing=Some(@model.FixedFraction(1, 2)),
  )
  apply_healing(mv, 0, hps, 100, @model.Weather::None, [@model.None], "", 0, "")
  @debug.assert_eq(hps[0], 100)
}

///|
/// `healing = None` (回復技ではない通常技) では `apply_healing` は no-op。
/// じこさいせい以外の Move でも apply_healing を呼ぶ可能性があるため、
/// 「healing が無いなら HP に触らない」契約を pin する。
test "apply_healing: None healing leaves HP untouched" {
  let hps = [50]
  let mv = mk_heal_move("じしん", "じめん", @model.Physical, 100)
  apply_healing(mv, 0, hps, 100, @model.Weather::None, [@model.None], "", 0, "")
  @debug.assert_eq(hps[0], 50)
}

///|
/// Integration: `with_post_hit_effects` の末尾で `apply_healing` が呼ばれて
/// いることを確認する。じこさいせい (damage=0, category=Status, healing=
/// FixedFraction(1,2)) を撃つと attacker 側 HP が max/2 加算される。配線の
/// 切り損ね (apply_healing 呼び出し漏れ) を E2E で検知する。
test "with_post_hit_effects: FixedFraction heals attacker active slot" {
  // attacker_max = 100 を `actual_stats[0]` で固定。
  let attacker_pokemon : @model.Pokemon = {
    global_no: "0292",
    name_ja: "ヌケニン",
    name_en: "Shedinja",
    type1: "むし",
    type2: "ゴースト",
    hp: 1,
    atk: 90,
    def_: 45,
    spa: 30,
    spd: 30,
    spe: 40,
    bst: 236,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.2,
    forms: [],
  }
  let attacker : Combatant = {
    pokemon: attacker_pokemon,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([100, 100, 100, 100, 100, 100]),
    ivs: None,
  }
  // defender は Combatant 配列を保持する必要は無いが、SwitchingGameState
  // を構築する都合上 hps[opp_active] が参照されるので存在自体は必要。
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [1, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
  let mv = mk_heal_move(
    "じこさいせい",
    "ノーマル",
    @model.Status,
    0,
    healing=Some(@model.FixedFraction(1, 2)),
  )
  let attacker_team = [attacker, attacker]
  let new_state = with_post_hit_effects(
    state, true, 0, 0, attacker_team, attacker_team, mv, 0,
  )
  // attacker (= my side) active slot HP は 1 + 100/2 = 51。
  @debug.assert_eq(new_state.my_hps[0], 51)
  // 控えと相手 HP は不変。
  @debug.assert_eq(new_state.my_hps[1], 100)
  @debug.assert_eq(new_state.opp_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[1], 100)
}

// =================================================================
// Stage 5: 天候設定技 (Weather-setting moves) + apply_eot weather tick
// =================================================================
//
// 天候設定技を `with_post_hit_effects` 経由で打つと、`state.weather` と
// `state.weather_turns_left` が書き換わる。`apply_eot` は EOT ごとに
// `weather_turns_left -= 1` し、`0` になった次の EOT で `Weather::None`
// にリセットする (= 天候切れ)。Gen9 base 5 ターン (天候石なし) を本段階
// では固定とする。

///|
/// Stage 5 用の最小 Combatant ヘルパー。actual_stats=Some([100,...]) で
/// max_hp=100 を固定する。`with_post_hit_effects` は attacker_team[active] の
/// max_hp 取得用にしか使わないので、pokemon の数値はダミーで良い。
fn mk_weather_combatant() -> Combatant {
  let p : @model.Pokemon = {
    global_no: "0001",
    name_ja: "テスト",
    name_en: "Test",
    type1: "ノーマル",
    type2: "",
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  {
    pokemon: p,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([100, 100, 100, 100, 100, 100]),
    ivs: None,
  }
}

///|
/// Stage 5 用の baseline state。HP は両側 100/100 で満タン、weather は None。
/// 個別テストでこの state を渡し、with_post_hit_effects / apply_eot の戻り値
/// で field を assert する。
fn mk_weather_state() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
/// Case A: にほんばれを撃つと state.weather = Sun、weather_turns_left = 5
/// に書き換わる。HP は不変 (天候技は補助技で damage を与えない)。
test "with_post_hit_effects: にほんばれ sets weather=Sun, turns_left=5" {
  let state = mk_weather_state()
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  let mv = mk_heal_move(
    "にほんばれ",
    "ほのお",
    @model.Status,
    0,
    weather_set=Some(@model.Weather::Sun),
  )
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.weather, @model.Weather::Sun)
  @debug.assert_eq(new_state.weather_turns_left, 5)
  // HP / status / ranks は不変。
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[0], 100)
}

///|
/// Case D-1: あまごい → Rain / 5 ターン。
test "with_post_hit_effects: あまごい sets weather=Rain, turns_left=5" {
  let state = mk_weather_state()
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  let mv = mk_heal_move(
    "あまごい",
    "みず",
    @model.Status,
    0,
    weather_set=Some(@model.Weather::Rain),
  )
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.weather, @model.Weather::Rain)
  @debug.assert_eq(new_state.weather_turns_left, 5)
}

///|
/// Case D-2: すなあらし → Sand / 5 ターン。
test "with_post_hit_effects: すなあらし sets weather=Sand, turns_left=5" {
  let state = mk_weather_state()
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  let mv = mk_heal_move(
    "すなあらし",
    "いわ",
    @model.Status,
    0,
    weather_set=Some(@model.Weather::Sand),
  )
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.weather, @model.Weather::Sand)
  @debug.assert_eq(new_state.weather_turns_left, 5)
}

///|
/// Case D-3: ゆきげしき → Snow / 5 ターン。
test "with_post_hit_effects: ゆきげしき sets weather=Snow, turns_left=5" {
  let state = mk_weather_state()
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  let mv = mk_heal_move(
    "ゆきげしき",
    "こおり",
    @model.Status,
    0,
    weather_set=Some(@model.Weather::Snow),
  )
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.weather, @model.Weather::Snow)
  @debug.assert_eq(new_state.weather_turns_left, 5)
}

///|
/// 対戦相手 (opp 側) が天候技を撃った場合も同様に weather を書き換える。
/// attacker_is_me=false でも weather フィールドはサイド非依存なので同じ。
test "with_post_hit_effects: opp 側の にほんばれ も weather を書き換える" {
  let state = mk_weather_state()
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  let mv = mk_heal_move(
    "にほんばれ",
    "ほのお",
    @model.Status,
    0,
    weather_set=Some(@model.Weather::Sun),
  )
  // 第2引数 false = opp 側が attacker。attacker_team は opp 側のチームを渡す。
  let new_state = with_post_hit_effects(state, false, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.weather, @model.Weather::Sun)
  @debug.assert_eq(new_state.weather_turns_left, 5)
}

///|
/// Case B: にほんばれ使用直後の state に対し apply_eot を 1 回呼ぶと
/// weather_turns_left=5 → 4、weather=Sun は維持される。
test "apply_eot: weather counter decrement by 1 (5 → 4, Sun keeps)" {
  let state0 = mk_weather_state()
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  let mv = mk_heal_move(
    "にほんばれ",
    "ほのお",
    @model.Status,
    0,
    weather_set=Some(@model.Weather::Sun),
  )
  let state_after_set = with_post_hit_effects(
    state0, true, 0, 0, team, team, mv, 0,
  )
  @debug.assert_eq(state_after_set.weather_turns_left, 5)
  let state_after_eot = apply_eot(state_after_set, team, team)
  @debug.assert_eq(state_after_eot.weather, @model.Weather::Sun)
  @debug.assert_eq(state_after_eot.weather_turns_left, 4)
}

///|
/// Case C: にほんばれ使用 + 5 EOT 経過で weather_turns_left=0、weather=None
/// にリセットされる。5 ターン (5 EOT) の境界:
///   set → turns_left=5
///   EOT1 → 4
///   EOT2 → 3
///   EOT3 → 2
///   EOT4 → 1
///   EOT5 → 0 で None にリセット
/// Bulbapedia / Smogon の "Weather lasts 5 turns" は「設定ターン + 後続 4
/// ターン」を指すが、本実装は base=5 を素直に counter として扱う。設定
/// 直後を turns_left=5 とし、5 EOT で 0 へ落とした時点で `weather=None`
/// に切り替える。
test "apply_eot: にほんばれ expires after 5 EOTs (Sun → None)" {
  let state0 = mk_weather_state()
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  let mv = mk_heal_move(
    "にほんばれ",
    "ほのお",
    @model.Status,
    0,
    weather_set=Some(@model.Weather::Sun),
  )
  let mut state = with_post_hit_effects(state0, true, 0, 0, team, team, mv, 0)
  // 4 EOT 経過後: turns_left=1, weather=Sun (まだ持続)
  for _ in 0..<4 {
    state = apply_eot(state, team, team)
  }
  @debug.assert_eq(state.weather, @model.Weather::Sun)
  @debug.assert_eq(state.weather_turns_left, 1)
  // 5 EOT 目: turns_left=0 + weather=None にリセット
  state = apply_eot(state, team, team)
  @debug.assert_eq(state.weather, @model.Weather::None)
  @debug.assert_eq(state.weather_turns_left, 0)
}

///|
/// Case C-extra: 天候切れ後の追加 EOT は weather=None / turns_left=0 で
/// idempotent。0 を下回って負値にならないこと、None 状態で再度 None に
/// 落ちないことを pin。
test "apply_eot: weather=None / turns_left=0 is fixpoint" {
  let state0 = mk_weather_state()
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  // 初期 None / 0 で apply_eot を回しても変化しない。
  let state1 = apply_eot(state0, team, team)
  @debug.assert_eq(state1.weather, @model.Weather::None)
  @debug.assert_eq(state1.weather_turns_left, 0)
  let state2 = apply_eot(state1, team, team)
  @debug.assert_eq(state2.weather, @model.Weather::None)
  @debug.assert_eq(state2.weather_turns_left, 0)
}

///|
/// 既存挙動が崩れないこと: 回復技でない普通技 (じしん) は weather を一切
/// 書き換えない。天候処理が誤って全 with_post_hit_effects 呼び出しで発火
/// していないことを negative pin。
test "with_post_hit_effects: 通常技は weather を書き換えない" {
  let mut state = mk_weather_state()
  state = { ..state, weather: @model.Weather::Sun, weather_turns_left: 3 }
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  let mv = mk_heal_move("じしん", "じめん", @model.Physical, 100)
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.weather, @model.Weather::Sun)
  @debug.assert_eq(new_state.weather_turns_left, 3)
}

// =================================================================
// Stage 6: WeatherDependent healing (つきのひかり / あさのひざし / シンセシス)
// =================================================================
//
// `HealingEffect::WeatherDependent(default_n, default_d, sunny_n, sunny_d,
//                                  harsh_n, harsh_d)` は state.weather を見て
// 3 系統から倍率を選ぶ:
//   - Sun                 → (sunny_n, sunny_d)   = (2, 3)   (= max * 2/3 回復)
//   - Rain / Sand / Snow  → (harsh_n, harsh_d)   = (1, 4)   (= max / 4 回復)
//   - None                → (default_n, default_d) = (1, 2) (= max / 2 回復)
//
// data.json では つきのひかり / あさのひざし / シンセシス すべて
// (1,2) / (2,3) / (1,4) の triple を持つ。本テストは「つきのひかり」を代表
// として 5 天候境界 + 動的切り替え (晴れ→消滅で default に戻る) を pin する。

///|
/// 天候連動回復の Move ヘルパー。data.json の triple を直接埋める。
fn mk_moonlight_move() -> @model.Move {
  mk_heal_move(
    "つきのひかり",
    "フェアリー",
    @model.Status,
    0,
    healing=Some(@model.WeatherDependent(1, 2, 2, 3, 1, 4)),
  )
}

///|
/// Case W-1: weather=None, HP=10/100 → default 倍率 1/2 → +50 → 60
test "apply_healing: WeatherDependent None → default 1/2 (HP=10 → 60)" {
  let hps = [10, 100]
  let mv = mk_moonlight_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None, @model.None],
    "",
    0,
    "",
  )
  @debug.assert_eq(hps[0], 60)
  // 非 active slot は触られない。
  @debug.assert_eq(hps[1], 100)
}

///|
/// Case W-2: weather=Sun, HP=10/100 → sunny 倍率 2/3 → +66 (整数除算) → 76
/// 100 * 2 / 3 = 66 (mainline の整数除算と一致)
test "apply_healing: WeatherDependent Sun → sunny 2/3 (HP=10 → 76)" {
  let hps = [10]
  let mv = mk_moonlight_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::Sun, [@model.None], "", 0, "")
  @debug.assert_eq(hps[0], 76)
}

///|
/// Case W-3: weather=Rain, HP=10/100 → harsh 倍率 1/4 → +25 → 35
test "apply_healing: WeatherDependent Rain → harsh 1/4 (HP=10 → 35)" {
  let hps = [10]
  let mv = mk_moonlight_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::Rain, [@model.None], "", 0, "")
  @debug.assert_eq(hps[0], 35)
}

///|
/// Case W-4: weather=Sand → harsh 倍率 1/4 (Rain と同じ branch)。
test "apply_healing: WeatherDependent Sand → harsh 1/4 (HP=10 → 35)" {
  let hps = [10]
  let mv = mk_moonlight_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::Sand, [@model.None], "", 0, "")
  @debug.assert_eq(hps[0], 35)
}

///|
/// Case W-5: weather=Snow → harsh 倍率 1/4 (Rain / Sand と同じ branch)。
test "apply_healing: WeatherDependent Snow → harsh 1/4 (HP=10 → 35)" {
  let hps = [10]
  let mv = mk_moonlight_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::Snow, [@model.None], "", 0, "")
  @debug.assert_eq(hps[0], 35)
}

///|
/// Case W-6: 動的切り替え。にほんばれで晴れにした state に対して
/// つきのひかりを撃つと sunny 倍率 (2/3) が選ばれる。整数除算: 100*2/3 = 66。
test "with_post_hit_effects: WeatherDependent under Sun heals max*2/3" {
  let mut state = mk_weather_state()
  state = {
    ..state,
    weather: @model.Weather::Sun,
    weather_turns_left: 5,
    my_hps: [10, 100],
  }
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  let mv = mk_moonlight_move()
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  // 10 + 100 * 2 / 3 = 10 + 66 = 76
  @debug.assert_eq(new_state.my_hps[0], 76)
  @debug.assert_eq(new_state.weather, @model.Weather::Sun)
}

///|
/// Case W-7: 動的切り替え (期限切れ)。晴れが切れた直後 (apply_eot で
/// weather=None に戻った state) で つきのひかり を撃つと default 倍率 (1/2)
/// に戻る。晴れ中の 2/3 と切れた後の 1/2 を同じテスト内で連続観測する。
///
/// シナリオ:
///   1. set sun (turns_left=5)
///   2. EOT × 5 で turns_left=0 + weather=None
///   3. つきのひかり → default (1/2) で +50 → HP=60
test "with_post_hit_effects: WeatherDependent reverts to default after Sun expires" {
  let mut state = mk_weather_state()
  state = {
    ..state,
    weather: @model.Weather::Sun,
    weather_turns_left: 5,
    my_hps: [10, 100],
  }
  let team = [mk_weather_combatant(), mk_weather_combatant()]
  // 5 EOT 経過で weather=None / turns_left=0 になる。
  for _ in 0..<5 {
    state = apply_eot(state, team, team)
  }
  @debug.assert_eq(state.weather, @model.Weather::None)
  @debug.assert_eq(state.weather_turns_left, 0)
  // 晴れが切れた状態で つきのひかり を撃つと default 1/2 が選ばれる。
  let mv = mk_moonlight_move()
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  // 10 + 100 / 2 = 60
  @debug.assert_eq(new_state.my_hps[0], 60)
}

///|
/// Case W-8: HP=max のときは天候に関わらず no-op (`add_hp_capped` の早期
/// return に従う)。Sun でも Rain でも HP は不変。WeatherDependent が
/// add_hp_capped を経由していることを境界で pin。
test "apply_healing: WeatherDependent no-op when HP=max regardless of weather" {
  let hps_sun = [100]
  let hps_rain = [100]
  let mv = mk_moonlight_move()
  apply_healing(
    mv,
    0,
    hps_sun,
    100,
    @model.Weather::Sun,
    [@model.None],
    "",
    0,
    "",
  )
  apply_healing(
    mv,
    0,
    hps_rain,
    100,
    @model.Weather::Rain,
    [@model.None],
    "",
    0,
    "",
  )
  @debug.assert_eq(hps_sun[0], 100)
  @debug.assert_eq(hps_rain[0], 100)
}

// =================================================================
// Stage 7: Rest + Sleep ability immunity
// =================================================================
//
// `HealingEffect::Rest` (ねむる) は本家挙動として以下を満たす:
//   1. HP を max まで全回復する (固定割合ではなく **満タンへリセット**)
//   2. attacker の status を `Sleep(2)` に **上書き** する。Burn / Poison /
//      Para / 既存 Sleep(0) 等あらゆる既存 status を強制的に置き換える
//   3. attacker の ability が Sleep を防ぐ (`ふみん` / `やるき` /
//      `スイートベール`) なら Rest は失敗。HP も status も不変
//   4. Magic Guard は Sleep を **止めない** (Magic Guard は residual damage
//      の immunity であって status 付与の immunity ではない)
//   5. attacker HP が既に max のとき Rest は「体力がいっぱいで眠れない」で
//      失敗。HP も status も不変 (本家挙動)
//
// Rest は `maybe_apply_status_fanout` を経由せず、`apply_healing` の中で
// 直接 `attacker_status[active] = Sleep(2)` を書き込む (既存 status を
// 上書きする本家挙動を pin するため、None 保護を持つ status fanout は
// 使えない)。
//
// 段階 7 では `apply_healing` のシグネチャを拡張し、`attacker_status` と
// `attacker_ability` を追加で受け取る。FixedFraction / WeatherDependent は
// この 2 引数を参照しないので既存テストの期待値は不変。

///|
/// Stage 7 用の Rest Move ヘルパー。ねむる単体は power=0 / category=Status /
/// healing=Some(Rest)。status_effect は付けない (Rest は apply_healing 内で
/// 直接 status を書き換えるため、status fanout を経由しない)。
fn mk_rest_move() -> @model.Move {
  mk_heal_move(
    "ねむる",
    "エスパー",
    @model.Status,
    0,
    healing=Some(@model.Rest),
  )
}

///|
/// Case R-1: HP=1 / status=Burn / ability=normal で Rest を撃つと
/// HP=max=100 / status=Sleep(2)。Burn が Sleep(2) に上書きされる本家挙動。
test "apply_healing: Rest from Burn restores HP=max and overwrites status to Sleep(2)" {
  let hps = [1, 100]
  let status : Array[@model.StatusCondition] = [@model.Burn, @model.None]
  let mv = mk_rest_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::None, status, "", 0, "")
  @debug.assert_eq(hps[0], 100)
  @debug.assert_eq(status[0], @model.Sleep(2))
  // 非 active slot は不変。
  @debug.assert_eq(hps[1], 100)
  @debug.assert_eq(status[1], @model.None)
}

///|
/// Case R-2: HP=1 / status=Sleep(0) / ability=normal で Rest を撃つと
/// HP=max / status=Sleep(2)。Sleep カウンタが 0 (まもなく覚醒) でも Rest で
/// 2 にリセットされる (本家「Rest は既存 Sleep の残ターンを上書きする」)。
/// HP=max では Rest が失敗するため、Sleep カウンタリセット観察用には
/// HP < max のシナリオで pin する。
test "apply_healing: Rest resets Sleep(0) counter to Sleep(2)" {
  let hps = [1]
  let status : Array[@model.StatusCondition] = [@model.Sleep(0)]
  let mv = mk_rest_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::None, status, "", 0, "")
  @debug.assert_eq(hps[0], 100)
  @debug.assert_eq(status[0], @model.Sleep(2))
}

///|
/// Case R-3: HP=max / status=None / ability=normal で Rest を撃つと
/// 「体力がいっぱいで眠れない」で失敗 — HP も status も不変。
/// 本家挙動 (https://bulbapedia.bulbagarden.net/wiki/Rest_(move))。これを
/// 入れないと満タン Rest 使いが状態異常解除目的で常時撃てて payoff が
/// overvalued になる。
test "apply_healing: Rest at full HP fails (no HP / status change)" {
  let hps = [100]
  let status : Array[@model.StatusCondition] = [@model.None]
  let mv = mk_rest_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::None, status, "", 0, "")
  @debug.assert_eq(hps[0], 100)
  @debug.assert_eq(status[0], @model.None)
}

///|
/// Case R-3b: HP=max / status=Burn / ability=normal で Rest を撃つと
/// 同じく failure (HP も status も変化しない)。満タンガードが status 上書き
/// よりも先に走り、Burn を「Rest で踏み消す」抜け道を塞ぐ境界 pin。
test "apply_healing: Rest at full HP with Burn fails (Burn preserved)" {
  let hps = [100]
  let status : Array[@model.StatusCondition] = [@model.Burn]
  let mv = mk_rest_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::None, status, "", 0, "")
  @debug.assert_eq(hps[0], 100)
  @debug.assert_eq(status[0], @model.Burn)
}

///|
/// Case R-4: HP=1 / status=Burn / ability=ふみん で Rest を撃つと失敗。
/// Insomnia は Sleep を完全に阻止するため、Rest 全体が unfire (HP も
/// status も不変)。
test "apply_healing: Rest fails under Insomnia (ふみん) — no HP / status change" {
  let hps = [1, 100]
  let status : Array[@model.StatusCondition] = [@model.Burn, @model.None]
  let mv = mk_rest_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    status,
    "ふみん",
    0,
    "",
  )
  @debug.assert_eq(hps[0], 1)
  @debug.assert_eq(status[0], @model.Burn)
}

///|
/// Case R-5: ability=やるき (Vital Spirit) でも Rest は失敗。
test "apply_healing: Rest fails under Vital Spirit (やるき)" {
  let hps = [1]
  let status : Array[@model.StatusCondition] = [@model.Burn]
  let mv = mk_rest_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    status,
    "やるき",
    0,
    "",
  )
  @debug.assert_eq(hps[0], 1)
  @debug.assert_eq(status[0], @model.Burn)
}

///|
/// Case R-6: ability=スイートベール (Sweet Veil) でも Rest は失敗。
test "apply_healing: Rest fails under Sweet Veil (スイートベール)" {
  let hps = [1]
  let status : Array[@model.StatusCondition] = [@model.Burn]
  let mv = mk_rest_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    status,
    "スイートベール",
    0,
    "",
  )
  @debug.assert_eq(hps[0], 1)
  @debug.assert_eq(status[0], @model.Burn)
}

///|
/// Case R-7: ability=マジックガード (Magic Guard) では Rest は失敗しない。
/// Magic Guard は residual damage を 0 化する特性であって Sleep の付与を
/// 阻止しないことを境界で pin。HP=max / status=Sleep(2) に遷移する。
test "apply_healing: Magic Guard does NOT block Rest (Sleep is inflicted)" {
  let hps = [1]
  let status : Array[@model.StatusCondition] = [@model.Burn]
  let mv = mk_rest_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    status,
    "マジックガード",
    0,
    "",
  )
  @debug.assert_eq(hps[0], 100)
  @debug.assert_eq(status[0], @model.Sleep(2))
}

// -----------------------------------------------------------------
// Stage H (terrain × sleep): エレキ / ミストフィールド下で grounded な
// 使用者は Rest で眠れず失敗する (HP も status も不変)。grounded 判定は
// caller が解決して `attacker_grounded` で渡す。apply_healing は DP /
// MC 両方が共有するため、ここでの pin は両 value path の parity を兼ねる。
// -----------------------------------------------------------------

///|
/// Case R-8: エレキフィールド + grounded 使用者の Rest は失敗 (HP=1 / Burn の
/// まま不変)。`attacker_grounded=true` を渡す。
test "apply_healing: Rest fails on grounded user under Electric Terrain" {
  let hps = [1, 100]
  let status : Array[@model.StatusCondition] = [@model.Burn, @model.None]
  let mv = mk_rest_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    status,
    "",
    0,
    "",
    field=@model.Field::Electric,
    attacker_grounded=true,
  )
  @debug.assert_eq(hps[0], 1)
  @debug.assert_eq(status[0], @model.Burn)
}

///|
/// Case R-9: ミストフィールド + grounded 使用者の Rest も同様に失敗。Misty は
/// 全状態異常を阻止するため Sleep 付与の Rest が unfire になる。
test "apply_healing: Rest fails on grounded user under Misty Terrain" {
  let hps = [1, 100]
  let status : Array[@model.StatusCondition] = [@model.Burn, @model.None]
  let mv = mk_rest_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    status,
    "",
    0,
    "",
    field=@model.Field::Misty,
    attacker_grounded=true,
  )
  @debug.assert_eq(hps[0], 1)
  @debug.assert_eq(status[0], @model.Burn)
}

///|
/// Case R-10: エレキフィールド でも **非 grounded** (ひこう / ふゆう / ふうせん
/// で浮いている) 使用者は眠れるので Rest は通常通り成功する。grounded gate が
/// `attacker_grounded` に正しく依存していることの境界 pin。
test "apply_healing: Rest succeeds on airborne user under Electric Terrain" {
  let hps = [1, 100]
  let status : Array[@model.StatusCondition] = [@model.Burn, @model.None]
  let mv = mk_rest_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    status,
    "",
    0,
    "",
    field=@model.Field::Electric,
    attacker_grounded=false,
  )
  @debug.assert_eq(hps[0], 100)
  @debug.assert_eq(status[0], @model.Sleep(2))
}

///|
/// Case R-11: グラスフィールド / サイコフィールド は sleep を阻止しないため、
/// grounded 使用者でも Rest は成功する (Misty / Electric 以外では gate が
/// 発火しないことの境界 pin)。
test "apply_healing: Rest succeeds on grounded user under Grassy Terrain" {
  let hps = [1, 100]
  let status : Array[@model.StatusCondition] = [@model.Burn, @model.None]
  let mv = mk_rest_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    status,
    "",
    0,
    "",
    field=@model.Field::Grassy,
    attacker_grounded=true,
  )
  @debug.assert_eq(hps[0], 100)
  @debug.assert_eq(status[0], @model.Sleep(2))
}

// =================================================================
// Stage 8: Drain + Liquid Ooze (ヘドロえき) 反転
// =================================================================
//
// `HealingEffect::Drain(n, d)` (ギガドレイン / メガドレイン / すいとる /
// きゅうけつ / ドレインキッス (3/4) / パラボラチャージ /
// ドレインパンチ) は与えた damage の n/d を attacker が回復する。
//
// 境界仕様:
//   1. `dmg > 0` の場合のみ発動。`dmg == 0` (タイプ免疫 / 0 ダメ) は no-op
//   2. 回復量は `max(1, dmg * n / d)` — 整数除算で 0 に丸まっても最低 1 回復
//   3. `dmg` は **dealt** (defender HP でクランプ済み、overkill 補正済み)。
//      raw 計算値ではなく実際に削れた HP に基づく
//   4. defender ability が `ヘドロえき` (Liquid Ooze) のとき、attacker は
//      回復量と同じ量の **damage** を受ける (回復→反転、`sub_hp_floor0` で
//      HP=0 を床)
//   5. HP=max のときは通常 Drain は `add_hp_capped` の早期 return で no-op。
//      ヘドロえき + HP=max は damage 反転なので発動 (max - amount で減る)
//
// 段階 8 で `apply_healing` のシグネチャに `dmg : Int` と `defender_ability :
// String` を末尾追加する。FixedFraction / WeatherDependent / Rest は参照
// しないので既存テストの挙動は不変。
//
// Magic Guard × Liquid Ooze の組合せ (attacker_ability=マジックガード で
// defender_ability=ヘドロえき のときに反転 damage を防ぐか) は Plan に明記
// されておらず、本段階では **反転して食らう** デフォルト挙動を採用する
// (精度低下ではなく Plan 未定義の 2 段階 ability 相互作用のため別 task)。

///|
/// Stage 8 用の Drain Move ヘルパー。デフォルトは ギガドレイン相当 (1/2)。
/// ドレインキッス (3/4) はパラメタで差し替える。
fn mk_drain_move(
  name? : String = "ギガドレイン",
  type_? : String = "くさ",
  power? : Int = 75,
  num? : Int = 1,
  den? : Int = 2,
) -> @model.Move {
  mk_heal_move(
    name,
    type_,
    @model.Special,
    power,
    healing=Some(@model.Drain(num, den)),
  )
}

///|
/// Case D-1: ギガドレイン / dmg=40 / defender_ability=normal で attacker HP は
/// 1 → 1 + max(1, 40*1/2) = 1 + 20 = 21。標準的な Drain 経路。
test "apply_healing: Drain(1/2) dmg=40 normal defender → +20" {
  let hps = [1, 100]
  let status : Array[@model.StatusCondition] = [@model.None, @model.None]
  let mv = mk_drain_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::None, status, "", 40, "")
  @debug.assert_eq(hps[0], 21)
  @debug.assert_eq(hps[1], 100)
}

///|
/// Case D-2: dmg=0 (タイプ免疫 / すいとる × ノーマル / 0 ダメ) → no-op。
/// `dmg > 0` ガードが効いて attacker HP も defender ability も無視される。
test "apply_healing: Drain dmg=0 → no-op (no healing, no Liquid Ooze trigger)" {
  let hps = [50]
  let mv = mk_drain_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None],
    "",
    0,
    "ヘドロえき",
  )
  @debug.assert_eq(hps[0], 50)
}

///|
/// Case D-3: dmg=1 で `dmg * 1 / 2 = 0` だが `max(1, _)` で最低 1 回復。
/// 整数除算で 0 に丸まる境界を pin。
test "apply_healing: Drain dmg=1 → +1 (max(1, _) floor)" {
  let hps = [10]
  let mv = mk_drain_move()
  apply_healing(mv, 0, hps, 100, @model.Weather::None, [@model.None], "", 1, "")
  @debug.assert_eq(hps[0], 11)
}

///|
/// Case D-4: overkill — defender が HP=50 のところに raw 200 ダメージ計算で
/// dealt=50 (クランプ済み) の場合、Drain は dealt=50 の半分 = +25 で回復する。
/// 呼び出し側が dealt-based の `dmg` を渡すことを前提に、`apply_healing` は
/// 渡された `dmg` をそのまま使う (raw vs dealt の区別は caller の責務)。
test "apply_healing: Drain dealt-based (dmg=50 dealt) → +25" {
  let hps = [40]
  let mv = mk_drain_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None],
    "",
    50,
    "",
  )
  // 40 + 50/2 = 40 + 25 = 65
  @debug.assert_eq(hps[0], 65)
}

///|
/// Case D-5: defender_ability=ヘドロえき で attacker HP が **減る**。
/// 1 + 20 → 1 - 20 (反転)、`sub_hp_floor0` で 0 床なので HP=0。
test "apply_healing: Drain reversed by ヘドロえき (dmg=40, HP=10) → HP=0 (floor)" {
  let hps = [10]
  let mv = mk_drain_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None],
    "",
    40,
    "ヘドロえき",
  )
  // 10 - max(1, 40/2) = 10 - 20 = -10 → floor0 → 0
  @debug.assert_eq(hps[0], 0)
}

///|
/// Case D-6: defender_ability=ヘドロえき / attacker HP=100 → 反転で 100 - 20 = 80
/// (HP=max でも damage 反転は発動する。`add_hp_capped` の早期 return は通常
/// 回復経路のみ、`sub_hp_floor0` 経路は独立)。
test "apply_healing: Drain reversed by ヘドロえき at full HP → HP=80" {
  let hps = [100]
  let mv = mk_drain_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None],
    "",
    40,
    "ヘドロえき",
  )
  @debug.assert_eq(hps[0], 80)
}

///|
/// Case D-7: ヘドロえき + dmg=0 → no-op (Drain は dmg=0 で発動しないので
/// 反転 damage も発生しない)。タイプ免疫で dmg=0 になった攻撃に ヘドロえき
/// が反応しないことを境界で pin。
test "apply_healing: Drain ヘドロえき with dmg=0 → no-op" {
  let hps = [50]
  let mv = mk_drain_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None],
    "",
    0,
    "ヘドロえき",
  )
  @debug.assert_eq(hps[0], 50)
}

///|
/// Case D-8: ドレインキッス (3/4) / dmg=40 → +30 (= 40*3/4)。Drain の分子分母
/// が 1/2 以外でも正しく適用されることを pin。
test "apply_healing: Drain(3/4) ドレインキッス dmg=40 → +30" {
  let hps = [10]
  let mv = mk_drain_move(
    name="ドレインキッス",
    type_="フェアリー",
    power=50,
    num=3,
    den=4,
  )
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None],
    "",
    40,
    "",
  )
  // 10 + 40 * 3 / 4 = 10 + 30 = 40
  @debug.assert_eq(hps[0], 40)
}

///|
/// Case D-8b (Issue #2 regression — pre_dmg_defender_hp recapture between legs):
/// 速度同順 (speed tie) で両方が同時に Drain を使うとき、両 leg は **各自の
/// pre_dmg_defender_hp** を捕捉する必要がある。faster leg で defender HP が
/// 既に減っているとき、slower leg が古い HP を読むと dealt が overcounted
/// になる。本テストでは `apply_healing` が dmg 引数で受け取る値が正しく
/// "現時点の defender HP でクランプ済み" であることを確認する。具体的に:
///
///   slot 0: defender HP=20、Drain dmg=40 想定だが actual dealt=20 (HP クランプ)
///   → 回復: 20/2 = 10、HP: 50 + 10 = 60
///
/// 旧 buggy 実装 (dmg を pre-leg HP で計算しない) では 40/2=20 が回復に使われ
/// 70 になる。caller (= resolve_attacker_leg / apply_damage_variants_fanout)
/// は actual_dmg を計算済みで渡すので、これは apply_healing 単体テストで
/// 「dmg=20 を渡せば +10 になる」契約を pin する。
test "apply_healing: Drain uses caller-supplied dealt dmg (Issue #2 contract)" {
  let hps = [50]
  let mv = mk_drain_move()
  // dealt=20 (caller側でクランプ済み) を渡す。+10 を期待。
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None],
    "",
    20,
    "",
  )
  @debug.assert_eq(hps[0], 60)
}

///|
/// Case D-9: HP=max で通常 Drain (defender normal) → no-op。`add_hp_capped`
/// の早期 return が効いて HP は不変。`max(1, _)` 最小回復も `add_hp_capped`
/// の `cur >= max_hp` ガードで吸収される。
test "apply_healing: Drain at full HP normal defender → no-op" {
  let hps = [100]
  let mv = mk_drain_move()
  apply_healing(
    mv,
    0,
    hps,
    100,
    @model.Weather::None,
    [@model.None],
    "",
    40,
    "",
  )
  @debug.assert_eq(hps[0], 100)
}

///|
/// Integration: `with_post_hit_effects` 経由で Drain が発動し、attacker HP が
/// 加算されることを確認する。dmg=40 を outer caller (= test) が引数として
/// 渡す既存パスを使い、apply_healing 末尾呼び出しが Drain を解決することを
/// E2E で pin。
test "with_post_hit_effects: Drain heals attacker by dealt/2" {
  // attacker / defender 共に max_hp=100 のミニマル combatant。
  let combatant : Combatant = {
    pokemon: {
      global_no: "0001",
      name_ja: "テスト",
      name_en: "Test",
      type1: "ノーマル",
      type2: "",
      hp: 100,
      atk: 100,
      def_: 100,
      spa: 100,
      spd: 100,
      spe: 100,
      bst: 600,
      ability1: "",
      ability2: "",
      dream_ability: "",
      weight: 1.0,
      forms: [],
    },
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([100, 100, 100, 100, 100, 100]),
    ivs: None,
  }
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [10, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
  let mv = mk_drain_move()
  let attacker_team = [combatant, combatant]
  let defender_team = [combatant, combatant]
  let new_state = with_post_hit_effects(
    state, true, 0, 0, attacker_team, defender_team, mv, 40,
  )
  // attacker HP: 10 + 40/2 = 30
  @debug.assert_eq(new_state.my_hps[0], 30)
}

///|
/// Integration: defender_ability=ヘドロえき で attacker は damage を受ける。
/// `with_post_hit_effects` が defender_team から ability を取り出して
/// `apply_healing` に渡すことを E2E で pin。
test "with_post_hit_effects: Drain reversed by defender's ヘドロえき" {
  let attacker_combatant : Combatant = {
    pokemon: {
      global_no: "0001",
      name_ja: "テスト",
      name_en: "Test",
      type1: "ノーマル",
      type2: "",
      hp: 100,
      atk: 100,
      def_: 100,
      spa: 100,
      spd: 100,
      spe: 100,
      bst: 600,
      ability1: "",
      ability2: "",
      dream_ability: "",
      weight: 1.0,
      forms: [],
    },
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([100, 100, 100, 100, 100, 100]),
    ivs: None,
  }
  let defender_combatant : Combatant = {
    ..attacker_combatant,
    ability: "ヘドロえき",
  }
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [50, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
  let mv = mk_drain_move()
  let attacker_team = [attacker_combatant, attacker_combatant]
  let defender_team = [defender_combatant, defender_combatant]
  let new_state = with_post_hit_effects(
    state, true, 0, 0, attacker_team, defender_team, mv, 40,
  )
  // attacker HP: 50 - 40/2 = 30 (反転で damage)
  @debug.assert_eq(new_state.my_hps[0], 30)
}

// =================================================================
// Stage 9: LeechSeed (やどりぎのタネ) — planting + EOT tick + Magic Guard
// =================================================================
//
// `HealingEffect::LeechSeed` (やどりぎのタネ) は次の意味論を持つ:
//   1. 使用時、相手 (defender) の active slot に seed フラグを立てる。
//      attacker 側 HP / status は変化しない (純粋な状態付与技)
//   2. defender が くさタイプ (mega 後の effective type で判定) ならば
//      植え付けは失敗 (フラグ変化なし)
//   3. すでに seeded な相手にもう一度撃っても no-op (上書きは無害だが
//      観測としてフラグは true のまま不変)
//   4. EOT で seeded 側の HP -= max/8、相手 active HP += 同量 (Liquid Ooze
//      の反転 は drain 専用なので leech seed には影響しない)
//   5. seeded 側の ability が マジックガード (Magic Guard) のとき、tick
//      による HP 減少は 0 化される (= seed 側不変)。mainline では
//      **相手側の加算も 0** になる (Magic Guard は両側のダメージ移動を
//      丸ごと止める)
//   6. seeded 側が tick で HP=0 になっても、その同ターン分の吸収は相手に
//      入る (mainline)。次ターン以降、HP=0 スロットは tick skip
//   7. Switch アームで switched-out スロットの seeded フラグはクリアされる
//      (双方同時 Switch にも対応)
//   8. 一度 switch out した seeded スロットが switch back in したとき
//      seeded=false が維持される (slot-scoped 剥がし)
//
// LeechSeed の植え付けは **defender 側** の状態を変えるため、attacker 側
// 中心の `apply_healing` シグネチャでは扱いきれない。stage 8 の申し送り
// 通り、`with_post_hit_effects` 内で `mv.healing == Some(LeechSeed)` の
// 場合に専用パスで `defender_leech_seeded[active]` を書き換える。
// EOT tick は `apply_eot` に追加し、Switch 剥がしは `transition_with_cache`
// の Switch arm に追加する。

///|
/// Stage 9 用の LeechSeed Move ヘルパー。power=0 / category=Status /
/// healing=Some(LeechSeed)。
fn mk_leech_seed_move() -> @model.Move {
  mk_heal_move(
    "やどりぎのタネ",
    "くさ",
    @model.Status,
    0,
    healing=Some(@model.LeechSeed),
  )
}

///|
/// Stage 9 用の最小 Combatant ヘルパー。type1 / ability をパラメタ化して
/// くさタイプ免疫 / Magic Guard の各境界に使う。
fn mk_seed_combatant(
  type1? : String = "ノーマル",
  type2? : String = "",
  ability? : String = "",
) -> Combatant {
  let p : @model.Pokemon = {
    global_no: "0001",
    name_ja: "テスト",
    name_en: "Test",
    type1,
    type2,
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: ability,
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  {
    pokemon: p,
    moves: [],
    ability,
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([100, 100, 100, 100, 100, 100]),
    ivs: None,
  }
}

///|
/// Stage 9 用 baseline state。両側 HP=100 / 満タン、weather=None、
/// leech_seeded すべて false。
fn mk_seed_state() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
/// Case L-1 (planting): my が やどりぎのタネ を撃つと opp_leech_seeded[active]
/// が true になり、my_leech_seeded は変化しない。attacker HP / opp HP も不変。
test "with_post_hit_effects: LeechSeed plants on defender (opp side)" {
  let state = mk_seed_state()
  let attacker_team = [mk_seed_combatant(), mk_seed_combatant()]
  let defender_team = [mk_seed_combatant(), mk_seed_combatant()]
  let mv = mk_leech_seed_move()
  let new_state = with_post_hit_effects(
    state, true, 0, 0, attacker_team, defender_team, mv, 0,
  )
  @debug.assert_eq(new_state.opp_leech_seeded[0], true)
  @debug.assert_eq(new_state.opp_leech_seeded[1], false)
  @debug.assert_eq(new_state.my_leech_seeded[0], false)
  @debug.assert_eq(new_state.my_leech_seeded[1], false)
  // HP は変化しない (Status 技、healing は seed 専用パスで処理)。
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[0], 100)
}

///|
/// Case L-1b (planting, opp 側 attacker): opp が やどりぎのタネ を撃つと
/// my_leech_seeded[active] が true になる。サイド対称性を pin。
test "with_post_hit_effects: LeechSeed by opp plants on my side" {
  let state = mk_seed_state()
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let mv = mk_leech_seed_move()
  let new_state = with_post_hit_effects(state, false, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.my_leech_seeded[0], true)
  @debug.assert_eq(new_state.my_leech_seeded[1], false)
  @debug.assert_eq(new_state.opp_leech_seeded[0], false)
  @debug.assert_eq(new_state.opp_leech_seeded[1], false)
}

///|
/// Case L-2 (二度がけ no-op): すでに opp_leech_seeded[0]=true な defender に
/// もう一度 やどりぎのタネ を撃っても観測上の変化は無い (true のまま)。
test "with_post_hit_effects: LeechSeed re-plant on seeded target is no-op" {
  let mut state = mk_seed_state()
  state = { ..state, opp_leech_seeded: [true, false] }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let mv = mk_leech_seed_move()
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.opp_leech_seeded[0], true)
  @debug.assert_eq(new_state.opp_leech_seeded[1], false)
}

///|
/// Case L-3 (くさタイプ免疫 / type1): defender が type1=くさ のとき
/// やどりぎのタネ は植え付けに失敗する (フラグ false のまま)。
test "with_post_hit_effects: LeechSeed fails on grass-type defender (type1)" {
  let state = mk_seed_state()
  let attacker_team = [mk_seed_combatant(), mk_seed_combatant()]
  let defender_team = [mk_seed_combatant(type1="くさ"), mk_seed_combatant()]
  let mv = mk_leech_seed_move()
  let new_state = with_post_hit_effects(
    state, true, 0, 0, attacker_team, defender_team, mv, 0,
  )
  @debug.assert_eq(new_state.opp_leech_seeded[0], false)
}

///|
/// Case L-3b (くさタイプ免疫 / type2): defender の type2 が くさ でも免疫が
/// 効く (単タイプ・複合タイプどちらでも くさ を含めば失敗)。
test "with_post_hit_effects: LeechSeed fails on grass-type defender (type2)" {
  let state = mk_seed_state()
  let attacker_team = [mk_seed_combatant(), mk_seed_combatant()]
  let defender_team = [
    mk_seed_combatant(type1="どく", type2="くさ"),
    mk_seed_combatant(),
  ]
  let mv = mk_leech_seed_move()
  let new_state = with_post_hit_effects(
    state, true, 0, 0, attacker_team, defender_team, mv, 0,
  )
  @debug.assert_eq(new_state.opp_leech_seeded[0], false)
}

///|
/// Case L-4 (mega 後 くさタイプ免疫): defender が mega 後に くさタイプ化
/// する場合、effective_combatant を経由した type 判定で植え付けに失敗する。
/// mega 前 type は ノーマル、mega 後 type1=くさ。
test "with_post_hit_effects: LeechSeed fails on mega-grass defender" {
  let mut state = mk_seed_state()
  // opp[0] を mega 済みにする。
  state = { ..state, opp_megaed: [true, false] }
  let attacker_team = [mk_seed_combatant(), mk_seed_combatant()]
  // mega_form が type1="くさ" にスイッチする raw normal pokemon。
  let mega_form : @model.MegaForm = {
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    type1: "くさ",
    type2: "",
    ability: "",
    name_ja: "テストM",
  }
  let raw : @model.Pokemon = {
    global_no: "0001",
    name_ja: "テスト",
    name_en: "Test",
    type1: "ノーマル",
    type2: "",
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  let defender : Combatant = {
    pokemon: raw,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: Some(mega_form),
    nature: None,
    stat_points: None,
    actual_stats: Some([100, 100, 100, 100, 100, 100]),
    ivs: None,
  }
  let defender_team = [defender, mk_seed_combatant()]
  let mv = mk_leech_seed_move()
  let new_state = with_post_hit_effects(
    state, true, 0, 0, attacker_team, defender_team, mv, 0,
  )
  // mega 後の effective type が くさ なので植え付け失敗。
  @debug.assert_eq(new_state.opp_leech_seeded[0], false)
}

///|
/// Case L-5 (EOT 1/8 吸収): my[0] が seeded な状態で apply_eot を回すと、
/// my[0] HP -= max/8、opp[opp_active] HP += 同量。max=100 → 12 ずつ移動。
test "apply_eot: LeechSeed tick — seeded my drains to opp" {
  let mut state = mk_seed_state()
  state = { ..state, my_leech_seeded: [true, false] }
  let my_team = [mk_seed_combatant(), mk_seed_combatant()]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  // opp HP を 50 に下げて回復観測しやすくする。
  state = { ..state, opp_hps: [50, 100] }
  let new_state = apply_eot(state, my_team, opp_team)
  // my[0]: 100 - 100/8 = 100 - 12 = 88
  @debug.assert_eq(new_state.my_hps[0], 88)
  // opp[0]: 50 + 12 = 62
  @debug.assert_eq(new_state.opp_hps[0], 62)
  // seeded フラグは EOT を跨いでも維持される。
  @debug.assert_eq(new_state.my_leech_seeded[0], true)
}

///|
/// Case L-5b (EOT 双方同時 seeded): 両側 active が同時に seeded な場合、
/// 両側独立に tick が発火する。
test "apply_eot: LeechSeed tick — both sides seeded simultaneously" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [true, false],
    opp_protean_locked: ["", ""],
  }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, team, team)
  // my[0]: 100 - 12 = 88 (seeded), opp[0]: 100 - 12 = 88 (seeded)
  // 同時に my[0] には opp の吸収 +12、opp[0] には my の吸収 +12
  // ⇒ my[0] = 100 - 12 + 12 = 100、opp[0] = 100 - 12 + 12 = 100
  // (満タンなので加算は add_hp_capped で no-op、減算のみ効いて 88)
  // 正確には:
  //   my[0] tick: 100 -= 12 → 88、opp[0] += 12 → 112 → cap 100
  //   opp[0] tick: 100 -= 12 → 88、my[0] += 12 → 100 (88+12 で cap)
  // よって最終: my[0]=100, opp[0]=88 もしくは my[0]=88, opp[0]=100 となる
  // — 適用順に依存。pkdx 実装では my → opp の固定順序を採用するので、
  // my tick 後 (my=88, opp=112→100)、opp tick 後 (opp=88, my=88+12=100)。
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[0], 88)
}

///|
/// Case L-6 (Magic Guard 免疫 / seeded 側): my[0] が seeded で ability=
/// マジックガード のとき、tick で HP は失わない (= 100 のまま)。mainline では
/// Magic Guard は両側のダメージ移動を丸ごと止めるため、相手 (opp) への加算も
/// 0 化される。
test "apply_eot: LeechSeed Magic Guard — seeded loses 0 HP, opp gains 0" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    opp_hps: [50, 100],
  }
  // my[0] を マジックガード 持ちに。
  let my_team = [
    mk_seed_combatant(ability="マジックガード"),
    mk_seed_combatant(),
  ]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  // my[0] HP は不変 (Magic Guard で tick damage 無効)。
  @debug.assert_eq(new_state.my_hps[0], 100)
  // opp[0] HP も加算なし (Magic Guard で吸収側も 0)。
  @debug.assert_eq(new_state.opp_hps[0], 50)
  // seeded フラグは維持。
  @debug.assert_eq(new_state.my_leech_seeded[0], true)
}

///|
/// Case L-7 (faint-from-tick 当ターン吸収は実 drained 量): seeded 側が tick で
/// HP=0 になる境界。my[0] HP=10、max=100、tick attempt=12。seed 側の HP は 0
/// 床にクランプ (`sub_hp_floor0` 経由) されるが、相手側への移動は実際に吸えた
/// 分 (= min(cur_hp, max/8) = 10) のみ。Showdown / Gen9 はドレイン同様 actual
/// drained 量を基準に回復するため、overkill 分の 2 が相手へ転用される旧挙動は
/// 修正済み (review: "Leech Seed: heal を実 drained 量にクランプ")。
test "apply_eot: LeechSeed faint-from-tick — opp gains only actual drained" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    my_hps: [10, 100],
    opp_hps: [50, 100],
  }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, team, team)
  // my[0]: 10 - 12 → floor0 → 0
  @debug.assert_eq(new_state.my_hps[0], 0)
  // opp[0]: 50 + 10 = 60 (actual drained = min(10, 12) = 10、overkill 分の 2 は
  // 相手側へ移動しない)
  @debug.assert_eq(new_state.opp_hps[0], 60)
}

///|
/// Case L-7b (Issue #4 regression — extreme overkill cap): seeded 側が HP=1 で
/// max=160 (= max/8=20) のとき、tick 試行は raw=20、実際に吸えるのは 1 だけ。
/// opp は 50 から始めて +1=51 だけ受け取り、19 分は「空から生まれない」。
/// 旧 buggy 実装 (sub に attempted を渡し、add にも attempted=20 を渡す) なら
/// opp は 70 に、修正後は 51 に。本テストで両者を strict に区別する。
test "apply_eot: LeechSeed extreme overkill — opp gains exactly drained amount" {
  let mut state = mk_seed_state()
  // max_hp=160 (custom): mk_seed_combatant の actual_stats[0]=100 default を
  // override する必要があるので、専用の combatant を組む。
  let p : @model.Pokemon = {
    global_no: "0001",
    name_ja: "テスト",
    name_en: "Test",
    type1: "ノーマル",
    type2: "",
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  let custom_combatant : Combatant = {
    pokemon: p,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some(
      // max_hp=160 → max/8=20
      [160, 100, 100, 100, 100, 100],
    ),
    ivs: None,
  }
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    my_hps: [1, 100],
    opp_hps: [50, 100],
  }
  let my_team = [custom_combatant, mk_seed_combatant()]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  // my[0]: 1 - drained (= min(1, 20) = 1) → 0
  @debug.assert_eq(new_state.my_hps[0], 0)
  // opp[0]: 50 + drained=1 = 51。旧 buggy 実装なら 70 になる。
  @debug.assert_eq(new_state.opp_hps[0], 51)
}

///|
/// Case L-8 (HP=0 skip): seeded スロットの HP が既に 0 のとき、次の EOT
/// では tick が発火しない (= my HP=0 のまま、opp 加算なし)。faint 後の
/// 残存 seed フラグが二度発火する事故を防ぐ。
test "apply_eot: LeechSeed HP=0 slot skips tick" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    my_hps: [0, 100],
    opp_hps: [50, 100],
  }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, team, team)
  // my[0]: 0 のまま (tick skip)
  @debug.assert_eq(new_state.my_hps[0], 0)
  // opp[0]: 50 のまま (吸収無し)
  @debug.assert_eq(new_state.opp_hps[0], 50)
}

///|
/// Case L-8b (ヘドロえき): my[0] が seeded で ability=ヘドロえき のとき、tick
/// で drained 量を相手 (opp[opp_active]) に **回復 ではなく ダメージ** として
/// 与える。種付き側の HP 減少は通常通り発生する (Liquid Ooze は seed 側を
/// 守らない、drain される側を罰するだけ)。max=100 → drained=12、my HP は
/// 100→88、opp HP は 50→38。
test "apply_eot: LeechSeed Liquid Ooze (seeded side) damages opp instead of healing" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    opp_hps: [50, 100],
  }
  let my_team = [
    mk_seed_combatant(ability="ヘドロえき"),
    mk_seed_combatant(),
  ]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  // my[0]: 100 - 12 = 88 (seed tick は通常通り)
  @debug.assert_eq(new_state.my_hps[0], 88)
  // opp[0]: 50 - 12 = 38 (回復ではなくダメージに反転)
  @debug.assert_eq(new_state.opp_hps[0], 38)
}

///|
/// Case L-8c (ヘドロえき + 相手 HP 不足): Liquid Ooze 反転ダメージは
/// `sub_hp_floor0` 経由で 0 床にクランプされる。opp_hps=5, drained=12 で
/// opp は 0 に落ちる (overkill 分は捨てる、回復側 cap の対称構造)。
test "apply_eot: LeechSeed Liquid Ooze reversal floors opp HP at 0" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    opp_hps: [5, 100],
  }
  let my_team = [
    mk_seed_combatant(ability="ヘドロえき"),
    mk_seed_combatant(),
  ]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.my_hps[0], 88)
  @debug.assert_eq(new_state.opp_hps[0], 0)
}

///|
/// Case L-8d (ヘドロえき / opp 側 seeded): サイド対称性。opp[0] が seeded で
/// ability=ヘドロえき のとき、my (本来の回復側) が drained 量のダメージを
/// 受ける。
test "apply_eot: LeechSeed Liquid Ooze (opp side seeded) damages my instead of healing" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    opp_leech_seeded: [true, false],
    opp_protean_locked: ["", ""],
    my_hps: [50, 100],
  }
  let my_team = [mk_seed_combatant(), mk_seed_combatant()]
  let opp_team = [
    mk_seed_combatant(ability="ヘドロえき"),
    mk_seed_combatant(),
  ]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.opp_hps[0], 88)
  @debug.assert_eq(new_state.my_hps[0], 38)
}

///|
/// Case L-9 (Switch で剥がし — my 側): my[0] が seeded な状態で my[0]→my[1]
/// に Switch すると、my_leech_seeded[0] が false にクリアされる。opp 側は不変。
test "transition_with_cache: Switch clears my seeded slot" {
  let mut state = mk_seed_state()
  state = { ..state, my_leech_seeded: [true, false] }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let cache = new_damage_cache()
  let outs = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::Switch(0),
    team,
    team,
    cache,
  )
  // 単一決定的遷移を仮定 (Switch+Switch は確率 1.0)。
  @debug.assert_eq(outs.length(), 1)
  let (_, new_state) = outs[0]
  @debug.assert_eq(new_state.my_leech_seeded[0], false)
  @debug.assert_eq(new_state.my_leech_seeded[1], false)
}

///|
/// Case L-10 (双方同時 Switch で双方剥がし): 両側 seeded で両側同時 Switch
/// すると両方の seeded フラグがクリアされる。
test "transition_with_cache: simultaneous Switch clears both seeded slots" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [true, false],
    opp_protean_locked: ["", ""],
  }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let cache = new_damage_cache()
  let outs = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::Switch(1),
    team,
    team,
    cache,
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, new_state) = outs[0]
  @debug.assert_eq(new_state.my_leech_seeded[0], false)
  @debug.assert_eq(new_state.opp_leech_seeded[0], false)
  // 控えに移動した slot はもともと false だったので不変。
  @debug.assert_eq(new_state.my_leech_seeded[1], false)
  @debug.assert_eq(new_state.opp_leech_seeded[1], false)
}

///|
/// Case L-11 (switch-back で seeded=false が維持される): seeded slot[0]→
/// slot[1] へ switch out すると slot[0] の seed が剥がれる。さらに後ターン
/// で slot[1]→slot[0] と switch back しても、slot[0] の seeded は false
/// のままである (slot-scoped 剥がしの永続性)。
test "transition_with_cache: switch-out then switch-back keeps seeded=false" {
  let mut state = mk_seed_state()
  state = { ..state, my_leech_seeded: [true, false] }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let cache = new_damage_cache()
  // 1) my[0]→my[1] へ switch out。opp 側も Switch (テスト都合)。
  let outs1 = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::Switch(0),
    team,
    team,
    cache,
  )
  @debug.assert_eq(outs1.length(), 1)
  let (_, state_after_out) = outs1[0]
  @debug.assert_eq(state_after_out.my_leech_seeded[0], false)
  @debug.assert_eq(state_after_out.my_active, 1)
  // 2) my[1]→my[0] へ switch back。
  let outs2 = transition_with_cache(
    state_after_out,
    ActionKind::Switch(0),
    ActionKind::Switch(0),
    team,
    team,
    cache,
  )
  @debug.assert_eq(outs2.length(), 1)
  let (_, state_after_back) = outs2[0]
  // slot[0] に戻っても seeded は false のまま (slot-scoped 剥がし)。
  @debug.assert_eq(state_after_back.my_leech_seeded[0], false)
  @debug.assert_eq(state_after_back.my_active, 0)
}

// =================================================================
// Stage 10: PainSplit (いたみわけ) — 双方 HP 平均化 + 各側独立 max クランプ
// =================================================================
//
// `HealingEffect::PainSplit` (いたみわけ) は次の意味論を持つ:
//   1. attacker_cur + defender_cur を合算して 2 で割る (floor 除算)。
//      MoonBit の `Int / Int` は floor 除算なので非負 HP では切り捨て方向と
//      一致する
//   2. 双方の active slot HP を `avg` に書き換える。ただし各側それぞれの
//      max_hp で independent にクランプする (asymmetric max への対応):
//        my_hps[my_active] = min(avg, my_max)
//        opp_hps[opp_active] = min(avg, opp_max)
//   3. attacker 側 HP / defender 側 HP のどちらが大きくても小さくても、
//      avg は対称に共有される (= 「平均化」)
//   4. fainted defender (HP=0) でも apply_healing 自体は (avg = attacker/2 で)
//      動く。mainline は fainted target に対し失敗扱いだが、本 PR では
//      alive_actions が ひんし を action 候補から除外するため通常ゲーム木では
//      到達しない。テスト都合で直接呼んだ場合の挙動を pin する
//   5. HP=max 同士のときは avg = max → no-op (実質的に観測不変)
//
// 実装方針: LeechSeed と同じく defender 側を書き換えるため、`apply_healing`
// は attacker 側バッファしか書けない設計の制約を回避し、`with_post_hit_effects`
// 内に専用パスを追加する。my_hps_new / opp_hps_new と defender_team から
// effective_hp を引いて defender_max を得る。

///|
/// Stage 10 用の PainSplit Move ヘルパー。power=0 / category=Status /
/// healing=Some(PainSplit)。data.json では「いたみわけ」エントリ。
fn mk_painsplit_move() -> @model.Move {
  mk_heal_move(
    "いたみわけ",
    "ノーマル",
    @model.Status,
    0,
    healing=Some(@model.PainSplit),
  )
}

///|
/// Stage 10 用の Combatant ヘルパー。max_hp を actual_stats[0] で指定できる
/// ようにする。pokemon の hp はダミー (effective_hp は actual_stats を優先)。
fn mk_painsplit_combatant(max_hp? : Int = 100) -> Combatant {
  let p : @model.Pokemon = {
    global_no: "0001",
    name_ja: "テスト",
    name_en: "Test",
    type1: "ノーマル",
    type2: "",
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  {
    pokemon: p,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([max_hp, 100, 100, 100, 100, 100]),
    ivs: None,
  }
}

///|
/// Stage 10 用 baseline state factory。両側 HP / leech_seeded / wish_turns を
/// 個別テストで上書きしやすいよう、初期値は 100/100 / false / -1 の中立。
fn mk_painsplit_state() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
/// Case P-1 (対称 max): attacker HP=10/max=100, defender HP=90/max=100 →
/// avg=(10+90)/2=50。双方 max=100 でクランプは効かず、my_hps[0]=opp_hps[0]=50。
test "with_post_hit_effects: PainSplit symmetric max (10/100, 90/100 → 50/50)" {
  let mut state = mk_painsplit_state()
  state = { ..state, my_hps: [10, 100], opp_hps: [90, 100] }
  let my_team = [mk_painsplit_combatant(), mk_painsplit_combatant()]
  let opp_team = [mk_painsplit_combatant(), mk_painsplit_combatant()]
  let mv = mk_painsplit_move()
  let new_state = with_post_hit_effects(
    state, true, 0, 0, my_team, opp_team, mv, 0,
  )
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.opp_hps[0], 50)
  // 非 active slot は不変。
  @debug.assert_eq(new_state.my_hps[1], 100)
  @debug.assert_eq(new_state.opp_hps[1], 100)
}

///|
/// Case P-2 (非対称 max — attacker 小 / defender 大): attacker HP=10/max=100,
/// defender HP=180/max=200 → avg=(10+180)/2=95。my_max=100, opp_max=200 で
/// 両方 95 < max なのでクランプ無し → my_hps[0]=95, opp_hps[0]=95。
test "with_post_hit_effects: PainSplit asymmetric max (10/100, 180/200 → 95/95)" {
  let mut state = mk_painsplit_state()
  state = { ..state, my_hps: [10, 100], opp_hps: [180, 100] }
  let my_team = [
    mk_painsplit_combatant(max_hp=100),
    mk_painsplit_combatant(max_hp=100),
  ]
  let opp_team = [
    mk_painsplit_combatant(max_hp=200),
    mk_painsplit_combatant(max_hp=200),
  ]
  let mv = mk_painsplit_move()
  let new_state = with_post_hit_effects(
    state, true, 0, 0, my_team, opp_team, mv, 0,
  )
  @debug.assert_eq(new_state.my_hps[0], 95)
  @debug.assert_eq(new_state.opp_hps[0], 95)
}

///|
/// Case P-3 (極端非対称 — attacker max 小 → クランプ発火): attacker HP=10/
/// max=50, defender HP=180/max=200 → avg=(10+180)/2=95。my_max=50 < 95 で
/// クランプ発火 → my_hps[0]=50 (= my_max)、opp_hps[0]=95 (クランプ不要)。
/// asymmetric max でも各側独立にクランプする本家挙動を pin。
test "with_post_hit_effects: PainSplit attacker-max clamps (10/50, 180/200 → 50/95)" {
  let mut state = mk_painsplit_state()
  state = { ..state, my_hps: [10, 100], opp_hps: [180, 100] }
  let my_team = [
    mk_painsplit_combatant(max_hp=50),
    mk_painsplit_combatant(max_hp=50),
  ]
  let opp_team = [
    mk_painsplit_combatant(max_hp=200),
    mk_painsplit_combatant(max_hp=200),
  ]
  let mv = mk_painsplit_move()
  let new_state = with_post_hit_effects(
    state, true, 0, 0, my_team, opp_team, mv, 0,
  )
  // avg=95、my_max=50 で頭打ち。
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.opp_hps[0], 95)
}

///|
/// Case P-4 (逆方向の極端非対称 — defender max 小 → defender 側クランプ):
/// attacker HP=180/max=200, defender HP=10/max=50 → avg=(180+10)/2=95。
/// opp_max=50 < 95 でクランプ → opp_hps[0]=50、my_hps[0]=95 (クランプ不要)。
/// Case P-3 のサイド反転、各側 independent クランプを pin。
test "with_post_hit_effects: PainSplit defender-max clamps (180/200, 10/50 → 95/50)" {
  let mut state = mk_painsplit_state()
  state = { ..state, my_hps: [180, 100], opp_hps: [10, 100] }
  let my_team = [
    mk_painsplit_combatant(max_hp=200),
    mk_painsplit_combatant(max_hp=200),
  ]
  let opp_team = [
    mk_painsplit_combatant(max_hp=50),
    mk_painsplit_combatant(max_hp=50),
  ]
  let mv = mk_painsplit_move()
  let new_state = with_post_hit_effects(
    state, true, 0, 0, my_team, opp_team, mv, 0,
  )
  @debug.assert_eq(new_state.my_hps[0], 95)
  @debug.assert_eq(new_state.opp_hps[0], 50)
}

///|
/// Case P-5 (floor 除算境界 / 奇数和): attacker HP=10, defender HP=91 →
/// (10+91)/2 = 101/2 = 50 (Int floor 除算)。両側 max=100 でクランプ無し →
/// my_hps[0]=opp_hps[0]=50。MoonBit の Int 除算が floor であることを pin
/// (mainline と一致)。
test "with_post_hit_effects: PainSplit floor division on odd sum (10+91 → 50/50)" {
  let mut state = mk_painsplit_state()
  state = { ..state, my_hps: [10, 100], opp_hps: [91, 100] }
  let team = [mk_painsplit_combatant(), mk_painsplit_combatant()]
  let mv = mk_painsplit_move()
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.opp_hps[0], 50)
}

///|
/// Case P-6 (fainted defender — 現状挙動 pin): defender HP=0 で attacker HP=80
/// に PainSplit を撃つと avg=(80+0)/2=40。両側 max=100 でクランプ無し →
/// my_hps[0]=40, opp_hps[0]=40。
///
/// mainline では PainSplit は受け手が ひんし のとき失敗するが、本 PR では
/// `alive_actions` が defender ひんし を action 候補から除外するため通常の
/// ゲーム木から到達しない。テスト都合で直接呼んだ場合の挙動を pin する
/// (= 失敗扱いではなく avg/2 で素直に動く)。明示ガードは alive_actions 側で
/// 担保されており、apply_healing 側に重複ガードは入れない。
test "with_post_hit_effects: PainSplit on fainted defender — current behavior pinned" {
  let mut state = mk_painsplit_state()
  state = { ..state, my_hps: [80, 100], opp_hps: [0, 100] }
  let team = [mk_painsplit_combatant(), mk_painsplit_combatant()]
  let mv = mk_painsplit_move()
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  // avg=(80+0)/2=40。alive_actions ガードに依存し、ここでは平均化される。
  @debug.assert_eq(new_state.my_hps[0], 40)
  @debug.assert_eq(new_state.opp_hps[0], 40)
}

///|
/// Case P-7 (HP=max 同士): 両者満タンで PainSplit を撃つと avg=(100+100)/2=100
/// → my_hps[0]=opp_hps[0]=100 (実質 no-op)。境界 HP=max で書き戻し動作を pin。
test "with_post_hit_effects: PainSplit at full HP both sides — no observable change" {
  let state = mk_painsplit_state()
  let team = [mk_painsplit_combatant(), mk_painsplit_combatant()]
  let mv = mk_painsplit_move()
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[0], 100)
}

///|
/// Case P-8 (opp 側 attacker — サイド対称性): opp が PainSplit を撃った場合
/// も同様に動く。attacker_is_me=false で attacker 側 = opp_hps、defender 側 =
/// my_hps を書き換える。HP=10 (opp) / 90 (my) → avg=50 → 双方 50。
test "with_post_hit_effects: PainSplit by opp side — symmetric behavior" {
  let mut state = mk_painsplit_state()
  state = { ..state, my_hps: [90, 100], opp_hps: [10, 100] }
  let team = [mk_painsplit_combatant(), mk_painsplit_combatant()]
  let mv = mk_painsplit_move()
  // attacker_is_me=false: opp が攻撃側、my が defender。
  let new_state = with_post_hit_effects(state, false, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.opp_hps[0], 50)
}

// =================================================================
// Stage 11: Wish (ねがいごと) — 2-turn delayed slot-bound healing
// =================================================================
//
// `HealingEffect::Wish` (ねがいごと) は次の意味論を持つ:
//   1. 使用時、attacker 側の active スロット index `i` に対して
//      `wish_turns[i] = 2` をセットする。これは「あと 2 EOT 後の終了処理で
//      発動」というカウンタ
//   2. EOT 毎に各 slot を走査し、`wish_turns[i] == 0` の slot で発動:
//      - HP > 0 なら `hps[i] += max_hp / 2` (`add_hp_capped` で max クランプ)
//      - HP == 0 (受け手がひんし) なら HP は不変だが「発動済み」として扱い
//        wish_turns[i] = -1 にリセット (= 蘇生せず Wish も消費される、本家挙動)
//   3. 続けて各 slot で `wish_turns[i] > 0` の場合は `-= 1` (tick decrement)。
//      発動済みで -1 に落ちた slot は次 EOT で再発動しない (idle 状態)
//   4. 交代しても wish_turns はスロットに居座る (slot-scoped、これが Wish の
//      戦略的価値)。Switch 時に剥がさない (= LeechSeed と対比的)
//   5. すでに pending な wish_turns に対して再度 ねがいごとを撃つと後着が
//      勝ち、wish_turns[i] = 2 にリセットされる (Gen9: 重ね掛け不可、後着優先)
//   6. 異なる slot の wish は完全に独立 (slot 0 と slot 1 で別タイマー)
//   7. opp 側も同様 (サイド対称)
//
// Wish の slot 書き換えは attacker の active slot に対して行うため、defender
// 側を触る LeechSeed / PainSplit と違って attacker 側 mutation で完結する。
// しかし `apply_healing` 経由ではなく `with_post_hit_effects` 内に専用パスを
// 設ける (現行 `apply_healing` シグネチャは wish_turns 配列を引数に取らない
// ため拡張すると他バリアントへの引数増を要し非対称になる、LeechSeed と同じ
// 流儀)。
//
// 段階 12 (EOT 公式順序整理) で天候ダメ → leftovers → やどりぎ → 状態異常 slip
// → ねがいごと発動 → 天候 tick → wish_turns tick の Gen9 公式順に並び替える
// 前提だが、本段階では既存 status slip / leech tick / weather tick の後に
// 「wish 発動 + wish_turns tick」を挿入する。同一 EOT 内で順序を変えても本段階
// の観測値 (HP +max/2 と wish_turns -1 の遷移) は変化しない (= 順序非依存)。

///|
/// Stage 11 用の Wish Move ヘルパー。power=0 / category=Status /
/// healing=Some(Wish)。data.json では「ねがいごと」エントリ。
fn mk_wish_move() -> @model.Move {
  mk_heal_move(
    "ねがいごと",
    "ノーマル",
    @model.Status,
    0,
    healing=Some(@model.Wish),
  )
}

///|
/// Stage 11 用の Combatant ヘルパー。max_hp を actual_stats[0] で指定できる
/// ようにする。pokemon の hp はダミー (effective_hp は actual_stats を優先)。
fn mk_wish_combatant(max_hp? : Int = 100) -> Combatant {
  let p : @model.Pokemon = {
    global_no: "0001",
    name_ja: "テスト",
    name_en: "Test",
    type1: "ノーマル",
    type2: "",
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  {
    pokemon: p,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([max_hp, 100, 100, 100, 100, 100]),
    ivs: None,
  }
}

///|
/// Stage 11 用 baseline state factory。両側 HP=100 / 満タン、weather=None、
/// wish_turns すべて -1 (= idle、pending なし)。
fn mk_wish_state() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
/// Case W-1 (使用ターン → wish_turns=2): my の active が ねがいごと を撃つと
/// my_wish_turns が 2 になり、opp_wish_turns は不変。HP も不変 (発動は 2 EOT 後)。
test "with_post_hit_effects: Wish sets attacker side's wish_turns to 2" {
  let state = mk_wish_state()
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let mv = mk_wish_move()
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.my_wish_turns, 2)
  // opp 側は完全に不変。
  @debug.assert_eq(new_state.opp_wish_turns, -1)
  // HP は不変 (発動は 2 EOT 後)。
  @debug.assert_eq(new_state.my_hps[0], 100)
}

///|
/// Case W-2 (1 EOT 後 → 2 → 1, HP 不変): ねがいごと使用直後の state に
/// apply_eot を 1 回呼ぶと wish_turns が 2 → 1 にデクリメントされる。
/// HP は変化しない (発動はまだ)。
test "apply_eot: Wish tick 2 → 1, no HP change" {
  let state0 = mk_wish_state()
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let mv = mk_wish_move()
  let state_after_set = with_post_hit_effects(
    state0, true, 0, 0, team, team, mv, 0,
  )
  @debug.assert_eq(state_after_set.my_wish_turns, 2)
  let state_after_eot = apply_eot(state_after_set, team, team)
  @debug.assert_eq(state_after_eot.my_wish_turns, 1)
  // HP は不変。
  @debug.assert_eq(state_after_eot.my_hps[0], 100)
}

///|
/// Case W-3 (2 EOT 後 → 0 で発動): ねがいごと使用 + EOT 2 回で wish_turns
/// が 0 になり発動し、active slot HP += max/2、その後 -1 に idle 化。HP=50 から始めると
/// 50 + 100/2 = 100 で満タンに到達。3 EOT 目以降は idle。
test "apply_eot: Wish triggers at turns=0, heals max/2, idles to -1" {
  let mut state = mk_wish_state()
  state = { ..state, my_hps: [50, 100] }
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let mv = mk_wish_move()
  state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(state.my_wish_turns, 2)
  // 1 EOT: 2 → 1, HP 不変
  state = apply_eot(state, team, team)
  @debug.assert_eq(state.my_wish_turns, 1)
  @debug.assert_eq(state.my_hps[0], 50)
  // 2 EOT: 1 → 0 で発動 → HP +50 → 100, wish_turns -1 (idle)
  state = apply_eot(state, team, team)
  @debug.assert_eq(state.my_hps[0], 100)
  @debug.assert_eq(state.my_wish_turns, -1)
}

///|
/// Case W-4 (3 EOT 目以降 idle): 発動後の wish_turns=-1 は次 EOT で変化しない。
/// HP も idle slot に対しては変化しない。
test "apply_eot: Wish idle (turns=-1) is fixpoint" {
  let mut state = mk_wish_state()
  state = { ..state, my_hps: [50, 100], my_wish_turns: -1 }
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  // 数回 EOT を回しても変化しない。
  for _ in 0..<3 {
    state = apply_eot(state, team, team)
  }
  @debug.assert_eq(state.my_hps[0], 50)
  @debug.assert_eq(state.my_wish_turns, -1)
}

///|
/// Case W-5 (active が指す Pokemon の max_hp で回復): wish_turns=0 で apply_eot
/// を回すと、その時点の active が指す Pokemon の max_hp に基づいて HP が回復する。
/// active=1 / slot 1 の max_hp=200 → HP += 100 (= 200/2)。これは slot-bound
/// semantics の核心 (Switch 後の Pokemon が Wish を受け取る、Case W-7 で確認)。
test "apply_eot: Wish heals current active's max_hp / 2" {
  let mut state = mk_wish_state()
  // active を slot 1 にして wish 発動 (turns=0) を観測する。
  // slot 1 の max_hp は 200 (異なる Pokemon)、HP は 10 から +100 で 110 へ。
  state = { ..state, my_active: 1, my_hps: [100, 10], my_wish_turns: 0 }
  let my_team = [mk_wish_combatant(max_hp=100), mk_wish_combatant(max_hp=200)]
  let opp_team = [mk_wish_combatant(), mk_wish_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  // active=1 の HP: 10 + 200/2 = 110、wish_turns は -1 に idle。
  @debug.assert_eq(new_state.my_hps[1], 110)
  @debug.assert_eq(new_state.my_wish_turns, -1)
  // 控え slot 0 は触られない (active でないため)。
  @debug.assert_eq(new_state.my_hps[0], 100)
}

///|
/// Case W-6 (HP=0 受け手 → 発動するが効果なし): active が HP=0 で wish_turns=0
/// のとき apply_eot を回すと wish は発動扱い (wish_turns → -1) だが HP は 0 の
/// まま不変 (蘇生しない、Wish も消費される、本家挙動)。
test "apply_eot: Wish on HP=0 active — Wish consumed, HP stays 0" {
  let mut state = mk_wish_state()
  state = { ..state, my_hps: [0, 100], my_wish_turns: 0 }
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let new_state = apply_eot(state, team, team)
  // HP=0 のまま (蘇生しない)。
  @debug.assert_eq(new_state.my_hps[0], 0)
  // wish_turns は -1 に idle 化 (Wish 自体は消費される、再発動しない)。
  @debug.assert_eq(new_state.my_wish_turns, -1)
}

///|
/// Case W-7 (Switch で wish_turns 保持 + 交代先が受け取る): ねがいごと使用 →
/// Switch で交代 → wish_turns は 2 のまま保持される (Switch では剥がれない、
/// これが LeechSeed との対比)。さらに 2 EOT 経過で wish_turns が 0 → 発動
/// する。Wish は **交代先の active Pokemon** に対して発動する (slot-bound
/// semantics、これが Wish の戦略的価値)。
test "transition_with_cache: Switch preserves wish_turns, replacement receives Wish" {
  let mut state = mk_wish_state()
  state = { ..state, my_wish_turns: 2 }
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let cache = new_damage_cache()
  // my[0] → my[1] へ Switch、opp は dummy Switch。Switch で wish は剥がれない。
  let outs = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::Switch(0),
    team,
    team,
    cache,
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, new_state) = outs[0]
  // wish_turns は 2 のまま保持 (= Switch で剥がれない、slot semantics)。
  @debug.assert_eq(new_state.my_wish_turns, 2)
  // my_active は 1 に切り替わる。
  @debug.assert_eq(new_state.my_active, 1)
}

///|
/// Case W-8 (二重掛けで後着 2 リセット): ねがいごと使用 → 1 EOT (wish=1) →
/// 再度 ねがいごと → wish_turns=2 にリセット (後着優先、Gen9 仕様)。
test "with_post_hit_effects: Wish overrides existing wish_turns (後着 reset)" {
  let mut state = mk_wish_state()
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let mv = mk_wish_move()
  // 1 回目: wish_turns = 2
  state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(state.my_wish_turns, 2)
  // 1 EOT で 2 → 1
  state = apply_eot(state, team, team)
  @debug.assert_eq(state.my_wish_turns, 1)
  // 2 回目: wish_turns = 2 にリセット (後着優先)
  state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(state.my_wish_turns, 2)
}

///|
/// Case W-9 (両側 wish 独立): my 側と opp 側の Wish counter は完全に独立。
/// my_wish_turns=2 / opp_wish_turns=0 で 1 EOT 実行すると:
///   - my: tick で 2 → 1、`==0` false なので発動しない (HP 不変)
///   - opp: tick skip (`>0` false)、`==0` true → 発動 → HP +max/2、-1
/// これで「サイド独立」を pin する。
test "apply_eot: Wish independent sides — opp fires, my ticks" {
  let mut state = mk_wish_state()
  state = {
    ..state,
    my_hps: [50, 100],
    opp_hps: [60, 100],
    my_wish_turns: 2,
    opp_wish_turns: 0,
    field: @model.Field::None,
    field_turns_left: 0,
  }
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let new_state = apply_eot(state, team, team)
  // my: wish_turns=2 → tick → 1, HP 不変
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.my_wish_turns, 1)
  // opp: wish_turns=0 → 発動 → HP +max/2 = +50 = 110... max=100 で cap → 100
  @debug.assert_eq(new_state.opp_hps[0], 100)
  @debug.assert_eq(new_state.opp_wish_turns, -1)
}

///|
/// Case W-10 (opp 側 — サイド対称性): opp が ねがいごと を撃った場合も
/// my 側と同様に opp_wish_turns = 2 がセットされる。
test "with_post_hit_effects: Wish by opp side — symmetric semantics" {
  let state = mk_wish_state()
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let mv = mk_wish_move()
  let new_state = with_post_hit_effects(state, false, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.opp_wish_turns, 2)
  @debug.assert_eq(new_state.my_wish_turns, -1)
}

///|
/// Case W-11 (両側 EOT 同時発動): my_wish_turns=0 / opp_wish_turns=0 で
/// apply_eot を回すと両 active が独立に回復する。両側同時 pending の
/// 場合の干渉なし。
test "apply_eot: Wish on both sides triggers independently" {
  let mut state = mk_wish_state()
  state = {
    ..state,
    my_hps: [50, 100],
    opp_hps: [30, 100],
    my_wish_turns: 0,
    opp_wish_turns: 0,
    field: @model.Field::None,
    field_turns_left: 0,
  }
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let new_state = apply_eot(state, team, team)
  // my active=0: 50 + 50 = 100
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.my_wish_turns, -1)
  // opp active=0: 30 + 50 = 80
  @debug.assert_eq(new_state.opp_hps[0], 80)
  @debug.assert_eq(new_state.opp_wish_turns, -1)
}

///|
/// Case W-12 (HP overflow → クランプ): wish 発動時の HP 加算が max を超える
/// 場合は `add_hp_capped` でクランプされる。HP=80 + max/2=50 = 130 → 100。
test "apply_eot: Wish heal caps at max_hp" {
  let mut state = mk_wish_state()
  state = { ..state, my_hps: [80, 100], my_wish_turns: 0 }
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let new_state = apply_eot(state, team, team)
  // 80 + 50 = 130 → cap 100
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.my_wish_turns, -1)
}

///|
/// Case W-13 (Plan H-D slot-bound regression test — the bug Issue #1 fixes):
/// my[0] が Wish を撃つ → Switch で my[1] にチェンジ → 2 EOT 経過 → Wish 発動
/// → 受け取るのは **交代先の my[1]** (slot-bound semantics)、Wish 使用者 my[0]
/// ではない。my[1] の max_hp=200、HP=50 → +100 → 150。
/// 旧実装 (Pokemon index keyed) では my[0] (max=100) が受け取り HP +50 になる
/// バグがあった。本テストでそれを Red 化する。
test "Wish slot-bound semantics: Switch swaps receiver to replacement" {
  let mut state = mk_wish_state()
  let my_team = [mk_wish_combatant(max_hp=100), mk_wish_combatant(max_hp=200)]
  let opp_team = [mk_wish_combatant(), mk_wish_combatant()]
  // my[0] が active で Wish 使用。HP は両者 50 から始めて遷移を観測しやすくする。
  state = { ..state, my_hps: [50, 50], opp_hps: [50, 50] }
  let mv = mk_wish_move()
  state = with_post_hit_effects(state, true, 0, 0, my_team, opp_team, mv, 0)
  @debug.assert_eq(state.my_wish_turns, 2)
  @debug.assert_eq(state.my_active, 0)
  // Switch で my[1] (max=200) へ交代。Wish counter は保持。
  let cache = new_damage_cache()
  let outs = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::Switch(0),
    my_team,
    opp_team,
    cache,
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, state2_post_switch) = outs[0]
  @debug.assert_eq(state2_post_switch.my_active, 1)
  @debug.assert_eq(state2_post_switch.my_wish_turns, 2)
  // transition_with_cache が apply_eot を 1 回挟んだので wish_turns は 1 に。
  // 直接 apply_eot を呼ぶ scenario の確認のため、ここではプログラム的に
  // 2 → 0 の遷移を確認するだけにする (transition の EOT 挟み込み挙動は
  // ScreenedSwitchingGame 側の責務)。
  // ここでは「もし wish_turns が 0 まで来たら、交代先 my[1] (max=200) が受け取る」
  // を直接 apply_eot で観察する。
  let state2 = { ..state2_post_switch, my_wish_turns: 0, my_hps: [50, 50] }
  let final_state = apply_eot(state2, my_team, opp_team)
  // 受け取りは my_active=1 / max=200 → HP=50 + 100 = 150。
  @debug.assert_eq(final_state.my_hps[1], 150)
  // 旧 (Pokemon-index keyed) なら my[0] が受け取り 50 + 50 = 100 になる。
  // 控え my[0] は不変。
  @debug.assert_eq(final_state.my_hps[0], 50)
  @debug.assert_eq(final_state.my_wish_turns, -1)
}

///|
/// Issue #5 regression — Turn advancement consistency.
/// `apply_eot` は state.turn を **そのまま保持** する (contract: bump は
/// transition / pass_turn_state / partial_act_outcomes 側で行う)。EOT 内で
/// turn を bump してしまうと、attack 経路と pass 経路で「カウンタの読み」
/// が 1 ターンずれる退化が起こる。本テストは apply_eot 単体で turn=42 を
/// 与えても turn=42 のまま帰ることを pin する。
test "apply_eot: preserves state.turn (Issue #5 contract)" {
  let mut state = mk_wish_state()
  state = { ..state, turn: 42 }
  let team = [mk_wish_combatant(), mk_wish_combatant()]
  let new_state = apply_eot(state, team, team)
  @debug.assert_eq(new_state.turn, 42)
}

///|
/// Issue #5 regression — Sand chip / Wish と turn の独立性。
/// EOT 内で Sand チップが発生し、Wish も発動するような state で apply_eot を
/// 呼んでも turn は不変。これは「EOT 内のサブイベントが turn を変えない」
/// 不変条件の最強テスト (= 各 step ごとに +1 してしまう退化を捕まえる)。
test "apply_eot: Sand+Wish leaves turn unchanged" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    weather: @model.Sand,
    weather_turns_left: 5,
    my_wish_turns: 0,
    turn: 7,
  }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, team, team)
  @debug.assert_eq(new_state.turn, 7)
  // 副次観測: weather counter は内部 state で tick (turn とは独立)
  @debug.assert_eq(new_state.weather_turns_left, 4)
  @debug.assert_eq(new_state.my_wish_turns, -1)
}

// =====================================================================
// Wish real-path regression: drive the full turn-resolution pipeline
// (`attempt_turn_with_cache` → `transition_with_cache` → `apply_eot`) end
// to end. Earlier W-* cases directly invoke `with_post_hit_effects` /
// `apply_eot` to isolate behaviour, but reviewers asked for a pinned
// turn-relative contract through the real entry point — used turn T → fires
// at EOT(T+1). Without these, the wish_turns docstring contract relies on
// implementation knowledge of how `apply_eot` is sequenced inside the per-
// turn driver.
// =====================================================================

///|
/// Combatant ヘルパー: 任意の moves と max_hp / spe を指定可能。real-path テスト
/// で「Wish 使う側 my[0]」「交代先 my[1]」「opp 側 idle」を作り分ける。
fn mk_wish_real_combatant(
  name? : String = "WishTest",
  moves? : Array[@model.Move] = [],
  max_hp? : Int = 100,
  spe? : Int = 100,
) -> Combatant {
  let p : @model.Pokemon = {
    global_no: "0001",
    name_ja: name,
    name_en: name,
    type1: "ノーマル",
    type2: "",
    hp: max_hp,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  {
    pokemon: p,
    moves,
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([max_hp, 100, 100, 100, 100, spe]),
    ivs: None,
  }
}

///|
/// Wish real-path regression — used turn T heals at EOT(T+1).
///
/// シナリオ:
///   Turn T (= state.turn 0): my[0] が ねがいごと を撃ち、opp は idle (no-op)。
///   `attempt_turn_with_cache` 呼び出し後、my_wish_turns は 2 でセットされた
///   直後に同 turn の EOT で 1 へ tick される (= 2→1)。HP は不変。
///   Turn T+1 (= state.turn 1): 両側 idle。EOT が 1→0 へ tick し、atomic に
///   発動して active (my[0]) を max/2 ぶん回復。my_wish_turns は -1 へ idle 化。
///
/// この観測は wish_turns docstring の "set on turn T → fires at EOT(T+1)"
/// 契約を turn 解決パイプライン全体で pin する。set=2 の tick-then-fire 設計
/// または tick / fire を分割する set=1 設計のどちらでも、外部観測上は等価で
/// なければならない。
test "attempt_turn_with_cache: Wish used on turn T heals at EOT(T+1)" {
  let wish_mv = mk_heal_move(
    "ねがいごと",
    "ノーマル",
    @model.Status,
    0,
    healing=Some(@model.Wish),
  )
  let idle_mv = mk_heal_move("まもる", "ノーマル", @model.Status, 0)
  // my[0] / my[1] とも Wish + idle を持つ (UseMove(0) / UseMove(1) で参照可能に)。
  let my0 = mk_wish_real_combatant(
    name="MyA",
    moves=[wish_mv, idle_mv],
    max_hp=100,
    spe=120,
  )
  let my1 = mk_wish_real_combatant(
    name="MyB",
    moves=[wish_mv, idle_mv],
    max_hp=200,
    spe=80,
  )
  let opp0 = mk_wish_real_combatant(
    name="OppA",
    moves=[idle_mv],
    max_hp=100,
    spe=60,
  )
  let my_team = [my0, my1]
  let opp_team = [opp0]
  let s0 : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [50, 50],
    opp_hps: [100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false],
    opp_protean_locked: [""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
  // Turn T: my[0] uses Wish, opp uses idle. EOT inside attempt_turn_with_cache
  // ticks the just-set wish_turns from 2 → 1; HP is unchanged this turn.
  let outs_t = attempt_turn_with_cache(
    s0,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs_t.length(), 1)
  let (_, s1) = outs_t[0]
  @debug.assert_eq(s1.my_wish_turns, 1)
  @debug.assert_eq(s1.my_hps[0], 50)
  @debug.assert_eq(s1.turn, 1)
  // Turn T+1: both sides idle. EOT ticks wish_turns 1 → 0 and atomically
  // fires the heal on the current active (my[0], max=100): 50 + 50 = 100.
  let outs_t1 = attempt_turn_with_cache(
    s1,
    UseMove(1),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs_t1.length(), 1)
  let (_, s2) = outs_t1[0]
  @debug.assert_eq(s2.my_hps[0], 100)
  @debug.assert_eq(s2.my_wish_turns, -1)
  @debug.assert_eq(s2.turn, 2)
}

///|
/// Wish real-path regression — Switch threads the heal to the replacement.
///
/// シナリオ:
///   Turn T: my[0] (max=100) が ねがいごと を撃つ。EOT で wish_turns 2→1。
///   Turn T+1: my[0]→my[1] (max=200) へ Switch。EOT で wish_turns 1→0 → 発動。
///   発動時の current active = my[1] (max=200) → heal +100。Wisher の my[0]
///   ではなく交代先 my[1] が受ける (mainline "the replacement receives the
///   Wish" 仕様)。
///
/// W-13 がこの slot-bound 受信を直接 apply_eot で観測するのに対し、本テスト
/// は real turn-resolution path 経由で同じ契約を観測する。
test "attempt_turn_with_cache: Switch threads Wish to replacement (real path)" {
  let wish_mv = mk_heal_move(
    "ねがいごと",
    "ノーマル",
    @model.Status,
    0,
    healing=Some(@model.Wish),
  )
  let idle_mv = mk_heal_move("まもる", "ノーマル", @model.Status, 0)
  let my0 = mk_wish_real_combatant(
    name="MyA",
    moves=[wish_mv, idle_mv],
    max_hp=100,
    spe=120,
  )
  let my1 = mk_wish_real_combatant(
    name="MyB",
    moves=[wish_mv, idle_mv],
    max_hp=200,
    spe=80,
  )
  let opp0 = mk_wish_real_combatant(
    name="OppA",
    moves=[idle_mv],
    max_hp=100,
    spe=60,
  )
  let my_team = [my0, my1]
  let opp_team = [opp0]
  let s0 : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps: [50, 50],
    opp_hps: [100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false],
    opp_protean_locked: [""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
  // Turn T: my[0] uses Wish, EOT ticks 2 → 1.
  let outs_t = attempt_turn_with_cache(
    s0,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs_t.length(), 1)
  let (_, s1) = outs_t[0]
  @debug.assert_eq(s1.my_wish_turns, 1)
  @debug.assert_eq(s1.my_active, 0)
  // Turn T+1: my[0] → my[1] Switch, EOT ticks 1 → 0 and fires.
  // Receiver is the current active (= my[1], max=200): 50 + 100 = 150.
  let outs_t1 = attempt_turn_with_cache(
    s1,
    Switch(1),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs_t1.length(), 1)
  let (_, s2) = outs_t1[0]
  @debug.assert_eq(s2.my_active, 1)
  @debug.assert_eq(s2.my_hps[1], 150)
  @debug.assert_eq(s2.my_hps[0], 50) // 控え (元 Wisher) は不変
  @debug.assert_eq(s2.my_wish_turns, -1)
}

// =====================================================================
// Stage 12 (EOT 順序整理): Gen9 公式順序の verification 群。
//
// Plan H-2 / 段階 12 申し送りの順序 (1.Sand chip → 2.leftovers → 3.leech →
// 4.status → 5.wish → 6.weather counter) を行ベースで観測する。
// 各テストは「順序を入れ替えると観測値が変わる組合せ」を狙って組み立てる。
// =====================================================================

///|
/// Sand チップ基本動作: weather=Sand、type=ノーマル、ability="" の active は
/// max/16 を失う。weather counter は 5→4 にデクリメント (この EOT 内では
/// まだ Sand 健在 → チップ発火)。
test "apply_eot: Sand chip deals max/16 to non-immune Normal-type" {
  let mut state = mk_seed_state()
  state = { ..state, weather: @model.Sand, weather_turns_left: 5 }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, team, team)
  // my[0]: 100 - 100/16 = 100 - 6 = 94
  @debug.assert_eq(new_state.my_hps[0], 94)
  @debug.assert_eq(new_state.opp_hps[0], 94)
  @debug.assert_eq(new_state.weather_turns_left, 4)
}

///|
/// Sand チップは はがね には入らない (type-based immunity)。
test "apply_eot: Sand chip skips はがね-type active" {
  let mut state = mk_seed_state()
  state = { ..state, weather: @model.Sand, weather_turns_left: 5 }
  let my_team = [mk_seed_combatant(type1="はがね"), mk_seed_combatant()]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[0], 94)
}

///|
/// Sand チップは いわ / じめん (type2 経由) でも skip。
test "apply_eot: Sand chip skips いわ secondary type" {
  let mut state = mk_seed_state()
  state = { ..state, weather: @model.Sand, weather_turns_left: 5 }
  let my_team = [
    mk_seed_combatant(type1="みず", type2="いわ"),
    mk_seed_combatant(),
  ]
  let opp_team = [mk_seed_combatant(type1="じめん"), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.my_hps[0], 100) // いわ で immunity
  @debug.assert_eq(new_state.opp_hps[0], 100) // じめん で immunity
}

///|
/// Sand チップは マジックガード で完全に skip (ability immunity)。
test "apply_eot: Sand chip skipped by マジックガード" {
  let mut state = mk_seed_state()
  state = { ..state, weather: @model.Sand, weather_turns_left: 5 }
  let my_team = [
    mk_seed_combatant(ability="マジックガード"),
    mk_seed_combatant(),
  ]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[0], 94)
}

///|
/// Sand チップは すなかき / すながくれ / すなのちから が block する。一方
/// すなおこし (Sand Stream) は砂を**呼ぶ**だけで chip 免疫を持たないため、
/// 非免疫タイプ (ここでは素ノーマル) の すなおこし 持ちは通常通り max/16 を
/// 失う。本家ユーザー (バンギラス等) はタイプ免疫で守られるが、それは call
/// site の type 判定であってこの ability では守られない。
test "apply_eot: Sand chip skipped by sand-related abilities (not すなおこし)" {
  let mut state = mk_seed_state()
  state = { ..state, weather: @model.Sand, weather_turns_left: 5 }
  let my_team = [mk_seed_combatant(ability="すなかき"), mk_seed_combatant()]
  let opp_team = [
    mk_seed_combatant(ability="すなおこし"),
    mk_seed_combatant(),
  ]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.my_hps[0], 100) // すなかき で免疫
  @debug.assert_eq(new_state.opp_hps[0], 94) // すなおこし は免疫なし → max/16 減
}

///|
/// ぼうじん (Overcoat) は Gen6 以降 砂嵐 / あられ などの天候チップを完全に
/// 無効化する。Sand 下で ぼうじん 持ち active が HP を失わないこと。
test "apply_eot: Sand chip skipped by ぼうじん (Overcoat)" {
  let mut state = mk_seed_state()
  state = { ..state, weather: @model.Sand, weather_turns_left: 5 }
  let my_team = [mk_seed_combatant(ability="ぼうじん"), mk_seed_combatant()]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[0], 94)
}

///|
/// Sand 以外 (Rain / Sun / Snow / None) はチップ damage を出さない。
test "apply_eot: non-Sand weather deals no chip damage" {
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  for wx in [@model.Rain, @model.Sun, @model.Snow, @model.Weather::None] {
    let state = { ..mk_seed_state(), weather: wx, weather_turns_left: 5 }
    let new_state = apply_eot(state, team, team)
    @debug.assert_eq(new_state.my_hps[0], 100)
    @debug.assert_eq(new_state.opp_hps[0], 100)
  }
}

///|
/// 順序入れ替え検証 (Sand → Leftovers): HP=4 の active が Sand 中で
/// たべのこし 持ち。新順序では Sand チップが先に走り max/16=6 のダメージで
/// HP=0 に落ち、たべのこし 回復は HP<=0 ガードで no-op (KO)。
/// 順序が逆 (Leftovers → Sand) だったら、Leftovers が HP=4 → 4+6=10 → Sand
/// チップ → 10-6=4 で生存していた。本 PR の順序が Sand → Leftovers である
/// ことを境界 HP で観測する。
test "apply_eot order: Sand chip precedes Leftovers (KO at HP=4)" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    weather: @model.Sand,
    weather_turns_left: 5,
    my_hps: [4, 100],
  }
  let my_team = [
    mk_seed_combatant_with_item("たべのこし"),
    mk_seed_combatant(),
  ]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  // Sand first (4-6 → floor0=0) → Leftovers gated by HP<=0 → 0 (KO)
  @debug.assert_eq(new_state.my_hps[0], 0)
}

///|
/// 順序入れ替え検証 (Sand → Leftovers, alive case): HP=50 の active が Sand
/// 中で たべのこし 持ち。新順序では Sand チップ -6 → 44、たべのこし +6 → 50。
/// 順序が逆だったら Leftovers +6 → 56 → Sand -6 → 50。最終 HP は同じ 50 だが、
/// 中間状態 (Sand チップで KO 寸前まで削れる) が観測される境界は HP=4 の
/// 上位ケースで担保する (上の test 参照)。本ケースは "alive-side 順序は
/// 観測値が同じになる" ことを確認する pin として残す。
test "apply_eot order: Sand+Leftovers net zero at survivable HP (HP=50)" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    weather: @model.Sand,
    weather_turns_left: 5,
    my_hps: [50, 100],
  }
  let my_team = [
    mk_seed_combatant_with_item("たべのこし"),
    mk_seed_combatant(),
  ]
  let opp_team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  // Sand -6 → 44 → Leftovers +6 → 50
  @debug.assert_eq(new_state.my_hps[0], 50)
}

///|
/// 順序入れ替え検証 (Leech → Status): seeded + BadPoison(3) で HP=12。
/// 新順序 (Leech 先 / Status 後):
///   Leech: -max/8 = -12 → HP=0
///   Status: HP<=0 ガード → BadPoison カウンタは 3 のまま不変
/// 順序が逆 (Status 先 / Leech 後) だったら:
///   Status (BadPoison 3→4): -max*4/16 = -25 → HP=floor0=0
///   Leech: HP<=0 ガード → skip
/// 中間値は違うが最終 HP は両方 0。観測値で順序を確定するため、BadPoison
/// counter (3 のまま不変か 4 に進むか) を assertion する。新順序では 3 のまま。
test "apply_eot order: Leech precedes Status (BadPoison counter frozen on faint)" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    my_hps: [12, 100],
    my_status: [@model.BadPoison(3), @model.None],
  }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, team, team)
  @debug.assert_eq(new_state.my_hps[0], 0)
  // Leech が先に発火して HP=0 → status slip は早期 return → BadPoison 不変
  // (= 新順序の signature)。
  match new_state.my_status[0] {
    @model.BadPoison(n) => @debug.assert_eq(n, 3)
    _ => @debug.assert_eq(true, false) // unexpected status shape
  }
  // opp は leech 吸収分 +12
  @debug.assert_eq(new_state.opp_hps[0], 100) // 既に max なので cap
}

///|
/// 順序入れ替え検証 (Leech → Status, observable opp gain): seeded + Burn で
/// HP=12、opp HP=50。新順序:
///   Leech: -12 → HP=0、opp += 12 → 62
///   Status (Burn): HP<=0 → skip
/// 旧順序だったら:
///   Status (Burn): -6 → HP=6
///   Leech: -12 → HP=0、opp += 12 → 62
/// opp の +12 は両順序で発生するが、`new_state.my_status[0]` (= Burn のまま)
/// と `my_hps[0]=0` の組合せは順序に依存しない。`opp_hps[0]=62` を pin する。
test "apply_eot order: Leech + Burn — opp gains max/8 regardless of fade" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    my_leech_seeded: [true, false],
    my_protean_locked: ["", ""],
    my_hps: [12, 100],
    opp_hps: [50, 100],
    my_status: [@model.Burn, @model.None],
  }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, team, team)
  @debug.assert_eq(new_state.my_hps[0], 0)
  @debug.assert_eq(new_state.opp_hps[0], 62)
}

///|
/// 順序入れ替え検証 (Wish 発動 → Weather counter): Sun 残 1 ターン + Wish
/// 即発動 slot。新順序 (Wish 発動 → weather counter tick):
///   Wish: my[0] += max/2 = +50 → HP=100 (start 50)
///   Weather counter: Sun が 1→0 で消える → next_weather=None
/// 観測すべきは「Wish 発動時点で state.weather はまだ Sun のままで参照される」
/// — Wish の回復量は天候依存ではないので Sun/None 区別なく max/2 で同じ。
/// 順序逆 (counter → Wish) でも heal 量は変わらない。本ケースは「Wish は
/// counter tick の前に発動する」signature を「次の EOT で天候が None に
/// 戻っている」ことから間接的に観測する。
test "apply_eot order: Wish fires before weather counter resets" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    weather: @model.Sun,
    weather_turns_left: 1,
    my_hps: [50, 100],
    my_wish_turns: 1,
  }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, team, team)
  // Wish: tick 1→0、HP += 50 → 100、wish_turns → -1
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.my_wish_turns, -1)
  // Weather counter: 1 → 0 → None
  match new_state.weather {
    @model.Weather::None => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
  @debug.assert_eq(new_state.weather_turns_left, 0)
}

///|
/// 順序入れ替え検証 (Sand chip → Wish 発動): Sand 残 1 ターン + my[0] HP=4 +
/// 即発動 Wish slot。新順序:
///   1. Sand chip: -6 → floor0=0 → my[0] KO
///   5. Wish 発動: HP<=0 ガード → 蘇生しない (HP=0 のまま、wish_turns=-1 へ
///      consume だけする)
///   6. Weather counter: 1→0→None
/// 順序逆 (Wish 先 → Sand 後) だったら Wish: 4 + 50 = 54 → Sand -6 → 48 で
/// 生存していた。Wish の "ひんし は蘇生しない" 仕様と Sand の "step 1 で
/// 先に走る" 仕様の組合せで HP=0 KO が観測される。
test "apply_eot order: Sand KO precedes Wish (no revive)" {
  let mut state = mk_seed_state()
  state = {
    ..state,
    weather: @model.Sand,
    weather_turns_left: 1,
    my_hps: [4, 100],
    my_wish_turns: 1,
  }
  let team = [mk_seed_combatant(), mk_seed_combatant()]
  let new_state = apply_eot(state, team, team)
  // Sand チップで KO → Wish は蘇生しない
  @debug.assert_eq(new_state.my_hps[0], 0)
  // Wish 自体は consume される
  @debug.assert_eq(new_state.my_wish_turns, -1)
  // Weather counter は 1 → 0 → None
  @debug.assert_eq(new_state.weather_turns_left, 0)
}

///|
/// Sand チップ helper — mk_seed_combatant に item セット。
/// 既存 mk_seed_combatant は ability / type のみパラメタ化していたので、
/// item を取れる薄い wrapper を追加する。stage 12 EOT 順序検証で
/// 「Sand 中の たべのこし」を組むためだけに使う。
fn mk_seed_combatant_with_item(item : String) -> Combatant {
  let base = mk_seed_combatant()
  {
    pokemon: base.pokemon,
    moves: base.moves,
    ability: base.ability,
    item,
    tera_type: base.tera_type,
    stat_system: base.stat_system,
    mega_form: base.mega_form,
    nature: base.nature,
    stat_points: base.stat_points,
    actual_stats: base.actual_stats,
    ivs: base.ivs,
  }
}
