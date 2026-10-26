#!/bin/zsh
# Screenshot of the demo window with one button pulled.
# usage: Scripts/shot.sh TARGET DX DY OUT.png [demo flags, e.g. --merge --style clear --release]
#   TARGET = attach|pill|mic|pin|search     DX DY = cursor offset in points (y up)
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET=${1:-mic}; DX=${2:-0}; DY=${3:-0}; OUT=${4:-shot.png}; shift 4 || true
READY=$(mktemp -t jellyglass-ready); rm -f "$READY"

swift build -c release >/dev/null
.build/release/JellyGlassDemo --pull "$TARGET" "$DX" "$DY" --ready-file "$READY" "$@" &
PID=$!
for _ in {1..120}; do [[ -s "$READY" ]] && break; sleep 0.1; done
[[ -s "$READY" ]] || { kill $PID 2>/dev/null; echo "demo never became ready" >&2; exit 1; }
/usr/sbin/screencapture -x -o -l "$(cat "$READY")" "$OUT"
kill $PID 2>/dev/null || true
rm -f "$READY"
echo "saved $OUT"
