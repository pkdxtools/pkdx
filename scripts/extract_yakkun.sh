#!/usr/bin/env bash
# yakkun.com から1ページ分の技データ・種族値を抽出する
# Usage: extract_yakkun.sh <url> <output_prefix>
# Example: extract_yakkun.sh https://yakkun.com/ch/zukan/n3 n3
set -euo pipefail

URL="$1"
PREFIX="$2"
OUT_DIR="${3:-/tmp/champions_scrape/raw}"

# 技データ
playwright-cli goto "$URL" 2>&1 | tail -1
sleep 2

playwright-cli eval '() => {
  const t = document.querySelector("table:has(.move_name)");
  if (!t) return {moves:[],count:0};
  const rows = t.querySelectorAll(".move_main_row");
  const moves = [];
  for (const m of rows) {
    const n = m.querySelector(".move_name");
    const d = m.nextElementSibling;
    if (d && d.classList.contains("move_detail_row")) {
      const c = Array.from(d.children).map(x => x.textContent.trim());
      moves.push({name:n?n.textContent.trim():"",type:c[0],category:c[1],power:c[2],accuracy:c[3],pp:c[4],contact:c[5]});
    }
  }
  return {count:moves.length,moves};
}' 2>&1 | ruby -e '
require "json"
input=STDIN.read
if input =~ /### Result\n([\s\S]*?)(?:\n###|\z)/
  j=JSON.parse($1.strip)
  File.write("'"$OUT_DIR/$PREFIX"'_moves.json",JSON.pretty_generate(j))
  STDERR.puts "moves: #{j["count"]}"
end
'

# 種族値・特性
playwright-cli eval '() => {
  const t = document.querySelector("table.center");
  const r = Array.from(t.querySelectorAll("tr"));
  const g = (i) => { const c = r[i].querySelectorAll("td"); return c.length >= 2 ? parseInt(c[1].textContent.match(/\\d+/)[0]) : 0; };
  const stats = {hp:g(1),atk:g(2),def:g(3),spa:g(4),spd:g(5),spe:g(6)};
  const name = document.querySelector("h1").textContent.replace(/[-–].*/,"").trim();
  const typeImgs = document.querySelectorAll("img[alt*=タイプ]");
  const types = Array.from(typeImgs).map(i=>i.alt.replace("タイプ","").trim()).filter(Boolean);
  const abilities = [];
  let dreamAbility = null;
  const ths = document.querySelectorAll("th.left");
  for (const th of ths) {
    const txt = th.textContent.trim();
    if (txt.includes("特性") && !txt.includes("隠れ")) {
      const next = th.closest("tr")?.nextElementSibling;
      if (next) next.querySelectorAll("a").forEach(a => abilities.push(a.textContent.trim()));
    }
    if (txt.includes("隠れ特性")) {
      const next = th.closest("tr")?.nextElementSibling;
      if (next) { const a = next.querySelector("a"); if (a) dreamAbility = a.textContent.trim().replace(/^\*/, ""); }
    }
  }
  return {name,types,stats,abilities,dreamAbility};
}' 2>&1 | ruby -e '
require "json"
input=STDIN.read
if input =~ /### Result\n([\s\S]*?)(?:\n###|\z)/
  j=JSON.parse($1.strip)
  File.write("'"$OUT_DIR/$PREFIX"'_stats.json",JSON.pretty_generate(j))
  s=j["stats"]
  a = j["abilities"] || []
  d = j["dreamAbility"]
  STDERR.puts "stats: #{j["name"]} H#{s["hp"]}A#{s["atk"]}B#{s["def"]}C#{s["spa"]}D#{s["spd"]}S#{s["spe"]} abilities:#{a.join("/")}#{d ? " dream:#{d}" : ""}"
end
'
