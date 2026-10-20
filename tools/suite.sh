#!/usr/bin/env bash
# Runs the movement suite: every scene and script in tests/scenes.json,
# headless on the bitmap world with the trace on, each to
# runs/<scene>/<script>/trace.log, then tools/analyze.py over the lot.
#
#   tools/suite.sh [filter-regex]     e.g. tools/suite.sh 'gap_|slot_'
#   FRAMES=1 tools/suite.sh gap_32    records 60 fps frames (one per
#                                     physics tick) with their own trace
#                                     under frames/<scene>/<script>/, on
#                                     a virtual display (xvfb-run, with
#                                     software Vulkan: the same renderer
#                                     as the game, pixel for pixel) so
#                                     no window opens; ONSCREEN=1 uses
#                                     the real display and GPU instead
#   JOBS=n OUT=dir BASELINE=file.json
set -euo pipefail
cd "$(dirname "$0")/.."

filter="${1:-.}"
export FRAMES="${FRAMES:-0}"
# Recordings live apart from the headless traces, so a later headless
# run never overwrites the trace that maps a recording's frames to ticks.
if [[ "$FRAMES" == 1 ]]; then
  export OUT="${OUT:-frames}"
  jobs="${JOBS:-1}"
else
  export OUT="${OUT:-runs}"
  jobs="${JOBS:-6}"
fi
export GODOT="${GODOT:-$HOME/.local/bin/godot}"
export ONSCREEN="${ONSCREEN:-0}"

run_one() {
  local spec="$1"
  local dir="$OUT/${spec/:/\/}"
  mkdir -p "$dir"
  if [[ "$FRAMES" == 1 && "$ONSCREEN" != 1 ]] && command -v xvfb-run >/dev/null; then
    rm -f "$dir"/f*.png
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json GECKO_WORLD=bitmap GECKO_SCENE="$spec" GECKO_TRACE=1 GECKO_SEED=1 \
      timeout 600 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --display-driver x11 --rendering-driver vulkan \
      --path . --write-movie "$dir/f.png" --fixed-fps 60 --disable-vsync > "$dir/trace.log" 2>&1 || true
  elif [[ "$FRAMES" == 1 ]]; then
    rm -f "$dir"/f*.png
    GECKO_WORLD=bitmap GECKO_SCENE="$spec" GECKO_TRACE=1 GECKO_SEED=1 \
      timeout 600 "$GODOT" --path . --write-movie "$dir/f.png" --fixed-fps 60 --disable-vsync > "$dir/trace.log" 2>&1 || true
  else
    GECKO_WORLD=bitmap GECKO_SCENE="$spec" GECKO_TRACE=1 GECKO_SEED=1 \
      timeout 300 "$GODOT" --headless --path . --fixed-fps 60 > "$dir/trace.log" 2>&1 || true
  fi
  echo "$spec: $(grep -c '^t' "$dir/trace.log") ticks"
}
export -f run_one

python3 -I tools/analyze.py --list | grep -E "$filter" | xargs -P "$jobs" -I{} bash -c 'run_one "$@"' _ {}

if [[ -n "${BASELINE:-}" ]]; then
  python3 -I tools/analyze.py "$OUT" --baseline "$BASELINE"
else
  python3 -I tools/analyze.py "$OUT"
fi
