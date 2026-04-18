# 008_move_meta_ailment — payoff 層の状態異常サポートに必要な ailment 情報を
# move_meta に追加する。
#
# 追加カラム:
#   ailment_ja       — 付与する状態異常の日本語名。空文字は「状態異常付与なし」。
#                      "まひ" / "やけど" / "どく" / "もうどく" / "ねむり"
#   ailment_chance   — 付与確率 (0-100)。省略時 100。
#
# MVP スコープ: 命中率 100 でない専用ステータス技（鬼火 85、電磁波 90 など）
# のみ扱う。副次効果（ほのおのパンチの 10% やけど）は含めない。
#
# 冪等性: ALTER TABLE は既に列があるとエラーになるので pragma で検査。

require 'json'

existing_cols = db.execute('PRAGMA table_info(move_meta)').map { |r| r[1] }

unless existing_cols.include?('ailment_ja')
  db.execute("ALTER TABLE move_meta ADD COLUMN ailment_ja TEXT NOT NULL DEFAULT ''")
end

unless existing_cols.include?('ailment_chance')
  db.execute('ALTER TABLE move_meta ADD COLUMN ailment_chance INTEGER NOT NULL DEFAULT 100')
end

data = JSON.parse(File.read(File.join(patch_dir, 'data.json')))

updated = 0
inserted = 0

data.each do |entry|
  move_name = entry['name']
  ailment_ja = entry['ailment_ja'] || ''
  ailment_chance = entry['ailment_chance'] || 100

  existing = db.get_first_value('SELECT 1 FROM move_meta WHERE name_ja = ?', [move_name])
  if existing
    db.execute(
      'UPDATE move_meta SET ailment_ja = ?, ailment_chance = ? WHERE name_ja = ?',
      [ailment_ja, ailment_chance, move_name]
    )
    updated += 1
  else
    db.execute(
      'INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance) VALUES (?, 0, ?, ?, ?)',
      [move_name, '[]', ailment_ja, ailment_chance]
    )
    inserted += 1
  end
end

puts "    ailment columns added; #{updated} updated, #{inserted} inserted"
