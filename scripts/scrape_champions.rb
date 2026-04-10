#!/usr/bin/env ruby
# frozen_string_literal: true

# Champions ポケモンの技データ・種族値を yakkun.com からスクレイピング
# playwright-cli --headed を使用（Cloudflare対策）
# 1ページ10秒以上の間隔を空ける

require 'json'
require 'open3'
require 'fileutils'
require 'time'

def extract_result_json(output)
  if output =~ /### Result\n([\s\S]*?)(?:\n###|\z)/
    json_text = $1.strip
    JSON.parse(json_text)
  else
    nil
  end
rescue JSON::ParserError
  nil
end

URLS_FILE = ARGV[0] || '/tmp/champions_urls.json'
OUTPUT_DIR = ARGV[1] || '/tmp/champions_scrape'
INTERVAL = 12 # 秒（余裕を持って12秒）

FileUtils.mkdir_p(OUTPUT_DIR)
FileUtils.mkdir_p(File.join(OUTPUT_DIR, 'raw'))

data = JSON.parse(File.read(URLS_FILE))
urls = data['urls']

# URLごとにユニーク化（メガと通常が同じURL）
unique_urls = urls.values.uniq
pokemon_by_url = {}
urls.each { |name, url| (pokemon_by_url[url] ||= []) << name }

JS_MOVES = <<~'JS'
  () => {
    const table = document.querySelector("table:has(.move_name)");
    if (!table) return { moves: [], error: "no move table" };
    const mainRows = table.querySelectorAll(".move_main_row");
    const moves = [];
    for (const main of mainRows) {
      const nameEl = main.querySelector(".move_name");
      const name = nameEl ? nameEl.textContent.trim() : "";
      const detail = main.nextElementSibling;
      if (detail && detail.classList.contains("move_detail_row")) {
        const cells = Array.from(detail.children).map(c => c.textContent.trim());
        moves.push({ name, type: cells[0]||"", category: cells[1]||"", power: cells[2]||"", accuracy: cells[3]||"", pp: cells[4]||"", contact: cells[5]||"", desc: cells[6]||"" });
      }
    }
    return { moves, count: moves.length };
  }
JS

JS_STATS = <<~'JS'
  () => {
    const statEls = document.querySelectorAll(".pokemon_status_pokemon td");
    if (statEls.length < 6) return { error: "no stats found", count: statEls.length };
    const stats = Array.from(statEls).map(el => el.textContent.trim());
    const nameEl = document.querySelector("h2.pokemon_name, .pokemon_name");
    const name = nameEl ? nameEl.textContent.trim() : "";
    const typeEls = document.querySelectorAll(".pokemon_type .type");
    const types = Array.from(typeEls).map(el => el.textContent.trim());
    const abilityEls = document.querySelectorAll(".pokemon_ability a, .pokemon_ability span");
    const abilities = Array.from(abilityEls).map(el => el.textContent.trim()).filter(a => a !== "");
    return { name, types, stats: { hp: stats[0], atk: stats[1], def: stats[2], spa: stats[3], spd: stats[4], spe: stats[5] }, abilities };
  }
JS

# 進捗ファイル（中断再開用）
progress_file = File.join(OUTPUT_DIR, 'progress.json')
completed = File.exist?(progress_file) ? JSON.parse(File.read(progress_file)) : []

remaining = unique_urls - completed
puts "Total: #{unique_urls.size}, Completed: #{completed.size}, Remaining: #{remaining.size}"

if remaining.empty?
  puts 'All pages already scraped.'
  exit 0
end

# ブラウザを開く
puts 'Opening browser...'
output, status = Open3.capture2e('playwright-cli', 'open', '--headed', remaining.first)
puts output
unless status.success?
  abort 'Failed to open browser.'
end

remaining.each_with_index do |url, i|
  pokemon_names = pokemon_by_url[url]
  safe_name = pokemon_names.first.gsub(/[^\w]/, '_')

  puts "[#{i + 1}/#{remaining.size}] #{pokemon_names.first} (#{url})"

  # ページ遷移
  output, _status = Open3.capture2e('playwright-cli', 'goto', url)

  # ページ読み込み待機
  sleep 3

  # 技データ取得
  moves_output, _status = Open3.capture2e('playwright-cli', 'eval', JS_MOVES)

  # 種族値取得
  stats_output, _status = Open3.capture2e('playwright-cli', 'eval', JS_STATS)

  moves_data = extract_result_json(moves_output)
  stats_data = extract_result_json(stats_output)

  unless moves_data
    puts "  WARN: Failed to parse moves"
  end
  unless stats_data
    puts "  WARN: Failed to parse stats"
  end

  # raw データ保存
  File.write(File.join(OUTPUT_DIR, 'raw', "#{safe_name}_moves.json"), moves_output)
  File.write(File.join(OUTPUT_DIR, 'raw', "#{safe_name}_stats.json"), stats_output)

  # パース済みデータ保存
  result = {
    url: url,
    pokemon_names: pokemon_names,
    moves: moves_data,
    stats: stats_data,
    scraped_at: Time.now.iso8601,
  }
  File.write(File.join(OUTPUT_DIR, "#{safe_name}.json"), JSON.pretty_generate(result))

  # 進捗更新
  completed << url
  File.write(progress_file, JSON.generate(completed))

  move_count = moves_data&.dig('count') || '?'
  puts "  OK: #{move_count} moves"

  # レート制限
  sleep INTERVAL if i < remaining.size - 1
end

puts 'Closing browser...'
system('playwright-cli', 'close')

puts "Done. #{completed.size} pages scraped to #{OUTPUT_DIR}"
