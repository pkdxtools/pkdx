///|
/// Extract the `damages` array from a damage-result JSON (as produced by
/// `@cli.format_damage` with `Json` output). Returns `None` if the input
/// is not valid JSON, has no `damages` field, or the field is not a
/// numeric array — callers should treat that as a cache miss.
///
/// Used by the payoff layer when the SQLite-backed damage cache is wired
/// in as an L2 underneath the in-memory `@payoff.DamageCache`, so the
/// 16-roll table recovered from disk can feed the mean-damage reducer
/// without re-running `calc_damage`.
pub fn parse_damages_from_json(json_str : String) -> Array[Int]? {
  let parsed = try? @json.parse(json_str)
  match parsed {
    Err(_) => None
    Ok(j) =>
      match j {
        Object(obj) =>
          match obj.get("damages") {
            Some(Array(arr)) => {
              let out : Array[Int] = []
              for i = 0; i < arr.length(); i = i + 1 {
                match arr[i] {
                  Number(n, ..) => out.push(n.to_int())
                  _ => return None
                }
              }
              Some(out)
            }
            _ => None
          }
        _ => None
      }
  }
}

///|
/// Mean of a 16-roll damages array. Matches `@payoff.compute_mean_damage`'s
/// integer-division convention so L1/L2 agree on the reducer. Returns 0
/// for empty input (immune matchups stored as `[]`).
pub fn mean_of_damages(damages : Array[Int]) -> Int {
  let n = damages.length()
  if n == 0 {
    return 0
  }
  let mut s = 0
  for i = 0; i < n; i = i + 1 {
    s = s + damages[i]
  }
  s / n
}

///|
/// A single chance-node outcome decoded from a v2 cache entry. Mirrors
/// `@model.DamageVariant`'s public shape with the fields downstream callers
/// actually need (probability, hits count, total damages); per-hit
/// `damage_per_roll` is intentionally omitted to keep the L2 wire format
/// compact — call sites that need per-hit detail re-run `calc_damage`.
pub(all) struct ParsedVariant {
  probability : Double
  hits_count : Int
  total_damages : Array[Int]
}

///|
/// Extract the `variants[]` payload from a damage-result JSON (v2 format).
/// Returns `None` when the input is not valid JSON, has no `variants`
/// field (legacy v1 entry), or the field is malformed — callers treat
/// those as a cache miss and fall back to recomputing.
pub fn parse_variants_from_json(json_str : String) -> Array[ParsedVariant]? {
  let parsed = try? @json.parse(json_str)
  match parsed {
    Err(_) => None
    Ok(j) =>
      match j {
        Object(obj) =>
          match obj.get("variants") {
            Some(Array(arr)) => {
              let out : Array[ParsedVariant] = []
              for i = 0; i < arr.length(); i = i + 1 {
                match arr[i] {
                  Object(v_obj) => {
                    let prob = match v_obj.get("probability") {
                      Some(Number(n, ..)) => n
                      _ => return None
                    }
                    let hits_count = match v_obj.get("hits_count") {
                      Some(Number(n, ..)) => n.to_int()
                      _ => return None
                    }
                    let total = match v_obj.get("total_damages") {
                      Some(Array(td)) => {
                        let acc : Array[Int] = []
                        for j = 0; j < td.length(); j = j + 1 {
                          match td[j] {
                            Number(n, ..) => acc.push(n.to_int())
                            _ => return None
                          }
                        }
                        acc
                      }
                      _ => return None
                    }
                    out.push({ probability: prob, hits_count, total_damages: total })
                  }
                  _ => return None
                }
              }
              Some(out)
            }
            _ => None
          }
        _ => None
      }
  }
}
