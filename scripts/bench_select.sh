#!/usr/bin/env bash
# Reproducible wall-clock + peak-RSS bench for pkdx select / Nash.
#
# Each case runs in separate processes, so VmHWM / GNU time max RSS are not
# mixed across cases. Every process runs `select-bench --repeats N` (N = -n,
# default 1). Wall times are reported as the median, min and max across
# processes. Solver seeds are fixed inside `pkdx select-bench` (see
# docs/select_nash_bench.md). This script does not change algorithms.
#
# Process count per case (docs/select_nash_bench.md): 5 when the first
# process takes under 1 s, otherwise 3. -p N fixes it.
#
# Usage:
#   scripts/bench_select.sh                  # tier=default
#   scripts/bench_select.sh -t smoke
#   scripts/bench_select.sh -t full          # long; production-shaped 6v6
#   scripts/bench_select.sh -c nash_rps_3
#   scripts/bench_select.sh -c select_status_heavy -p 1   # one process
#   scripts/bench_select.sh -t smoke -n 3    # 3 in-process repeats per process
#
# Output: a TSV on stdout (header + one row per case). Columns other than the
# wall times are taken from process 1 (`phases` carries that process's
# per-phase timings). A warning is printed if a later process disagrees on a
# deterministic column (value, solver, dp_*, ...).
#
# Prereqs: local build of this tree (`moon build --target native --release src/main`
# or a debug build). The release binary from GitHub does not include
# `select-bench` until this command ships. Run from anywhere; the script
# cds to the repo root so the degenerate-matrix fixture path resolves.
#
# Peak RSS uses GNU time (`/usr/bin/time -v`). If it is missing, or the
# installed `time` rejects -v (BSD/macOS), the timings are still recorded and
# the RSS column is "-".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TIER="default"
CASE_ID=""
REPEATS="1"
PROCS="auto"

while getopts "t:c:n:p:" opt; do
  case "$opt" in
    t) TIER="$OPTARG" ;;
    c) CASE_ID="$OPTARG" ;;
    n) REPEATS="$OPTARG" ;;
    p) PROCS="$OPTARG" ;;
    *) echo "usage: $0 [-t smoke|default|full] [-c CASE] [-n REPEATS] [-p PROCS|auto]" >&2; exit 1 ;;
  esac
done

case "$REPEATS" in
  *[!0-9]* | 0 | "") echo "bench_select.sh: -n must be a positive integer (got: '$REPEATS')" >&2; exit 1 ;;
esac
case "$PROCS" in
  auto) ;;
  *[!0-9]* | 0 | "") echo "bench_select.sh: -p must be a positive integer or auto (got: '$PROCS')" >&2; exit 1 ;;
esac

pick_pkdx() {
  local release debug
  release="$REPO_ROOT/_build/native/release/build/src/main/main.exe"
  debug="$REPO_ROOT/_build/native/debug/build/src/main/main.exe"
  if [ -x "$release" ]; then
    echo "$release"
  elif [ -x "$debug" ]; then
    echo "$debug"
  elif [ -x "$REPO_ROOT/bin/pkdx" ]; then
    echo "$REPO_ROOT/bin/pkdx"
  else
    echo ""
  fi
}

PKDX="$(pick_pkdx)"
if [ -z "$PKDX" ]; then
  echo "bench_select.sh: no pkdx binary." >&2
  echo "  Build one from the repo root:" >&2
  echo "    moon update && bash scripts/configure_native_link_flags.sh" >&2
  echo "    moon build --target native --release src/main" >&2
  exit 1
fi

if ! "$PKDX" select-bench --list --tier smoke >/dev/null 2>&1; then
  echo "bench_select.sh: '$PKDX select-bench' failed." >&2
  echo "  The binary does not include this command. Rebuild from this tree." >&2
  exit 1
fi

cd "$REPO_ROOT"

echo "# pkdx select-bench"
echo "# binary: $PKDX"
# Full `moon version --all` (moon, moonc, moonrun, feature flags). moonc is
# the compiler identity; future toolchain pins use the moonc distribution
# URL, not the moon CLI date stamp alone.
MOONC_VERSION="unknown"
if command -v moon >/dev/null 2>&1; then
  echo "# moon version --all:"
  while IFS= read -r line || [ -n "$line" ]; do
    echo "# $line"
  done < <(moon version --all 2>&1)
  # Second field of `moonc v0.10.18+6c83a7f62 (date) path`.
  MOONC_VERSION="$(moon version --all 2>/dev/null | awk '/^moonc / { print $2; exit }')"
  if [ -z "$MOONC_VERSION" ]; then
    MOONC_VERSION="unknown"
  fi
else
  echo "# moon version --all: (moon not on PATH)"
fi
echo "# moonc: $MOONC_VERSION"
echo "# uname: $(uname -srm)"
echo "# nproc: $(nproc 2>/dev/null || echo 1)"
echo "# tier: $TIER"
echo "# repeats per process: $REPEATS; processes per case: $PROCS (auto = 5 if the first run is under 1 s, else 3)"
echo "# official baseline: docs/select_nash_bench.md (4 vCPU, moonc 0.10.18+6c83a7f62). Wall times depend on machine load and CPU count; value / solver / dp_* do not."
echo

# GNU time is optional. Probe it once: a missing binary or a BSD `time`
# (which rejects -v) falls back to running pkdx without it.
GNU_TIME=""
if [ -x /usr/bin/time ] && /usr/bin/time -v true >/dev/null 2>&1; then
  GNU_TIME="/usr/bin/time"
else
  echo "bench_select.sh: GNU time (/usr/bin/time -v) not available; gnu_time_max_rss_kb is '-'" >&2
fi

list_cases() {
  if [ -n "$CASE_ID" ]; then
    echo "$CASE_ID"
  else
    "$PKDX" select-bench --list --tier "$TIER"
  fi
}

# One process for one case. TSV goes to $2, GNU time report to $3 (empty
# when GNU time is unavailable).
run_once() {
  local case_id="$1" tsv_file="$2" rss_file="$3"
  if [ -n "$GNU_TIME" ]; then
    "$GNU_TIME" -v -o "$rss_file" "$PKDX" select-bench --case "$case_id" --repeats "$REPEATS" >"$tsv_file"
  else
    "$PKDX" select-bench --case "$case_id" --repeats "$REPEATS" >"$tsv_file"
  fi
}

# Median of numbers on stdin (one per line). An odd count returns a sample
# verbatim; an even count returns the mean of the two middle values.
median_of() {
  sort -g | awk '
    { a[NR] = $1 }
    END {
      if (NR == 0) { print "-"; exit }
      if (NR % 2) { print a[(NR + 1) / 2] }
      else { printf "%.6g\n", (a[NR / 2] + a[NR / 2 + 1]) / 2 }
    }'
}

header_done=0

# Runs one case in as many processes as the rule above asks, then prints one
# TSV row: process 1's row with wall_ms_median / wall_ms_min replaced by the
# cross-process median / min, plus wall_ms_max, procs and peak RSS.
run_case() {
  local case_id="$1"
  local walls rsss first_tsv tsv_file rss_file wall rss n target
  local wall_med wall_min wall_max rss_med
  walls="$(mktemp)"
  rsss="$(mktemp)"
  first_tsv="$(mktemp)"
  n=0
  target=0
  while :; do
    n=$((n + 1))
    tsv_file="$(mktemp)"
    rss_file="$(mktemp)"
    if ! run_once "$case_id" "$tsv_file" "$rss_file"; then
      echo "bench_select.sh: case $case_id failed" >&2
      cat "$tsv_file" >&2 || true
      rm -f "$walls" "$rsss" "$first_tsv" "$tsv_file" "$rss_file"
      exit 1
    fi
    # Data row is the second line of the TSV; column 4 is wall_ms_median.
    wall="$(awk -F'\t' 'NR == 2 { print $4 }' "$tsv_file")"
    if [ -z "$wall" ]; then
      echo "bench_select.sh: case $case_id: no data row in process $n output" >&2
      rm -f "$walls" "$rsss" "$first_tsv" "$tsv_file" "$rss_file"
      exit 1
    fi
    echo "$wall" >>"$walls"
    rss="$(awk -F: '/Maximum resident set size/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' "$rss_file")"
    if [ -n "$rss" ]; then
      echo "$rss" >>"$rsss"
    fi
    if [ "$n" -eq 1 ]; then
      cp "$tsv_file" "$first_tsv"
      if [ "$PROCS" = auto ]; then
        if awk -v w="$wall" 'BEGIN { exit !(w + 0 < 1000) }'; then
          target=5
        else
          target=3
        fi
      else
        target="$PROCS"
      fi
    elif ! diff -q <(cut -f6-10,12- "$first_tsv") <(cut -f6-10,12- "$tsv_file") >/dev/null; then
      # Deterministic for a fixed seed and binary: rows..exploitability and
      # cells..note. Column 11 (phases) carries per-phase timings, so it is
      # skipped here and taken from process 1.
      echo "bench_select.sh: case $case_id: process $n differs from process 1 in a deterministic column" >&2
    fi
    rm -f "$tsv_file" "$rss_file"
    if [ "$n" -ge "$target" ]; then
      break
    fi
  done

  wall_med="$(median_of <"$walls")"
  # Min / max keep the process's own number string (no re-formatting).
  wall_min="$(awk 'NR == 1 || $1 + 0 < mv { mv = $1 + 0; s = $1 } END { print s }' "$walls")"
  wall_max="$(awk 'NR == 1 || $1 + 0 > mv { mv = $1 + 0; s = $1 } END { print s }' "$walls")"
  if [ -s "$rsss" ]; then
    rss_med="$(median_of <"$rsss")"
  else
    rss_med="-"
  fi

  if [ "$header_done" -eq 0 ]; then
    head -n 1 "$first_tsv" | awk -v ORS='\n' '{ print $0 "\twall_ms_max\tprocs\tgnu_time_max_rss_kb\tmoonc" }'
    header_done=1
  fi
  # Replace the in-process median / min of process 1 with the cross-process
  # values. Keeps the rest of the row (value, solver, dp_*) from process 1.
  awk -F'\t' -v OFS='\t' \
    -v med="$wall_med" -v mn="$wall_min" -v mx="$wall_max" \
    -v procs="$n" -v rss="$rss_med" -v moonc="$MOONC_VERSION" \
    'NR == 2 { $4 = med; $5 = mn; print $0, mx, procs, rss, moonc }' "$first_tsv"

  rm -f "$walls" "$rsss" "$first_tsv"
}

while IFS= read -r case_id; do
  [ -z "$case_id" ] && continue
  run_case "$case_id"
done < <(list_cases)
