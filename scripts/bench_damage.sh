#!/usr/bin/env bash
# Run pkdx damage-bench over a matrix of cache-entry counts and
# iteration counts. Emits the raw TSV reports to stdout; pipe elsewhere
# to aggregate.
#
# Usage:
#   scripts/bench_damage.sh                # default matrix
#   scripts/bench_damage.sh -N "10 100"    # custom N set
#
# Prereqs: setup.sh has been run (pokedex.db + pkdx binary are in place).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKDX="$REPO_ROOT/bin/pkdx"

# Default matrix — 4 cache sizes × 1 iteration count is enough to see if
# the lookup time scales with N.
ENTRIES_LIST="10 100 1000 10000"
ITERATIONS=1000

while getopts "N:I:" opt; do
  case "$opt" in
    N) ENTRIES_LIST="$OPTARG" ;;
    I) ITERATIONS="$OPTARG" ;;
    *) echo "usage: $0 [-N \"10 100\"] [-I 1000]" >&2; exit 1 ;;
  esac
done

cd "$REPO_ROOT"

for N in $ENTRIES_LIST; do
  echo "=== entries=$N iterations=$ITERATIONS ==="
  # Bench emits the TSV on stderr; mirror to stdout.
  "$PKDX" damage-bench --entries "$N" --iterations "$ITERATIONS" 2>&1 >/dev/null | \
    sed "s/^/N=$N\t/"
  echo
done
