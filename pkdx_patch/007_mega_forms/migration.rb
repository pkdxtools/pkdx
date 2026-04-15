# 007_mega_forms — pokedex.db 内のメガ進化データが SwitchingGame から
# 参照できる整合性を持っているか検証する。
#
# 経緯: Task B (roadmap Issue #38912f7b) で `ActionKind::Mega` を SwitchingGame
# に追加するにあたり、`pokedex.db` の `local_pokedex_status` / `_type` /
# `_ability` にメガ形態の行がバージョンごとに揃っている必要がある。
# 001_mega_legendsza / 002_champions_pokemon が既にデータを投入しているため、
# 007 はデータを上書きせず「件数が想定下限を満たしているか」だけ検証する。
# 将来 upstream pokedex が規格変更で mega 行を落とした際の early warning。
#
# apply.rb から eval される。db (SQLite3::Database) と patch_dir が利用可能。

expected = {
  # バージョン名 → legal mega 形態の最低件数（下限）。
  # 001/002 の実績値を下限として扱う。現行の DB ダンプ時点の値を直接書くと
  # upstream 側の軽微な揺れで false-negative になるので、"これ以上" という
  # 下限値で固定する。
  'legendsza'  => 60,
  'champions'  => 55,
}

missing = []
report = {}

expected.each do |version, min_count|
  rows_status = db.get_first_value(
    "SELECT COUNT(*) FROM local_pokedex_status WHERE version = ? AND mega_evolution IS NOT NULL AND mega_evolution != ''",
    [version]
  ).to_i
  rows_type = db.get_first_value(
    "SELECT COUNT(*) FROM local_pokedex_type WHERE version = ? AND mega_evolution IS NOT NULL AND mega_evolution != ''",
    [version]
  ).to_i
  rows_ability = db.get_first_value(
    "SELECT COUNT(*) FROM local_pokedex_ability WHERE version = ? AND mega_evolution IS NOT NULL AND mega_evolution != ''",
    [version]
  ).to_i

  report[version] = { status: rows_status, type: rows_type, ability: rows_ability }

  if [rows_status, rows_type, rows_ability].min < min_count
    missing << "#{version}: status=#{rows_status}, type=#{rows_type}, ability=#{rows_ability} (expected >= #{min_count})"
  end
end

# status / type / ability の各件数で同じ mega_evolution を参照できることを
# 念のため cross-check (SwitchingGame がメガ形態に切り替えた時に
# stat / type / ability を全部揃って引けなければならない)。
mismatches = []
expected.each_key do |version|
  orphans = db.execute(
    "SELECT DISTINCT s.mega_evolution
       FROM local_pokedex_status s
  LEFT JOIN local_pokedex_type t
         ON s.id = t.id
        AND s.version = t.version
        AND COALESCE(s.mega_evolution, '') = COALESCE(t.mega_evolution, '')
  LEFT JOIN local_pokedex_ability a
         ON s.id = a.id
        AND s.version = a.version
        AND COALESCE(s.mega_evolution, '') = COALESCE(a.mega_evolution, '')
      WHERE s.version = ?
        AND s.mega_evolution IS NOT NULL
        AND s.mega_evolution != ''
        AND (t.id IS NULL OR a.id IS NULL)",
    [version]
  )
  if orphans.any?
    mismatches << "#{version}: #{orphans.map(&:first).join(', ')}"
  end
end

if missing.any? || mismatches.any?
  msg = []
  msg << "Mega-form data integrity check FAILED." if missing.any? || mismatches.any?
  msg << "Below minimum count:" if missing.any?
  missing.each { |m| msg << "  #{m}" }
  if mismatches.any?
    msg << "Orphan mega rows (missing status/type/ability pair):"
    mismatches.each { |m| msg << "  #{m}" }
  end
  msg << "Run 001_mega_legendsza and/or 002_champions_pokemon before 007."
  abort msg.join("\n    ")
end

report.each do |v, counts|
  puts "    #{v}: #{counts[:status]} status / #{counts[:type]} type / #{counts[:ability]} ability mega rows"
end
puts "    Mega-form integrity: OK"
