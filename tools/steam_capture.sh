#!/usr/bin/env bash
# Records a play session at 1920x1080 for Steam screenshots and the trailer.
#
# The game's window is 1920x1000; Steam wants 16:9 screenshots of at least
# 1920x1080. A temporary override.cfg sets the viewport to 1080 for this run
# only. Godot's movie mode writes every frame as a PNG plus a WAV, so play as
# usual and pick frames afterwards. The game runs slower than real time while
# it writes frames, but the recording plays back at full speed.
#
#   tools/steam_capture.sh                    # play cave 5, quit the window to stop
#   GECKO_LIGHT=1 tools/steam_capture.sh      # with the light pass on
#   tools/steam_capture.sh --quit-after 1800  # stop by itself after 60 s
#
# The controls hint covers the top for the first 10 s: skip those frames.
# Output: steam/capture/<time>/f00000000.png ..., f.wav, and clip.mp4 when
# ffmpeg is installed. About 11 MB a second of play: delete takes you do not keep.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$HOME/.local/bin/godot}"
OUT="steam/capture/$(date +%Y%m%d-%H%M%S)"

if [[ -e override.cfg ]]; then
    echo "override.cfg already exists. Move it away first, this script writes its own." >&2
    exit 1
fi
mkdir -p "$OUT"
printf '[display]\n\nwindow/size/viewport_height=1080\n' > override.cfg
trap 'rm -f override.cfg' EXIT

GECKO_SOUND="${GECKO_SOUND:-1}" "$GODOT" --path . --write-movie "$OUT/f.png" --fixed-fps 30 "$@" || true

n=$(find "$OUT" -name 'f*.png' | wc -l)
echo "$n frames in $OUT"
if (( n > 0 )) && command -v ffmpeg >/dev/null 2>&1; then
    audio=()
    [[ -f "$OUT/f.wav" ]] && audio=(-i "$OUT/f.wav" -c:a aac -b:a 192k)
    ffmpeg -loglevel error -y -framerate 30 -i "$OUT/f%08d.png" "${audio[@]}" \
        -c:v libx264 -crf 16 -preset slow -pix_fmt yuv420p "$OUT/clip.mp4"
    echo "clip: $OUT/clip.mp4"
fi
echo "Copy the frames you want to steam/screenshots/ (at least 5, gameplay only)."
