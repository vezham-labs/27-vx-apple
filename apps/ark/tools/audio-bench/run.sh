#!/bin/sh
# Audio Bench: see README.md. Builds Ark Audio Lab first if it isn't there.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
[ -x "$HOME/Developer/Ark/derived/audio-lab/Ark Audio Lab.app/Contents/MacOS/audiolab" ] || "$HERE/../call-audio/build.sh"
exec node "$HERE/bench.mjs" "$@"
