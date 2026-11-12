///|
/// Format moves as JSON array. Includes `priority` and `stat_effects`
/// (payoff-layer metadata populated from `move_meta` via `query_moves`);
/// skills consuming this output can forward it to `pkdx select` without
/// a separate DB query.
///
/// 追加効果の `status_effect` (やけど / まひ / こおり 等) と `flinch_chance` (ひるみ率)
/// も同じ経路で載せる。既定値 (`None` / 0) のときはキーを省略する: `pkdx select` は
/// キー無しを None / 0 として読むので、効果の無い技の出力は従来とバイト単位で同じになる。
///
/// move_meta 由来の反動 (`recoil_num` / `recoil_den`)・自滅 (`self_ko`)・反動ターン
/// (`recharge`)・回復 (`heal_kind` とその数値)・天候設定 (`weather_set`)・フィールド設定
/// (`field_set`) も同じ規則で載せる。DB の値が真実で、select はこれらを JSON から読み、
/// DB を引かない。名前だけで決まるもの (崩れ技 / てっていこうせんの反動 / 技の分類) は
/// 名前リストで判定されるので、キーは出さない。
fn moves_to_json(moves : Array[@model.Move]) -> String {
  let mut s = "["
  for i = 0; i < moves.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    let m = moves[i]
    let cat_str = @model.category_to_jp(m.category)
    s = s +
      "{\"name\":\"" +
      m.name +
      "\",\"type\":\"" +
      m.type_ +
      "\",\"category\":\"" +
      cat_str +
      "\",\"power\":" +
      m.power.to_string() +
      ",\"accuracy\":" +
      m.accuracy.to_string() +
      ",\"pp\":" +
      m.pp.to_string() +
      ",\"learn_method\":\"" +
      m.learn_method +
      "\",\"priority\":" +
      m.priority.to_string() +
      ",\"stat_effects\":" +
      stat_effects_to_json(m.stat_effects) +
      status_effect_to_json(m.status_effect) +
      flinch_chance_to_json(m.flinch_chance) +
      recoil_to_json(m.recoil_num, m.recoil_den) +
      self_ko_to_json(m.self_ko) +
      recharge_to_json(m.recharge) +
      healing_to_json(m.healing) +
      weather_set_to_json(m.weather_set) +
      field_set_to_json(m.field_set) +
      "}"
  }
  s + "]"
}

///|
/// `status_effect` を `,"status_effect":{"kind":"やけど","chance":10}` の形で返す。
/// `None` は空文字 (キーを省略)。形は `pkdx select` の `parse_status_effect_object`
/// が読む入力契約そのもの (`kind` は和名、`chance` は命中後の確率)。
fn status_effect_to_json(se : (@model.StatusKind, Int)?) -> String {
  match se {
    Some((kind, chance)) =>
      ",\"status_effect\":{\"kind\":\"" +
      @model.status_kind_to_jp(kind) +
      "\",\"chance\":" +
      chance.to_string() +
      "}"
    None => ""
  }
}

///|
/// `flinch_chance` を `,"flinch_chance":30` の形で返す。0 以下は空文字 (キーを省略)。
fn flinch_chance_to_json(chance : Int) -> String {
  if chance > 0 {
    ",\"flinch_chance\":" + chance.to_string()
  } else {
    ""
  }
}

///|
/// 反動 (`recoil_num > 0` のときだけ) を `,"recoil_num":1,"recoil_den":3` の形で返す。
/// 既定 (0 / 1) は空文字。`pkdx select` の `parse_move_json` は `recoil_den <= 0` を 1 とみなす。
fn recoil_to_json(num : Int, den : Int) -> String {
  if num > 0 {
    ",\"recoil_num\":" + num.to_string() + ",\"recoil_den\":" + den.to_string()
  } else {
    ""
  }
}

///|
/// 自滅 (`self_ko`: じばく / だいばくはつ 等) を `,"self_ko":true` の形で返す。`false` は空文字。
fn self_ko_to_json(self_ko : Bool) -> String {
  if self_ko {
    ",\"self_ko\":true"
  } else {
    ""
  }
}

///|
/// 反動ターン (`recharge`: はかいこうせん 等) を `,"recharge":true` の形で返す。`false` は空文字。
fn recharge_to_json(recharge : Bool) -> String {
  if recharge {
    ",\"recharge\":true"
  } else {
    ""
  }
}

///|
/// `healing` を `pkdx select` の入力キー (`heal_kind` と kind ごとの数値) の形で返す。
/// `None` は空文字。数値は kind が参照するものだけを出す (`@db.parse_healing` と同じ解釈):
/// - fixed / drain: `heal_num` / `heal_den`
/// - weather: 既定の分数 (`heal_num` / `heal_den`) と晴れ / 雨・雪・砂の分数 (`heal_sunny_*` / `heal_harsh_*`)
/// - rest / leech_seed / pain_split / wish: `heal_kind` のみ
fn healing_to_json(h : @model.HealingEffect?) -> String {
  match h {
    Some(FixedFraction(n, d)) => heal_fraction_json("fixed", n, d)
    Some(Drain(n, d)) => heal_fraction_json("drain", n, d)
    Some(WeatherDependent(dn, dd, sn, sd, hn, hd)) =>
      heal_fraction_json("weather", dn, dd) +
      ",\"heal_sunny_num\":" +
      sn.to_string() +
      ",\"heal_sunny_den\":" +
      sd.to_string() +
      ",\"heal_harsh_num\":" +
      hn.to_string() +
      ",\"heal_harsh_den\":" +
      hd.to_string()
    Some(Rest) => ",\"heal_kind\":\"rest\""
    Some(LeechSeed) => ",\"heal_kind\":\"leech_seed\""
    Some(PainSplit) => ",\"heal_kind\":\"pain_split\""
    Some(Wish) => ",\"heal_kind\":\"wish\""
    None => ""
  }
}

///|
/// 分数型の回復 (fixed / drain / weather の既定分数) の `heal_kind` / `heal_num` / `heal_den`。
fn heal_fraction_json(kind : String, n : Int, d : Int) -> String {
  ",\"heal_kind\":\"" +
  kind +
  "\",\"heal_num\":" +
  n.to_string() +
  ",\"heal_den\":" +
  d.to_string()
}

///|
/// `weather_set` を `,"weather_set":"rain"` の形で返す。値は DB の canonical
/// (sun / rain / sand / snow) で、`@db.parse_weather_set` が受ける形と一致する。`None` は空文字。
fn weather_set_to_json(w : @model.Weather?) -> String {
  match w {
    Some(Sun) => ",\"weather_set\":\"sun\""
    Some(Rain) => ",\"weather_set\":\"rain\""
    Some(Sand) => ",\"weather_set\":\"sand\""
    Some(Snow) => ",\"weather_set\":\"snow\""
    _ => ""
  }
}

///|
/// `field_set` を `,"field_set":"electric"` の形で返す。値は DB の canonical
/// (electric / grassy / misty / psychic) で、`@db.parse_field_set` が受ける形と一致する。`None` は空文字。
fn field_set_to_json(f : @model.Field?) -> String {
  match f {
    Some(Electric) => ",\"field_set\":\"electric\""
    Some(Grassy) => ",\"field_set\":\"grassy\""
    Some(Misty) => ",\"field_set\":\"misty\""
    Some(Psychic) => ",\"field_set\":\"psychic\""
    _ => ""
  }
}

///|
/// Format `stat_effects` as a JSON array of 3-element tuples
/// `[[stat, delta, target], ...]`. `target` is `0` = self, `1` = opp.
/// Phase 3 contract used by `pkdx select` (which also accepts the legacy
/// 2-element form for tests / older pipelines).
fn stat_effects_to_json(effs : Array[@model.StatEffect]) -> String {
  let mut s = "["
  for i = 0; i < effs.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    let e = effs[i]
    s = s +
      "[" +
      e.stat.to_string() +
      "," +
      e.delta.to_string() +
      "," +
      e.target.to_string() +
      "]"
  }
  s + "]"
}

///|
/// Format moves as a table.
fn moves_to_table(moves : Array[@model.Move]) -> String {
  let mut s = pad_right("Move", 16) +
    pad_right("Type", 10) +
    pad_right("Cat", 6) +
    pad_right("Pow", 5) +
    pad_right("Acc", 5) +
    pad_right("PP", 4) +
    "Method\n"
  s = s + "─".to_string().repeat(60) + "\n"
  for i = 0; i < moves.length(); i = i + 1 {
    let m = moves[i]
    let cat_str = @model.category_to_jp(m.category)
    s = s +
      pad_right(m.name, 16) +
      pad_right(m.type_, 10) +
      pad_right(cat_str, 6) +
      pad_right(m.power.to_string(), 5) +
      pad_right(m.accuracy.to_string(), 5) +
      pad_right(m.pp.to_string(), 4) +
      m.learn_method +
      "\n"
  }
  s
}

///|
/// Output move list.
pub fn format_moves(moves : Array[@model.Move], fmt : OutputFormat) -> String {
  match fmt {
    Json => moves_to_json(moves)
    Table => moves_to_table(moves)
  }
}
