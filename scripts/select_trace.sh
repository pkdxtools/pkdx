#!/usr/bin/env bash
# select_trace.sh — passthrough recorder for `pkdx select --progress=json`.
#
# Saves the stderr JSON Lines stream (with the t_ms / pid fields the CLI
# already embeds) to a trace file for offline analysis with
# `analyze_trace.sh`. Optionally tees the live stream to a viz consumer
# (e.g. select_grid_viz.sh) so the user keeps the grid visualisation.
#
# Usage:
#   bin/pkdx select --parallel=auto --progress=json --progress-every=1 \
#     < input.json > result.json \
#     2> >(scripts/select_trace.sh /tmp/trace.jsonl)
#
#   # with viz pass-through:
#   bin/pkdx select ... 2> >(scripts/select_trace.sh /tmp/trace.jsonl \
#       | scripts/select_grid_viz.sh)
#
# Output:
#   - Each input line is appended verbatim to the trace file.
#   - stdout receives the same lines unchanged so a downstream viz tail
#     can render in real time.

set -u

TRACE_FILE="${1:-/tmp/pkdx_select_trace.jsonl}"
mkdir -p "$(dirname "$TRACE_FILE")"
: > "$TRACE_FILE"

while IFS= read -r line; do
  printf '%s\n' "$line" >> "$TRACE_FILE"
  printf '%s\n' "$line"
done
