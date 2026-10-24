#!/usr/bin/env bash
# The packs' art in the game (tests/packs_test.gd): every case in its own
# run of the particle world on levels/packs_lab.json, on a virtual
# display with the GPU's Vulkan driver (PACK_ICD=path picks another),
# three at a time. Each run's log is runs/packs/<case>.txt. Exits 0 when
# every case prints PACK TEST OK.
#
#   tools/packs_test.sh [case-regex]
#   tools/packs_test.sh shots     a frame of each band, runs/packs/shot_*.png, for a look
set -uo pipefail
cd "$(dirname "$0")/.."

export GODOT="${GODOT:-$HOME/.local/bin/godot}"
export PACK_ICD="${PACK_ICD:-/usr/share/vulkan/icd.d/nvidia_icd.json}"
filter="${1:-.}"
all="bands rig plant_sway strand support worm jelly water_tint"
cases="$all"
[[ "$filter" == shots ]] && cases="shots"
mkdir -p runs/packs
touch runs/.gdignore

run_case() {
  local c="$1"
  local log="runs/packs/$c.txt"
  VK_ICD_FILENAMES="$PACK_ICD" PACK_CASE="$c" GECKO_PROBE=res://tests/packs_test.gd GECKO_SCENE=packs_lab:hold GECKO_SEED=1 GECKO_STAY=1 \
    timeout 300 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --display-driver x11 --rendering-driver vulkan --audio-driver Dummy \
    --path . --fixed-fps 60 --disable-vsync > "$log" 2>&1
  if grep -q '^PACK TEST OK' "$log"; then echo "$c: ok"; else echo "$c: FAILS"; fi
}
export -f run_case

echo $cases | tr ' ' '\n' | grep -E "$filter" | xargs -P "${JOBS:-3}" -I{} bash -c 'run_case "$@"' _ {}
fails=0
for c in $cases; do
  [[ "$c" =~ $filter ]] || continue
  log="runs/packs/$c.txt"
  grep -E '^PACK ' "$log" | grep -v 'TEST' | sed "s/^/$c: /"
  grep -E 'SCRIPT ERROR' "$log" | head -3 | sed "s/^/$c: /"
  grep -q '^PACK TEST OK' "$log" || fails=$((fails + 1))
done
echo "packs: $fails failing"
[[ $fails == 0 ]]
