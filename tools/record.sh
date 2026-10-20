#!/usr/bin/env bash
# Records one scene or station in the particle world, the way
# FRAMES=1 tools/suite.sh records the bitmap world: 60 fps frames (one
# per physics tick) and their trace under frames/<scene>/<script>/, on
# a virtual display with software Vulkan so no window opens (ONSCREEN=1
# uses the real display and GPU). For the stations that need loose
# lumps (levels/clutch.json, sim_only), which the headless suite skips.
#
#   tools/record.sh <scene>:<script>      then tools/sheet.sh, tools/flicker.py
#   python3 -I tools/analyze.py frames    scores whatever frames/ holds
set -euo pipefail
cd "$(dirname "$0")/.."

spec="$1"
dir="frames/${spec/:/\/}"
mkdir -p "$dir"
# Godot would otherwise import every recorded frame as a texture.
touch frames/.gdignore
rm -f "$dir"/f*.png "$dir"/f*.png.import
export GODOT="${GODOT:-$HOME/.local/bin/godot}"
if [[ "${ONSCREEN:-0}" == 1 ]]; then
  GECKO_SCENE="$spec" GECKO_TRACE=1 GECKO_SEED=1 \
    timeout 900 "$GODOT" --audio-driver Dummy --path . --write-movie "$dir/f.png" --fixed-fps 60 --disable-vsync > "$dir/trace.log" 2>&1 || true
else
  VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json GECKO_SCENE="$spec" GECKO_TRACE=1 GECKO_SEED=1 \
    timeout 900 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --display-driver x11 --rendering-driver vulkan --audio-driver Dummy \
    --path . --write-movie "$dir/f.png" --fixed-fps 60 --disable-vsync > "$dir/trace.log" 2>&1 || true
fi
echo "$spec: $(grep -c '^t' "$dir/trace.log") ticks, $(ls "$dir"/f*.png 2>/dev/null | wc -l) frames"
