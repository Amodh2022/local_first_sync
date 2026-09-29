#!/usr/bin/env bash
# Publishes one adapter from packages/ to pub.dev.
#
# Why this script exists: pub applies ignore files from parent directories of
# the git repository to a nested package, and the root .pubignore excludes
# packages/ so core's archive stays clean. Publishing an adapter in place
# would therefore hide its own files. Instead, copy it to a temp directory
# outside the repo and publish from there.
#
# Usage: tool/publish_adapter.sh <package-name> [--dry-run]
#
# A real publish drops pubspec_overrides.yaml, so the adapter resolves core
# from pub.dev. Publish the core version it depends on first. A dry run keeps
# the override, pointed at this checkout, so it works before core is published.
set -euo pipefail

name="${1:?usage: tool/publish_adapter.sh <package-name> [--dry-run]}"
mode="${2:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/packages/$name"
[[ -f "$src/pubspec.yaml" ]] || { echo "no package at $src" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
dest="$tmp/$name"
mkdir -p "$dest"
# Copy only what git tracks or would track (skips .dart_tool/, build/, etc.).
(cd "$src" && git ls-files --cached --others --exclude-standard -z . |
  xargs -0 -I{} cp --parents {} "$dest/")

if [[ "$mode" == "--dry-run" ]]; then
  printf 'dependency_overrides:\n  local_first_sync:\n    path: %s\n' "$root" \
    > "$dest/pubspec_overrides.yaml"
  (cd "$dest" && dart pub get >/dev/null && dart pub publish --dry-run)
else
  rm -f "$dest/pubspec_overrides.yaml"
  (cd "$dest" && dart pub get && dart pub publish)
fi
