#!/usr/bin/env bash
# A whole-run contact sheet of a recording: every Nth tick from start to
# end, cropped round the gecko at 2x, five per row, the tick in each
# corner. The evidence that a scene plays through cleanly.
#
#   tools/evidence.sh <scene>:<script> [every=15] [out.png]
#
# Uses the recording under frames/<scene>/<script>/ (FRAMES=1
# tools/suite.sh records one).
set -euo pipefail
cd "$(dirname "$0")/.."

spec="$1"; every="${2:-15}"
dir="frames/${spec/:/\/}"
out="${3:-docs/evidence/${spec/:/_}.png}"
[[ -f "$dir/trace.log" ]] || { echo "no recording at $dir"; exit 1; }
mkdir -p "$(dirname "$out")"

tmp=$(mktemp -d)
n=0
last=$(awk '$1 ~ /^F/ {t=$4} END {print t}' "$dir/trace.log")
for t in $(seq 1 "$every" "$last"); do
  read -r frame sx sy < <(awk -v t="$t" '$1 ~ /^F/ && $4 == t {print substr($1, 2), $2, $3; exit}' "$dir/trace.log")
  [[ -z "${frame:-}" ]] && continue
  f="$dir/$(printf 'f%08d.png' "$frame")"
  [[ -f "$f" ]] || continue
  x=$((sx - 120)); y=$((sy - 68)); [[ $x -lt 0 ]] && x=0; [[ $y -lt 0 ]] && y=0
  convert "$f" -crop 240x136+$x+$y +repage -filter point -resize 200% \
    -gravity northwest -pointsize 13 -fill white -annotate +3+2 "t$t" "$tmp/$(printf '%04d' $n).png"
  n=$((n + 1))
done
[[ $n -gt 0 ]] || { echo "no frames found"; exit 1; }
montage "$tmp"/*.png -tile 5x -geometry +2+2 -background '#222' "$tmp/sheet.png"
convert "$tmp/sheet.png" -define png:compression-level=9 "$out"
rm -rf "$tmp"
echo "$out ($n frames)"
