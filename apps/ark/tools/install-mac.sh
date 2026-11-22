#!/bin/zsh
# Builds Ark for Mac (Release, app.vezham.ark) and installs it as ~/Applications/Ark.app
# (or ARK_INSTALL_PATH).
#
#   tools/install-mac.sh              # latest HEAD
#   tools/install-mac.sh <git-ref>    # any branch, tag or commit, e.g. origin/claude/some-branch
#   tools/install-mac.sh --patched-webkit [<git-ref>]
#                                     # signed so it may run on Ark's own WebKit build
#                                     # (Mac/ArkLocalWebKit.entitlements; see Mac/Sources/PatchedWebKit.swift)
#
# Builds from a clean export of the ref, so it doesn't matter which branch this checkout (or any
# worktree) is on, or what's uncommitted in it. Website data, sign-ins, tabs and extensions live
# in the sandbox container for app.vezham.ark, which reinstalling never touches. Xcode's
# Run button builds "Ark Dev" (app.vezham.ark.dev) with its own container instead.
set -euo pipefail

repo="${0:A:h:h}"
patched_webkit=0
if [[ "${1:-}" == --patched-webkit ]]; then patched_webkit=1; shift; fi
ref="${1:-HEAD}"
work="$HOME/Library/Caches/app.vezham.ark.install"
src="$work/src"
# ~/Applications, always: /Applications needs admin rights on some Macs, and one fixed
# place means a single copy. Launch Services and the default-browser setting treat it the same.
app="${ARK_INSTALL_PATH:-$HOME/Applications/Ark.app}"
bundle_id="app.vezham.ark"

echo "==> Fetching $ref"
if [[ "$ref" == origin/* ]]; then
  for attempt in 1 2 3 4; do
    git -C "$repo" fetch --quiet origin "${ref#origin/}" && break
    [[ $attempt == 4 ]] && { echo "fetch failed" >&2; exit 1; }
    sleep $((2 ** attempt))
  done
fi
commit=$(git -C "$repo" rev-parse --short "$ref^{commit}")

echo "==> Exporting $ref ($commit)"
rm -rf "$work/export" && mkdir -p "$work/export" "$src"
bash "$repo/tools/export-source.sh" "$commit" "$work/export"
# Copy only files that changed, keeping the rest's timestamps so the build stays incremental.
rsync -rlc --delete --exclude Ark.xcodeproj "$work/export/" "$src/"
rm -rf "$work/export"

echo "==> Building Ark (Release)"
cd "$src/apps/ark"
xcodegen generate --quiet
extra=()
[[ -z "${ARK_DEVELOPMENT_TEAM:-}" ]] || extra+=(DEVELOPMENT_TEAM="$ARK_DEVELOPMENT_TEAM")
# The local daily also gets the development-only call recording switch (Settings › Audio), never in releases.
(( patched_webkit )) && extra+=(CODE_SIGN_ENTITLEMENTS=Mac/ArkLocalWebKit.entitlements 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ARK_CALL_RECORDING')
# A fresh product each time: an incremental build keeps whatever an earlier build embedded (Chromium, after call
# tabs were removed).
rm -rf "$work/DerivedData/Build/Products/Release/Ark.app"
xcodebuild -project Ark.xcodeproj -scheme ArkMac -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$work/DerivedData" \
  -allowProvisioningUpdates -quiet build "${extra[@]}"
built="$work/DerivedData/Build/Products/Release/Ark.app"
if (( patched_webkit )); then
  codesign -d --entitlements - "$built" 2>/dev/null | grep -q allow-dyld-environment-variables \
    || { echo "built app isn't signed for Ark's WebKit (Mac/ArkLocalWebKit.entitlements missing from the ref?)" >&2; exit 1; }
fi
[[ "$(defaults read "$built/Contents/Info.plist" CFBundleIdentifier)" == "$bundle_id" ]] \
  || { echo "built app doesn't have the bundle ID $bundle_id" >&2; exit 1; }

# Any running copy with this ID shares the container (an old Xcode build too), so it quits first.
running() { [[ "$(osascript -e "application id \"$bundle_id\" is running")" == true ]]; }
if running; then
  echo "==> Quitting the running Ark (tabs are saved on quit)"
  osascript -e "tell application id \"$bundle_id\" to quit" || true
  for _ in {1..60}; do running || break; sleep 0.25; done
  running && { echo "Ark didn't quit; quit it and run this again" >&2; exit 1; }
fi

echo "==> Installing $app"
mkdir -p "${app:h}"
rm -rf "$app"
ditto "$built" "$app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Old Xcode builds with the same ID stay registered and can catch links or the default-browser
# setting, so Launch Services forgets every copy but this one. (Their files aren't touched.)
swift -e "import AppKit; for u in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: \"$bundle_id\") { print(u.path) }" 2>/dev/null |
  while IFS= read -r other; do [[ "$other" == "$app" ]] || "$lsregister" -u "$other" 2>/dev/null || true; done
"$lsregister" -f "$app"
open "$app"
echo "==> Ark $commit installed and running"
