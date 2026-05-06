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
# version.mbt の更新だけではバイナリに反映されない。`pkdx context` の
# version_drift がローカルセッションで発火し続ける原因になるので、
# 同じワークフローの中でリビルドまで誘導する。CI ビルドに任せたい場合は
# このメッセージを無視してよい (commit すれば release バイナリが追従する)。
echo "next: cd pkdx && moon build --target native --release src/main"
