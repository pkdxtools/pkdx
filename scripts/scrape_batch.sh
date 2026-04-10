#!/usr/bin/env bash
# Champions ポケモンデータを1ページずつスクレイピング
# ブラウザは事前に playwright-cli open --headed で開いておくこと
# Usage: scrape_batch.sh [start_index] [end_index]
set -euo pipefail

URL_LIST="/tmp/champions_url_list.tsv"
OUT_DIR="/tmp/champions_scrape/raw"
PROGRESS="/tmp/champions_scrape/progress.txt"

START=${1:-0}
END=${2:-999}

mkdir -p "$OUT_DIR"
touch "$PROGRESS"

MOVE_JS='() => {
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
}'

STAT_JS='() => {
  const t = document.querySelector("table.center");
  const r = Array.from(t.querySelectorAll("tr"));
  const g = (i) => { const c = r[i].querySelectorAll("td"); return c.length >= 2 ? parseInt(c[1].textContent.match(/[0-9]+/)[0]) : 0; };
  return {name: document.querySelector("h1").textContent.replace(/[-].*/,"").trim(), types: Array.from(document.querySelectorAll("img[alt*=タイプ]")).map(i=>i.alt.replace("タイプ","").trim()).filter(Boolean), stats:{hp:g(1),atk:g(2),def:g(3),spa:g(4),spd:g(5),spe:g(6)}};
}'

PARSE_RUBY='require "json"; input=STDIN.read; if input =~ /### Result\n([\s\S]*?)(?:\n###|\z)/; j=JSON.parse($1.strip); File.write(ARGV[0],JSON.pretty_generate(j)); puts j.to_json; end'

while IFS=$'\t' read -r idx name url; do
  # 範囲チェック
  [ "$idx" -lt "$START" ] && continue
  [ "$idx" -ge "$END" ] && break

  # URLからプレフィックス抽出
  prefix=$(echo "$url" | grep -o 'n[0-9a-z]*$')

  # 処理済みチェック
  if grep -q "^${prefix}$" "$PROGRESS" 2>/dev/null; then
    continue
  fi

  echo -n "[$idx] $name ($prefix)... "

  # ページ遷移
  playwright-cli goto "$url" >/dev/null 2>&1
  sleep 3

  # 技データ
  mc=$(playwright-cli eval "$MOVE_JS" 2>&1 | ruby -e "$PARSE_RUBY" "$OUT_DIR/${prefix}_moves.json" 2>/dev/null | ruby -e 'require "json"; puts JSON.parse(STDIN.read)["count"] rescue "?"')
  echo -n "moves:$mc "

  # 種族値
  sc=$(playwright-cli eval "$STAT_JS" 2>&1 | ruby -e "$PARSE_RUBY" "$OUT_DIR/${prefix}_stats.json" 2>/dev/null | ruby -e 'require "json"; s=JSON.parse(STDIN.read)["stats"]; puts "H#{s["hp"]}A#{s["atk"]}B#{s["def"]}C#{s["spa"]}D#{s["spd"]}S#{s["spe"]}" rescue "?"')
  echo "stats:$sc"

  # 進捗記録
  echo "$prefix" >> "$PROGRESS"

  # レート制限
  sleep 10

done < "$URL_LIST"

echo "Done!"
