#!/bin/zsh
set -euo pipefail
project="${0:A:h:h}"
export APPLE_RELEASES_DIR=${ARK_RELEASES_DIR:-"$HOME/Developer/Ark/releases/mac"}
export APPLE_BUNDLE_WEBKIT=${ARK_BUNDLE_WEBKIT:-}
exec zsh "$project/../../vx/tools/release-apple/release-mac.sh" "$project" "$@"
