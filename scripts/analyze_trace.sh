#!/usr/bin/env bash
# analyze_trace.sh — summarise a trace captured by `select_trace.sh`.
#
# Computes:
#   - Phase wall time (phase_start.t_ms .. phase_end.t_ms per pid)
#   - Per-cell wall time distribution (cell_done.t_ms - cell_start.t_ms,
#     joined by pid+phase+row+col so same-shard pairs only)
#     p50 / p90 / p95 / p99 / max + total / count
#   - dp_node classification breakdown (saddle / nash / pruned) per phase
#   - Top-10 slowest cells (phase, row, col, ms, pid)
#
# Requires: jq, awk. Trace file must be JSON Lines with the t_ms / pid
# fields embedded (i.e. pkdx 0.5.5+ --progress=json).
#
# Usage:
#   scripts/analyze_trace.sh /tmp/trace.jsonl

set -u

TRACE_FILE="${1:-/tmp/pkdx_select_trace.jsonl}"

if [ ! -f "$TRACE_FILE" ]; then
  echo "trace file not found: $TRACE_FILE" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found in PATH — required for trace analysis" >&2
  exit 1
fi

LINE_COUNT=$(wc -l < "$TRACE_FILE" | tr -d ' ')
echo "==> Trace: $TRACE_FILE  ($LINE_COUNT events)"

# ---------- Phase wall time -------------------------------------------------
echo
echo "==> Phase wall time (per pid)"
jq -rc 'select(.event=="phase_start" or .event=="phase_end")
  | [.pid, .phase, .event, .t_ms] | @tsv' "$TRACE_FILE" \
  | awk -F'\t' '
    {
      pid=$1; phase=$2; ev=$3; ms=$4
      key=pid "|" phase
      if (ev=="phase_start") starts[key]=ms
      else if (ev=="phase_end" && starts[key]!="") {
        dur=ms - starts[key]
        printf "  pid=%-7s phase=%-15s duration_ms=%d\n", pid, phase, dur
        delete starts[key]
      }
    }'

# ---------- Per-cell durations ---------------------------------------------
echo
echo "==> Per-cell durations (cell_done - cell_start, joined by pid+phase+row+col)"

# Build a TSV: pid \t phase \t row \t col \t event \t t_ms
CELLS_TSV=$(mktemp -t pkdx_cells.XXXXXX)
trap 'rm -f "$CELLS_TSV" "$CELLS_TSV.dur"' EXIT

jq -rc 'select(.event=="cell_start" or .event=="cell_done")
  | [.pid, .phase, .row, .col, .event, .t_ms] | @tsv' \
  "$TRACE_FILE" > "$CELLS_TSV"

awk -F'\t' '
  { key=$1 "|" $2 "|" $3 "|" $4 }
  $5=="cell_start" { starts[key]=$6 }
  $5=="cell_done"  && starts[key]!="" {
    dur=$6 - starts[key]
    printf "%s\t%s\t%s\t%s\t%d\n", $1, $2, $3, $4, dur
    delete starts[key]
  }
' "$CELLS_TSV" > "$CELLS_TSV.dur"

# Per-phase percentiles via awk: collect durations, sort, slice.
# Function pct() must be declared at top level (mawk/nawk reject nested defs).
awk -F'\t' '
  function pct(arr, ph, cnt, p,    idx) {
    idx=int(cnt * p + 0.5)
    if (idx<1) idx=1
    if (idx>cnt) idx=cnt
    return arr[ph, idx]
  }
  { phase=$2; ms=$5
    n[phase]++
    rows[phase, n[phase]]=ms
    tot[phase]+=ms
    if (ms > max[phase]) max[phase]=ms
  }
  END {
    for (ph in n) {
      cnt=n[ph]
      # Insertion sort (small N in practice: ~900 cells per phase).
      for (i=2; i<=cnt; i++) {
        v=rows[ph, i]
        j=i-1
        while (j>=1 && rows[ph, j] > v) {
          rows[ph, j+1]=rows[ph, j]
          j--
        }
        rows[ph, j+1]=v
      }
      printf "  phase=%-15s n=%-5d total_ms=%-9d max_ms=%-7d p50=%-6d p90=%-6d p95=%-6d p99=%-6d\n", \
             ph, cnt, tot[ph], max[ph], \
             pct(rows, ph, cnt, 0.50), pct(rows, ph, cnt, 0.90), \
             pct(rows, ph, cnt, 0.95), pct(rows, ph, cnt, 0.99)
    }
  }
' "$CELLS_TSV.dur"

# ---------- dp_node classification breakdown -------------------------------
echo
echo "==> DP node classification (per phase, requires --progress-every>0)"
jq -rc 'select(.event=="dp_node") | [.pid, .classification] | @tsv' "$TRACE_FILE" \
  | awk -F'\t' '
    { pid=$1; kind=$2; total[kind]++; per_pid[pid, kind]++; pids[pid]=1 }
    END {
      grand=0; for (k in total) grand+=total[k]
      if (grand==0) {
        print "  (no dp_node events — run with --progress-every=1 to enable)"
      } else {
        printf "  total: %d nodes\n", grand
        for (k in total) printf "    %s: %d (%.1f%%)\n", k, total[k], 100*total[k]/grand
      }
    }'

# ---------- Top-10 slowest cells -------------------------------------------
echo
echo "==> Top-10 slowest cells"
sort -t $'\t' -k5,5nr "$CELLS_TSV.dur" | head -n 10 \
  | awk -F'\t' '{ printf "  pid=%-7s phase=%-15s row=%-3s col=%-3s duration_ms=%s\n", $1, $2, $3, $4, $5 }'

echo
echo "==> Done."
