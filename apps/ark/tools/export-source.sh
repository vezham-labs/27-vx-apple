#!/usr/bin/env bash
# Export the app and its local Swift package from the same Git ref.
set -euo pipefail

commit=${1:?usage: export-source.sh <commit> <destination>}
destination=${2:?usage: export-source.sh <commit> <destination>}
workspace=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
paths=(apps/ark)
package=packages-apple/browser-kit

# Older refs already include BrowserKit inside apps/ark.
if git -C "$workspace" cat-file -e "$commit:$package/Package.swift" 2>/dev/null; then
  paths+=("$package")
fi

mkdir -p "$destination"
git -C "$workspace" archive "$commit" -- "${paths[@]}" | tar -x -C "$destination"
