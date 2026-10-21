#!/usr/bin/env bash
# Opens the pose editor (pose_editor.gd) on its own, as F3 does from the
# game. GECKO_POSE=name opens that animation instead of wake.
#
#   tools/pose_editor.sh                 the wake-up animation
#   GECKO_POSE=stretch tools/pose_editor.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/.local/bin/godot}"
exec "$GODOT" --path . res://pose_editor.tscn "$@"
