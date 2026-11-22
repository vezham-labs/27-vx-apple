#!/bin/zsh
set -euo pipefail
project="${0:A:h:h}"
export APPLE_RELEASES_DIR=${ARK_RELEASES_DIR:-"$HOME/Developer/Ark/releases/mac"}
exec zsh "$project/../../vx/tools/release-apple/publish-mac.sh" "$project" "$@"
