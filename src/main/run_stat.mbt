fn resolve_nature(
  nature_name : String,
  nature_up : String,
  nature_down : String,
) -> @model.Nature {
  // Priority 1: Japanese nature name
  if nature_name.length() > 0 {
    match @model.nature_from_ja(nature_name) {
      Some(n) => return n
      None => {
        println("Warning: Unknown nature '" + nature_name + "', using neutral")
      }
    }
  }
  // Priority 2: up/down stat specification
  if nature_up.length() > 0 && nature_down.length() > 0 {
    let up = @model.stat_index_from_str(nature_up)
    let down = @model.stat_index_from_str(nature_down)
    match (up, down) {
      (Some(u), Some(d)) =>
        return {
          name_ja: nature_up + "↑" + nature_down + "↓",
          name_en: "Custom",
          up: Some(u),
          down: Some(d),
        }
      _ =>
        println(
          "Warning: Unknown stat '" +
          nature_up +
          "'/'" +
          nature_down +
          "', using neutral",
        )
    }
  }
  // Default: neutral (Hardy)
  { name_ja: "がんばりや", name_en: "Hardy", up: None, down: None }
}

///|
fn run_stat_calc(
  name : String,
  evs_str : String,
  ivs_str : String,
  nature_name : String,
  nature_up : String,
  nature_down : String,
  game : GameContext,
  format : @cli.OutputFormat,
) -> Unit {
  let nature = resolve_nature(nature_name, nature_up, nature_down)
  // ステータス計算式と入力パース (SP vs EV/IV) が完全に分かれるため、
  // 新 GameVersion variant 追加時に必ずどちらの経路を踏むか明示する。
  match game.version {
    @model.Champions => {
      let sps = @cli.parse_csv_ints(evs_str, 0, 6)
      // Validate SP constraints
      let mut total = 0
      for i = 0; i < 6; i = i + 1 {
        if sps[i] < 0 || sps[i] > 32 {
          println("Error: SP values must be 0-32, got " + sps[i].to_string())
          return
        }
        total = total + sps[i]
      }
      if total > 66 {
        println("Error: Total SP must be ≤ 66, got " + total.to_string())
        return
      }
      with_db(version=game.version, fn(db) {
        match @db.query_pokemon(db, name, game.version) {
          Ok(pokemon) => {
            let stats = @damage.calc_all_stats_champions(pokemon, sps, nature)
            println(
              @cli.format_stat_calc(
                pokemon, stats, nature, sps, sps, format, is_champions=true,
              ),
            )
          }
          Err(e) => println("Error: " + e)
        }
      })
    }
    @model.Other(_) => {
      let evs = @cli.parse_csv_ints(evs_str, 0, 6)
      let ivs = @cli.parse_csv_ints(ivs_str, 31, 6)
      with_db(version=game.version, fn(db) {
        match @db.query_pokemon(db, name, game.version) {
          Ok(pokemon) => {
            let stats = @damage.calc_all_stats(pokemon, ivs, evs, nature)
            println(
              @cli.format_stat_calc(pokemon, stats, nature, ivs, evs, format),
            )
          }
          Err(e) => println("Error: " + e)
        }
      })
    }
  }
}

///|
fn run_stat_reverse(
  target : String,
  stats_str : String,
  iv : Int,
  ev : Int,
  nature_mod : String,
  is_hp : Bool,
  game : GameContext,
  format : @cli.OutputFormat,
) -> Unit {
  if stats_str.length() > 0 {
    // Pokemon mode — 逆算アルゴリズムと validation が SP/EV で別実装。
    // 新 GameVersion variant が増えたら必ずここを再検討する。
    let actual_stats = @cli.parse_csv_ints(stats_str, 0, 6)
    with_db(version=game.version, fn(db) {
      match @db.query_pokemon(db, target, game.version) {
        Ok(pokemon) =>
          match game.version {
            @model.Champions => {
              let results = @damage.reverse_spread_champions(
                pokemon, actual_stats,
              )
              println(
                @cli.format_stat_reverse_pokemon(
                  pokemon, actual_stats, results, format, is_champions=true,
                ),
              )
            }
            @model.Other(_) => {
              let results = @damage.reverse_spread(pokemon, actual_stats, iv)
              println(
                @cli.format_stat_reverse_pokemon(
                  pokemon, actual_stats, results, format,
                ),
              )
            }
          }
        Err(e) => println("Error: " + e)
      }
    })
  } else {
    // Single stat mode
    let actual = @cli.parse_int(target, 0)
    if actual <= 0 {
      println("Error: Invalid stat value '" + target + "'")
      return
    }
    let (nature_num, nature_den) = match nature_mod {
      "up" => (11, 10)
      "down" => (9, 10)
      _ => (1, 1)
    }
    match game.version {
      @model.Champions => {
        if ev < 0 || ev > 32 {
          println("Error: SP values must be 0-32, got " + ev.to_string())
          return
        }
        let base = @damage.reverse_base_from_stat_champions(
          actual, ev, is_hp, nature_num, nature_den,
        )
        println(
          @cli.format_stat_reverse_single(
            actual, base, 0, ev, is_hp, nature_mod, format, is_champions=true,
          ),
        )
      }
      @model.Other(_) => {
        let base = @damage.reverse_base_from_stat(
          actual, iv, ev, is_hp, nature_num, nature_den,
        )
        println(
          @cli.format_stat_reverse_single(
            actual, base, iv, ev, is_hp, nature_mod, format,
          ),
        )
      }
    }
  }
}

///|
fn run_init_cache_team() -> Unit {
  println(@writer.generate_team_placeholder().stringify())
}

///|
fn run_init_cache_pokemon() -> Unit {
  println(@writer.generate_pokemon_placeholder().stringify())
}

///|
fn run_hbd(
  name : String,
  fixed_ev_str : String,
  ivs_str : String,
  nature_name : String,
  nature_up : String,
  nature_down : String,
  snap : @model.HpSnap,
  phys_weight : Int,
  spec_weight : Int,
  top : Int,
  game : GameContext,
  format : @cli.OutputFormat,
) -> Unit {
  // Default fixed_ev: optimize H/B/D, zero A/C/S.
  let fixed_ev = if fixed_ev_str.length() == 0 {
    let arr : FixedArray[Int] = FixedArray::make(6, 0)
    arr[0] = -1
    arr[2] = -1
    arr[4] = -1
    arr
  } else {
    match @cli.parse_fixed_ev(fixed_ev_str) {
      Ok(arr) => arr
      Err(e) => {
        println("Error: " + e)
        return
      }
    }
  }
  let nature = resolve_nature(nature_name, nature_up, nature_down)
  let weights : @damage.HbdWeights = { phys: phys_weight, spec: spec_weight }
  // HBD 最適化は SP (cap 32 / 合計 66) と EV (cap 252 / 合計 510) で
  // 探索空間も validate ルールも別。新 variant 追加時にどう扱うか必ず明示する。
  match game.version {
    @model.Champions => {
      // Champions: validate per-stat cap and total SP budget
      let mut fixed_total = 0
      for i = 0; i < 6; i = i + 1 {
        if fixed_ev[i] >= 0 {
          if fixed_ev[i] > 32 {
            println(
              "Error: SP values must be 0-32, got " + fixed_ev[i].to_string(),
            )
            return
          }
          fixed_total = fixed_total + fixed_ev[i]
        }
      }
      if fixed_total > 66 {
        println(
          "Error: total fixed SP (" +
          fixed_total.to_string() +
          ") exceeds Champions budget of 66",
        )
        return
      }
      with_db(version=game.version, fn(db) {
        match @db.query_pokemon(db, name, game.version) {
          Ok(pokemon) => {
            let result = if top <= 1 {
              @damage.optimize_hbd_champions(
                pokemon, fixed_ev, nature, snap, weights,
              )
            } else {
              @damage.optimize_hbd_topn_champions(
                pokemon, fixed_ev, nature, snap, weights, top,
              )
            }
            println(
              @cli.format_hbd(
                pokemon, nature, snap, weights, result, format, is_champions=true,
              ),
            )
          }
          Err(e) => println("Error: " + e)
        }
      })
    }
    @model.Other(_) => {
      let ivs = @cli.parse_csv_ints(ivs_str, 31, 6)
      with_db(version=game.version, fn(db) {
        match @db.query_pokemon(db, name, game.version) {
          Ok(pokemon) => {
            let result = if top <= 1 {
              @damage.optimize_hbd(
                pokemon, fixed_ev, ivs, nature, snap, weights,
              )
            } else {
              @damage.optimize_hbd_topn(
                pokemon, fixed_ev, ivs, nature, snap, weights, top,
              )
            }
            println(
              @cli.format_hbd(pokemon, nature, snap, weights, result, format),
            )
          }
          Err(e) => println("Error: " + e)
        }
      })
    }
  }
}
