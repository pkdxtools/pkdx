#!/usr/bin/env bash
# Rewrites the `cc-link-flags` (and on Windows, `stub-cc-flags`) entries in
# every moon.pkg that depends on BLAS so the platform-specific linker / header
# paths reach moon's native backend. MoonBit has no env var equivalent
# (MOON_CC_LINK_FLAGS does not exist; only MOON_CC / MOON_AR are read), so the
# in-place rewrite is currently the only mechanism available.
#
# `moon update` re-pulls the vendored mizchi/* moon.pkg files, which is why
# build-pkdx.yml runs this script *before each* `moon build` / `moon test`.
set -euo pipefail

case "${RUNNER_OS:-$(uname -s)}" in
  Linux)
    FLAGS="-lopenblas -llapack -lm"
    STUB_CFLAGS=""
    ;;
  macOS | Darwin)
    FLAGS="-framework Accelerate"
    STUB_CFLAGS=""
    ;;
  Windows | MINGW* | MSYS* | CYGWIN*)
    FLAGS="-LC:/msys64/mingw64/lib -lopenblas"
    STUB_CFLAGS="-IC:/msys64/mingw64/include -IC:/msys64/mingw64/include/openblas"
    ;;
  *)
    echo "unsupported runner OS: ${RUNNER_OS:-$(uname -s)}" >&2
    exit 1
    ;;
esac

PKGS=(
  src/payoff/moon.pkg
  .mooncakes/mizchi/numbt/src/moon.pkg
  .mooncakes/mizchi/blas/src/moon.pkg
  .mooncakes/mizchi/blas/src/bench/moon.pkg
  .mooncakes/ushironoko/nash-mbt/moon.pkg
)

# `moon update` is what restores .mooncakes/, so the vendored packages may not
# exist yet on a fresh clone. Tracking what we touched lets us fail loudly if
# *no* package matched — that almost certainly means the layout drifted and
# the rewrite turned into a silent no-op.
matched=0

for pkg in "${PKGS[@]}"; do
  if [ ! -f "$pkg" ]; then
    continue
  fi

  if ! grep -q '"cc-link-flags":' "$pkg"; then
    echo "configure_native_link_flags: $pkg has no cc-link-flags entry — layout changed?" >&2
    exit 1
  fi

  sed -i.bak "s|\"cc-link-flags\": \"[^\"]*\"|\"cc-link-flags\": \"$FLAGS\"|g" "$pkg"
  if ! grep -qF "\"cc-link-flags\": \"$FLAGS\"" "$pkg"; then
    echo "configure_native_link_flags: failed to rewrite cc-link-flags in $pkg" >&2
    exit 1
  fi

  if [ -n "$STUB_CFLAGS" ]; then
    if grep -q '"stub-cc-flags":' "$pkg"; then
      sed -i.bak "s|\"stub-cc-flags\": \"[^\"]*\"|\"stub-cc-flags\": \"$STUB_CFLAGS\"|g" "$pkg"
    else
      sed -i.bak "s|\"cc-link-flags\": \"$FLAGS\"|\"cc-link-flags\": \"$FLAGS\", \"stub-cc-flags\": \"$STUB_CFLAGS\"|g" "$pkg"
    fi
    if ! grep -qF "\"stub-cc-flags\": \"$STUB_CFLAGS\"" "$pkg"; then
      echo "configure_native_link_flags: failed to set stub-cc-flags in $pkg" >&2
      exit 1
    fi
  else
    # Strip any stub-cc-flags left over from a previous Windows run so the
    # script is idempotent across OS switches (only matters for local dev;
    # CI runners are ephemeral).
    sed -i.bak 's|, "stub-cc-flags": "[^"]*"||g' "$pkg"
    sed -i.bak 's|"stub-cc-flags": "[^"]*", ||g' "$pkg"
  fi

  rm -f "$pkg.bak"
  matched=$((matched + 1))
done

if [ "$matched" -eq 0 ]; then
  echo "configure_native_link_flags: no moon.pkg was rewritten — run \`moon update\` first?" >&2
  exit 1
fi

echo "configure_native_link_flags: rewrote $matched moon.pkg file(s)"
echo "  cc-link-flags: $FLAGS"
if [ -n "$STUB_CFLAGS" ]; then
  echo "  stub-cc-flags: $STUB_CFLAGS"
fi
