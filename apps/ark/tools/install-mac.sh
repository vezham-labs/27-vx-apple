#!/bin/zsh
set -euo pipefail
project="${0:A:h:h}"
export APPLE_INSTALL_PATH=${ARK_INSTALL_PATH:-}
export APPLE_LOCAL_WEBKIT_ENTITLEMENTS=Mac/ArkLocalWebKit.entitlements
export APPLE_LOCAL_WEBKIT_SWIFT_FLAG=ARK_CALL_RECORDING
export APPLE_LEGACY_SCHEME=ArkMac
export APPLE_LEGACY_PRODUCT=Ark
exec zsh "$project/../../vx/tools/release-apple/install-mac.sh" "$project" "$@"
