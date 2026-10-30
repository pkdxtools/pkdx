#!/usr/bin/env bash
# moon 0.1.20261028 rejects legacy moon.mod.json / moon.pkg.json. Several
# mooncakes (nash-mbt, numbt, blas, and transitive mizchi packages) are still
# published in that format. Download them, migrate each manifest in the local
# cache, rewrite native link flags, then build.
#
# Usage:
#   scripts/moon_build_native.sh            # debug build of src/main
#   scripts/moon_build_native.sh --release  # release build of src/main
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RELEASE=()
if [ "${1:-}" = "--release" ]; then
  RELEASE=(--release)
elif [ -n "${1:-}" ]; then
  echo "usage: $0 [--release]" >&2
  exit 1
fi

moon update

migrate_legacy_manifests() {
  local migrated=0
  local json dir dest
  while IFS= read -r json; do
    [ -n "$json" ] || continue
    dir="$(dirname "$json")"
    case "$json" in
      */moon.mod.json) dest="$dir/moon.mod" ;;
      */moon.pkg.json) dest="$dir/moon.pkg" ;;
      *) continue ;;
    esac
    if [ ! -f "$dest" ]; then
      echo "migrate_legacy_manifests: $json -> $dest"
      moon tool migrate-manifest --old "$json" --dest "$dest"
    fi
    rm -f "$json"
    migrated=1
  done < <(find .mooncakes -name moon.mod.json -o -name moon.pkg.json | sort)
  [ "$migrated" -eq 1 ]
}

for round in 1 2 3 4 5 6 7 8 9 10; do
  migrated=0
  if migrate_legacy_manifests; then
    migrated=1
  fi
  bash scripts/configure_native_link_flags.sh
  if moon build --target native "${RELEASE[@]}" src/main; then
    exit 0
  fi
  if [ "$migrated" -eq 0 ]; then
    echo "moon_build_native: build failed and no legacy manifests remain" >&2
    exit 1
  fi
  echo "moon_build_native: retrying after manifest migration (round $round)"
done

echo "moon_build_native: gave up after 10 rounds" >&2
exit 1
