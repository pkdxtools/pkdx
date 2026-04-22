#!/usr/bin/env bash
set -euo pipefail

# Installs the bun runtime used by `site/` (Astro dev server / bun:test / smoke).
# setup.sh omits this intentionally; invoke this script when a skill that needs a
# local dev server (e.g. blog skill's preview) reports that bun is missing.
#
# Version is pinned to match `site/package.json` @types/bun (SSoT). Override by
# exporting BUN_VERSION=1.x.y before running.

BUN_VERSION="${BUN_VERSION:-1.3.12}"
BUN_INSTALL_DIR="${BUN_INSTALL:-$HOME/.bun}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  darwin|linux) ;;
  mingw*|msys*|cygwin*)
    echo "Error: native Windows is not supported. Use WSL2 (README 対応環境)." >&2
    exit 1
    ;;
  *) echo "Error: Unsupported OS: $OS" >&2; exit 1 ;;
esac

echo "=== install_bun ==="
echo "  target version: $BUN_VERSION"
echo "  install dir:    $BUN_INSTALL_DIR"
echo ""

# --- Step 1: version check ---
# bun on PATH satisfies launch.json's `runtimeExecutable: "bun"` regardless of
# location (mise, homebrew, ~/.bun). Only reinstall on version mismatch.
if command -v bun &>/dev/null; then
  CURRENT_VERSION="$(bun --version 2>/dev/null || echo 'unknown')"
  if [ "$CURRENT_VERSION" = "$BUN_VERSION" ]; then
    echo "  bun $CURRENT_VERSION is already installed ($(command -v bun))."
    echo "  Nothing to do."
    exit 0
  fi
  echo "  bun $CURRENT_VERSION detected at $(command -v bun)."
  echo "  Target is $BUN_VERSION. Proceeding with pinned install to $BUN_INSTALL_DIR."
  echo ""
fi

# --- Step 2: install via official installer with pinned version ---
if ! command -v curl &>/dev/null; then
  echo "Error: curl is required to download bun." >&2
  exit 1
fi

echo "[1/2] Downloading bun $BUN_VERSION..."
BUN_INSTALL="$BUN_INSTALL_DIR" curl -fsSL https://bun.com/install | bash -s "bun-v$BUN_VERSION"
echo ""

# --- Step 3: verify + PATH guidance ---
echo "[2/2] Verifying..."
INSTALLED_BIN="$BUN_INSTALL_DIR/bin/bun"
if [ ! -x "$INSTALLED_BIN" ]; then
  echo "Error: $INSTALLED_BIN was not created. Installation failed." >&2
  exit 1
fi

INSTALLED_VERSION="$("$INSTALLED_BIN" --version 2>/dev/null || echo 'unknown')"
echo "  installed: $INSTALLED_BIN (v$INSTALLED_VERSION)"
echo ""

# PATH guidance — the official installer appends export lines to shell rc files,
# but that only takes effect in a new shell. Tell the user how to use it now.
if ! command -v bun &>/dev/null || [ "$(command -v bun)" != "$INSTALLED_BIN" ]; then
  cat <<EOF
Next step: add bun to PATH for the current shell.

  export BUN_INSTALL="$BUN_INSTALL_DIR"
  export PATH="\$BUN_INSTALL/bin:\$PATH"

The official installer has already written equivalent lines to your shell rc
(~/.zshrc / ~/.bashrc), so new shells will pick it up automatically.
EOF
else
  echo "bun is on PATH: $(command -v bun)"
fi
