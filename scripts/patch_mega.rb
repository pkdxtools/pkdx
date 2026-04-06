#!/usr/bin/env ruby
# frozen_string_literal: true

# pokedex.db にメガシンカデータをパッチするスクリプト
# upstream の DB 再生成を待たずに、LegendsZA JSON からメガシンカ情報を反映する

require 'json'
require 'sqlite3'

REPO_ROOT = File.expand_path('..', __dir__)
DB_PATH = File.join(REPO_ROOT, 'pokedex', 'pokedex.db')
ZA_JSON = File.join(REPO_ROOT, 'pokedex', 'pokedex', 'LegendsZA', 'LegendsZA.json')
VERSION = 'legendsza'

unless File.exist?(DB_PATH)
  abort "Error: #{DB_PATH} not found. Run ./setup.sh first."
end

unless File.exist?(ZA_JSON)
  abort "Error: #{ZA_JSON} not found. Run 'git submodule update --init'."
end

data = JSON.parse(File.read(ZA_JSON))
pokedex = data['pokedex']

megas = []
pokedex.each do |_region_name, entries|
  entries.each do |_no, forms|
    forms.each do |_form_id, info|
      next unless info['mega_evolution'] && info['mega_evolution'] != ''
      megas << info
    end
  end
end

if megas.empty?
  puts 'No mega evolution data found in JSON.'
  exit 0
end

db = SQLite3::Database.new(DB_PATH)
db.transaction

patched = 0

megas.each do |mega|
  id = mega['id']
  global_no = id.split('_').first
  mega_name = mega['mega_evolution']

  # local_pokedex: mega_evolution カラムを設定
  db.execute(
    'UPDATE local_pokedex SET mega_evolution = ? WHERE id = ? AND version = ?',
    [mega_name, id, VERSION]
  )

  # local_pokedex_status: メガシンカ種族値に更新
  db.execute(
    'UPDATE local_pokedex_status SET mega_evolution = ?, hp = ?, attack = ?, defense = ?, special_attack = ?, special_defense = ?, speed = ? WHERE id = ? AND version = ?',
    [mega_name, mega['hp'], mega['attack'], mega['defense'], mega['special_attack'], mega['special_defense'], mega['speed'], id, VERSION]
  )

  # local_pokedex_type: タイプを更新
  type2 = mega['type2']
  type2 = nil if type2 == ''
  db.execute(
    'UPDATE local_pokedex_type SET mega_evolution = ?, type1 = ?, type2 = ? WHERE id = ? AND version = ?',
    [mega_name, mega['type1'], type2, id, VERSION]
  )

  # local_pokedex_ability: メガ特性を設定
  ability2 = mega['ability2']
  ability2 = nil if ability2 == ''
  dream = mega['dream_ability']
  dream = nil if dream == ''
  db.execute(
    'UPDATE local_pokedex_ability SET mega_evolution = ?, ability1 = ?, ability2 = ?, dream_ability = ? WHERE id = ? AND version = ?',
    [mega_name, mega['ability1'], ability2, dream, id, VERSION]
  )

  # pokedex_name: メガ名に更新（jpn/eng のみ、他言語は元名のまま）
  names = mega['name'] || {}
  if names['jpn']
    db.execute(
      'UPDATE pokedex_name SET mega_evolution = ?, name = ? WHERE id = ? AND language = ?',
      [mega_name, names['jpn'], id, 'jpn']
    )
  end
  if names['eng']
    db.execute(
      'UPDATE pokedex_name SET mega_evolution = ?, name = ? WHERE id = ? AND language = ?',
      [mega_name, names['eng'], id, 'eng']
    )
  end

  patched += 1
end

db.commit
puts "Patched #{patched} mega evolution entries in #{DB_PATH}"
