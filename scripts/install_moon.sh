#!/usr/bin/env bash
# Install the MoonBit toolchain pinned by scripts/moon-version.
#
# cli.moonbitlang.com only publishes channel directories (latest / nightly /
# pre-release). Dated paths such as binaries/0.1.YYYYMMDD/ return 403, so the
# installer cannot be given the pin as MOONBIT_INSTALL_VERSION. This script
# installs the `latest` channel and then refuses to continue unless
# `moon version` reports the pin. CI and local setup both call this script,
# so a toolchain drift fails closed until scripts/moon-version is updated.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN="$(tr -d '[:space:]' < "$ROOT/scripts/moon-version")"
if [ -z "$PIN" ]; then
  echo "install_moon: scripts/moon-version is empty" >&2
  exit 1
fi

# A leftover env var would make the official installer request a dated URL.
unset MOONBIT_INSTALL_VERSION || true

moon_bin() {
  if [ -n "${USERPROFILE:-}" ] && [ -x "${USERPROFILE}/.moon/bin/moon.exe" ]; then
    printf '%s\n' "${USERPROFILE}/.moon/bin/moon.exe"
    return
  fi
  if [ -x "${HOME}/.moon/bin/moon" ]; then
    printf '%s\n' "${HOME}/.moon/bin/moon"
    return
  fi
  if [ -x "${HOME}/.moon/bin/moon.exe" ]; then
    printf '%s\n' "${HOME}/.moon/bin/moon.exe"
    return
  fi
  printf '\n'
}

version_matches() {
  local bin="$1"
  local got
  got="$("$bin" version 2>/dev/null | head -n 1 || true)"
  case "$got" in
    "moon ${PIN}"|"moon ${PIN} "*)
      return 0
      ;;
    *)
      printf '%s\n' "$got"
      return 1
      ;;
  esac
}

install_latest() {
  local os
  os="$(uname -s)"
  case "$os" in
    MINGW*|MSYS*|CYGWIN*)
      if ! command -v powershell.exe >/dev/null 2>&1; then
        echo "install_moon: powershell.exe is required on Windows" >&2
        exit 1
      fi
      powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item Env:MOONBIT_INSTALL_VERSION -ErrorAction SilentlyContinue; Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; irm https://cli.moonbitlang.com/install/powershell.ps1 | iex"
      ;;
    Darwin|Linux)
      curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
      ;;
    *)
      echo "install_moon: unsupported OS: $os" >&2
      exit 1
      ;;
  esac
}

BIN="$(moon_bin)"
if [ -n "$BIN" ] && version_matches "$BIN" >/dev/null; then
  echo "install_moon: $($BIN version | head -n 1) matches pin ${PIN}"
  exit 0
fi

echo "install_moon: installing MoonBit latest (pin ${PIN})"
install_latest

BIN="$(moon_bin)"
if [ -z "$BIN" ]; then
  echo "install_moon: moon binary not found after install" >&2
  exit 1
fi

if ! GOT="$(version_matches "$BIN")"; then
  echo "install_moon: latest toolchain is '${GOT:-unknown}', pin is moon ${PIN}" >&2
  echo "install_moon: update scripts/moon-version after checking the new toolchain, then rerun." >&2
  exit 1
fi

echo "install_moon: $($BIN version | head -n 1)"
