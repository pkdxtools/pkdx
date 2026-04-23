///|
/// Shared damage-calculation helpers used by the payoff layer
/// (`switching_game`, `team_monte_carlo`, `monte_carlo`). Hosts the 16-roll
/// mean-damage reduction and the canonical `DamageCalcInput` builder.

///|
/// Mean damage over the 16-roll table. Zero for immune matchups.
///
/// ばけのかわが剥がれる初撃は engine が `damages=0` + `disguise_blocked=true`
/// を返す。このターン攻撃側は実ダメを 0 しか稼げないが、防御側は 1/8 の
/// chip ダメージを払う (Gen7 以降仕様) ので、payoff 層で「このターンの相手
/// への与ダメ期待値」を評価する上では 0 ではなく `max_hp / 8` 固定を加算
/// する方が現実に近い。本関数ではこれを固定加算として織り込む。
fn avg_damage(r : @model.DamageCalcResult) -> Double {
  if r.is_immune {
    return 0.0
  }
  let mut s = 0
  for i in 0..<16 {
    s += r.damages[i]
  }
  let base = s.to_double() / 16.0
  if r.disguise_blocked {
    base + r.defender_hp.to_double() / 8.0
  } else {
    base
  }
}

///|
/// Effective Lv50 max-HP realized from a combatant's base HP plus its
/// `stat_system`. Payoff helpers that need a denominator for damage ratios
/// (e.g. `pkdx nash graph` team-form fast path) go through here instead of
/// reading `c.pokemon.hp` directly, which carries the base stat.
///
/// `actual_stats` が与えられていればユーザ指定の HP 実数値を優先する。
/// そうでなければ stat_system のデフォルト (Champions: SP=32, Standard:
/// EV252/IV31) で算出する。damage engine の def_hp_override と整合するため、
/// ratio 計算で使う分母をここで揃えておく。
fn effective_hp(c : Combatant) -> Int {
  match c.actual_stats {
    Some(arr) => arr[0]
    None =>
      match c.stat_system {
        @model.Champions => @damage.calc_stat_champions(c.pokemon.hp, is_hp=true)
        @model.Standard => @damage.calc_stat(c.pokemon.hp, is_hp=true)
      }
  }
}

///|
/// `actual_stats` は `[H, A, B, C, D, Spe]` 順の HABCDS 配列。engine.mbt の
/// `stat_resolution` と同じ分岐を payoff 層でも辿る:
///   - ボディプレス → 攻撃側 Def (index 2)
///   - Psyshock family (サイコショック / サイコブレイク / しんぴのつるぎ)
///       → 防御側 Def (2) を参照する特殊技
///   - 物理技   → 攻撃側 Atk (1)、防御側 Def (2)
///   - 特殊技   → 攻撃側 SpA (3)、防御側 SpD (4)
///
/// シェルアームズは payoff 層では補正済み stat を持たない段階で判定できない
/// ので、現状 Move.category (Special) のまま扱う。将来の PR で actual_stats
/// から動的選択する場合は `payoff/team_monte_carlo` 側で早期判定する。
fn attack_defense_stat_indices(mv : @model.Move) -> (Int, Int) {
  let is_physical = mv.category == @model.Physical
  let name = mv.name
  let is_body_press = name == "ボディプレス"
  let is_psyshock_family = name == "サイコショック" ||
    name == "サイコブレイク" ||
    name == "しんぴのつるぎ"
  let atk_idx = if is_body_press {
    2
  } else if is_physical {
    1
  } else {
    3
  }
  let def_idx = if is_psyshock_family {
    2
  } else if is_physical {
    2
  } else {
    4
  }
  (atk_idx, def_idx)
}

///|
/// Build a `DamageCalcInput` with the combatants' abilities/items/tera, the
/// given attacker/defender ranks, and no weather/field. Used as the canonical
/// reference input for payoff computation.
///
/// Combatant が `nature` / `actual_stats` を保持しているとき、対応する
/// engine フィールドへ流し込む。欠損時は engine の legacy default
/// (攻撃側 max SP+性格 / 防御側 無投資) にフォールバックする。
fn build_input_with_ranks(
  atk : Combatant,
  dfn : Combatant,
  mv : @model.Move,
  atk_rank : Int,
  def_rank : Int,
) -> @model.DamageCalcInput {
  let (atk_idx, def_idx) = attack_defense_stat_indices(mv)
  let atk_stat_override = match atk.actual_stats {
    Some(arr) => arr[atk_idx]
    None => 0
  }
  let def_stat_override = match dfn.actual_stats {
    Some(arr) => arr[def_idx]
    None => 0
  }
  let def_hp_override = match dfn.actual_stats {
    Some(arr) => arr[0]
    None => 0
  }
  {
    attacker: atk.pokemon,
    defender: dfn.pokemon,
    move_: mv,
    atk_ability: atk.ability,
    def_ability: dfn.ability,
    atk_item: atk.item,
    def_item: dfn.item,
    weather: @model.Weather::None,
    field: @model.Field::None,
    tera_type: atk.tera_type,
    critical: false,
    atk_nature: atk.nature,
    def_nature: dfn.nature,
    atk_stat_override,
    def_stat_override,
    def_hp_override,
    atk_rank,
    def_rank,
    fainted_count: 0,
    is_double: false,
    stat_system: atk.stat_system,
    wall: @model.Wall::NoWall,
    screen_pierce: false,
    atk_status_condition: @model.StatusCondition::None,
    def_status_condition: @model.StatusCondition::None,
    atk_rank_up_count: 0,
    def_rank_up_count: 0,
    atk_hp_num: 2,
    atk_hp_den: 2,
    def_item_removable: false,
    multi_hit_mode: @model.MultiHit::Auto,
    disguise_active: false,
  }
}
