#!/usr/bin/env bash
# Rebuilds packages-apple/browser-kit/Sources/BrowserCore/Resources/autoconsent.js from DuckDuckGo's
# autoconsent package (MPL-2.0). Run from apps/ark: tools/autoconsent/build.sh [version]
set -euo pipefail
cd "$(dirname "$0")/../.."
RESOURCES=../../packages-apple/browser-kit/Sources/BrowserCore/Resources
VERSION="${1:-17.2.0}"
WORK=.autoconsent
rm -rf "$WORK" && mkdir -p "$WORK"
curl -sSfL "https://registry.npmjs.org/@duckduckgo/autoconsent/-/autoconsent-$VERSION.tgz" | tar xz -C "$WORK"
OUT="$RESOURCES/autoconsent.js"
{
  echo "/*! DuckDuckGo autoconsent $VERSION, MPL-2.0: https://github.com/duckduckgo/autoconsent */"
  npx --yes esbuild@0.25.0 tools/autoconsent/entry.ts --bundle --format=iife --minify --target=safari16 --log-level=warning
} > "$OUT"
node tools/autoconsent/frame-gate.mjs "$WORK/package" "$RESOURCES/autoconsent-frames.js"
cp "$WORK/package/LICENSE" "$RESOURCES/autoconsent-LICENSE.txt"
rm -rf "$WORK"
echo "Wrote $OUT ($(wc -c < "$OUT") bytes)"
