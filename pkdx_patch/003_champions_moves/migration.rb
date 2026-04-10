# 003_champions_moves — Champions 技データを pokedex.db にパッチ
#
# apply.rb から eval される。db (SQLite3::Database) と patch_dir が利用可能。

require 'json'

data = JSON.parse(File.read(File.join(patch_dir, 'data.json')))
waza_version = 'Champions'

data.each do |move|
  waza = move['waza']

  db.execute(
    'INSERT OR REPLACE INTO local_waza (waza, version, type, category, pp, power, accuracy) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [waza, waza_version, move['type'], move['category'], move['pp'], move['power'], move['accuracy']]
  )

  db.execute(
    'INSERT OR IGNORE INTO local_waza_language (waza, version, language, name, description) VALUES (?, ?, ?, ?, ?)',
    [waza, waza_version, 'jpn', waza, nil]
  )
end

puts "    Inserted/replaced #{data.size} Champions move entries"
