#!/bin/sh
# Installs open-spike.sh and the camera/mic check page into ~/Developer/Ark/derived/webkit-spike, and writes the
# double-click launchers to ~/Applications (nothing is started):
#   Ark WebKit Spike.command                  for meetings: the frozen WebKit build (WebKitBuild/Release-meeting,
#                                                the 3a31ddd unit), default settings, debug dump on
#   Ark WebKit Spike (tuned).command          opt-in: the current build (WebKitBuild/Release) with the best settings
#                                                from the newest sweep of a real unit dump, if its replay was faithful
#   Ark WebKit Spike (camera & mic check).command
#                                                opens a local page that asks for the camera and mic, so the
#                                                permissions are granted before a meeting
# All start the spike through LaunchServices (open-spike.sh), so macOS asks about the camera and mic for the spike
# itself. The daily Ark is never touched.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DERIVED="$HOME/Developer/Ark/derived/webkit-spike"
DEST=${DEST:-$HOME/Applications}
mkdir -p "$DEST" "$DERIVED/preflight"
cp "$HERE/open-spike.sh" "$DERIVED/open-spike.sh" && chmod +x "$DERIVED/open-spike.sh"
cp "$HERE/preflight/index.html" "$DERIVED/preflight/index.html"

cat > "$DEST/Ark WebKit Spike.command" <<'CMD'
#!/bin/sh
# Ark WebKit Spike for a real call: patched WebKit (WebRTC processing in WebKit's capture unit), no Chromium call
# tabs, Ark's in-page call audio script off, unit debug dump on. Started through LaunchServices so macOS asks
# about the camera and mic for the spike itself. Your daily Ark (~/Applications/Ark.app) is untouched.
OPEN="$HOME/Developer/Ark/derived/webkit-spike/open-spike.sh"
if pgrep -f "Ark WebKit Spike.app/Contents/MacOS/Ark" >/dev/null; then
  osascript -e 'tell application id "app.vezham.ark.webkitspike" to activate'
  echo "Ark WebKit Spike is already running."
  exit 0
fi
unset ARK_AUDIO_BENCH ARK_AUDIO_BENCH_URL ARK_AUDIO_BENCH_CALL_TABS ARK_AUDIO_BENCH_CALL_AUDIO ARK_CALL_AUDIO
# Pinned to the WebKit build of 3a31ddd (an APFS clone made before newer WebKit rebuilds); drop this to use WebKitBuild/Release.
export ARK_SPIKE_WEBKIT="$HOME/Developer/ArkWebKit/WebKitBuild/Release-meeting"
export ARK_CALL_AUDIO_DUMP=1
echo "=== $(date) start (meeting)" >>"$HOME/Library/Logs/Ark WebKit Spike.log"
"$OPEN" >/dev/null && echo "Started Ark WebKit Spike. You can close this window."
CMD

cat > "$DEST/Ark WebKit Spike (camera & mic check).command" <<'CMD'
#!/bin/sh
# Opens a local page in Ark WebKit Spike that asks for the camera and microphone and shows the camera and a mic
# level (nothing recorded, nothing played). Allow both when Ark and macOS ask; then meetings won't stall on it.
DIR="$HOME/Developer/Ark/derived/webkit-spike/preflight"
OPEN="$HOME/Developer/Ark/derived/webkit-spike/open-spike.sh"
PORT=8791
URL="http://127.0.0.1:$PORT/index.html"
# A local web server for 15 minutes (localhost counts as secure, so the page may ask for the camera).
if ! curl -s -o /dev/null "$URL"; then
  ( cd "$DIR" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 ) >/dev/null 2>&1 &
  SERVER=$!
  ( sleep 900; kill "$SERVER" ) >/dev/null 2>&1 &
  for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null "$URL" && break; sleep 0.3; done
fi
if pgrep -f "Ark WebKit Spike.app/Contents/MacOS/Ark" >/dev/null; then
  open -a "$HOME/Developer/Ark/derived/webkit-spike/Ark WebKit Spike.app" "$URL"
else
  unset ARK_AUDIO_BENCH ARK_AUDIO_BENCH_URL ARK_CALL_AUDIO
  export ARK_SPIKE_WEBKIT="$HOME/Developer/ArkWebKit/WebKitBuild/Release-meeting"
  echo "=== $(date) start (camera & mic check)" >>"$HOME/Library/Logs/Ark WebKit Spike.log"
  "$OPEN" "$URL" >/dev/null
fi
echo "Opened the camera & mic check in Ark WebKit Spike: allow the camera and microphone when asked."
CMD

cat > "$DEST/Ark WebKit Spike (tuned).command" <<'CMD'
#!/bin/sh
# Opt-in: Ark WebKit Spike on the current patched WebKit build (WebKitBuild/Release) with the best settings
# from the newest sweep of a real unit dump (tools/audio-bench/sweep.mjs, via soundcheck.sh or aftercall.mjs --sweep).
# Refuses when there is no such sweep, or when its replay didn't reproduce the live call (then the "best" setting
# isn't trustworthy). Debug dump on. Your daily Ark is untouched; the plain launcher is the fallback.
OPEN="$HOME/Developer/Ark/derived/webkit-spike/open-spike.sh"
if pgrep -f "Ark WebKit Spike.app/Contents/MacOS/Ark" >/dev/null; then
  echo "Ark WebKit Spike is already running: quit it first to start it with tuned settings."
  exit 1
fi
PICK=$(node --input-type=module -e '
import fs from "node:fs"; import path from "node:path"; import os from "node:os";
const root = path.join(os.homedir(), "Developer/Ark/derived/audio-bench"), found = [];
const walk = (d, depth) => { let es = []; try { es = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
  for (const e of es) { const p = path.join(d, e.name); if (e.isDirectory() && depth < 3) walk(p, depth + 1); else if (e.name === "sweep.json") found.push(p); } };
walk(root, 0);
const ok = found.map((p) => { try { return { p, r: JSON.parse(fs.readFileSync(p, "utf8")), t: fs.statSync(p).mtimeMs }; } catch { return null; } })
  .filter((x) => x && x.r.dumpMode === "webkit-unit").sort((a, b) => b.t - a.t);
if (!ok.length) { console.log("NONE\tNo sweep of a real unit dump yet: run the sound check or aftercall.mjs --sweep first."); process.exit(0); }
const { p, r } = ok[0];
if (!(r.replayVsLiveDb <= -20)) { console.log(`NONE\tNewest sweep (${p}) did not reproduce the live call (replay vs live ${r.replayVsLiveDb} dB): not applying its settings.`); process.exit(0); }
console.log(`${r.bestEnv === "(defaults)" ? "" : r.bestEnv}\t${p}: ${r.line}`);
')
SETTINGS=$(printf '%s' "$PICK" | cut -f1)
WHY=$(printf '%s' "$PICK" | cut -f2-)
if [ "$SETTINGS" = NONE ]; then echo "$WHY"; echo "Use the plain Ark WebKit Spike launcher instead."; exit 1; fi
unset ARK_AUDIO_BENCH ARK_AUDIO_BENCH_URL ARK_AUDIO_BENCH_CALL_TABS ARK_AUDIO_BENCH_CALL_AUDIO ARK_CALL_AUDIO ARK_SPIKE_WEBKIT
for kv in $SETTINGS; do case "$kv" in ARK_CALL_AUDIO_*=*) export "$kv";; esac; done
export ARK_CALL_AUDIO_DUMP=1
echo "=== $(date) start (tuned: ${SETTINGS:-defaults}; from $WHY)" >>"$HOME/Library/Logs/Ark WebKit Spike.log"
"$OPEN" >/dev/null || exit $?
echo "Started Ark WebKit Spike on the current build with: ${SETTINGS:-default settings}"
echo "From: $WHY"
echo "You can close this window."
CMD

chmod +x "$DEST/Ark WebKit Spike.command" "$DEST/Ark WebKit Spike (tuned).command" "$DEST/Ark WebKit Spike (camera & mic check).command"
echo "Installed $DERIVED/open-spike.sh and the launchers in $DEST"
