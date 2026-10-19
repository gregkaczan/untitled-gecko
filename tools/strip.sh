#!/usr/bin/env bash
# Builds a contact sheet of movie-mode frames cropped around the gecko.
#
#   GECKO_DEMO=tunnel GECKO_TRACE=1 godot --path . --write-movie frames/f.png \
#       --fixed-fps 30 --quit-after 420 | grep '^F' > frames/trace.log
#   (cd frames && ../tools/strip.sh trace.log ../sheet.png 6 $(seq 9 6 114))
#
# strip.sh <log> <out.png> <cols> <frame...>: the log holds one "F<n> <x> <y>"
# line per frame with the gecko's screen position, which the trace prints.
log=$1; out=$2; cols=$3; shift 3
tmp=$(mktemp -d)
n=0
for i in "$@"; do
  read -r sx sy < <(grep "^F$i " "$log" | head -1 | awk '{print $2, $3}')
  [ -z "$sx" ] && continue
  x=$((sx - 320)); y=$((sy - 180)); [ $x -lt 0 ] && x=0; [ $y -lt 0 ] && y=0
  [ $x -gt 1280 ] && x=1280; [ $y -gt 720 ] && y=720
  convert "$(printf 'f%08d.png' $i)" -crop 640x360+$x+$y +repage "$tmp/$(printf '%03d' $n).png"
  n=$((n+1))
done
montage "$tmp"/*.png -tile ${cols}x -geometry 400x225+2+2 -background '#222' "$out"
rm -rf "$tmp"
