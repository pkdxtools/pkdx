///|
fn strategies_close(
  s1 : MixedStrategy,
  s2 : MixedStrategy,
  tol : Double,
) -> Bool {
  if s1.len() != s2.len() {
    return false
  }
  for i in 0..<s1.len() {
    if (s1.at(i) - s2.at(i)).abs() > tol {
      return false
    }
  }
  true
}

///|
fn matrix(data : Array[Array[Double]]) -> FiniteMatrix {
  FiniteMatrix::new(data).unwrap()
}

///|
test "rps_equilibrium_uniform" {
  let a = matrix([[0.0, -1.0, 1.0], [1.0, 0.0, -1.0], [-1.0, 1.0, 0.0]])
  let uniform = MixedStrategy::uniform(3)
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true(value.abs() < 1.0e-7)
      assert_true(strategies_close(row_strategy, uniform, 1.0e-7))
      assert_true(strategies_close(col_strategy, uniform, 1.0e-7))
    }
    _ => assert_true(false)
  }
}

///|
test "matching_pennies_mixed" {
  let a = matrix([[1.0, -1.0], [-1.0, 1.0]])
  let uniform = MixedStrategy::uniform(2)
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true(value.abs() < 1.0e-7)
      assert_true(strategies_close(row_strategy, uniform, 1.0e-7))
      assert_true(strategies_close(col_strategy, uniform, 1.0e-7))
    }
    _ => assert_true(false)
  }
}

///|
test "saddle_point_pure_equilibrium" {
  // Row 0 has row-min = 2 at col 0. Col 0 has col-max = 2 at row 0. Saddle at (0,0).
  let a = matrix([[2.0, 3.0, 5.0], [1.0, 2.0, 4.0], [0.0, 1.0, 3.0]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true((value - 2.0).abs() < 1.0e-7)
      assert_true((row_strategy.at(0) - 1.0).abs() < 1.0e-7)
      assert_true((col_strategy.at(0) - 1.0).abs() < 1.0e-7)
    }
    _ => assert_true(false)
  }
}

///|
test "2x2_mixed_closed_form" {
  // A = [[a,b],[c,d]] mixed equilibrium:
  //   p* = (d - c) / (a - b - c + d), q* = (d - b) / (a - b - c + d)
  //   v = (a d - b c) / (a - b - c + d)
  let a_val = 3.0
  let b_val = 1.0
  let c_val = 2.0
  let d_val = 4.0
  let denom = a_val - b_val - c_val + d_val // 4.0
  let expected_p0 = (d_val - c_val) / denom // 0.5
  let expected_q0 = (d_val - b_val) / denom // 0.75
  let expected_v = (a_val * d_val - b_val * c_val) / denom // 2.5
  let a = matrix([[a_val, b_val], [c_val, d_val]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true((value - expected_v).abs() < 1.0e-7)
      assert_true((row_strategy.at(0) - expected_p0).abs() < 1.0e-7)
      assert_true((col_strategy.at(0) - expected_q0).abs() < 1.0e-7)
    }
    _ => assert_true(false)
  }
}

///|
test "minimax_equals_maximin" {
  // For any zero-sum game, v(A) = -v(-Aᵀ). Verify by swapping row/col roles.
  let a = matrix([[3.0, 1.0, 4.0], [1.0, 5.0, 9.0], [2.0, 6.0, 5.0]])
  // Opponent game: -Aᵀ as row-player matrix for the column player.
  let neg_at = Array::make(3, ([] : Array[Double]))
  for j in 0..<3 {
    let row = Array::make(3, 0.0)
    for i in 0..<3 {
      row[i] = -a.at(i, j)
    }
    neg_at[j] = row
  }
  let a_opp = matrix(neg_at)
  match (solve_zero_sum(a), solve_zero_sum(a_opp)) {
    (Optimal(value=v1, ..), Optimal(value=v2, ..)) =>
      assert_true((v1 + v2).abs() < 1.0e-7)
    _ => assert_true(false)
  }
}

///|
test "value_invariant_under_constant_shift" {
  let a = matrix([[2.0, -1.0, 3.0], [0.0, 4.0, -2.0], [1.0, 2.0, 0.0]])
  let shift = 7.5
  let a_shifted_data = Array::make(3, ([] : Array[Double]))
  for r in 0..<3 {
    let row = Array::make(3, 0.0)
    for c in 0..<3 {
      row[c] = a.at(r, c) + shift
    }
    a_shifted_data[r] = row
  }
  let a_shifted = matrix(a_shifted_data)
  match (solve_zero_sum(a), solve_zero_sum(a_shifted)) {
    (
      Optimal(value=v1, row_strategy=p1, col_strategy=q1),
      Optimal(value=v2, row_strategy=p2, col_strategy=q2),
    ) => {
      assert_true((v2 - v1 - shift).abs() < 1.0e-7)
      assert_true(strategies_close(p1, p2, 1.0e-7))
      assert_true(strategies_close(q1, q2, 1.0e-7))
    }
    _ => assert_true(false)
  }
}

///|
test "value_scales_linearly_in_payoff" {
  let a = matrix([[1.0, -1.0], [-1.0, 1.0]])
  let k = 5.0
  let ak_data = Array::make(2, ([] : Array[Double]))
  for r in 0..<2 {
    let row = Array::make(2, 0.0)
    for c in 0..<2 {
      row[c] = a.at(r, c) * k
    }
    ak_data[r] = row
  }
  let ak = matrix(ak_data)
  match (solve_zero_sum(a), solve_zero_sum(ak)) {
    (Optimal(value=v1, ..), Optimal(value=v2, ..)) =>
      assert_true((v2 - v1 * k).abs() < 1.0e-7)
    _ => assert_true(false)
  }
}

///|
test "dominated_row_has_zero_probability" {
  // Row 2 is strictly dominated by row 0: 0 ≤ 2, 0 ≤ 3.
  let a = matrix([[2.0, 3.0], [1.0, 4.0], [0.0, 0.0]])
  match solve_zero_sum(a) {
    Optimal(row_strategy~, ..) => assert_true(row_strategy.at(2) < 1.0e-7)
    _ => assert_true(false)
  }
}

///|
test "negative_entries_handled_without_big_m" {
  // All-negative matrix. The shift-and-normalize technique must handle it.
  let a = matrix([[-1.0, -2.0], [-3.0, -1.0]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      // Sanity: value should be in the convex hull of A entries, i.e. [-3, -1]
      assert_true(value >= -3.0 - 1.0e-7 && value <= -1.0 + 1.0e-7)
      // Strategies are valid distributions
      let sp = row_strategy.at(0) + row_strategy.at(1)
      let sq = col_strategy.at(0) + col_strategy.at(1)
      assert_true((sp - 1.0).abs() < 1.0e-7)
      assert_true((sq - 1.0).abs() < 1.0e-7)
    }
    _ => assert_true(false)
  }
}

///|
test "shapley_3x3_degenerate_game" {
  // Degenerate 3×3 with row-0 and row-1 identical in two columns — Lemke–Howson
  // explores multiple edges. Bland-based simplex must still terminate and
  // return some valid equilibrium (not necessarily unique).
  let a = matrix([[0.0, 0.0, 1.0], [0.0, 0.0, -1.0], [-1.0, 1.0, 0.0]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      // Exploitability ≤ 1e-6 certifies equilibrium without pinning the vector.
      let expl = exploitability(a, row_strategy, col_strategy)
      assert_true(expl.abs() < 1.0e-6)
      // Value is the Nash value regardless of which equilibrium is selected.
      ignore_value(value)
    }
    _ => assert_true(false)
  }
}

///|
fn ignore_value(_v : Double) -> Unit {
  ()
}

///|
test "janken_reproduces_monocycle_nash_baseline" {
  // Reference: monocycle_nash baseline/janken_solve — the janken (RPS) matrix
  // from the characters form with v vectors forming an equilateral triangle.
  // Value 0, uniform strategies, exploitability 0.
  let a = matrix([[0.0, -1.0, 1.0], [1.0, 0.0, -1.0], [-1.0, 1.0, 0.0]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true(value.abs() < 1.0e-7)
      let expl = exploitability(a, row_strategy, col_strategy)
      assert_true(expl.abs() < 1.0e-6)
      // Support uniformity
      for i in 0..<3 {
        assert_true((row_strategy.at(i) - 1.0 / 3.0).abs() < 1.0e-6)
        assert_true((col_strategy.at(i) - 1.0 / 3.0).abs() < 1.0e-6)
      }
    }
    _ => assert_true(false)
  }
}
///|
test "solve_zero_sum_pure_saddle_skips_lp" {
  // A 3x3 matrix whose maxmin = minmax at (row 1, col 1) with value -2.
  // row_mins: row 0 = -1, row 1 = -2 (max), row 2 = -3. maxmin = -2 at row 1? NO
  // Let's pick: want a real saddle. Use:
  //   [[ 1,  2,  3],   row 0 min = 1
  //    [ 0, -2,  4],   row 1 min = -2
  //    [-1,  5, -3]]   row 2 min = -3
  // col 0 max = 1, col 1 max = 5, col 2 max = 4. minmax = col 0 max = 1. maxmin = row 0 = 1.
  // Saddle at (0, 0) with value 1.
  let a = matrix([[1.0, 2.0, 3.0], [0.0, -2.0, 4.0], [-1.0, 5.0, -3.0]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true((value - 1.0).abs() < 1.0e-9)
      assert_true((row_strategy.at(0) - 1.0).abs() < 1.0e-9)
      assert_true((col_strategy.at(0) - 1.0).abs() < 1.0e-9)
    }
    _ => assert_true(false)
  }
}

///|
test "solve_zero_sum_switching_game_tl3_regression" {
  // Captured 20x20 outer Nash matrix from the Nosada vs カマカマキリ repro at
  // turn_limit=3 (bit issue #38912f7b Task C). Before the saddle fast-path fix,
  // this matrix triggers `InconsistentGame("col strategy has negative component
  // ...")` after ~70s of simplex pivots through near-degenerate entries.
  //
  // Ground truth (via scipy.optimize.linprog highs): value = -0.057961 with a
  // pure saddle at row 14/15 vs col 19 (maxmin == minmax).
  let a = matrix([
    [0.05436720142602347, 0.0468378573782422, 0.054367201426026135, 0.041584837051237056, 0.04683785737824375, 0.05822090714319228, 0.04329622094938279, 0.046837857378242864, 0.035773173152049864, 0.0432962209493819, -0.06497175141242795, -0.06497175141243394, -0.06497175141242906, -0.06497175141242617, -0.06497175141248634, -0.0649717514124255, 0.12938799762329212, 0.061404622855513624, 0.06149639353551972, -0.17878787878788005],
    [0.0543672014260248, 0.046837857378241754, 0.05436720142602436, 0.04152128576127723, 0.046837857378242864, 0.05822090714319139, 0.06384622800799988, 0.04683785737824264, 0.036076432398664204, 0.04329622094938257, -0.0649717514124295, -0.06497175141242972, -0.06497175141242906, -0.06497175141242972, -0.06497175141242861, -0.06497175141243039, 0.12938799762329212, 0.06140462285551229, 0.061496393535518834, -0.17878787878788094],
    [0.06530753789894628, 0.04683785737824375, 0.056676278379766964, 0.04241897671969319, 0.04683785737824331, 0.05822090714319472, 0.04429742659672797, 0.04683785737824264, 0.03610775621454909, 0.04429742659672775, -0.02174794731812235, -0.00721441891449115, -0.0118552612291134, -0.021747947318121685, -0.02988894483274329, -0.01185526122911229, 0.1293879976232919, 0.06172255887060496, 0.06183508346371025, -0.17817827643756035],
    [0.054367201426028355, 0.046837857378242864, 0.0543672014260308, 0.04155024544480601, 0.04683785737824264, 0.05864939360361365, 0.043296220949383235, 0.046837857378243086, 0.035960829953152196, 0.04329622094938257, -0.06236243477872283, -0.06236243477872416, -0.06236243477872261, -0.0623624347787235, -0.06236243477872283, -0.062362434778722386, 0.12938799762329123, 0.061404622855526725, 0.06149639353552172, -0.0731092282467547],
    [0.018384241215746888, 0.018384241215748442, 0.018384241215746, 0.014050115398990703, 0.03654188948306647, 0.036541889483065804, 0.06405520178993784, 0.036541889483066026, 0.031204854876966115, 0.03050032741068498, -0.09873169624479239, -0.09873169624479283, -0.09873169624479439, -0.09873169624479461, -0.09873169624479461, -0.09873169624479261, 0.12938799762329145, 0.061404622855513846, 0.061496393535518834, -0.18989898989899023],
    [0.06229248861834136, 0.0374677043490097, 0.04302801621955954, 0.02426530420315398, 0.03746770434901059, 0.0434067672051901, 0.030569810176256818, 0.03654188948306536, 0.03056981017626037, 0.030569810176256818, -0.02498495688893443, -0.007214260446253951, -0.01479732694026592, -0.02513630044145354, -0.04038943769943404, -0.014797326940245714, 0.1293879976232919, 0.06172255887060607, 0.06183508346371114, -0.16674718747280526],
    [-0.011082491064010602, -0.011082491064012157, -0.011082491064014155, -0.011082491064012823, -0.011082491064013267, -0.011082491064012379, -0.011082491064015487, -0.011082491064011935, -0.011082491064016153, -0.011082491064011268, -0.09208854402747302, -0.09208854402747346, -0.09208854402747146, -0.09208854402747302, -0.09208854402747368, -0.09208854402747213, 0.12938799762329256, 0.06140462285552073, 0.06149639353552061, -0.09820399247453349],
    [0.062292488618341135, 0.03746770434901103, 0.04302752040120028, 0.024856725902376198, 0.037467704349009034, 0.04340676720519032, 0.07297004116634498, 0.03654188948306669, 0.031362710298775465, 0.03056981017625815, -0.032654699942467946, -0.0072144189144904836, -0.011563610818077219, -0.032654699942468834, -0.04384778376573806, -0.011795602608167366, 0.12938799762329234, 0.061722558870602295, 0.061835083463709806, -0.39009766331409534],
    [-0.009611510215680186, -0.009611510215676855, -0.009611510215677965, -0.009611510215680852, 0.03654188948306536, 0.036541889483065804, 0.06384622800800122, 0.03654188948306403, 0.03131951922916221, 0.030500327410683647, -0.20197377951615203, -0.20197377951615292, -0.20197377951615159, -0.20197377951615247, -0.20197377951615092, -0.20197377951615358, 0.129387997623293, 0.06140462285551718, 0.061496393535519056, -0.09857246444377843],
    [0.06229248861834158, 0.03749034369055959, 0.04302752040120317, 0.0242587123597533, 0.03749034369056026, 0.043406767205190544, 0.03056981017625615, 0.03654188948306558, 0.030569810176261925, 0.030569810176258816, -0.012403070557482243, -0.007214418914490928, -0.014797645129969395, -0.012708273114196311, -0.03557726370093528, -0.014797645129944303, 0.12938799762329234, 0.06172255887060807, 0.061835083463709806, -0.09494949494949734],
    [0.2166681772863226, 0.1145534435278075, 0.16217415323954087, 0.05971479500891297, 0.1273663625931558, 0.18064059543871314, 0.05971479500891452, 0.12292687454122597, 0.05971479500892429, 0.059714795008911636, 0.08629741036611249, 0.13028403771202712, 0.059714795008911414, 0.08386625030001804, 0.05971479500889787, 0.05971479500891275, 0.11529537974759396, 0.05971479500893673, 0.05971479500891341, -0.1600118835412927],
    [0.21666817728632304, 0.11622202363552625, 0.16243994328441147, 0.06957744041008485, 0.12736636259315537, 0.18061421229947427, 0.0704488068795408, 0.1229268745412262, 0.07044880687954058, 0.07044880687954169, 0.08858369038833613, 0.13021541436297168, 0.06402871799164678, 0.08608425556304633, 0.06402871799164567, 0.06402871799164589, 0.11529537974759196, 0.07044880687954214, 0.07044880687953992, -0.13883182390716908],
    [0.21666817728632304, 0.11611254459195641, 0.1624416897876384, 0.05971479500891319, 0.1273663625931556, 0.18068806439139373, 0.059714795008911414, 0.12292687454122575, 0.05971479500891941, 0.059714795008912525, 0.08783449612642169, 0.13042970532632503, 0.05971479500891208, 0.08535195235821602, 0.05971479500894272, 0.059714795008931176, 0.11529537974759019, 0.05971479500892185, 0.059714795008911636, -0.057960635402622085],
    [0.21666817728632348, 0.1162220236355267, 0.16250596949338902, 0.06957744041008374, 0.1273663625931558, 0.18064059543871447, 0.07044880687954125, 0.12292687454122575, 0.07044880687954014, 0.0704488068795408, 0.08858369038833636, 0.1302953472591688, 0.06402871799164656, 0.08608425556304611, 0.06402871799164989, 0.06402871799164678, 0.11529537974759418, 0.07044880687954036, 0.0704488068795408, -0.15876273373884797],
    [0.21666817728632348, 0.11611254459195686, 0.16244168978764018, 0.059714795008911414, 0.1273663625931556, 0.1806880643913944, 0.059714795008913635, 0.12292687454122597, 0.05971479500892474, 0.0597147950089123, 0.08783449612642191, 0.13042970532632459, 0.05971479500891275, 0.0853519523582158, 0.059714795008897203, 0.05971479500890009, 0.11529537974759041, 0.05971479500893895, 0.059714795008912525, -0.057960635402620975],
    [0.2166681772863226, 0.1162220236355258, 0.1625741434396517, 0.06957744041008418, 0.1273663625931556, 0.18068806439139484, 0.07044880687954169, 0.12292687454122597, 0.07044880687954014, 0.07044880687954014, 0.08858369038833591, 0.13044035740672943, 0.06402871799164589, 0.08608425556304589, 0.06402871799164433, 0.06402871799164855, 0.11529537974759263, 0.07044880687954036, 0.07044880687953947, -0.05796063540262253],
    [0.053482476661689704, -0.026965728623075558, 0.024367872072727392, 0.0018931546426699253, -0.02466796327349674, 0.02436787207272939, 0.05858513208621452, -0.028957679872835707, -0.03938968185754099, -0.002454674230955023, -0.02042304153193819, -0.011417753719643597, -0.011484240302093163, -0.02084505271100534, -0.022390761309889706, -0.011588934324428868, -0.00429218611472737, -0.0010870883829268152, 0.005295351904019974, -0.15017877525659395],
    [-0.030858406058937637, -0.03401992624224115, -0.06336770568856265, -0.030858406058937193, -0.019661442870386514, -0.06336770568856243, 0.05217049323629852, -0.06374586423086637, -0.020958490587272838, -0.06340601149654712, -0.0628606971885528, -0.06286069718856169, -0.06286069718856258, -0.0628606971885659, -0.06286069718856191, -0.06286069718856258, -0.033483262564284244, -0.0013257336849021861, -0.03330195273660452, -0.09892124957538839],
    [0.05350042875720451, -0.014434923716224457, 0.02436787207273272, -0.0054037370413746455, -0.01210120301369444, 0.024367872072730057, -0.005277033525937558, -0.016319593093110596, -0.032293475599726174, -0.005281096491797532, -0.017842613863194634, -0.011417753719643597, -0.013810588606729013, -0.018275957578961055, -0.018809524310192227, -0.01381058860673079, -0.0017864859912590791, -0.0007543144478228125, 0.005235720504756403, -0.09494949494949334],
    [0.05787749665999464, 0.016036016924580343, 0.024367872072727836, 0.05253884597890668, 0.029036407044351842, 0.024367872072730945, 0.30588681849551436, 0.017554462847092278, 0.01044806804378462, 0.020259043659857534, -0.04334198631234565, -0.011417753719643375, -0.011563610818076553, -0.0443249023264094, -0.05707424279604445, -0.011795602608167588, -0.005645834832580077, -0.003205198465134007, 0.010417912237667082, -0.09494949494949001],
  ])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true((value - -0.057960635402622).abs() < 1.0e-6)
      // All strategy components non-negative after sanitize
      for i in 0..<row_strategy.len() {
        assert_true(row_strategy.at(i) >= 0.0)
      }
      for j in 0..<col_strategy.len() {
        assert_true(col_strategy.at(j) >= 0.0)
      }
      // Exploitability near zero
      let expl = exploitability(a, row_strategy, col_strategy)
      assert_true(expl.abs() < 1.0e-6)
    }
    _ => assert_true(false)
  }
}
