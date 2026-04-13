#!/bin/sh
set -eu
VERSION=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' pkdx/moon.mod.json)
if [ -z "$VERSION" ]; then
  echo "Error: failed to read version from pkdx/moon.mod.json" >&2
  exit 1
fi
TARGET="pkdx/src/main/version.mbt"
echo "///|" > "$TARGET"
echo "let pkdx_version : String = \"$VERSION\"" >> "$TARGET"
echo "synced version: $VERSION"
