# 004_champions_learnset — Champions 技習得データを pokedex.db にパッチ
#
# apply.rb から eval される。db (SQLite3::Database) と patch_dir が利用可能。

require 'json'

data = JSON.parse(File.read(File.join(patch_dir, 'data.json')))
waza_version = 'Champions'

data.each do |entry|
  form       = entry['form'].to_s == '' ? nil : entry['form']
  region     = entry['region'].to_s == '' ? nil : entry['region']
  mega_evo   = entry['mega_evolution'].to_s == '' ? nil : entry['mega_evolution']
  gigantamax = entry['gigantamax'].to_s == '' ? nil : entry['gigantamax']

  db.execute(
    'INSERT OR IGNORE INTO local_pokedex_waza (id, globalNo, form, region, mega_evolution, gigantamax, version, pokedex, conditions, waza) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [entry['id'], entry['globalNo'], form, region, mega_evo, gigantamax,
     waza_version, entry['pokedex'], entry['conditions'], entry['waza']]
  )
end

puts "    Inserted #{data.size} Champions learnset entries"
