#!/usr/bin/env bash
# The chain critters' regression test (tests/critters_test.gd): every
# case in its own run of the particle world on the critters_lab scene,
# on a virtual display with the GPU's Vulkan driver (CRIT_ICD=path picks
# another; ONSCREEN=1 uses the real display), three at a time. Each
# run's log is runs/critters/<case>.txt. Exits 0 when every case prints
# CRIT TEST OK.
#
#   tools/critters_test.sh [case-regex]
#   tools/critters_test.sh shots     frames of each critter, runs/critters/shot_*.png, for a look
#   tools/critters_test.sh slime_look  the sim's render round each slime, runs/critters/cells_slime_*.png
set -uo pipefail
cd "$(dirname "$0")/.."

export GODOT="${GODOT:-$HOME/.local/bin/godot}"
export CRIT_ICD="${CRIT_ICD:-/usr/share/vulkan/icd.d/nvidia_icd.json}"
export ONSCREEN="${ONSCREEN:-0}"
filter="${1:-.}"
all="shroom_rest shroom_land shroom_boost shroom_chew shroom_cut shroom_rock decor vine_swing vine_cut vine_climb vine_catch slime_creep slime_bite slime_wade longslug perf"
# shots and slime_look are not part of the test: only when asked for by name.
cases="$all"
[[ "$filter" == shots || "$filter" == slime_look ]] && cases="$filter"
mkdir -p runs/critters
touch runs/.gdignore

run_case() {
  local c="$1"
  local log="runs/critters/$c.txt"
  if [[ "$ONSCREEN" == 1 ]]; then
    CRIT_CASE="$c" GECKO_PROBE=res://tests/critters_test.gd GECKO_SCENE=critters_lab:hold GECKO_SEED=1 \
      timeout 300 "$GODOT" --audio-driver Dummy --path . --fixed-fps 60 --disable-vsync > "$log" 2>&1
  else
    VK_ICD_FILENAMES="$CRIT_ICD" CRIT_CASE="$c" GECKO_PROBE=res://tests/critters_test.gd GECKO_SCENE=critters_lab:hold GECKO_SEED=1 \
      timeout 300 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --display-driver x11 --rendering-driver vulkan --audio-driver Dummy \
      --path . --fixed-fps 60 --disable-vsync > "$log" 2>&1
  fi
  if grep -q '^CRIT TEST OK' "$log"; then echo "$c: ok"; else echo "$c: FAILS"; fi
}
export -f run_case

# The two perf runs alone, one after the other, after the rest: the
# sim's cost of the critters is perf's tick against perf_base's.
echo $cases | tr ' ' '\n' | grep -E "$filter" | grep -v '^perf' | xargs -P "${JOBS:-3}" -I{} bash -c 'run_case "$@"' _ {}
perf_fail=0
if echo $cases | tr ' ' '\n' | grep -E "$filter" | grep -q '^perf$'; then
  run_case perf_base
  run_case perf
  base=$(grep -oP '^CRIT perf sim \K[0-9]+' runs/critters/perf_base.txt || echo 0)
  full=$(grep -oP '^CRIT perf sim \K[0-9]+' runs/critters/perf.txt || echo 999999)
  if (( full - base < 2000 )); then echo "perf: CRIT ok   perf_sim: the sim's tick ${full} us with the critters, ${base} without"
  else echo "perf: CRIT FAIL perf_sim: the sim's tick ${full} us with the critters, ${base} without"; perf_fail=1; fi
fi
fails=0
for c in $cases; do
  [[ "$c" =~ $filter ]] || continue
  log="runs/critters/$c.txt"
  grep -E '^CRIT (FAIL|note)' "$log" | sed "s/^/$c: /"
  grep -q '^CRIT TEST OK' "$log" || { fails=$((fails + 1)); grep -q '^CRIT' "$log" || echo "$c: no CRIT lines, see $log"; }
done
fails=$((fails + perf_fail))
echo "critters: $fails failing"
[[ $fails == 0 ]]
