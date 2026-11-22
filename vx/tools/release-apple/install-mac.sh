#!/bin/zsh
# Build and install the Mac app from a clean export of a Git ref.
set -euo pipefail
source "${0:A:h}/common.zsh"
setup_project "${1:?usage: install-mac.sh <app-directory> [--patched-webkit] [git-ref]}"
shift
patched_webkit=0
if [[ "${1:-}" == --patched-webkit ]]; then patched_webkit=1; shift; fi
ref="${1:-HEAD}"
work="$cache_root/$project_path/install"
src="$work/src"
commit=$(resolve_ref "$ref")

echo "==> Exporting $ref ($commit)"
rm -rf "$work/export" && mkdir -p "$work/export" "$src"
export_project "$commit" "$work/export"
# Copy only files that changed, keeping the rest's timestamps so the build stays incremental.
rsync -rlc --delete --exclude '*.xcodeproj' "$work/export/" "$src/"
rm -rf "$work/export"

cd "$src/$project_path"
read_macos_config "$PWD"
# Existing Ark refs predate the release mapping. Their scheme and product names are passed by the app wrapper.
scheme=${scheme:-${APPLE_LEGACY_SCHEME:-}}
product=${product:-${APPLE_LEGACY_PRODUCT:-}}
[[ -n "$scheme" && -n "$product" ]] || { echo "Set the macOS release scheme and productName in vx.deploy.yaml." >&2; exit 1; }
app=${APPLE_INSTALL_PATH:-"$HOME/Applications/$product.app"}
echo "==> Building $product (Release)"
generate_xcode_project "$PWD"
extra=()
# The local daily also gets the development-only call recording switch (Settings › Audio), never in releases.
if (( patched_webkit )); then
  entitlement=${APPLE_LOCAL_WEBKIT_ENTITLEMENTS:?This app has no local WebKit entitlement configuration}
  [[ -f "$entitlement" ]] || { echo "Missing $entitlement at the selected ref." >&2; exit 1; }
  extra+=(CODE_SIGN_ENTITLEMENTS="$entitlement"
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) ${APPLE_LOCAL_WEBKIT_SWIFT_FLAG:-}")
fi
# A fresh product each time: an incremental build keeps whatever an earlier build embedded (Chromium, after call
# tabs were removed).
rm -rf "$work/DerivedData/Build/Products/Release/$product.app"
xcodebuild -project "$xcode_project" -scheme "$scheme" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$work/DerivedData" \
  -allowProvisioningUpdates -quiet build "${extra[@]}"
built="$work/DerivedData/Build/Products/Release/$product.app"
if (( patched_webkit )); then
  codesign -d --entitlements - "$built" 2>/dev/null | grep -q allow-dyld-environment-variables \
    || { echo "built app isn't signed for Ark's WebKit (check the signing settings at the selected ref)" >&2; exit 1; }
fi
[[ "$(defaults read "$built/Contents/Info.plist" CFBundleIdentifier)" == "$bundle_id" ]] \
  || { echo "built app doesn't have the bundle ID $bundle_id" >&2; exit 1; }

# Any running copy with this ID shares the container (an old Xcode build too), so it quits first.
running() { [[ "$(osascript -e "application id \"$bundle_id\" is running")" == true ]]; }
if running; then
  echo "==> Quitting the running $product (tabs are saved on quit)"
  osascript -e "tell application id \"$bundle_id\" to quit" || true
  for _ in {1..60}; do running || break; sleep 0.25; done
  running && { echo "$product didn't quit; quit it and run this again" >&2; exit 1; }
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
echo "==> $product $commit installed and running"
