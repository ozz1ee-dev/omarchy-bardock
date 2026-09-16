#!/bin/bash
# Link the plugin into the shell's plugin directory, and optionally put it on
# the bar at the screen corner.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin="$here"
target="$HOME/.config/omarchy/plugins/ozz1ee.bardock"
with_bar=0
[[ ${1:-} == "--bar" ]] && with_bar=1

[[ -f $plugin/manifest.json ]] || { echo "no plugin at $plugin" >&2; exit 1; }

mkdir -p "$(dirname "$target")"
ln -sfn "$plugin" "$target"
echo "linked $target -> $plugin"

omarchy plugin validate "$target"
echo "manifest is valid"

if (( with_bar )); then
  omarchy bar put ozz1ee.bardock --section right --index 99
  omarchy bar move ozz1ee.bardock --section right --index 99 2>/dev/null || true
  omarchy restart shell
  sleep 6
  omarchy-shell ozz1ee.bardock state >/dev/null && echo "the bar is up with the dock in the corner"
fi
