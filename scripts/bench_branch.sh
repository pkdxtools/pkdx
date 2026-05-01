#!/usr/bin/env bash
# Run the Phase 3-C branch-count test as a wall-clock benchmark.
#
# branch_count_test.mbt は決定論的な cached_states 上限を assert する側で、
# 時間計測は CI から切り離してこちらに置く。CI ではこのスクリプトは走らせず、
# 開発者が手元で「variants 統合の探索時間が劣化していないか」を見るために使う。
#
# Usage:
#   scripts/bench_branch.sh           # 1 回測定
#   scripts/bench_branch.sh -n 5      # 5 回測定して min/max/avg
#
# Prereqs: setup.sh has been run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKDX_DIR="$REPO_ROOT/pkdx"

REPEATS=1
while getopts "n:" opt; do
  case "$opt" in
    n) REPEATS="$OPTARG" ;;
    *) echo "usage: $0 [-n REPEATS]" >&2; exit 1 ;;
  esac
done

if [ ! -d "$PKDX_DIR" ]; then
  echo "bench_branch.sh: $PKDX_DIR not found — run ./setup.sh from the repo root." >&2
  exit 1
fi

cd "$PKDX_DIR"

# millis 取得は GNU date / BSD date 両対応 (perl にフォールバック)。
now_ms() {
  if date +%s%3N >/dev/null 2>&1 && [ "$(date +%3N)" != "3N" ]; then
    date +%s%3N
  else
    perl -MTime::HiRes=time -e 'printf("%d\n", time()*1000)'
  fi
}

run_once() {
  local start end
  start=$(now_ms)
  moon test --target native -p pkdx/payoff -f branch_count_test.mbt >/dev/null 2>&1
  end=$(now_ms)
  echo $(( end - start ))
}

echo "=== Phase 3-C branch-count bench (n=$REPEATS) ==="
echo "Note: 時間 assertion なし。回帰検出は手動レビュー。"
echo

declare -a samples=()
for i in $(seq 1 "$REPEATS"); do
  ms=$(run_once)
  samples+=("$ms")
  echo "  run $i: ${ms} ms"
done

if [ "$REPEATS" -gt 1 ]; then
  min=${samples[0]}
  max=${samples[0]}
  sum=0
  for s in "${samples[@]}"; do
    [ "$s" -lt "$min" ] && min=$s
    [ "$s" -gt "$max" ] && max=$s
    sum=$(( sum + s ))
  done
  avg=$(( sum / REPEATS ))
  echo
  echo "  min=${min}ms  max=${max}ms  avg=${avg}ms"
fi
