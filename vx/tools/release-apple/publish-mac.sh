#!/bin/zsh
# Publish the artifacts using the configuration recorded when they were packaged.
set -euo pipefail
source "${0:A:h}/common.zsh"
setup_project "${1:?usage: publish-mac.sh <app-directory> <version>}"
version="${2:?usage: publish-mac.sh <app-directory> <version>}"
[[ "$version" =~ '^[0-9]+(\.[0-9]+){1,2}$' ]] || { echo "Invalid release version" >&2; exit 1; }

receipt="$releases/.vx/$version.json"
[[ -f "$receipt" ]] || { echo "Missing $receipt. Package this release first." >&2; exit 1; }
macos=$(jq -ce --arg version "$version" 'select(.version == $version) | .macos' "$receipt")
product=$(require_mac_setting '.release.productName')
bundle_id=$(require_mac_setting '.bundleIdentifier')
bucket=$(require_mac_setting '.release.sparkle.bucket')
download_url=$(require_mac_setting '.release.sparkle.downloadBaseUrl')
feed_url=$(require_mac_setting '.release.sparkle.feedUrl')
public_key=$(require_mac_setting '.release.sparkle.publicKey')

zip="$releases/$product-$version.zip"
dmg="$releases/dmg/$product-$version.dmg"
appcast="$releases/appcast.xml"
for file in "$zip" "$dmg" "$appcast"; do
  [[ -f "$file" ]] || { echo "Missing $file" >&2; exit 1; }
done
encoded_zip=$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$product-$version.zip")
grep -Fq "$product-$version.zip" "$appcast" || grep -Fq "$encoded_zip" "$appcast" \
  || { echo "Appcast does not include $version" >&2; exit 1; }
plist="$product.app/Contents/Info.plist"
[[ "$(unzip -p "$zip" "$plist" | plutil -extract CFBundleIdentifier raw -)" == "$bundle_id" &&
   "$(unzip -p "$zip" "$plist" | plutil -extract CFBundleShortVersionString raw -)" == "$version" &&
   "$(unzip -p "$zip" "$plist" | plutil -extract SUFeedURL raw -)" == "$feed_url" &&
   "$(unzip -p "$zip" "$plist" | plutil -extract SUPublicEDKey raw -)" == "$public_key" ]] \
  || { echo "The release ZIP does not match its deployment settings" >&2; exit 1; }
build=$(unzip -p "$zip" "$plist" | plutil -extract CFBundleVersion raw -)

object_key() {
  node -e 'process.stdout.write(decodeURIComponent(new URL(process.argv[1]).pathname).slice(1))' "$1"
}
prefix=$(object_key "$download_url")
feed_key=$(object_key "$feed_url")
[[ -n "$feed_key" && "$feed_key" != */ ]] || { echo "Sparkle feed URL must identify a file" >&2; exit 1; }

put() {
  echo "==> $2"
  (cd "$project" && npx --yes wrangler r2 object put "$bucket/$2" --file "$1" --content-type "$3" --remote >/dev/null)
}

put "$zip" "$prefix$product-$version.zip" application/zip
for delta in "$releases"/"$product$build"-*.delta(N); do
  put "$delta" "$prefix${delta:t}" application/octet-stream
done
put "$dmg" "$prefix$product-$version.dmg" application/x-apple-diskimage
put "$dmg" "$prefix$product.dmg" application/x-apple-diskimage
put "$appcast" "$feed_key" "application/rss+xml; charset=utf-8"
echo "==> $product $version ($build) uploaded to $bucket"
