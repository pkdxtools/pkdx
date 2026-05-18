///|
/// Right-pad `s` with spaces up to `width` (or return unchanged if already
/// wider). Shared by every table formatter in this package.
fn pad_right(s : String, width : Int) -> String {
  let len = s.length()
  if len >= width {
    return s
  }
  let mut result = s
  for i = 0; i < width - len; i = i + 1 {
    result = result + " "
  }
  result
}

///|
/// Format a probability with up to 4 decimal digits, dropping trailing zeros
/// so 0.2 emits "0.2" (not "0.2000") and 0.375 stays "0.375".
fn format_probability(p : Double) -> String {
  let scaled = (p * 10000.0 + 0.5).to_int()
  if scaled == 10000 {
    return "1"
  }
  if scaled == 0 {
    return "0"
  }
  let mut digits = scaled.to_string()
  // Pad to 4 fractional digits ("75" → "0075", "375" → "0375").
  while digits.length() < 4 {
    digits = "0" + digits
  }
  // Strip trailing zeros but keep at least one digit after the decimal.
  let mut end = digits.length()
  while end > 1 && digits.unsafe_get(end - 1) == 0x30 {
    end = end - 1
  }
  "0." + digits[0:end].to_owned()
}

///|
/// Format a double with exactly one decimal digit (no %/unit suffix).
/// Used for damage percentages and HBD scores.
fn format_one_decimal(v : Double) -> String {
  let int_part = v.to_int()
  let frac = ((v - int_part.to_double()) * 10.0).to_int().abs()
  int_part.to_string() + "." + frac.to_string()
}

///|
/// `性格名 (Atk↑ Def↓)` like decoration. Used by both stat-calc / stat-reverse
/// pokemon-mode tables and HBD's nature header.
fn nature_label(nature : @model.Nature) -> String {
  match (nature.up, nature.down) {
    (Some(up), Some(down)) =>
      nature.name_ja +
      " (" +
      stat_index_label(up) +
      "↑ " +
      stat_index_label(down) +
      "↓)"
    _ => nature.name_ja
  }
}

///|
fn stat_index_label(s : @model.StatIndex) -> String {
  match s {
    HP => "HP"
    Atk => "Atk"
    Def => "Def"
    SpA => "SpA"
    SpD => "SpD"
    Spe => "Spe"
  }
}
