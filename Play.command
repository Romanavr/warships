#!/bin/zsh
set -eu
PROJECT_DIR="${0:A:h}"
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
if [[ ! -x "$GODOT_BIN" ]]; then
  print "Godot was not found in /Applications. Install Godot, then open project.godot."
  exit 1
fi
exec "$GODOT_BIN" --path "$PROJECT_DIR" -- --start-paused
