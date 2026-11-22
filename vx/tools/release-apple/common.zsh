# Shared helpers for the Apple release scripts. The caller supplies the app directory.
setup_project() {
  project=${1:A}
  workspace=$(git -C "$project" rev-parse --show-toplevel)
  project_path=${project#"$workspace"/}
  [[ "$project_path" != "$project" && -f "$project/vx.deploy.yaml" ]] \
    || { echo "Expected an Apple app directory inside the workspace" >&2; return 1; }
  releases=${APPLE_RELEASES_DIR:-"$workspace/dist/apple-releases/$project_path"}
  releases=${releases:A}
  cache_root=${APPLE_RELEASE_CACHE_DIR:-"$HOME/Library/Caches/vx.apple"}
  cache_root=${cache_root:A}
}

resolve_ref() {
  local ref=$1
  if [[ "$ref" == origin/* ]]; then
    for attempt in 1 2 3 4; do
      git -C "$workspace" fetch --quiet origin "${ref#origin/}" && break
      [[ $attempt == 4 ]] && { echo "fetch failed" >&2; return 1; }
      sleep $((2 ** attempt))
    done
  fi
  git -C "$workspace" rev-parse --verify --end-of-options "$ref^{commit}"
}

export_project() {
  local commit=$1 destination=$2
  mkdir -p "$destination"
  if [[ -f "$project/tools/export-source.sh" ]]; then
    bash "$project/tools/export-source.sh" "$commit" "$destination"
  else
    git -C "$workspace" archive "$commit" -- "$project_path" | tar -x -C "$destination"
  fi
}

project_config() {
  (cd "$workspace" && node --import tsx packages-apple/config/src/lib/project-config/cli.ts "$@")
}

read_macos_config() {
  local config
  config=$(project_config deployment "$1")
  macos=$(jq -ce '.targets.macos' <<< "$config")
  bundle_id=$(mac_setting '.bundleIdentifier')
  distribution=$(mac_setting '.distribution')
  team=$(mac_setting '.release.teamId')
  scheme=$(mac_setting '.release.scheme')
  product=$(mac_setting '.release.productName')
}

mac_setting() {
  jq -r "$1 // empty" <<< "$macos"
}

require_mac_setting() {
  local value
  value=$(mac_setting "$1")
  [[ -n "$value" ]] || { echo "Set targets.macos${1} in vx.deploy.yaml at the selected ref." >&2; return 1; }
  printf '%s\n' "$value"
}

generate_xcode_project() {
  project_config generate "$1"
  xcodegen generate --quiet
  local projects=( *.xcodeproj(N) )
  (( ${#projects} == 1 )) || { echo "Expected one generated Xcode project in $PWD" >&2; return 1; }
  xcode_project=$projects[1]
}
