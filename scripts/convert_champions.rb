#!/usr/bin/env ruby
# frozen_string_literal: true

# スクレイピングデータ（/tmp/champions_scrape/raw/）を読み込み、
# pkdx_patch用の data.json を3つ生成する。
# pokedex.db を参照して globalNo を名前ベースで解決する。

require 'json'
require 'sqlite3'

RAW_DIR    = ARGV[0] || '/tmp/champions_scrape/raw'
PATCH_DIR  = ARGV[1] || File.join(__dir__, '..', 'pkdx_patch')
DB_PATH    = ARGV[2] || File.join(__dir__, '..', 'pokedex', 'pokedex.db')

unless File.exist?(DB_PATH)
  abort "Error: #{DB_PATH} not found."
end
unless File.directory?(RAW_DIR)
  abort "Error: #{RAW_DIR} not found."
end

db = SQLite3::Database.new(DB_PATH)

# --- globalNo 逆引きキャッシュ構築 ---
# pokedex_name から日本語名 → globalNo のマップを構築
name_to_gno = {}
db.execute(<<~SQL).each do |row|
  SELECT name, globalNo FROM pokedex_name
  WHERE language = 'jpn'
    AND COALESCE(form, '') = ''
    AND COALESCE(region, '') = ''
    AND COALESCE(mega_evolution, '') = ''
SQL
  name_to_gno[row[0]] ||= row[1]
end

# --- 特性データの逆引きキャッシュ ---
ability_map = {}
%w[scarlet_violet sword_shield legendsza sun_moon].each do |ver|
  db.execute(
    'SELECT id, ability1, ability2, dream_ability FROM local_pokedex_ability WHERE version = ?',
    [ver]
  ).each do |row|
    ability_map[row[0]] ||= { ability1: row[1], ability2: row[2], dream_ability: row[3] }
  end
end

# --- 特殊フォーム → form_bytes ハードコードテーブル ---
SPECIAL_FORM_BYTES = {
  'n128a' => '04000000',
  'n128b' => '04000001',
  'n128c' => '04000002',
  'n479h' => '00000001',
  'n479w' => '00000002',
  'n479f' => '00000003',
  'n479s' => '00000004',
  'n479c' => '00000005',
  'n711s' => '00000001',
  'n711l' => '00000002',
  'n711k' => '00000003',
  'n745f' => '00000001',
  'n745d' => '00000002',
  'n678f' => '00000001',
  'n902f' => '00000001',
}.freeze

SUFFIX_TO_FORM_BYTES = {
  ''  => '00000000',
  'm' => '00000100',
  'x' => '00000100',
  'y' => '00000101',
  'a' => '01000000',
  'g' => '02000000',
  'h' => '03000000',
}.freeze

# Champions限定メガの英語名
NEW_MEGA_ENG = {
  'メガチリーン'     => 'Mega Chimecho',
  'メガゴルーグ'     => 'Mega Golurk',
  'メガフラエッテ'   => 'Mega Floette',
  'メガニャオニクス' => 'Mega Meowstic',
  'メガケケンカニ'   => 'Mega Crabominable',
  'メガスコヴィラン' => 'Mega Scovillain',
  'メガキラフロル'   => 'Mega Glimmora',
}.freeze

def clean_move_name(name)
  name.sub(/New$/, '')
end

def extract_base_name(mega_name)
  base = mega_name.sub(/^メガ/, '')
  # リザードンX/Y, ミュウツーX/Y
  base.sub(/[XY]$/, '')
end

def resolve_form_bytes(file_key, suffix)
  return SPECIAL_FORM_BYTES[file_key] if SPECIAL_FORM_BYTES.key?(file_key)
  SUFFIX_TO_FORM_BYTES[suffix] || '00000000'
end

def is_mega?(suffix)
  %w[m x y].include?(suffix)
end

def mega_evolution_name(name, suffix)
  return '' unless is_mega?(suffix)
  name
end

def region_name(suffix, file_key)
  return 'パルデアのすがた' if file_key.start_with?('n128') && %w[a b c].include?(suffix)
  case suffix
  when 'a' then 'アローラのすがた'
  when 'g' then 'ガラルのすがた'
  when 'h'
    # ロトムのhは特殊フォーム、リージョンではない
    return '' if file_key.start_with?('n479')
    'ヒスイのすがた'
  else ''
  end
end

# --- メイン処理 ---
pokemon_data = []
all_moves = {}
learnset_data = []
errors = []

stats_files = Dir.glob(File.join(RAW_DIR, '*_stats.json')).sort

stats_files.each do |stats_file|
  file_key = File.basename(stats_file).sub(/_stats\.json$/, '')
  moves_file = File.join(RAW_DIR, "#{file_key}_moves.json")

  unless File.exist?(moves_file)
    errors << "Missing moves file for #{file_key}"
    next
  end

  stats = JSON.parse(File.read(stats_file))
  moves = JSON.parse(File.read(moves_file))

  name = stats['name']
  suffix = file_key.sub(/^n\d+/, '')

  # globalNo 解決
  if is_mega?(suffix)
    base_name = extract_base_name(name)
    gno = name_to_gno[base_name]
    unless gno
      errors << "Cannot resolve globalNo for mega base '#{base_name}' (#{file_key})"
      next
    end
  elsif SPECIAL_FORM_BYTES.key?(file_key)
    # 特殊フォーム: ファイル番号から globalNo を取得（Gen1-8なので安全）
    num = file_key.match(/n(\d+)/)[1]
    gno = num.rjust(4, '0')
  elsif suffix != '' && %w[a g h f d s l k w c b].include?(suffix)
    # リージョン/フォーム: ベース名で検索
    gno = name_to_gno[name]
    unless gno
      # フォーム名が異なる場合はファイル番号を使用
      num = file_key.match(/n(\d+)/)[1]
      gno = num.rjust(4, '0')
    end
  else
    # 通常フォーム: 名前ベース逆引き
    gno = name_to_gno[name]
    unless gno
      errors << "Cannot resolve globalNo for '#{name}' (#{file_key})"
      next
    end
  end

  form_bytes = resolve_form_bytes(file_key, suffix)
  id = "#{gno}_#{form_bytes}_0_000_0"
  mega_evo = mega_evolution_name(name, suffix)
  region = region_name(suffix, file_key)

  # form フィールド: pokedex_name の既存データに合わせる（大半は空）
  form = ''

  # 特性取得
  abilities = ability_map[id] || { ability1: nil, ability2: nil, dream_ability: nil }

  # 既存の pokedex/pokedex_name エントリがあるか確認
  existing = db.get_first_value('SELECT 1 FROM pokedex WHERE id = ?', [id])
  new_entry = existing.nil?

  types = stats['types']
  type1 = types[0]
  type2 = types.length > 1 ? types[1] : nil

  pokemon_entry = {
    'id'               => id,
    'no'               => gno,
    'globalNo'         => gno,
    'form'             => form,
    'region'           => region,
    'mega_evolution'   => mega_evo,
    'gigantamax'       => '',
    'pokedex'          => 'チャンピオンズ',
    'type1'            => type1,
    'type2'            => type2,
    'hp'               => stats['stats']['hp'],
    'attack'           => stats['stats']['atk'],
    'defense'          => stats['stats']['def'],
    'special_attack'   => stats['stats']['spa'],
    'special_defense'  => stats['stats']['spd'],
    'speed'            => stats['stats']['spe'],
    'ability1'         => abilities[:ability1],
    'ability2'         => abilities[:ability2],
    'dream_ability'    => abilities[:dream_ability],
    'new_pokedex_entry' => new_entry,
  }

  if new_entry && mega_evo != ''
    pokemon_entry['new_pokedex_name_jpn'] = name
    pokemon_entry['new_pokedex_name_eng'] = NEW_MEGA_ENG[name] || "Mega #{name}"
  end

  pokemon_data << pokemon_entry

  # 技データ収集
  moves['moves'].each do |move|
    waza = clean_move_name(move['name'])
    all_moves[waza] ||= {
      'waza'     => waza,
      'type'     => move['type'],
      'category' => move['category'],
      'pp'       => move['pp'],
      'power'    => move['power'],
      'accuracy' => move['accuracy'],
    }

    learnset_data << {
      'id'              => id,
      'globalNo'        => gno,
      'form'            => form,
      'region'          => region,
      'mega_evolution'  => mega_evo,
      'gigantamax'      => '',
      'pokedex'         => 'チャンピオンズ',
      'conditions'      => '基本',
      'waza'            => waza,
    }
  end
end

# --- エラー報告 ---
unless errors.empty?
  $stderr.puts "Errors (#{errors.size}):"
  errors.each { |e| $stderr.puts "  #{e}" }
  abort 'Conversion failed.'
end

# --- data.json 出力 ---
pokemon_out = File.join(PATCH_DIR, '002_champions_pokemon', 'data.json')
moves_out   = File.join(PATCH_DIR, '003_champions_moves', 'data.json')
learn_out   = File.join(PATCH_DIR, '004_champions_learnset', 'data.json')

File.write(pokemon_out, JSON.pretty_generate(pokemon_data))
File.write(moves_out, JSON.pretty_generate(all_moves.values))
File.write(learn_out, JSON.pretty_generate(learnset_data))

puts "Pokemon: #{pokemon_data.size} entries -> #{pokemon_out}"
puts "Moves:   #{all_moves.size} unique moves -> #{moves_out}"
puts "Learnset: #{learnset_data.size} entries -> #{learn_out}"

new_entries = pokemon_data.count { |p| p['new_pokedex_entry'] }
puts "New pokedex entries: #{new_entries}"
