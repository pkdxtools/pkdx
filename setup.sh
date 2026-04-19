#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="pkdxtools/pkdx"
LEGACY_REPO="ushironoko/pkdx"
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

echo "=== pkdx setup ==="
echo ""

# --- Step 0: Remote configuration (fork detection + legacy URL migration) ---
UPSTREAM_REPO="pkdxtools/pkdx"
ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"

echo "[0/4] Remote configuration..."

# Migrate legacy upstream URL (ushironoko/pkdx -> pkdxtools/pkdx) in place.
# Redirects keep fetch working, but we want the authoritative name stored.
if git -C "$REPO_ROOT" remote get-url upstream &>/dev/null; then
  CURRENT_UPSTREAM_URL="$(git -C "$REPO_ROOT" remote get-url upstream)"
  if echo "$CURRENT_UPSTREAM_URL" | grep -q "$LEGACY_REPO"; then
    NEW_UPSTREAM_URL="$(echo "$CURRENT_UPSTREAM_URL" | sed "s|$LEGACY_REPO|$UPSTREAM_REPO|")"
    git -C "$REPO_ROOT" remote set-url upstream "$NEW_UPSTREAM_URL"
    echo "  Migrated upstream URL: $LEGACY_REPO -> $UPSTREAM_REPO"
  fi
fi

if echo "$ORIGIN_URL" | grep -qE "($UPSTREAM_REPO|$LEGACY_REPO)"; then
  # origin is the upstream repo itself (clone setup)
  echo "  Clone setup detected. No additional remote needed."
else
  # origin is a fork
  if git -C "$REPO_ROOT" remote get-url upstream &>/dev/null; then
    echo "  upstream remote already configured."
  else
    git -C "$REPO_ROOT" remote add upstream "https://github.com/$UPSTREAM_REPO.git"
    echo "  Added upstream remote: https://github.com/$UPSTREAM_REPO.git"
  fi
fi
echo ""

# --- Step 1: pokedex submodule ---
echo "[1/5] Initializing pokedex submodule..."
if [ ! -d "$REPO_ROOT/pokedex/.git" ] && [ ! -f "$REPO_ROOT/pokedex/.git" ]; then
  git -C "$REPO_ROOT" submodule update --init
  echo "  Done."
else
  echo "  Already initialized."
fi

# --- Step 2: pokedex.db ---
echo "[2/5] Generating pokedex.db..."
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

# --- Step 2.7: BLAS dependency (for nash / select / meta-divergence) ---
# nash/select/meta-divergence 系サブコマンドは numbt / mizchi/blas 経由で BLAS
# に依存する。OS 別に利用可否を案内し、必要な環境変数を echo する。
echo "[2.7/5] BLAS dependency check..."
case "$OS_TAG" in
  darwin)
    # macOS は Accelerate.framework が標準搭載。追加インストール不要。
    echo "  macOS: Accelerate.framework is built in."
    echo "  When building tests locally, export the link flag:"
    echo "    export MOON_CC_LINK_FLAGS=\"-framework Accelerate\""
    ;;
  linux)
    # OpenBLAS + LAPACK が必要。MOON_CC_LINK_FLAGS で cc-link-flags を上書き。
    if command -v dpkg &>/dev/null && dpkg -s libopenblas-dev &>/dev/null && dpkg -s liblapack-dev &>/dev/null; then
      echo "  Linux: libopenblas-dev + liblapack-dev detected."
    elif command -v rpm &>/dev/null && rpm -q openblas-devel &>/dev/null; then
      echo "  Linux: openblas-devel detected."
    else
      echo "  Linux: BLAS/LAPACK not detected. Install one of:"
      echo "    Debian/Ubuntu: sudo apt-get install libopenblas-dev liblapack-dev"
      echo "    RHEL/Fedora:   sudo dnf install openblas-devel lapack-devel"
      echo "    (nash / select / meta-divergence will fail to build without them.)"
    fi
    echo "  When building locally, export the right link flags:"
    echo "    export MOON_CC_LINK_FLAGS=\"-lopenblas -llapack -lm\""
    ;;
  windows)
    # 現在 nash 系統は Windows 非対応。ビルドは失敗する可能性があるため警告。
    echo "  Windows: nash / select / meta-divergence subcommands are NOT supported"
    echo "    on this platform. The pre-built Windows release binary omits them;"
    echo "    local builds will fail at link time without a Windows BLAS toolchain."
    ;;
esac

# --- Step 3: pkdx binary ---
echo "[3/5] Downloading pkdx binary ($BINARY_NAME)..."

LOCAL_BUILD="$REPO_ROOT/pkdx/_build/native/release/build/src/main/main.exe"
LOCAL_BUILD_DEBUG="$REPO_ROOT/pkdx/_build/native/debug/build/src/main/main.exe"

# Detect stale local build: if any source file is newer than the binary, it's outdated
is_build_stale() {
  local bin="$1"
  [ ! -f "$bin" ] && return 1
  local newest_src
  newest_src=$(find "$REPO_ROOT/pkdx/src" -name '*.mbt' -newer "$bin" -print -quit 2>/dev/null)
  [ -n "$newest_src" ]
}

NEED_DOWNLOAD=true
if [ -f "$LOCAL_BUILD" ] && ! is_build_stale "$LOCAL_BUILD"; then
  echo "  Local build is up to date."
  NEED_DOWNLOAD=false
elif [ -f "$LOCAL_BUILD_DEBUG" ] && ! is_build_stale "$LOCAL_BUILD_DEBUG"; then
  echo "  Local build (debug) is up to date."
  NEED_DOWNLOAD=false
elif [ -f "$LOCAL_BUILD" ] || [ -f "$LOCAL_BUILD_DEBUG" ]; then
  echo "  Local build is outdated. Removing stale build..."
  rm -f "$LOCAL_BUILD" "$LOCAL_BUILD_DEBUG"
fi

if [ "$NEED_DOWNLOAD" = true ]; then
  mkdir -p "$CACHE_DIR"
  BINARY="$CACHE_DIR/$BINARY_NAME"

  # Always re-download to ensure latest release
  rm -f "$BINARY"
  {
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
  }
fi

# --- Step 3.5: pkdx_patch migrations ---
# Binary download (Step 3) precedes migrate so `bin/pkdx` is resolvable.
# 旧 Ruby 版 (pkdx_patch/apply.rb + sqlite3 gem) は pkdx バイナリ内蔵の
# SQLite3 を使う MoonBit 実装に置き換え済み。コンテナで sqlite3 gem が
# ビルドできない環境 (cc on the web 等) でも動作する。
echo "[3.5/5] Applying pkdx patches..."
if [ -f "$REPO_ROOT/pokedex/pokedex.db" ]; then
  export POKEDEX_DB="$REPO_ROOT/pokedex/pokedex.db"
  if "$REPO_ROOT/bin/pkdx" migrate --repo-root "$REPO_ROOT"; then
    :
  else
    echo "  Error: pkdx migrate failed." >&2
    exit 1
  fi
else
  echo "  Skipped (pokedex.db not found)."
fi

# --- Step 4: box directory ---
echo "[4/5] Initializing data directories..."
for dir in "$REPO_ROOT/box/teams" "$REPO_ROOT/box/pokemons" "$REPO_ROOT/box/cache"; do
  mkdir -p "$dir"
done
echo "  Done."

# --- Step 5: Codex CLI compatibility (Windows symlink repair) ---
# AGENTS.md と .agents/skills は git にシムリンクとしてコミットされている。
# Windows Git は core.symlinks=false の場合シムリンクを「リンク先パス文字列を含む通常ファイル」として
# チェックアウトしてしまうため、Codex CLI から正しく読めない。ここで検出して修復する。
echo "[5/5] Codex CLI compatibility..."
if [ "$OS_TAG" = "windows" ]; then
  cd "$REPO_ROOT"

  # AGENTS.md: 通常ファイル化されていれば hardlink で再作成
  if [ -f AGENTS.md ] && [ ! -L AGENTS.md ]; then
    content="$(cat AGENTS.md)"
    if [ "$content" = "CLAUDE.md" ]; then
      rm -f AGENTS.md
      if cmd //c "mklink /H AGENTS.md CLAUDE.md" >/dev/null 2>&1; then
        echo "  AGENTS.md: hardlinked to CLAUDE.md"
      else
        cp CLAUDE.md AGENTS.md
        echo "  AGENTS.md: copied from CLAUDE.md (mklink unavailable)"
      fi
    fi
  fi

  # .agents/skills: 通常ファイル化されていれば junction で再作成
  if [ -f .agents/skills ] && [ ! -L .agents/skills ] && [ ! -d .agents/skills ]; then
    content="$(cat .agents/skills)"
    if [ "$content" = "../.claude/skills" ]; then
      rm -f .agents/skills
      if cmd //c "mklink /J .agents\\skills .claude\\skills" >/dev/null 2>&1; then
        echo "  .agents/skills: junction to .claude/skills"
      else
        cp -r .claude/skills .agents/skills
        echo "  .agents/skills: copied from .claude/skills (mklink unavailable)"
      fi
    fi
  fi
else
  # Mac/Linux: シムリンクはそのまま動作するので何もしない
  echo "  Symlinks active (non-Windows)."
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
