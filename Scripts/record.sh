#!/bin/zsh
# Records the scripted showreel of the demo window into docs/media (mov -> mp4 + gif).
# Needs: macOS 26, screen-recording permission for the terminal, ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release >/dev/null
STAGE=$(mktemp -t jg-stage); DUR=$(mktemp -t jg-dur); rm -f "$STAGE" "$DUR"
mkdir -p docs/media

.build/release/JellyGlassDemo --showreel --still-backdrop --stage-file "$STAGE" --duration-file "$DUR" "$@" &
PID=$!
for _ in {1..100}; do [[ -s "$STAGE" && -s "$DUR" ]] && break; sleep 0.1; done
read X Y W H < "$STAGE"; SECONDS_TO_RECORD=$(printf '%.0f' "$(cat "$DUR")")
sleep 0.4
/usr/sbin/screencapture -v -x -V "$SECONDS_TO_RECORD" -R"$X,$Y,$W,$H" docs/media/showreel.mov
kill $PID 2>/dev/null || true

ffmpeg -v error -y -i docs/media/showreel.mov -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart docs/media/showreel.mp4
ffmpeg -v error -y -i docs/media/showreel.mov -vf "fps=20,scale=820:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" docs/media/showreel.gif
rm -f docs/media/showreel.mov
ls -la docs/media
