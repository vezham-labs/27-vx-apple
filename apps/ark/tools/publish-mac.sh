#!/bin/zsh
# Publishes a Mac release made by tools/release-mac.sh to an Ark R2 bucket: uploads its files to the
# bucket served by the release host at /mac/appcast.xml and /mac/releases/.
#
#   tools/publish-mac.sh <version>
#
# The appcast goes up last, so installed copies never see an update whose files aren't there yet.
# Ark.dmg is replaced too, which is what the site's Download button gives new users.
set -euo pipefail

version="${1:?usage: tools/publish-mac.sh <version>}"
repo="${0:A:h:h}"
releases="${ARK_RELEASES_DIR:-$HOME/Developer/Ark/releases/mac}"
bucket="${ARK_RELEASE_BUCKET:?Set ARK_RELEASE_BUCKET}"

zip="$releases/Ark-$version.zip"
dmg="$releases/dmg/Ark-$version.dmg"
for f in "$zip" "$dmg" "$releases/appcast.xml"; do
  [[ -f "$f" ]] || { echo "missing $f; run tools/release-mac.sh $version first" >&2; exit 1; }
done
grep -q "Ark-$version.zip" "$releases/appcast.xml" || { echo "appcast.xml doesn't list $version" >&2; exit 1; }
build=$(unzip -p "$zip" Ark.app/Contents/Info.plist | plutil -extract CFBundleVersion raw -)

put() {  # put <file> <key> <content-type>
  echo "==> $2"
  (cd "$repo" && npx --yes wrangler r2 object put "$bucket/$2" --file "$1" --content-type "$3" --remote >/dev/null)
}

put "$zip" "mac/releases/Ark-$version.zip" application/zip
for delta in "$releases"/Ark$build-*.delta(N); do
  put "$delta" "mac/releases/${delta:t}" application/octet-stream
done
put "$dmg" "mac/releases/Ark-$version.dmg" application/x-apple-diskimage
put "$dmg" "mac/releases/Ark.dmg" application/x-apple-diskimage
put "$releases/appcast.xml" "mac/appcast.xml" "application/rss+xml; charset=utf-8"

echo "==> Ark $version ($build) uploaded to $bucket"
