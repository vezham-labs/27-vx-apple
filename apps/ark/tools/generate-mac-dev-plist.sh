#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

output=Mac/Info.dev.generated.plist
temp=$(mktemp "${output}.XXXXXX")
trap 'rm -f "$temp"' EXIT
cp Mac/Info.plist "$temp"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$temp"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleDocumentTypes' "$temp"
if ! cmp -s "$temp" "$output"; then
  mv "$temp" "$output"
fi
