#!/bin/zsh
# Moves the everyday Ark (~/Applications/Ark.app, app.vezham.ark) onto Ark's own WebKit build, with a
# backup first and a way back. Nothing here runs by itself: each step is a subcommand.
#
#   tools/daily-patched-webkit.sh backup              # quits Ark, snapshots its app and data (APFS clones)
#   tools/daily-patched-webkit.sh install [<ref>]     # backup, then install-mac.sh --patched-webkit <ref>
#   tools/daily-patched-webkit.sh status              # which WebKit the running Ark is on
#   tools/daily-patched-webkit.sh off                 # stay on the system WebKit from the next start (keeps the install)
#   tools/daily-patched-webkit.sh rollback [<backup>] # quits Ark, puts the backed-up app and data back
#
# Why a data backup: Ark's WebKit is newer than the system's (627 against 624 on macOS 26.7), and may upgrade
# website data files (IndexedDB, local storage, the tracking prevention database) in place; the system WebKit might
# then not read them. The network cache is per version and needs nothing. Cookies are CFNetwork's, not WebKit's.
# Backups go to ~/Developer/Ark/backups/daily-<time> as APFS clones (no extra disk until files change).
set -euo pipefail

repo="${0:A:h:h}"
source "$repo/../../vx/tools/release-apple/common.zsh"
setup_project "$repo"
read_macos_config "$repo"
product=$(require_mac_setting '.release.productName')
app=${ARK_INSTALL_PATH:-"$HOME/Applications/$product.app"}
if [[ -d "$app" && "$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier)" != "$bundle_id" ]]; then
  echo "The installed app at $app does not match the bundle ID in vx.deploy.yaml." >&2
  exit 1
fi
backups="$HOME/Developer/Ark/backups"
webkit="$HOME/Developer/ArkWebKit/WebKitBuild/Ark-daily"
# Everything that holds Ark's state, as installed today (unsandboxed; SandboxMigration moved it out).
data=(
  "$HOME/Library/WebKit/$bundle_id"
  "$HOME/Library/HTTPStorages/$bundle_id"
  "$HOME/Library/HTTPStorages/$bundle_id.binarycookies"
  "$HOME/Library/Application Support/$bundle_id"
)
# Preferences go through cfprefsd (defaults export / import), not as a file: it caches them. By path: an old sandbox
# container for the same bundle ID still exists, and `defaults ... app.vezham.ark` would use its copy, not the
# one the (unsandboxed) app reads.
prefs="$HOME/Library/Preferences/$bundle_id.plist"

running() { [[ "$(osascript -e "application id \"$bundle_id\" is running")" == true ]]; }
quit_ark() {
  running || return 0
  echo "==> Quitting Ark (tabs are saved on quit)"
  osascript -e "tell application id \"$bundle_id\" to quit" || true
  for _ in {1..80}; do running || return 0; sleep 0.25; done
  echo "Ark didn't quit; quit it and run this again" >&2; exit 1
}

backup() {
  quit_ark
  local dest="$backups/daily-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dest/data"
  echo "==> Backing up to $dest"
  [[ -d "$app" ]] && cp -cR "$app" "$dest/Ark.app"
  for p in "${data[@]}"; do
    [[ -e "$p" ]] || continue
    local rel="${p#$HOME/}"
    mkdir -p "$dest/data/${rel:h}"
    cp -cR "$p" "$dest/data/$rel"
  done
  defaults export "$prefs" "$dest/preferences.plist"
  git -C "$repo" rev-parse --short HEAD > "$dest/ark-repo-head.txt" 2>/dev/null || true
  echo "$dest" > "$backups/latest-daily"
  du -sh "$dest" | sed 's/^/   size (as clones, shared until changed): /'
  echo "$dest"
}

case "${1:-}" in
  backup) backup ;;
  install)
    ref="${2:-HEAD}"
    [[ -e "$webkit/WebKit.framework/Versions/A/WebKit" ]] || { echo "No Ark WebKit at $webkit" >&2; exit 1; }
    backup
    "$repo/tools/install-mac.sh" --patched-webkit "$ref"
    sleep 4
    echo "==> $(tail -1 "$HOME/Library/Logs/Ark/webkit.log" 2>/dev/null)"
    echo "Settings › Audio shows which WebKit it's on. To go back: $0 off (quick) or $0 rollback (app and data)."
    ;;
  status)
    pid=$(pgrep -nf "$app/Contents/MacOS/$product" || true)
    [[ -n "$pid" ]] || { echo "Ark isn't running"; exit 0; }
    if lsof -p "$pid" -Fn 2>/dev/null | grep -q "^n$webkit/WebKit.framework/"; then echo "Ark's WebKit ($webkit)"; else echo "system WebKit"; fi
    tail -1 "$HOME/Library/Logs/Ark/webkit.log" 2>/dev/null || true
    ;;
  off)
    defaults write "$prefs" patchedWebKit -bool false
    echo "Ark will start on the system WebKit next time (Settings › Audio to switch back on)."
    ;;
  rollback)
    src="${2:-$(cat "$backups/latest-daily" 2>/dev/null || true)}"
    [[ -n "$src" && -d "$src" ]] || { echo "No backup given or recorded in $backups/latest-daily" >&2; exit 1; }
    quit_ark
    aside="$backups/replaced-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$aside/data"
    echo "==> Moving the current app and data aside to $aside (nothing deleted)"
    [[ -d "$app" ]] && mv "$app" "$aside/Ark.app"
    for p in "${data[@]}"; do
      [[ -e "$p" ]] || continue
      local_rel="${p#$HOME/}"
      mkdir -p "$aside/data/${local_rel:h}"
      mv "$p" "$aside/data/$local_rel"
    done
    echo "==> Restoring from $src"
    [[ -d "$src/Ark.app" ]] && cp -cR "$src/Ark.app" "$app"
    for p in "${data[@]}"; do
      local_rel="${p#$HOME/}"
      [[ -e "$src/data/$local_rel" ]] || continue
      mkdir -p "${p:h}"
      cp -cR "$src/data/$local_rel" "$p"
    done
    defaults export "$prefs" "$aside/preferences.plist"
    [[ -f "$src/preferences.plist" ]] && defaults import "$prefs" "$src/preferences.plist"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
    echo "Restored. Open Ark when ready (it's the backed-up app, on the system WebKit)."
    ;;
  *) sed -n '2,15p' "$0"; exit 1 ;;
esac
