#!/bin/zsh
# Builds a release WebKit for one macOS major, for bundling into Ark (BUNDLING.md, tools/release-mac.sh).
#
#   tools/call-audio/webkit/build-release-webkit.sh <webkit source tree> <major>     # e.g. ~/Developer/ArkWebKit-release 26
#
# The tree must be the commit in WEBKIT_COMMIT with webkit.patch applied and ArkAudioTimeline.h / ArkCallGuard.h
# copied in (README.md), and must NOT have ArkCallAudioRecording.h: that dev-only file compiles in the call dump.
# Output: <tree>/WebKitBuild-release-<major>.0/Release, deployment target <major>.0, labelled in ARK_WEBKIT.txt.
# A clean build takes about an hour on Apple silicon and ~30 GB; it stops if less than 40 GB is free.
# Afterwards it checks every binary's minimum macOS and that WebCore has no dump code.
set -euo pipefail
here="${0:A:h}"
tree="${1:?usage: build-release-webkit.sh <webkit source tree> <major>}"
major="${2:?usage: build-release-webkit.sh <webkit source tree> <major>}"
tree="${tree:A}"
cocoa="$tree/Source/WebCore/platform/mediastream/cocoa"
out="$tree/WebKitBuild-release-$major.0"

[[ "$(git -C "$tree" rev-parse HEAD)" == "$(cat "$here/WEBKIT_COMMIT")" ]] || { echo "$tree isn't at WEBKIT_COMMIT" >&2; exit 1; }
for h in ArkCallAudioInternalUnit.h ArkSideSpeakers.h ArkAudioTimeline.h ArkCallGuard.h; do
  [[ -f "$cocoa/$h" ]] || { echo "missing $cocoa/$h (apply webkit.patch and copy the headers, README.md)" >&2; exit 1; }
done
[[ -e "$cocoa/ArkCallAudioRecording.h" ]] && { echo "$cocoa/ArkCallAudioRecording.h is there: a release WebKit must not record calls" >&2; exit 1; }
# The engine: this branch's files, or those at ARK_ENGINE_REF (a commit) when the release ships an earlier engine.
ref="${ARK_ENGINE_REF:-}"
engine() {
  if [[ -z "$ref" ]]; then
    cat "$here/../$1"
    return
  fi
  local path="apps/ark/tools/call-audio/$1"
  # Earlier engine refs kept the source under Spike.
  if ! git -C "$here" cat-file -e "$ref:$path" 2>/dev/null; then
    path="apps/ark/Spike/CallAudio/$1"
  fi
  git -C "$here" show "$ref:$path"
}
for pair in "webkit/ArkCallAudioInternalUnit.h ArkCallAudioInternalUnit.h" "webkit/ArkSideSpeakers.h ArkSideSpeakers.h" \
            "core/CallGuard.h ArkCallGuard.h" "core/AudioTimeline.h ArkAudioTimeline.h"; do
  src="${pair%% *}" dst="${pair##* }"
  cmp -s <(engine "$src") "$cocoa/$dst" || { echo "$dst differs from the engine ${ref:-on this branch}" >&2; exit 1; }
done
free_gb=$(df -g "$tree" | awk 'NR==2 {print $4}')
(( free_gb >= 40 )) || { echo "only ${free_gb} GB free; a WebKit build needs about 30" >&2; exit 1; }

# No label until this build has passed its checks, so a failed build can't be bundled as a good one.
rm -f "$out/Release/ARK_WEBKIT.txt"
echo "==> Building WebKit for macOS $major.0 into $out (about an hour)"
cd "$tree"
# BUILD_JOBS limits parallel compiles (e.g. half the cores, to stay out of the way of a call).
jobs=(); [[ -n "${BUILD_JOBS:-}" ]] && jobs=(-jobs "$BUILD_JOBS")
WEBKIT_OUTPUTDIR="$out" nice -n "${BUILD_NICE:-0}" Tools/Scripts/build-webkit --release $jobs \
  MACOSX_DEPLOYMENT_TARGET="$major.0" WK_MACOSX_DEPLOYMENT_TARGET="$major.0"

fw="$out/Release"
echo "==> Checking"
bad=0
for b in WebKit WebCore JavaScriptCore WebGPU WebKitLegacy; do
  minos=$(otool -l "$fw/$b.framework/Versions/A/$b" | awk '/LC_BUILD_VERSION/ {f=1} f && /minos/ {print $2; exit}')
  [[ "$minos" == "$major.0" ]] || { echo "$b: minos $minos, wanted $major.0" >&2; bad=1; }
done
# Nothing recording-related: the dump, its memory and timing log, or the per-device memory (development only).
dumps=$(strings -a "$fw/WebCore.framework/Versions/A/WebCore" | grep -c -E "ARK_CALL_AUDIO_DUMP|ark-call-audio-|gpuProcessMemoryMB|resyncAt|remembered gain|ARK_CALL_AUDIO_REMEMBER" || true)
[[ "$dumps" == 0 ]] || { echo "WebCore has recording-related code ($dumps strings)" >&2; bad=1; }
# (grep -c, not -q: -q stops reading early and pipefail would count the cut-off strings as a failure)
(( $(strings -a "$fw/WebCore.framework/Versions/A/WebCore" | grep -c "ArkCallAudioInternalUnit ready" || true) > 0 )) || { echo "WebCore lacks Ark's call audio unit" >&2; bad=1; }
(( bad == 0 )) || exit 1
patch_id=$(git -C "$tree" diff | shasum | cut -c1-12)
echo "release $major.0 $(git -C "$tree" rev-parse --short HEAD) patch $patch_id engine ${ref:-$(git -C "$here" rev-parse --short HEAD)} $(date +%Y-%m-%d)" > "$fw/ARK_WEBKIT.txt"
echo "==> $fw: $(cat "$fw/ARK_WEBKIT.txt")"
