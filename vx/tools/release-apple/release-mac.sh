#!/bin/zsh
# Package a signed Developer ID release from a committed app configuration.
set -euo pipefail

source "${0:A:h}/common.zsh"
setup_project "${1:?usage: release-mac.sh <app-directory> [--local] <version> [git-ref]}"
shift
local_only=0
[[ "${1:-}" == --local ]] && { local_only=1; shift; }
version="${1:?usage: tools/release-mac.sh [--local] <version> [git-ref]}"
ref="${2:-HEAD}"
work="$cache_root/$project_path/release"
(( local_only )) && work="$work-local"
bundle_webkit=(${=APPLE_BUNDLE_WEBKIT:-})
export_root="$work/src"
src="$export_root/$project_path"
derived="$work/DerivedData"
archive="$work/app.xcarchive"

[[ "$version" =~ '^[0-9]+(\.[0-9]+){1,2}$' ]] || { echo "version should look like 1.2 or 1.2.3" >&2; exit 1; }
commit=$(resolve_ref "$ref")
# Sparkle compares CFBundleVersion, so it has to grow with every release: the commit count does.
build=$(git -C "$workspace" rev-list --count "$commit")

echo "==> Exporting $ref ($commit) as $version ($build)"
rm -rf "$export_root" "$archive" "$work/upload" "$work/notarized" "$work/export"
export_project "$commit" "$export_root"
read_macos_config "$src"
[[ "$distribution" == developer-id ]] || { echo "This release command requires macOS distribution: developer-id." >&2; exit 1; }
scheme=$(require_mac_setting '.release.scheme')
product=$(require_mac_setting '.release.productName')
team=$(require_mac_setting '.release.teamId')
feed_url=$(require_mac_setting '.release.sparkle.feedUrl')
sparkle_key=$(require_mac_setting '.release.sparkle.publicKey')
download_prefix=$(require_mac_setting '.release.sparkle.downloadBaseUrl')
(( local_only )) || [[ ! -e "$releases/$product-$version.zip" ]] || { echo "Release ZIP already exists" >&2; exit 1; }
(( local_only )) || mkdir -p "$releases"

check_release() {
  codesign --verify --deep --strict "$1"
  if [[ -x "$src/tools/mac-check-release.sh" ]]; then
    "$src/tools/mac-check-release.sh" "$1"
  fi
}

echo "==> Archiving"
cd "$src"
generate_xcode_project "$src"
xcodebuild -project "$xcode_project" -scheme "$scheme" -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" -archivePath "$archive" \
  -allowProvisioningUpdates -quiet \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" VX_SPARKLE_UPDATES=YES \
  archive

plist="$archive/Products/Applications/$product.app/Contents/Info.plist"
[[ "$(defaults read "$plist" CFBundleIdentifier)" == "$bundle_id" ]] || { echo "wrong bundle ID" >&2; exit 1; }
[[ "$(defaults read "$plist" SUFeedURL)" == "$feed_url" && "$(defaults read "$plist" SUPublicEDKey)" == "$sparkle_key" ]] || { echo "Sparkle settings differ from vx.deploy.yaml" >&2; exit 1; }

if (( ${#bundle_webkit} )); then
  [[ -x "$src/tools/mac-bundle-webkit.sh" ]] || { echo "This app has no WebKit bundling hook." >&2; exit 1; }
  echo "==> Bundling WebKit (${bundle_webkit[*]})"
  archived_app="$archive/Products/Applications/$product.app"
  # Sign like the archive did (its identity); the Developer ID export re-signs everything afterwards.
  identity=$(codesign -dvv "$archived_app" 2>&1 | sed -n 's/^Authority=//p' | head -1)
  [[ -n "$identity" ]] || { echo "can't tell how the archive was signed" >&2; exit 1; }
  "$src/tools/mac-bundle-webkit.sh" "$archived_app" "$identity" "${bundle_webkit[@]}"
  # WebKit's dSYMs with the app's, for crash reports.
  mkdir -p "$archive/dSYMs" && cp -cR "$archive/Products/Applications/dSYMs/"* "$archive/dSYMs/" && rm -rf "$archive/Products/Applications/dSYMs"
fi

if (( local_only )); then
  echo "==> Signing with Developer ID, to disk only (nothing goes to the notary service)"
  export_options="$work/ExportOptions.plist"
  cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>$distribution</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$export_options" \
    -exportPath "$work/export" -allowProvisioningUpdates > "$work/export.log" 2>&1 \
    || { tail -20 "$work/export.log" >&2; echo "export failed (log: $work/export.log)" >&2; exit 1; }
  app="$work/export/$product.app"
  check_release "$app"
  zip="$work/$product-$version.zip"
  rm -f "$zip" && ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
  echo
  echo "==> Local build of $product $version ($build, $commit), not notarised: $app"
  echo "    on disk $(du -sh "$app" | cut -f1), zipped $(du -h "$zip" | cut -f1) ($zip)"
  exit 0
fi

echo "==> Signing with Developer ID and sending to Apple's notary service"
export_options="$work/ExportOptions.plist"
cat > "$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>$distribution</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>upload</string>
</dict></plist>
EOF
# Stop here if the upload didn't go through: xcodebuild has printed "EXPORT FAILED" after a timeout without the
# script noticing, which then waited half an hour for a notarisation that was never requested.
export_status=0
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$export_options" \
  -exportPath "$work/upload" -allowProvisioningUpdates > "$work/upload.log" 2>&1 || export_status=$?
{ grep -v 'Progress [0-9]*%' "$work/upload.log" || true; } | tail -20
if (( export_status != 0 )) || grep -q "EXPORT FAILED" "$work/upload.log" || ! grep -q "EXPORT SUCCEEDED" "$work/upload.log"; then
  echo "The upload to Apple's notary service failed (exit $export_status, log: $work/upload.log). Stopping." >&2
  exit 1
fi

echo "==> Waiting for notarisation (usually a few minutes)"
for attempt in {1..60}; do
  if xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$work/notarized" >/dev/null 2>&1; then
    break
  fi
  [[ $attempt == 60 ]] && { echo "not notarised after 30 minutes; check Xcode's Organizer" >&2; exit 1; }
  sleep 30
done
app="$work/notarized/$product.app"
xcrun stapler validate -q "$app"
spctl --assess --type execute "$app" || { echo "Gatekeeper rejected the notarised app" >&2; exit 1; }
check_release "$app"

echo "==> Zipping"
zip="$releases/$product-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
notes="$src/release-notes/mac/$version.md"
[[ -f "$notes" ]] && cp "$notes" "$releases/$product-$version.md"

echo "==> Making the DMG for first downloads"
# Drag-to-Applications window: background art in Mac/Distribution (600×360 pt, @1x and @2x in one
# TIFF), the app on the left, the Applications link over the drawn folder. create-dmg lays the
# window out by scripting Finder, so the first run asks to let the terminal control Finder.
# The DMG isn't signed or notarised itself; the app inside is, and its ticket is stapled.
command -v create-dmg >/dev/null || { echo "create-dmg is missing: brew install create-dmg" >&2; exit 1; }
mkdir -p "$releases/dmg"
dmg="$releases/dmg/$product-$version.dmg"
dmg_stage="$work/dmg" && rm -rf "$dmg_stage" && mkdir -p "$dmg_stage" && ditto "$app" "$dmg_stage/$product.app"
dmg_background=()
if [[ -f "$src/Mac/Distribution/dmg-background.tiff" ]]; then
  dmg_background=(--background "$src/Mac/Distribution/dmg-background.tiff")
fi
create-dmg --volname "$product" "${dmg_background[@]}" \
  --window-pos 200 120 --window-size 600 400 --icon-size 100 \
  --icon "$product.app" 175 190 --hide-extension "$product.app" --app-drop-link 425 190 \
  --no-internet-enable "$dmg" "$dmg_stage" >/dev/null
mount=$(mktemp -d)
hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mount" >/dev/null
layout_ok=1
required_files=(.DS_Store Applications "$product.app")
(( ${#dmg_background} == 0 )) || required_files+=(.background/dmg-background.tiff)
for f in "${required_files[@]}"; do
  [[ -e "$mount/$f" ]] || { echo "DMG is missing $f" >&2; layout_ok=0; }
done
spctl --assess --type execute "$mount/$product.app" || layout_ok=0
hdiutil detach "$mount" -quiet
[[ $layout_ok == 1 ]] || { echo "DMG check failed; don't ship it" >&2; exit 1; }
# The site's Download button always points at $product.dmg, the newest build.
cp "$dmg" "$releases/dmg/$product.dmg"

echo "==> Updating the appcast"
sparkle_bin="$derived/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$sparkle_bin/generate_appcast" --download-url-prefix "$download_prefix" --embed-release-notes \
  --maximum-deltas 3 "$releases"

mkdir -p "$releases/.vx"
jq -n --arg commit "$commit" --arg version "$version" --argjson macos "$macos" \
  '{commit: $commit, version: $version, macos: $macos}' > "$releases/.vx/$version.json"
echo
echo "==> $product $version ($build, $commit) is ready in $releases"
echo "    Upload to $download_prefix: $product-$version.zip, any new *.delta files, and from dmg/"
echo "    $product-$version.dmg and $product.dmg"
echo "    Then publish appcast.xml at $feed_url (last, so it never points at a missing file)"
