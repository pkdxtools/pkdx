#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="ushironoko/pokemon-builder"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pkdx"

# --- OS/Arch detection ---
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  darwin)  OS_TAG="darwin" ;;
  linux)   OS_TAG="linux" ;;
  mingw*|msys*|cygwin*) OS_TAG="windows" ;;
  *) echo "Error: Unsupported OS: $OS" >&2; exit 1 ;;
esac

case "$ARCH" in
  arm64|aarch64) ARCH_TAG="arm64" ;;
  x86_64|amd64)  ARCH_TAG="x86_64" ;;
  *) echo "Error: Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

BINARY_NAME="pkdx-${OS_TAG}-${ARCH_TAG}"
if [ "$OS_TAG" = "windows" ]; then
  BINARY_NAME="${BINARY_NAME}.exe"
fi

echo "=== pokemon-builder setup ==="
echo ""

# --- Step 1: pokedex submodule ---
echo "[1/3] Initializing pokedex submodule..."
if [ ! -d "$REPO_ROOT/pokedex/.git" ] && [ ! -f "$REPO_ROOT/pokedex/.git" ]; then
  git -C "$REPO_ROOT" submodule update --init
  echo "  Done."
else
  echo "  Already initialized."
fi

# --- Step 2: pokedex.db ---
echo "[2/3] Generating pokedex.db..."
if [ -f "$REPO_ROOT/pokedex/pokedex.db" ]; then
  echo "  Already exists."
else
  if ! command -v ruby &>/dev/null; then
    echo "  Error: ruby is required to generate pokedex.db" >&2
    echo "  Install Ruby and re-run this script." >&2
    exit 1
  fi
  (cd "$REPO_ROOT/pokedex" && ruby tools/import_db.rb)
  echo "  Done."
fi

# --- Step 3: pkdx binary ---
echo "[3/3] Downloading pkdx binary ($BINARY_NAME)..."

# Skip if local build exists
LOCAL_BUILD="$REPO_ROOT/pkdx/_build/native/release/build/src/main/main.exe"
LOCAL_BUILD_DEBUG="$REPO_ROOT/pkdx/_build/native/debug/build/src/main/main.exe"
if [ -f "$LOCAL_BUILD" ] || [ -f "$LOCAL_BUILD_DEBUG" ]; then
  echo "  Local build found. Skipping download."
else
  mkdir -p "$CACHE_DIR"
  BINARY="$CACHE_DIR/$BINARY_NAME"

  if [ -f "$BINARY" ]; then
    echo "  Already cached at $BINARY"
  else
    DOWNLOADED=false

    if command -v gh &>/dev/null; then
      if gh release download latest --repo "$REPO" --pattern "$BINARY_NAME" --dir "$CACHE_DIR" 2>/dev/null; then
        DOWNLOADED=true
      fi
    fi

    if [ "$DOWNLOADED" = false ] && command -v curl &>/dev/null; then
      RELEASE_URL=$(curl -sI "https://github.com/$REPO/releases/latest" | grep -i "^location:" | tr -d '\r' | sed 's/.*\///')
      if [ -n "$RELEASE_URL" ]; then
        URL="https://github.com/$REPO/releases/download/$RELEASE_URL/$BINARY_NAME"
        if curl -sfL "$URL" -o "$BINARY" 2>/dev/null; then
          DOWNLOADED=true
        fi
      fi
    fi

    if [ "$DOWNLOADED" = true ] && [ -f "$BINARY" ]; then
      chmod +x "$BINARY"
      echo "  Downloaded to $BINARY"
    else
      echo "  Warning: No release found. You can build locally instead:"
      echo "    cd pkdx && moon build --target native"
      echo "  (requires MoonBit toolchain: curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash)"
    fi
  fi
fi

# --- Verify ---
echo ""
echo "=== Verification ==="

if [ -f "$REPO_ROOT/pokedex/pokedex.db" ]; then
  echo "  pokedex.db: OK"
else
  echo "  pokedex.db: MISSING"
fi

export POKEDEX_DB="$REPO_ROOT/pokedex/pokedex.db"
if "$REPO_ROOT/bin/pkdx" query "ピカチュウ" --format json >/dev/null 2>&1; then
  echo "  pkdx:       OK"
else
  echo "  pkdx:       NOT AVAILABLE (build locally or wait for a release)"
fi

echo ""
echo "Setup complete. Usage:"
echo "  export POKEDEX_DB=$REPO_ROOT/pokedex/pokedex.db"
echo "  bin/pkdx query \"ガブリアス\""
