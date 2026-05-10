///|
/// Handler logic for `pkdx meta-divergence`.
///
/// Given an empirical meta (usage distribution `σ`) and a symmetric payoff
/// matrix `A`, report how far `σ` is from best-responding to itself:
///
/// - `expected_value = σᵀ A σ`
/// - `regret[i] = (A σ)_i − expected_value`   (positive → under-used)
/// - `exploitability = max_i regret[i]` (best deviation gain)
/// - `over_used[i]`: currently played with positive mass but regret < −ε
/// - `under_used[i]`: regret > +ε but currently played with near-zero mass
///
/// Input JSON:
/// ```
/// {
///   "usage":  [Double, ...],                 # sums to 1
///   "matrix": [[Double, ...], ...],          # n × n symmetric payoff
///   "labels": [String, ...]                  # optional
/// }
/// ```

///|
pub suberror MetaCliError {
  InvalidJsonMeta(String)
  MissingFieldMeta(String)
  UsageNotNormalised(Double)
  ShapeMismatch(Int, Int)
} derive(Show)

///|
fn json_number_meta(j : Json, ctx : String) -> Double raise MetaCliError {
  match j {
    Number(n, ..) => n
    _ => raise InvalidJsonMeta("expected number at " + ctx)
  }
}

///|
fn parse_usage(j : Json) -> Array[Double] raise MetaCliError {
  match j {
    Array(arr) => {
      let out = Array::make(arr.length(), 0.0)
      let mut total = 0.0
      for i in 0..<arr.length() {
        let v = json_number_meta(arr[i], "usage[" + i.to_string() + "]")
        if v < 0.0 {
          raise InvalidJsonMeta("usage[" + i.to_string() + "] must be non-negative")
        }
        out[i] = v
        total = total + v
      }
      if (total - 1.0).abs() > 1.0e-6 {
        raise UsageNotNormalised(total)
      }
      out
    }
    _ => raise InvalidJsonMeta("usage must be an array")
  }
}

///|
fn parse_meta_matrix(j : Json) -> Array[Array[Double]] raise MetaCliError {
  match j {
    Array(arr) => {
      let n = arr.length()
      if n == 0 {
        raise InvalidJsonMeta("matrix must be non-empty")
      }
      let data = Array::make(n, ([] : Array[Double]))
      for i in 0..<n {
        match arr[i] {
          Array(row_json) => {
            let row = Array::make(row_json.length(), 0.0)
            for j2 in 0..<row_json.length() {
              row[j2] = json_number_meta(
                row_json[j2],
                "matrix[" + i.to_string() + "][" + j2.to_string() + "]",
              )
            }
            data[i] = row
          }
          _ => raise InvalidJsonMeta("matrix[" + i.to_string() + "] must be an array")
        }
      }
      let cols = data[0].length()
      for i in 0..<n {
        if data[i].length() != cols {
          raise ShapeMismatch(n, cols)
        }
      }
      data
    }
    _ => raise InvalidJsonMeta("matrix must be an array")
  }
}

///|
/// Meta-divergence report.
pub(all) struct MetaReport {
  exploitability : Double
  expected_value : Double
  regrets : Array[Double]
  over_used : Array[Int]
  under_used : Array[Int]
  labels : Array[String]
}

///|
/// Compute the meta-divergence report directly from `usage` and `matrix`.
///
/// - `σᵀ A σ` expected value
/// - per-index regret = (A σ)_i − σᵀ A σ
/// - over-used / under-used thresholds at `1.0e-3` on regret and usage
pub fn compute_meta_divergence(
  usage : Array[Double],
  matrix : Array[Array[Double]],
  labels : Array[String],
) -> MetaReport {
  let n = usage.length()
  // A σ
  let aq = Array::make(n, 0.0)
  for i in 0..<n {
    let mut s = 0.0
    for j in 0..<n {
      s = s + matrix[i][j] * usage[j]
    }
    aq[i] = s
  }
  // σᵀ A σ
  let mut ev = 0.0
  for i in 0..<n {
    ev = ev + usage[i] * aq[i]
  }
  let regrets = Array::make(n, 0.0)
  for i in 0..<n {
    regrets[i] = aq[i] - ev
  }
  let mut expl = regrets[0]
  for i in 1..<n {
    if regrets[i] > expl {
      expl = regrets[i]
    }
  }
  if expl < 0.0 {
    expl = 0.0
  }
  let over : Array[Int] = []
  let under : Array[Int] = []
  let eps = 1.0e-3
  for i in 0..<n {
    if usage[i] > eps && regrets[i] < -eps {
      over.push(i)
    }
    if regrets[i] > eps && usage[i] < eps {
      under.push(i)
    }
  }
  {
    exploitability: expl,
    expected_value: ev,
    regrets,
    over_used: over,
    under_used: under,
    labels,
  }
}

///|
fn fmt_labels_meta(labels : Array[String], n : Int) -> Array[String] {
  if labels.length() >= n {
    labels
  } else {
    let out = Array::make(n, "")
    for i in 0..<n {
      out[i] = i.to_string()
    }
    out
  }
}

///|
/// Run `pkdx meta-divergence`. Accepts the input JSON and returns a JSON
/// string report.
pub fn run_meta_divergence(input_json : String) -> String raise MetaCliError {
  let root = try @json.parse(input_json) catch {
    err => raise InvalidJsonMeta(err.to_string())
  }
  let obj = match root {
    Object(m) => m
    _ => raise InvalidJsonMeta("top-level must be an object")
  }
  let usage = match obj.get("usage") {
    Some(j) => parse_usage(j)
    None => raise MissingFieldMeta("usage")
  }
  let matrix = match obj.get("matrix") {
    Some(j) => parse_meta_matrix(j)
    None => raise MissingFieldMeta("matrix")
  }
  if matrix.length() != usage.length() || matrix[0].length() != usage.length() {
    raise ShapeMismatch(matrix.length(), usage.length())
  }
  let labels_in = match obj.get("labels") {
    Some(Array(arr)) => {
      let out = Array::make(arr.length(), "")
      for i in 0..<arr.length() {
        out[i] = match arr[i] {
          String(s) => s
          _ => i.to_string()
        }
      }
      out
    }
    _ => []
  }
  let labels = fmt_labels_meta(labels_in, usage.length())
  let r = compute_meta_divergence(usage, matrix, labels)
  let mut out = "{"
  out = out + "\"exploitability\":" + r.exploitability.to_string()
  out = out + ",\"expected_value\":" + r.expected_value.to_string()
  out = out + ",\"regrets\":" + fmt_double_array(r.regrets)
  out = out + ",\"over_used\":" + fmt_int_array(r.over_used)
  out = out + ",\"under_used\":" + fmt_int_array(r.under_used)
  out = out + ",\"labels\":" + fmt_string_array(r.labels)
  out + "}"
}
