#!/usr/bin/env bash
# Install the MoonBit toolchain pinned by scripts/moon-version.
#
# scripts/moon-version is the moonc version without a leading "v":
#   0.10.18+6c83a7f62
# which is what `moonc -v` reports as `v0.10.18+6c83a7f62`.
#
# The official installers accept that string (unix.sh via MOONBIT_INSTALL_VERSION
# or argv; powershell.ps1 via MOONBIT_INSTALL_VERSION only) and request:
#   https://cli.moonbitlang.com/binaries/<ver with + as %2B>/moonbit-<target>
#   https://cli.moonbitlang.com/cores/core-<ver with + as %2B>.{tar.gz,zip}
# This script downloads that exact toolchain archive, checks it against
# scripts/moon-sha256.txt, then runs the official installer with the same
# version. Binaries are not mirrored. A checksum or moonc version mismatch
# exits non-zero. An already-installed toolchain still has its moonc version
# checked (CI cache hits included) and is reinstalled when it does not match.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN="$(tr -d '[:space:]' < "$ROOT/scripts/moon-version")"
SHA_FILE="$ROOT/scripts/moon-sha256.txt"

if [ -z "$PIN" ]; then
  echo "install_moon: scripts/moon-version is empty" >&2
  exit 1
fi
if ! printf '%s' "$PIN" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9A-Fa-f]+$'; then
  echo "install_moon: scripts/moon-version must be X.Y.Z+hash (moonc version), got '${PIN}'" >&2
  exit 1
fi
if [ ! -f "$SHA_FILE" ]; then
  echo "install_moon: missing ${SHA_FILE}" >&2
  exit 1
fi

archive_name() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Linux)
      case "$arch" in
        x86_64) printf '%s\n' "moonbit-linux-x86_64.tar.gz" ;;
        aarch64 | arm64) printf '%s\n' "moonbit-linux-aarch64.tar.gz" ;;
        *)
          echo "install_moon: unsupported Linux arch: ${arch}" >&2
          exit 1
          ;;
      esac
      ;;
    Darwin)
      case "$arch" in
        arm64) printf '%s\n' "moonbit-darwin-aarch64.tar.gz" ;;
        *)
          echo "install_moon: unsupported macOS arch: ${arch} (CI uses arm64 / darwin-aarch64)" >&2
          exit 1
          ;;
      esac
      ;;
    MINGW* | MSYS* | CYGWIN*)
      # powershell.ps1 always fetches the x86_64 zip, including on ARM64 Windows.
      printf '%s\n' "moonbit-windows-x86_64.zip"
      ;;
    *)
      echo "install_moon: unsupported OS: ${os}" >&2
      exit 1
      ;;
  esac
}

is_windows() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

moon_home_dir() {
  if [ -n "${MOON_HOME:-}" ]; then
    printf '%s\n' "$MOON_HOME"
    return
  fi
  printf '%s\n' "${HOME}/.moon"
}

moonc_path() {
  local d
  for d in "$(moon_home_dir)" "${HOME}/.moon" "${USERPROFILE:-}/.moon"; do
    [ -n "$d" ] || continue
    if [ -x "${d}/bin/moonc" ]; then
      printf '%s\n' "${d}/bin/moonc"
      return 0
    fi
    if [ -x "${d}/bin/moonc.exe" ]; then
      printf '%s\n' "${d}/bin/moonc.exe"
      return 0
    fi
  done
  return 1
}

# moonc -v prints "v0.10.18+6c83a7f62 (2026-10-28)". The pin omits the leading v.
version_matches() {
  local bin="$1"
  local got token
  got="$("$bin" -v 2>/dev/null | head -n 1 || true)"
  token="${got%% *}"
  if [ "$token" = "v${PIN}" ] || [ "$token" = "$PIN" ]; then
    printf '%s\n' "$got"
    return 0
  fi
  printf '%s\n' "$got"
  return 1
}

file_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print tolower($1)}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print tolower($1)}'
    return
  fi
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '$file').Hash.ToLower()"
    return
  fi
  echo "install_moon: need sha256sum, shasum, or powershell.exe to verify downloads" >&2
  exit 1
}

pinned_url() {
  local archive="$1"
  local enc
  enc="${PIN//+/%2B}"
  printf '%s\n' "https://cli.moonbitlang.com/binaries/${enc}/${archive}"
}

download_and_verify() {
  local archive url tmp expected got
  archive="$(archive_name)"
  url="$(pinned_url "$archive")"
  expected="$(awk -v name="$archive" '$2 == name { print tolower($1); exit }' "$SHA_FILE")"
  if [ -z "$expected" ]; then
    echo "install_moon: no sha256 recorded for ${archive} in ${SHA_FILE}" >&2
    exit 1
  fi
  tmp="$(mktemp)"
  echo "install_moon: downloading ${url}"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
    rm -f "$tmp"
    echo "install_moon: failed to download pinned toolchain: ${url}" >&2
    exit 1
  fi
  got="$(file_sha256 "$tmp")"
  rm -f "$tmp"
  if [ "$got" != "$expected" ]; then
    echo "install_moon: sha256 mismatch for ${url}" >&2
    echo "install_moon: expected ${expected}" >&2
    echo "install_moon: got      ${got}" >&2
    exit 1
  fi
  echo "install_moon: sha256 ok (${archive})"
}

install_pinned() {
  export MOONBIT_INSTALL_VERSION="$PIN"
  if is_windows; then
    if ! command -v powershell.exe >/dev/null 2>&1; then
      echo "install_moon: powershell.exe is required on Windows" >&2
      exit 1
    fi
    # Single-quoted PIN so '+' is not expanded. The installer percent-encodes it.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "\$env:MOONBIT_INSTALL_VERSION='${PIN}'; Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; irm https://cli.moonbitlang.com/install/powershell.ps1 | iex"
  else
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
  fi
}

if BIN="$(moonc_path)"; then
  if GOT="$(version_matches "$BIN")"; then
    echo "install_moon: ${GOT} matches pin ${PIN}"
    exit 0
  fi
  echo "install_moon: installed moonc '${GOT:-unknown}' does not match pin ${PIN}; reinstalling" >&2
fi

download_and_verify
install_pinned

if ! BIN="$(moonc_path)"; then
  echo "install_moon: moonc not found after install (looked in $(moon_home_dir)/bin)" >&2
  exit 1
fi
if ! GOT="$(version_matches "$BIN")"; then
  echo "install_moon: moonc version '${GOT:-unknown}' does not match pin ${PIN}" >&2
  exit 1
fi
echo "install_moon: ${GOT}"
