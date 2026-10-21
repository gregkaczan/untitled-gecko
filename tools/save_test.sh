#!/usr/bin/env bash
# The editor's save and load test (tests/save_test.gd) in the particle
# world, which needs a GPU: a window on a virtual display with the
# GPU's Vulkan driver (SAVE_ICD=path picks another, lvp_icd.json for
# software Vulkan at a fifth of the speed; ONSCREEN=1 uses the real
# display instead). The shots and the diff land in runs/save/, the
# whole log in runs/save/log.txt. Exits 0 on SAVE TEST OK.
#
#   tools/save_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export GODOT="${GODOT:-$HOME/.local/bin/godot}"
icd="${SAVE_ICD:-/usr/share/vulkan/icd.d/nvidia_icd.json}"
mkdir -p runs/save
touch runs/.gdignore
rm -f runs/save/*.png
if [[ "${ONSCREEN:-0}" == 1 ]]; then
  GECKO_PROBE=res://tests/save_test.gd GECKO_EDIT=1 GECKO_SEED=1 \
    timeout 900 "$GODOT" --audio-driver Dummy --path . --fixed-fps 60 --disable-vsync > runs/save/log.txt 2>&1 || true
else
  VK_ICD_FILENAMES="$icd" GECKO_PROBE=res://tests/save_test.gd GECKO_EDIT=1 GECKO_SEED=1 \
    timeout 900 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --display-driver x11 --rendering-driver vulkan --audio-driver Dummy \
    --path . --fixed-fps 60 --disable-vsync > runs/save/log.txt 2>&1 || true
fi
grep -E '^SAVE' runs/save/log.txt || { echo "no SAVE lines: see runs/save/log.txt"; exit 1; }
grep -q '^SAVE TEST OK' runs/save/log.txt
