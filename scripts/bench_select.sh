#!/usr/bin/env bash
# Reproducible wall-clock + peak-RSS bench for pkdx select / Nash.
#
# One process per case so VmHWM / GNU time max RSS are not mixed across
# cases. Solver seeds are fixed inside `pkdx select-bench` (see
# docs/select_nash_bench.md). This script does not change algorithms.
#
# Usage:
#   scripts/bench_select.sh                  # tier=default
#   scripts/bench_select.sh -t smoke
#   scripts/bench_select.sh -t full          # long; production-shaped 6v6
#   scripts/bench_select.sh -c nash_rps_3
#   scripts/bench_select.sh -t smoke -n 1    # override repeats
#
# Prereqs: local build of this tree (`moon build --target native --release src/main`
# or a debug build). The release binary from GitHub does not include
# `select-bench` until this command ships. Run from anywhere; the script
# cds to the repo root so the degenerate-matrix fixture path resolves.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TIER="default"
CASE_ID=""
REPEATS=""

while getopts "t:c:n:" opt; do
  case "$opt" in
    t) TIER="$OPTARG" ;;
    c) CASE_ID="$OPTARG" ;;
    n) REPEATS="$OPTARG" ;;
    *) echo "usage: $0 [-t smoke|default|full] [-c CASE] [-n REPEATS]" >&2; exit 1 ;;
  esac
done

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
echo "# note: ツールチェーン更新後に rebase して再計測予定（現在の数値は暫定）"
echo

list_cases() {
  if [ -n "$CASE_ID" ]; then
    echo "$CASE_ID"
  else
    "$PKDX" select-bench --list --tier "$TIER"
  fi
}

REPEAT_ARGS=()
if [ -n "$REPEATS" ]; then
  REPEAT_ARGS=(--repeats "$REPEATS")
fi

header_done=0
while IFS= read -r case_id; do
  [ -z "$case_id" ] && continue
  rss_file="$(mktemp)"
  tsv_file="$(mktemp)"
  # GNU time writes the resource report to stderr when -v is set. -o keeps
  # it separate from any pkdx stderr.
  if /usr/bin/time -v -o "$rss_file" "$PKDX" select-bench --case "$case_id" "${REPEAT_ARGS[@]}" >"$tsv_file"; then
    :
  else
    echo "bench_select.sh: case $case_id failed" >&2
    cat "$tsv_file" >&2 || true
    rm -f "$rss_file" "$tsv_file"
    exit 1
  fi
  max_rss="$(awk -F: '/Maximum resident set size/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' "$rss_file")"
  if [ -z "$max_rss" ]; then
    max_rss="-"
  fi
  if [ "$header_done" -eq 0 ]; then
    head -n 1 "$tsv_file" | awk -v ORS='\n' '{ print $0 "\tgnu_time_max_rss_kb\tmoonc" }'
    header_done=1
  fi
  # Data row is the second line. Append RSS and the moonc version token
  # (`v0.10.18+6c83a7f62`). The full `moon version --all` text is the
  # comment block above the table.
  awk -v rss="$max_rss" -v moonc="$MOONC_VERSION" \
    'NR==2 { print $0 "\t" rss "\t" moonc }' "$tsv_file"
  rm -f "$rss_file" "$tsv_file"
done < <(list_cases)
