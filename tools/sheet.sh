#!/usr/bin/env bash
# A contact sheet of the frames around one physics tick of a suite run,
# cropped tight round the gecko and shown at 2x, one frame per tick.
#
#   tools/sheet.sh <scene>:<script> <tick> [span=12] [out.png]
#
# Uses the recording under frames/<scene>/<script>/ and records it first
# (FRAMES=1 tools/suite.sh) when there is none. The recording's own
# trace.log maps a tick to its frame and screen position.
set -euo pipefail
cd "$(dirname "$0")/.."

spec="$1"; tick="$2"; span="${3:-12}"
dir="frames/${spec/:/\/}"
out="${4:-$dir/sheet_$tick.png}"
if ! ls "$dir"/f*.png >/dev/null 2>&1; then
  echo "no frames in $dir, recording $spec"
  FRAMES=1 tools/suite.sh "^$spec\$" > /dev/null
fi

tmp=$(mktemp -d)
n=0
for t in $(seq $((tick - span)) $((tick + span))); do
  read -r frame sx sy < <(awk -v t="$t" '$1 ~ /^F/ && $4 == t {print substr($1, 2), $2, $3; exit}' "$dir/trace.log")
  [[ -z "${frame:-}" ]] && continue
  f="$dir/$(printf 'f%08d.png' "$frame")"
  [[ -f "$f" ]] || continue
  x=$((sx - 120)); y=$((sy - 68)); [[ $x -lt 0 ]] && x=0; [[ $y -lt 0 ]] && y=0
  convert "$f" -crop 240x136+$x+$y +repage -filter point -resize 200% \
    -gravity north -pointsize 14 -fill white -annotate +0+2 "t$t" "$tmp/$(printf '%04d' $n).png"
  n=$((n + 1))
done
[[ $n -gt 0 ]] || { echo "no frames found for ticks around $tick"; exit 1; }
montage "$tmp"/*.png -tile 5x -geometry +3+3 -background '#222' "$out"
rm -rf "$tmp"
echo "$out"
