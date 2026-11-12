///|
/// Format moves as JSON array. Includes `priority` and `stat_effects`
/// (payoff-layer metadata populated from `move_meta` via `query_moves`);
/// skills consuming this output can forward it to `pkdx select` without
/// a separate DB query.
///
/// 追加効果の `status_effect` (やけど / まひ / こおり 等) と `flinch_chance` (ひるみ率)
/// も同じ経路で載せる。既定値 (`None` / 0) のときはキーを省略する: `pkdx select` は
/// キー無しを None / 0 として読むので、効果の無い技の出力は従来とバイト単位で同じになる。
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
