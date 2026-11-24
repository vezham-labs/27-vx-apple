# Ark upstream sync log

Start each upstream review at the last synced commit. After applying and verifying a sync, add a log entry with the new upstream SHA, the Ark commit, and the changes adopted or skipped.

## Current Mac sync pass — November 24, 2026

The [incoming review inventory](ark-upstream-review.md) lists all 149 Browsa and 114 Search commits between the recorded baselines and the pulled heads, with a refined execution order that preserves the full goal. Both source checkouts are clean and match their remote-tracking heads. Review dispositions do not advance the last-synced baseline until adoption and verification are complete.

Arc is the reference for the entire sidebar's layout, styling, interactions, and animations. Browsa and Search supply implementation references; their UI is not the visual acceptance target. Prioritize Mac fixes while mobile runtime verification remains deferred.

Before reviewing incoming commits, Ark added insertion positions and a visible insertion marker for dragging pins within a folder. The previous drag resolver only calculated individual positions among root pins. `ark:build-mac` passed; interactive verification of this new folder reorder path is still pending. Earlier SpikeArk checks established pinning, moving into a folder, and returning to Today, but did not establish reordering.

Fetched upstream heads: Browsa `e981df56c551fc83efc39efe1b7d61cd7abe3071`; Search `33ec7aea1823c81c77a2be196e442dd54e36efa7`. These are review targets, not fully synced baselines. Neither reference checkout was switched or merged.

Adapted Browsa `85f6092a072347c472cc7e841ecbced7707e5ba5` in Ark's `PageActivity.swift`: coalesce media events over 200 ms instead of rescanning media for every event. Ark additionally cancels the pending report on `pagehide` so an old timer cannot overwrite the inactive report. Input and submit reporting remain immediate. An in-memory Node check of the extracted script verified that 100 media events scheduled one scan and page hide cancelled the pending timer. This uses a mock DOM, not live WebKit, and does not establish a measured CPU improvement. Live timing verification remains pending.

Next review candidates include upstream extension permission and redirect checks, private-window extension controls, and avoiding unchanged Live Folder writes. New upstream visual designs require comparison against Arc before adoption.

## Browsa

| Field                    | Value                                                                                                                           |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| Reference repository     | [jmaorr/Browsa](https://github.com/jmaorr/Browsa)                                                                               |
| Upstream branch          | `main`                                                                                                                          |
| Last synced upstream SHA | [`19eef7990aec8bd5491ef06ffc14928b7a73033f`](https://github.com/jmaorr/Browsa/commit/19eef7990aec8bd5491ef06ffc14928b7a73033f)  |
| Ark checkpoint           | `4610dbf947dcfbcbb21d5ef555fb50a3923baab2`                                                                                      |
| Status                   | Baseline imported. See the [Ark integration notes](../../apps-docs/docs/content/docs/ark/index.mdx) for build and test results. |

## Pending review

- [`ed71db69e6bd0647652563ee91a573b0e593dd2b`](https://github.com/jmaorr/Browsa/commit/ed71db69e6bd0647652563ee91a573b0e593dd2b) was one commit ahead of the baseline in the local Browsa checkout on November 23, 2026. It brings the Mac call window back on screen when its display is gone.

In the Browsa checkout, fetch the current upstream branch and list commits since the last synced SHA.

```sh
git fetch origin main
git log --oneline 19eef7990aec8bd5491ef06ffc14928b7a73033f..FETCH_HEAD
```

## Search

| Field                  | Value                                                                                                                               |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Reference repository   | [driceroland/Search](https://github.com/driceroland/Search)                                                                         |
| Upstream branch        | `main`                                                                                                                              |
| Source SHA for capture | [`6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`](https://github.com/driceroland/Search/commit/6f2b186bfa862d282ee9f424be1dfd5eb8ddc316) |
| Adopted                | WebKit PDF rasterization from `Snap.swift` for Ark Mac’s **Copy Full Page Image** command.                                          |
| UI reference           | Arc 1.174.1 on the local Mac exposes capture through File. Ark also offers the command through ⌘K.                                  |
| Verification           | The Ark Mac build passed. A 500-by-300 WebKit viewport produced a 500-by-1600 PNG that included offscreen content.                  |
| Pending review         | Region capture, mobile split tabs and site styles, pin folders, and iCloud sync.                                                    |

### Search audit increment: Mac automatic video PiP

| Field                 | Value                                                                                                                                                                                                                                                                                                                              |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reference repository  | [driceroland/Search](https://github.com/driceroland/Search)                                                                                                                                                                                                                                                                        |
| Search source SHA     | [`6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`](https://github.com/driceroland/Search/commit/6f2b186bfa862d282ee9f424be1dfd5eb8ddc316)                                                                                                                                                                                               |
| Ark implementation    | `d8d7209466f8c6438a7fd0f19381e33a7bc2f43a` adds opt-in Mac PiP for eligible ordinary videos and closes Ark-owned PiP before tab unload.                                                                                                                                                                                                       |
| Search files reviewed | `Sources/Search/NativePiP.swift`, `Float.swift`, and `Player.swift`. Ark adapted native system PiP; Search’s own floating WebView player remains a separate, open Mini player feature.                                                                                                                                                |
| Verification          | The isolated macOS 27.2 fixture passed tab-switch PiP, return to inline playback, muted-video exclusion, site-PiP ownership, and source-tab cleanup. Clean Mac Nx build passed. Mobile, app-deactivation, streaming-service, and performance checks remain open. The comparison and [Search audit](ark-search-audit.md) record scope and limitations. |

The adjacent **Mini player** row was reviewed against Search’s `Float.swift`. Its Ark-owned video window adds custom controls, positioning, resize, and docking behavior beyond native system PiP. This Mac gap has now been implemented and the basic open/play/return path verified; mobile custom-player parity remains open.

### Search audit increment: Mac Mini Player

| Field                 | Value                                                                                                                                                                                                                                                                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reference repository  | [driceroland/Search](https://github.com/driceroland/Search)                                                                                                                                                                                                                                                                           |
| Search source SHA     | [`6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`](https://github.com/driceroland/Search/commit/6f2b186bfa862d282ee9f424be1dfd5eb8ddc316)                                                                                                                                                                                                  |
| Search file           | `Sources/Search/Float.swift`                                                                                                                                                                                                                                                                                                           |
| Ark implementation    | [`bf17ed2`](../../../../commit/bf17ed2) adapts the floating player to an Ark-owned Mac panel and its command/menu, Library lifecycle, and WebKit bridge. Native PiP remains available.                                                                                                                                                |
| Verification          | `pnpm nx run ark:build-mac` passed. On macOS 27.2, the isolated Ark-branded fixture entered via ⌘K, advanced a 1280×720 video in the floating panel, produced a visible decoded frame in the WebKit snapshot, and restored inline playback when its tab was selected. No simulator or screen-recording API was used in the final fixture run. |
| Open                  | The Mac fixture verified Pause and Play against the video element and the native accessibility label. Minimize and Restore passed the frame round trip. Both seek buttons moved playback by 15 seconds. The optional swipe setting enabled right-edge docking and return in the local wheel-event fixture. Native corner drag events verified proportional resize and the minimum width. Exercise physical trackpad gestures and multiple displays; benchmark Ark’s ordinary-video panel; verify real streaming sites and custom-player parity on iPhone/iPad/Duo.                                                                                                                                                              |

### Search audit increment: Mac floating-window compositing

Search’s `Float.swift` records lower WindowServer GPU time for a live video window without its shadow in its 1080p and 4K checks. Ark applies that setting to the live WebKit call panel in `CallPiP.swift` (`hasShadow = false`). The clean Mac Nx build passed. Ark’s own runtime GPU benchmark and visual review remain open, and the ordinary-video mini player remains a separate gap.

| Field                | Value                                                                                                                                                                                                                                               |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reference repository | [driceroland/Search](https://github.com/driceroland/Search)                                                                                                                                                                                         |
| Search source SHA    | [`6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`](https://github.com/driceroland/Search/commit/6f2b186bfa862d282ee9f424be1dfd5eb8ddc316)                                                                                                                |
| Ark commit           | [`cdfb068`](../../../../commit/cdfb068)                                                                                                                                                                                                             |
| Verification         | `pnpm nx run ark:build-mac` passed. No simulator was started. Ark runtime GPU measurement and floating-panel visual review are pending; no Ark performance delta is claimed.                                                                         |

### Search follow-up: manual Mac PiP control

| Field                | Value                                                                                                                                                                                                                                                                         |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reference repository | [driceroland/Search](https://github.com/driceroland/Search)                                                                                                                                                                                                                   |
| Search source SHA    | [`6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`](https://github.com/driceroland/Search/commit/6f2b186bfa862d282ee9f424be1dfd5eb8ddc316)                                                                                                                                          |
| Ark follow-up        | `250fb410abf3fea0edd43be7c47908fa91939c36` adds View → Picture in Picture, ⇧⌘P, and a command-bar action to toggle the current page’s largest ready video. The customizable shortcut uses the Search default.                                                                                                    |
| Verification         | The isolated macOS 27.2 fixture passed manual entry and return with automatic mode off, plus automatic entry, return, muted-video exclusion, and source-tab cleanup. The clean-source Mac Nx build passed. The Search-style custom video window remains an open Mini player gap. |

### Feature audit

The [Search feature audit](ark-search-audit.md) maps all 42 comparison rows to Search and Ark code. This pass adds a last-used-tab action and versioned Space link export on Mac. It also moves full-page PNG rasterization and encoding off the main thread.

The Mac build passed. Local fixtures checked tab selection and Space isolation, export ordering and filtering, and offscreen capture on a worker thread.

### Mac site styles and previews

Ark Mac now supports host-scoped CSS through **Edit Site Style**. A local WebKit fixture verified live changes and reload persistence. Another host and a private tab kept the original styling. Clearing the saved CSS restored it on the styled host.

The [Mac preview gallery](../../preview/index.html#ark-mac-features) and [audit](ark-search-audit.md#mac-previews) include the editor, applied style, last-used tab, full-page capture, and Space export.

The [archive microbenchmark](ark-search-audit.md#mac-archive-measurement) measured a drop from 48.433 ms to 0.713 ms for the removal step with 10,000 synthetic tabs and 5,000 stale entries.

### Mac Split View

Ark Mac now pairs two Today web tabs from the same Space. Its pane state follows the pinned Search reference’s separation of tab order, axis, size, and focus. Ark records this state per window and Space through scene storage.

The isolated app fixture verified both viewport layouts, mouse focus, keeping the unfocused pane out of the archive, reopening a pair by selecting one of its tabs, and leaving the partner open when a pane closes. The saved-state codec round-tripped the pair. Full app relaunch and mobile verification remain open. The [Mac gallery](../../preview/index.html#ark-mac-features) includes the side-by-side preview.

### Space link transfer

Mac and iOS now import and export the same version 1 Space link files through BrowserKit. Import creates a new Space with the original pinned and Today link order and defers opening pages. Folder structure and browser session state remain outside this file format. Search’s pinned source has bookmark import and sync, so Ark uses its own Space file format.

The Mac and iOS builds and 85 BrowserKit tests passed. The archive tests cover version 1 compatibility, link filtering and ordering, and import limits. The Mac fixture opened both native file dialogs. On iPad Pro 11-inch (M5), the UI test found both transfer controls and opened the native Files exporter for the Personal Space. Saving and reimporting through Files and the iPhone and Duo UI checks remain open. The [Mac preview gallery](../../preview/index.html#ark-mac-features) includes the import command and stacked Split View.

### Full-page capture on iOS

Ark now uses one BrowserKit renderer for the full-page capture adapted from Search's `Snap.swift`. Mac keeps its File and ⌘K commands. The iOS page menu copies the PNG to the device-local clipboard. Rasterization and encoding run off the main thread with a 16-megapixel budget and a 16,384-pixel dimension limit.

The Mac and iOS builds passed with 87 BrowserKit tests. The renderer tests verified that the full PDF height is preserved and that tall output is bounded. An isolated Mac fixture copied a 2,456-by-2,044 PNG with content below the viewport. The [Mac gallery](../../preview/index.html#ark-mac-features) also shows Space Routing, Custom Shortcuts, and the ad and tracker blocking controls.

The iPhone 18 Pro and iPad Pro 11-inch (M5) simulators opened the page menu, ran Copy Full Page Image, and displayed the copy confirmation. The iPad passed after extending the XCTest time allowance. On Duo, Xcode first stalled while connecting to Instruments. After an explicit boot-status wait, the simulator reported Data Migration Failed, and Xcode stalled during app installation before running any tests.

### Mac region capture

**Copy Page Area** in File and ⌘K opens a drag selection for the active web viewport. WebKit captures the selected rectangle and BrowserKit encodes the PNG off the main thread. The clipboard write uses the same host-local and private-tab handling as full-page capture. The Search reference covers viewport rectangle and output sizing in `Snap.swift`. Ark's picker uses AppKit view coordinates.

Mouse events sent through Ark's AppKit dispatcher selected a 300-by-180-point area and produced a 600-by-360 PNG with matching page content. Cancelling left the clipboard unchanged. The build and all 87 BrowserKit tests passed. The [Mac gallery](../../preview/index.html#ark-mac-features) includes the selection and the cropped PNG.

### iOS region capture

**Copy Page Area** in the page menu opens a selection over the live viewport. Drag to choose an area, then tap Copy Area. The picker tracks the active tab and page, and BrowserKit copies the resulting PNG to the device-local clipboard.

Mac and iOS now share the viewport image sizing adapted from Search's `Snap.swift`. Both apps built and all 88 BrowserKit tests passed. The sizing test checks native resolution and both output limits. iPhone 18 Pro and iPad Pro 11-inch (M5) verified that a drag enables Copy Area, copies the PNG, and closes the picker. Duo region verification remains open.

### Element capture

Ark uses a WebKit element hit test and converts the result from CSS to view coordinates, following the viewport geometry in Search's `Snap.swift`. The Mac command is in File and ⌘K, and iOS exposes it under More. The capture clips the element's rectangular bounds to the visible viewport.

The Mac fixture clicked the Observations heading through the app's event dispatcher and copied a 1,424-by-62 PNG matching the heading's bounds. The [Mac gallery](../../preview/index.html#ark-mac-features) includes both the picker and its output.

The iOS build passed. The iPhone 18 Pro and iPad Pro 11-inch (M5) simulators selected a named element on a local page and displayed the clipboard confirmation. Duo element verification remains open.

### Mac Recent Tabs

Ark applies the recent order and bounded previews from Search's `TabSwitcher.swift` and `Tab.swift` to its own keyboard and mouse picker. It offers up to eight tabs in the current window and Space. Previews request at most 192 points from existing WebKit sessions and run one at a time. Private and unbuilt tabs use icons.

The [synthetic ownership-filter measurement](ark-search-audit.md#mac-recent-tabs-measurement) went from 699.902 ms to 1.037 ms for 10,000 candidates across two windows, with identical output.

The Mac fixture showed previews for two loaded pages and an icon for the dormant tab. It confirmed the picker left that tab unloaded until Down and Return selected it. Open Recent Tabs in the Tabs menu, in ⌘K, or with ⇧⌘A. The [Mac gallery](../../preview/index.html#ark-mac-features) includes the picker.

### iOS site styles

**Edit Site Style** in the iOS page menu saves CSS for the current HTTP or HTTPS host. Mac and iOS use the same BrowserKit store and WebKit stylesheet code, adapting the pinned Search reference's host-scoped CSS. Private tabs stay excluded. Mac Agent tabs stay excluded as well.

Both builds and all 90 BrowserKit tests passed. The new tests cover persisted edits, clearing, and host normalization. The Mac fixture verified live application, persistence across a page reload, unchanged styles on a different host and in a private tab, and removal without reloading. The first iPhone run saved CSS and verified the heading disappeared. XCTest exceeded its allowance, then tapped Reload when trying to reopen the editor. The corrected retry timed out during XCTest accessibility initialization before the test started. The mobile clear check remains open.

The iPad retry reached XCTest's launch step, where the runner reported that Ark had no process ID. It did not reach the CSS editor.

### iOS Space Routing

**Space Routing** under Settings → Tabs adds opt-in host and path rules for new tabs opened from the address sheet and links received from other apps. External links without a matching rule use the existing destination setting. Ark leaves in-page navigation and popups with their originating tab. This follows the site-to-Space approach in Search's `SpaceRoutes.swift` and shares Ark's Mac matcher and sign-in and checkout exceptions.

The Mac and iOS builds and all 93 BrowserKit tests passed. The routing tests cover path precedence, subdomain and path boundaries, rules whose destination is missing, sign-in exclusions, and compatibility with older settings files. Mobile Settings and default-browser handoff still need runtime verification. The existing [Mac Space Routing preview](../../preview/ark/mac/features/space-routing.png) shows the Mac rule editor.

### Mac Link Preview window

Enable **Open links from other apps in a preview window** under Mac Settings → General. Ark opens external web links in a compact window and adopts the live page when you choose Open as Tab. This follows the session handoff in Search's `Little.swift`. Ark prioritizes its Space Routing rule, then the external-link fallback, then a regular Space. Escape closes the preview and ⌘Return opens it as a tab.

The Mac build passed. A local fixture verified promotion to the configured Space with the very same engine page, as well as closing without leaving a tab. Both checks passed in the first run and again after extending the preview tour's time limit. System default-browser launch from a closed Ark instance remains unverified. The [Mac preview gallery](../../preview/index.html#ark-mac-features) includes the compact window.

### Pinned folders

Ark adapts Search's per-Space folder records and stable pin membership from `PinFolders.swift`. Create, rename, collapse, and remove folders in the Mac and mobile sidebars or the mobile tab gallery. Use a pinned tab's **Move to Folder** menu to organize it. Removing a folder lifts its children to the parent and preserves the pin order. Space link export carries folders as optional fields, and import generates fresh folder IDs.

Both builds passed. All 97 BrowserKit tests passed, including nested snapshot and Space file round trips, legacy snapshots, and repair of invalid memberships. The Mac fixture verified that collapsing a nested pin kept its page selected, and the [Mac gallery](../../preview/index.html#ark-mac-features) shows the hierarchy. The iPhone 18 Pro and iPad Pro 11-inch (M5) UI tests created and collapsed a folder in the tab gallery. Duo UI verification and mobile nested membership remain open.

Mac adapts the folder-heading drop target from Search’s `PinDrop.swift` to Ark’s sidebar drag controller. The Mac build and local fixture verified that dropping a Today tab into a nested folder pins it, and that dragging a pin between parent and child folders keeps the tab selected. The [updated Mac preview](../../preview/ark/mac/features/pinned-folders.png) shows the result of the fixture’s drop. Reordering within a folder and native mobile folder dragging remain open.

The Duo folder test retry started with all other simulators shut down. CoreSimulator reported `Data Migration Failed` during boot again, and Xcode flagged the Duo runtime build version as invalid. After eight minutes without reaching the test, the run was stopped and the runner shut down Duo.

### Arc pinned-folder import

The Mac importer reads Arc's legacy string markers and newer object markers, using the structure in Search's `ImportArc.swift`. It imports nested pin folders and retains the source order of pinned and open tabs. Pins in deeper folders go into the nearest imported ancestor at Ark's three-level limit. The parser bounds its traversal and skips duplicate or cyclic nodes.

The Mac build passed. A local fixture verified the new and legacy markers in one Space, nested folder membership, pin order, continued import of open tabs, and skipping local file URLs. The [Mac preview](../../preview/ark/mac/features/arc-folder-import.png) shows the imported fixture Space.

### Live Folders

Ark adapts the RSS and Atom parsing, discovery, and stable article identity from Search’s `LiveFolders.swift`. Add a live folder at the root or below an existing folder, using a feed address or a page with a feed link. Selecting an article opens a tab in that Space. An open folder list refreshes in the background at most every 15 minutes, and **Refresh Feed** is available in the folder menu.

BrowserKit uses a session without cookies or saved credentials, limits each response to 2 MB, and retains up to 30 distinct web links per feed. Article URLs provide stable identities across refreshes. An unsuccessful refresh preserves the last saved articles. The shared tests cover RSS links and GUIDs, Atom alternate links, website discovery, parser bounds, stable identity, and snapshot compatibility.

The Mac and iOS builds and all 101 BrowserKit tests passed. The Mac fixture discovered a feed from a local page, refreshed an article title with the same article ID, and preserved the updated cache when the feed returned HTTP 503. The iPhone 18 Pro UI test added a loopback RSS feed in the tab gallery and opened the article in a browser tab. The [Mac screenshot](../../preview/ark/mac/features/live-folder.png) shows the refreshed articles. Arc-specific integrations and iPad and Duo runtime verification remain open.

Space link files now carry a Live Folder’s feed address. The receiving Space starts with an empty cache and waits for **Resume Feed** before fetching. The paused state survives an app restart. All 103 BrowserKit tests passed, including the subscription round trip and rejection of a file URL as a feed source. The Mac fixture confirmed that background refresh left the imported feed empty and a manual refresh fetched its articles.

The iPad Live Folder run reached XCTest after a CoreSimulator data migration warning. XCTest failed at app launch because it received no Ark process ID. The test never reached the tab gallery.

### Shared Collections

Ark shares a whole Space from Settings or a pin folder from its context menu. The system share sheet passes an importable Ark collection file. Sharing a folder carries its nested folders and pinned links, and leaves out parent folders, sibling folders, and Today tabs. Import opens the collection as a new Space.

The Mac and iOS builds and all 104 BrowserKit tests passed. The collection test exported through the system transfer format and reimported the payload, preserving nested membership and pin order. It also confirmed that the payload excluded unrelated links. The [Mac preview](../../preview/ark/mac/features/shared-collections.png) shows the Share controls. The pinned Search reference’s `Sharing.swift` covers page sharing. Delivery to another device, hosted collection links, and access controls remain open.

### Mobile Recent Tabs

Ark adds a visual picker to the mobile tab gallery and to the quick menu on the Tabs and Sidebar buttons. It uses the active tab first, then the current Space’s most recently used tabs, up to eight. This adapts Search’s `TabSwitcher.swift` ordering and preview approach to Ark’s existing tab gallery. The picker reuses cached images and uses an icon for private tabs. It requests no new WebKit page captures.

The iOS build and all 105 BrowserKit tests passed. The ordering test verifies the selected tab’s priority, recency across pinned and Today tabs, and the result limit. The iPhone 18 Pro UI test opened the visual picker from the gallery and switched to a previous tab. iPad and Duo runtime verification remain open.

### Mobile Split View

**Open Split View** in the page menu pairs two regular web tabs in the current Space’s Today list. You can also hold a tab in the gallery or sidebar and choose **Open in Split View**. Tap a pane heading or the page to direct the address bar and page commands to that tab. Drag the divider to resize the panes, or use **Separate Tabs** to return to one page. Narrow layouts stack the panes and wider layouts place them side by side. The pair and divider position are saved with the Space. Selecting another tab hides the pair until a member is selected again.

The iOS build and all 106 BrowserKit tests passed. The model test checks selection, resize bounds, restoration, and handling a missing member. Active members stay out of both session eviction and auto-archive. The first iPhone run stopped while locating the More button, before Split View opened. The iPhone 18 Pro retry opened Split View through the gallery context menu, confirmed both pages were live, and switched focus by tapping a pane heading and then a page. Duo runtime checks, pairing pinned tabs, and support for more than two panes remain open. The implementation follows Search’s split grouping in `Split.swift` and `PaneStage.swift`, and uses Ark’s mobile WebKit host for both pages.

The iPad Split View run passed app launch and opened the gallery, then timed out looking for the first tab’s title before it invoked Split View. The retry used stable fixture titles and passed on iPad Pro 11-inch (M5). It opened both pages and switched focus by tapping a heading and a page.

### Profiles per Space

Source audit confirmed that Mac `WebKitEngine` and mobile `WebViewPool` share the default WebKit website data store across regular Spaces and use a temporary store for Private. Search’s `Profiles.swift` keeps the default store for the existing profile and creates persistent WebKit stores keyed by UUID for additional profiles. The comparison records the current gap on all four platforms. Profile assignment, history and extension isolation, and runtime verification remain open.

The Mac engine now accepts a named browsing profile and reuses the persistent WebKit store for its UUID. Named pages have no extension controller while profile-aware extension isolation is open. The Mac build passed. A local debug fixture verified that two pages with the same profile share a cookie, other named, default, and private stores cannot read it, and clearing the named profile removes the cookie. Space assignments, mobile stores, scoped history and extension support remain open.

Mac Settings → Spaces now creates and assigns named website profiles. You can assign the same profile to multiple Spaces to share website sign-ins and storage. Existing Spaces keep their default store. Switching a Space’s profile reloads its tabs. Moving a tab within the same profile keeps its live page. Moving across profiles rebuilds it without the old back/forward state. Glance and Link Preview use the appropriate store. Profile-specific history and extensions and mobile assignment remain open.

The Mac build and all 107 BrowserKit tests passed. The Mac fixture verified that assignment rebuilt a WebKit page in the named store, same-profile moves kept the page, and cross-profile moves rebuilt it in the destination store. The shared snapshot test verified named profiles and assignments round-trip, with older settings retaining their defaults. The [Mac preview](../../preview/ark/mac/features/space-profiles.png) shows two Spaces sharing the Research profile.

Mobile Settings → Spaces now supports the same named website profile assignments as Mac. Switching profiles retires old WebKit sessions, clears stored navigation state and thumbnails, and mounts a page in the destination store. Restoring an archived or recently closed tab into a different profile drops its prior session and preview. The mobile clear-data action covers Default and named stores. The iOS build passed. The iPhone 18 Pro fixture verified cookie sharing between two Spaces assigned to one profile, separation from Default, and session replacement when assigning a profile and returning to Default. The iPad Pro 11-inch (M5) fixture passed the same checks on the final mobile build. CoreSimulator reported a migration warning before XCTest completed successfully. Only one simulator ran at a time.

Search’s `Profiles.swift` also keeps a history file per profile. Ark now records visits against the page’s WebKit profile and reads that profile in address suggestions. Suggestion results for open and archived tabs follow the same scope. The existing Default history file stays in place, and Clear History clears all profile history stores. Favourites remain shared, and named Mac profiles still lack extensions.

Both builds passed. A local storage check verified isolation after reopening files and clearing cold stores. A local Mac check verified that a named WebKit page’s visit appeared in another Space assigned the same profile and stayed out of Default suggestions. Mobile suggestion runtime checks remain open. The test-only changes used for these checks are omitted from this milestone.

### Pinned tabs in Mac Split View

Mac can pair a pinned web tab with a Today tab or another pin in the same Space. The chooser omits pins visible in another window, and reopening a saved split keeps it closed while a pane is busy elsewhere. Pinning or unpinning a pane in the same Space preserves its pair and divider. The production build passed. A temporary local Mac fixture verified the two live panes, window ownership, pinning and unpinning, and keeping the remaining pane on close. The [Mac preview](../../preview/ark/mac/features/pinned-split-view.png) shows a pin next to a Today tab. Mobile pinned tabs and splits with more than two panes remain open.

### Pinned tabs in mobile Split View

Mobile uses the same tab actions to pair a pin or Today web tab with the focused tab. Pinning and unpinning preserves the pair and divider. Closing a pinned pane ends the split and keeps the pin in the gallery or sidebar. Closing the focused pane selects its partner when the split is visible. All 107 existing BrowserKit tests passed after updating the existing Split View assertion for pinned membership. The iPhone 18 Pro runtime check passed. It opened a pinned pane through the gallery, switched focus between both live pages, and closed the pinned pane while retaining the pin and showing its partner. The temporary fixture stayed outside the commit. iPad and Duo pinned-pane verification remain open.

### Four-pane Mac Split View

**Add Pane** in Split View options adds up to four live web tabs from the current Space, following Search’s ordered groups in `Split.swift`. Dividers resize adjacent panes. Closing a pane preserves the group and focuses its neighbor when the closing pane was focused. Existing two-pane state decodes with its original orientation, focus, and size.

A temporary local Mac fixture verified four live views in order, neighbor-only resizing, saved proportions, and closing one pane while keeping the remaining three. A standalone Swift check verified legacy state and divider bounds. The [Mac preview](../../preview/ark/mac/features/four-pane-split-view.png) shows the resized four-pane layout. The temporary fixture stayed outside the commit. Multiple mobile panes beyond two and Mac relaunch verification remain open.

### Four-pane mobile Split View

**Add Pane** in the page menu and **Add to Split View** in the tab context menu can add up to four pinned or Today pages in a Space. The layout remains stacked on narrow displays and side by side at wider widths. Resizing a divider moves only its adjacent panes. Closing a pane keeps the remaining group and focuses a neighbor when needed. Visible panes stay in the WebKit pool and out of auto-archive. Existing two-pane snapshots decode with the same proportions.

The production iOS build and all 107 BrowserKit tests passed. A standalone Swift check verified legacy decoding, divider bounds, and the four-pane round trip. The first iPad run started with three panes, then the gallery long-press selected the candidate without opening its context menu. The page-menu retry hit a split heading while looking for the address bar and timed out before opening **More**. The corrected run was canceled during launch when the audit switched to Mac first. Four-pane runtime checks on iPhone, iPad, and Duo remain open.

### Mac Split View startup archive

The startup archive sweep now runs after AppKit finishes restoring windows, giving the SwiftUI window roots a chance to register visible panes. A temporary Mac fixture restored a four-pane group from saved state with all panes old enough to archive. It retained the group's saved orientation, divider sizes, and focus while sending an unrelated stale tab to Archive. The production Mac build passed. Full macOS quit-and-relaunch verification remains open.

### Clean Links

Search’s `CleanLink.swift` preserves the raw query fields and skips signed URLs. Ark now does the same in BrowserKit while preserving its existing tracker list for Mac and mobile copy and navigation. The 12-URL fixture covered signed queries, encoding, repeated and empty fields, fragments, and site rule boundaries. The previous code passed six cases. The updated code passed all 12, and all 107 existing BrowserKit tests passed. The [Mac preview](../../preview/ark/mac/features/clean-link-copy.png) shows the Copy Link command.

In a local release-optimized Swift benchmark, the median of seven paired runs over the same 60,000-URL batch fell from 1,144 ms to 755 ms. Each batch mixed untracked, tracked, encoded, and signed URLs. This measures URL cleaning, including result serialization, within a single process.

### Mac Glance handoff

Search’s `Peek.swift` moves the live preview into the tab. Ark now does the same for a finished Glance page when the destination uses the same website profile and engine and the URL needs no cleanup. The normal tab-opening path remains in use for other destinations and incomplete pages.

A loopback fixture served a page with caching disabled. Expanding Glance went from two main-document requests to one and retained the same WebKit view and a DOM change. The fixture also verified that the promoted page mounted in the browser window and entered history. Promotion from Default to Private created a separate view with a nonpersistent data store.

### Mac Glance from the sidebar and command bar

Sidebar tabs and favourites and command-bar URL results now offer **Preview Link**. The command bar also previews a selected link or typed URL with ⌥Return. The Mac fixture sent that keystroke to the native field, loaded the preview, and verified that the current tab stayed selected. It also checked that a preview requested from a private tab used a nonpersistent website store and that a non-web URL was rejected. The sidebar context menus use the same action. The [Mac screenshot](../../preview/ark/mac/features/command-bar-link-preview.png) shows the preview over the original tab. Hover and a configurable click modifier remain open.

### Mac Glance into Split View

Search’s `Peek.swift` offers keeping the preview beside its source. Ark’s **Open in Split View** button and ⌥⌘Return put Glance beside the current page or add it to that Space’s open split. The action is available when the website profile matches, the current tab can split, and the group has room.

The Mac fixture sent the keyboard shortcut, verified separate visible frames for both pages, and confirmed the transferred WebKit view used one main-document request from preview through handoff. It added a third and fourth pane without dropping the original tabs, rejected a fifth pane, and checked that a private preview could not enter a regular split. The [Mac screenshot](../../preview/ark/mac/features/glance-split-view.png) shows the loaded pages side by side.

### Mac sidebar Clean Links

Copy Link from a sidebar tab or favourite now takes the same path as the Mac command-bar action, and the command-bar subtitle shows the URL the action will copy. The fixture used a separate pasteboard and verified that the setting controls the copied URL and subtitle, that encoded values and fragments survive, and that signed URLs and the already open tab URL stay intact. The [Mac preview](../../preview/ark/mac/features/clean-link-copy.png) shows the cleaned URL. WebKit’s separate Mac Copy Link action for links inside a page still needs coverage. Search’s `Tab.swift` implements its clean command by invoking the native copy action and polling the general pasteboard.

### Mac command bar ranking

The command bar now ranks once per render or arrow-key action and uses those same rows for the highlight and Return target. Search’s `AddressCommands.swift` and `Fuzzy.swift` use a different matcher. Ark retained its ranking rules and removed repeated evaluation of the current command provider.

With 403 commands and 320 updates per paired run, the local Swift benchmark fell from 3,114.3 ms to 779.3 ms at the median of seven pairs. The comparison checked displayed results, selection, and keyboard actions. The Mac runtime fixture typed **last used tab** into the native field and confirmed Return switched back to the previous tab. The measurement covers local row generation and selection logic. SwiftUI rendering and remote suggestions were outside the workload.

### Mac routing by source app

Routing settings can assign an installed app to a Space. Ark looks up the sender of an external URL event by its Apple Event sender PID. When a source-app rule matches, it takes priority over site rules. Unknown senders follow the existing site and fallback rules, and sign-in and checkout exclusions still apply. The resolved destination goes to Link Preview or the first-window request when no normal window is open. Search’s `SpaceRoutes.swift` references site rules and destination windows. [Apple Event sender attribute](https://developer.apple.com/documentation/coreservices/keysenderpidattr)

An isolated macOS sender opened a loopback URL through LaunchServices. Ark identified its bundle ID and routed the link to Work despite a matching site rule for Personal. The local fixture also checked excluded sign-in URLs, disabled routing, unknown senders, Link Preview handoff, an isolated preferences round trip, and the queued first-window destination. The fixture addressed the isolated Ark bundle directly. The [Mac preview](../../preview/ark/mac/features/space-routing-source-app.png) shows the source-app setting. [LaunchServices fixture entry point](https://developer.apple.com/documentation/appkit/nsworkspace/open%28_%3Awithapplicationat%3Aconfiguration%3Acompletionhandler%3A%29)

### Mac site customization and hidden elements

Search’s `Curtain.swift` and `Hidden.swift` save hidden elements by host and let you restore them individually. Ark uses its existing element picker and stylesheet pipeline. **Hide Page Element…** is available from the View menu and ⌘K. The selected element stays hidden for that host, with immediate Undo and a Restore button for each entry in Site Style. The custom CSS file retains its format. Hidden selectors are saved separately beside it.

A Mac fixture used native mouse events to select a heading. It verified the hide in two tabs on the same host, checked that custom CSS stayed active, and exercised Undo, reload, restore, a Private tab, and reopening the saved store. All 107 existing BrowserKit tests passed. The mobile picker remains open. [Mac hide preview](../../preview/ark/mac/features/site-style-hidden-element.png) [Mac restore preview](../../preview/ark/mac/features/site-style-restore-element.png)

### Mac Developer Mode in named profiles

The Developer Mode row references Search’s `Inspector.swift` at `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`. Ark’s WebKit engine now applies the current developer extras preference when creating a named profile configuration and updates cached configurations when it changes. Before the fix, enabling Developer Mode before opening the first named-profile tab left that tab’s preference disabled. The same Mac fixture passed after the fix for named, Default, and Private pages. It also verified disabling the preference on live pages and reopening a named-profile page after re-enabling it. The preference checks read actual WKWebView settings. A subsequent macOS 27.2 run verified the command was offered for a named-profile page and invoked the same suggestion action used by the command bar. WebKit reported the inspector hidden before the action, visible afterward, and hidden after closing. The Mac build passed. Implementation commit: `dda6650`.

### Content-blocking updates finishing out of order

Ark's `WebKitEngine.applyBlocking` now assigns compiled rules only after checking that the requested settings are still current. Previously, enabling blocking and then disabling it while compilation was pending could leave stale rules cached for subsequently registered pages even though existing pages had their rules removed. A temporary Swift harness extracted the actual method and used a suspended compiler stub: before the fix the cache contained old rules while installed rules were empty; afterward both remained empty. This verifies the async state transition, not live WebKit network blocking. `pnpm nx run ark:build-mac` passed. No persistent test files or screen-recording access were needed. Search reference remains `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`; this is an Ark engine correctness fix.

### Mac extensions in named profiles

Search `Profiles.swift` and `Extensions.swift` at `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316` share one extension controller across profiles. Ark now attaches its existing shared controller to named-profile configurations, preserving each website data store. Installed extensions and their own settings remain shared, not isolated per profile.

The Mac fixture loaded a local Manifest V3 extension through Ark's actual extension loader. Its content script changed the named-profile page, while Default cookies and local storage were absent there; writing named-profile values left Default unchanged. The fixture also exposed an options-page failure: normal tab creation supplied the extension URL after creating its web view. Extension URLs now reach page creation first so WebKit selects the extension's own configuration. The same options page changed from a blank page with `NSURLErrorDomain -1008` to loaded content with no navigation error.

The Mac build passed. The temporary runtime hook was removed from `SnapshotTour.swift`. The [preview](../../preview/ark/mac/features/named-profile-extension.png) is a real WebKit page snapshot of the local content-script fixture, not a screenshot of a third-party extension. Store-extension compatibility, private-profile extension access, and cross-profile extension messaging were not validated by this fixture. The Profiles row remains Partial for the outstanding scope.

### Mac extension unload lifecycle

Search `Extensions.swift` at `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316` invalidates pending load tickets and retires extension resources on unload. Ark now invalidates its pending load generation, cancels keep-alive timers, stops and releases hidden keep-alive web views, and clears ping timestamps before unloading contexts.

A temporary Mac runtime fixture loaded a local MV3 background extension twice and inspected actual timers and weak web-view references after each unload. Before the fix, each unload retained one valid timer and one hidden view. After the fix, both cycles retained zero timers, the previous timers were invalid, and the views were released. A controlled suspension immediately after the async extension constructor tested unload during loading: the old code ended with one extension, timer, and view; the fixed code ended with zero of each. No fixture errors were reported. The artificial suspension makes the race repeatable; it is not an extension startup benchmark.

Temporary instrumentation was removed. The final Mac build passed. These checks establish resource teardown and cancellation behavior, not a quantified RAM, CPU, or battery improvement. Extension compatibility ratings remain unchanged.

### Mac Auto PiP when switching apps

The opt-in Auto PiP setting now covers switching away from Ark as well as switching tabs. When Ark resigns active, the visible regular tab may enter system PiP; when Ark becomes active again with that tab visible, Ark returns playback inline. Pending app-switch requests cancel if Ark regains focus before PiP starts. Calls, private tabs, Agent spaces, muted video, and Mini Player-owned tabs remain excluded. The setting label now describes both triggers.

A temporary Mac fixture played the local Ark video, activated Finder, and read WebKit presentation state from the live page: `picture-in-picture` while Ark was inactive, then `inline` after returning to Ark. `pnpm nx run ark:build-mac` passed, and temporary fixture code was removed. iPhone, iPad, Duo, and third-party streaming behavior remain open.

### Favorites follow website profiles

Search's `Profiles.swift` stores bookmarks by profile. Ark now stores favorites under the active website profile on Mac and the shared iOS app; Spaces assigned to the same profile see the same favorites. Existing snapshots without profile data keep their current favorites in Default, retaining order and IDs. New snapshots write the per-profile map and preserve the legacy Default field for compatibility. Profile-specific favorites also feed each profile's suggestions and bookmark history. A one-run DEBUG fixture, launched with isolated state, verified named-profile favorites appeared in both assigned Spaces, stayed separate from Default, and survived snapshot encoding. The temporary hook was removed. `pnpm nx run ark:build-mac --skip-nx-cache` and `pnpm nx run ark:build-ios --skip-nx-cache` passed. `pnpm nx run browser-kit:test-swift --skip-nx-cache` passed, including old-snapshot decoding and per-profile map round-tripping. Runtime checks on iPhone, iPad, and Duo remain open; Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Keep loading pages out of Mac LRU eviction

Search's `Sleep.swift` treats loading pages as awake. Ark's 24-controller LRU previously considered a loading, off-screen page evictable if its current `PageState.isBusy` was false. Eviction now also checks `PageState.isLoading`, preserving navigation in progress while retaining the existing cap for inactive ready pages. `pnpm nx run ark:build-mac --skip-nx-cache` passed. This is a state-transition safety fix, not a measured memory-performance improvement; Ark's timer-based tab sleeping and memory-pressure response remain unimplemented.

### Mac screenshots for theme and Developer Mode

An isolated DEBUG snapshot run captured the actual Space Theme editor and Settings → Advanced screen, including the Inspect Element toggle. Temporary snapshot-only code was removed. The images are linked from the Theme picker and Developer mode rows in the local comparison matrix.

### Mac idle-page unloading

The freshly built dist bundle launched through Launch Services and generated the [idle page settings preview](../../preview/ark/mac/features/idle-page-unloading.png), confirming screen recording access for that build identity.

Following Search's `Sleep.swift`, Mac Settings → General now offers Never, 10 minutes, 30 minutes (default), or 2 hours for releasing inactive WebViews. Ark saves WebKit session state before releasing the page and restores it when the tab is selected. A 60-second task checks idle pages; memory pressure reduces the limit to five minutes, or zero when critical. It skips visible, private, loading, and busy pages; calls, Agent tabs, Mini Player and Ark-owned PiP pages; active page media; prompts; and active downloads. Closing the last window releases eligible pages immediately. A one-run DEBUG fixture used a local HTML page and verified the page controller was released with session state, then recreated at the same URL when selected. The fixture was removed. `pnpm nx run browser-kit:test-swift --skip-nx-cache` and `pnpm nx run ark:build-mac --skip-nx-cache` passed. The fresh build app also generated the [idle page settings preview](../../preview/ark/mac/features/idle-page-unloading.png), confirming its screen recording access. Memory reduction has not been quantified. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Mac pinned-folder drag placement

Search's `PinTree.folderPlace` permits moving a folder heading before a sibling, into a folder, or to the end of a parent. Ark's `PinFolderList` now accepts folder drags on folder, pin, and root rows. `Space.movePinFolder` preserves sibling ordering and rejects cycles, live-folder parents, and moves deeper than Ark and Search's shared three-level limit. BrowserKit's 55 Swift tests passed, including coverage for reordering, nesting, cycles, and depth; `pnpm nx run ark:build-mac --skip-nx-cache` passed. The interactive Mac drop gesture remains unverified; the pinned-folder preview shows the nested layout. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Mac profile management

Search's `Profiles.swift` exposes profile creation, renaming, and deletion. Ark's Mac Settings → Spaces now supports the same management for per-Space website profiles. Renaming retains the profile UUID. Deletion asks for confirmation, returns assigned regular Spaces to Default, waits for their WebViews to unload, clears the named store's data and releases its cached configuration, then removes the per-profile history folder, favorites, archive records, and recently-closed records. A WebKitEngine regression test confirms a recreated store has no previous cookie. WebKit may retain the now-empty store registration while its network process is active, so physical store removal is best effort. BrowserKit's 59 tests passed, including profile-name validation and history-directory removal, and `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. Runtime deletion through Mac Settings remains unverified. Mobile rename/delete and Duo checks remain open. The current debug bundle ID is `app.vezham.ark.dev`; Launch Services returns `kLSNoExecutableErr` when opening the built bundle, and screen recording access is unconfirmed, so a new UI preview is pending. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Mac Peek click modifier

Search's `Prefs.swift` and `Peek.swift` let the user choose Shift-click, Option-Shift-click, or Option-Command-click. Ark's General settings now offer those choices plus the existing Option-click default. WebKit opens Glance only when the exact configured modifier set is held, leaving command-click and middle-click new-tab behavior intact for the other choices. BrowserKit tests cover all four mappings and reject extra modifiers. Hover previews remain open. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Profile scope comparison

The pinned Search `Profiles.swift` models separate browser profiles that own Space collections and browsing data, while intentionally sharing a single WebExtension controller across profiles. Ark's `WebsiteProfile` instead scopes website data to a profile assigned per Space. The comparison remains Partial because these are different profile boundaries and mobile rename/delete plus Duo runtime checks remain open; shared installed extensions match Search's explicit design and are not a Search parity gap. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Arc web app previews audit

Arc's 2021 Mac release notes define Previews as service-specific integrations on favorite web apps, showing recent pages and common actions. Code review found no equivalent in Ark or the pinned Search source; Ark Glance is a generic link preview and remains in the separate Peek row. Comparison status is No across Ark platforms. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Cross-device sync audit correction

The current Search `Sync.swift` is an opt-in user-folder transport for Macs, not the older CloudKit design recorded in the audit. It merges selected settings, Spaces, pins, pin folders, and bookmarks, while deliberately excluding open tabs and other device-local data; it has no iOS client. At the time of this audit Ark had no sync transport. Comparison status is No across Mac, iPhone, iPad, and Duo. Search's merge model is a reference for Ark, but its transport does not satisfy the four-client goal. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Shared sync merge core

Added a Foundation-only keyed merge core to BrowserCore for use by both Apple app targets. It resolves concurrent values deterministically, retains tombstones, rejects invalid or wrong-scope device files, preserves unknown item values, supports collection-loss guards, and canonicalizes JSON. Seven new BrowserCore tests cover merge order, tie-breaking, concurrent edits, joining, mass-deletion protection, file validation, and stable encoding. At that increment, the core had no Ark state projection, file provider, folder picker, or settings UI, so the comparison remained No. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Sync state projection

Added a shared snapshot projection and apply path in `BrowserSyncItems.swift`. It syncs stable Space metadata, pinned web URLs, pin-folder hierarchy and feed sources, per-profile favorites and website-profile identities, plus selected shared settings. Today tabs, archive, history, WebKit interaction state, site permission grants, collapsed folders, and live-feed article caches remain local. Credentialed or non-HTTP pins and favorites are omitted from the shared mapping and preserved on the local device; unsafe incoming URLs are rejected. Five new mapping tests cover local-state preservation, per-profile identity, and unsafe favorite rejection; all 70 BrowserCore tests pass. `pnpm nx run ark:build-mac` and `pnpm nx run ark:build-ios` also pass; neither build launches a simulator. The projection is not yet connected to state changes or a transport. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Shared-folder transport core

Added `BrowserSyncFolderTransport` to BrowserCore. It reads and writes scope-specific, per-device JSON files in a user-selected folder using coordinated reads and atomic writes, then reuses the deterministic merge and deletion guards. It bounds file count and size, rejects unsafe scope components and symlink targets, and leaves unknown or invalid peer files untouched. Two temporary-folder tests verify a new device joins without overwriting existing values, merged data returns to the first device, and an invalid scope creates no files. All 72 BrowserCore tests pass; the Mac and generic iOS simulator targets build. No simulator was launched. Folder selection/security-scoped bookmarks, automatic sync scheduling, and applying merged snapshots to live browser state remain unimplemented, so comparison status stays No on all four clients. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Local sync-folder coordinator

Added `BrowserSyncCoordinator` to persist a per-install device ID and a user-selected folder bookmark outside the shared sync file. It resolves and refreshes stale bookmarks, runs folder I/O away from the UI actor, applies the existing privacy-filtered snapshot mapping, and exposes sync status for settings UI. iOS uses the minimal directory bookmark required by its Files provider; macOS records a security-scoped bookmark. The BrowserKit test selected a temporary folder, synchronized a snapshot, and reopened the saved configuration; all 73 BrowserCore tests passed, and the generic iOS app build passed. The coordinator is not yet wired to either browser model or settings UI, and returned snapshots are not applied to live tabs, so Sync remains No across all four clients. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Sync integration: Mac and shared iOS client

Connected the coordinator to Mac's shared `Library` and iOS `BrowserState`. Both Settings screens can select a shared folder, show sync status and last-sync time, run sync manually, and disconnect. Browser saves and app activation trigger sync. Incoming merges preserve existing tab and Space objects where possible, reset a live page only when its URL changes, retain local Today tabs when a shared Space is removed, and keep private spaces, history, archive, WebKit state, and permissions device-local. Pin folders now expose the restore operation needed by the Mac app's live merge.

Verification: BrowserKit's 75 tests passed, including folder transport, coordinator bookmark persistence, local-only Space decoding, and deletion preservation. `pnpm nx run ark:build-ios --skip-nx-cache --output-style=static` and `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed; the first Mac build caught and led to fixing a pin-folder setter access error. No simulator was launched. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

Status: implementation is connected on Mac and the shared iOS target used by iPhone, iPad, and Duo, but remains **Unverified** in the comparison until runtime folder selection and cross-client convergence are observed on those devices. Screen recording permission is not needed for this verification; the current ad-hoc Mac app still cannot provide a stable macOS TCC identity for unrelated capture previews.

### Sync status evidence review

The existing BrowserKit suite covers the privacy-filtered snapshot projection, deterministic peer merge, temporary-folder transport between device files, and coordinator bookmark persistence. Both Mac and generic iOS app targets build. This proves the core file-sync path in fixtures, while Settings folder selection and convergence through a real cloud/file provider remain unverified on each runtime client. The matrix now rates sync **Partial** on Mac, iPhone, iPad, and Duo: the implementation is available in all targets but intentionally excludes Today tabs, history, archive, WebKit state, and permission grants. Runtime verification needs a real shared folder provider and at least two clients; the platform code does not require screen-recording access. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Mobile Boosts: hide and restore page elements

Search's `Curtain.swift` and `Hidden.swift` provide a visual element picker and persistent, host-scoped hiding. Ark's shared iOS app adds **Hide Page Element…** to page actions, reuses its area-selection overlay for touch selection, and computes a unique CSS selector in WebKit. Private tabs cannot enter this flow because Ark's existing site-style host check excludes them.

### Boosts detail and preview parity

Search's `Curtain.swift` stores a readable label, size/location note, and date for each hidden element, then lets a row preview the item before restoring it. Ark now stores that metadata in `HiddenSiteElement`; the decoder migrates existing selector-only `site-hidden-elements.json` files in place on the next edit. WebKit derives a stable selector using IDs, test/accessibility attributes, non-generated classes, and a unique DOM path, and names the element from its accessible label, semantic type, or text. Mac and mobile restore lists show the label and note. Mac previews while hovering; mobile has a **Preview** action. Both temporarily reveal, outline, and scroll the selected item into view; closing the mobile editor restores its hidden state. Restore All now persists and applies once for the host instead of issuing one file write and stylesheet update per item.

The pinned Search source remains [`6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`](https://github.com/driceroland/Search/commit/6f2b186bfa862d282ee9f424be1dfd5eb8ddc316). Search's `Curtain.peek` scrolls the element into view and outlines it; Ark's shared stylesheet apply path now provides the same feedback through Mac hover and the mobile Preview action. Verification: all 75 existing BrowserKit tests passed; Mac and generic iOS builds passed. The Mac build caught a missing `BrowserCore` import in the editor, which is fixed. No simulator was launched and no persistent test files were added. These existing tests do not directly cover metadata migration or preview rendering; mobile element selection and preview still need runtime checks on iPhone, iPad, and Duo. No performance benchmark was run; Restore All now performs one persistence/apply operation per host rather than one per hidden element.

### Mobile website profile management

Search's `Profiles.swift` supports profile creation, renaming, and deletion. Ark's shared iOS Settings now adds rename and delete actions beside the existing create and assignment controls. Deletion resets every assigned Space to Default, clears active WebKit sessions and profile references from favorites, archive, and recently closed tabs, removes the cached named configuration, deletes its website data, and removes its per-profile history directory. This keeps the mobile profile lifecycle aligned with Mac while retaining Ark's per-Space website-profile model.

Verification: `pnpm nx run ark:build-ios --skip-nx-cache --output-style=static` passed. No simulator was launched and no persistent tests were added. iPhone and iPad rename/delete interaction, deletion cleanup at runtime, and Duo layout checks remain open. The Profiles row stays Partial because Ark profiles do not own independent Space collections and mobile behavior has not yet been exercised. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Mobile pinned-tab drag and drop

Search's `PinDrop.swift` lets pinned rows move into a folder or reorder among sibling pins, and moves tabs across the Today/pinned boundary. Ark already had nested folder-row drag, while mobile pins only had the folder assignment menu. The shared Mac and iOS pin list and root-pin views now make pinned rows draggable, reorder them around another pin, and drop them into a folder or back to the top level. Today tabs can be dragged into a pinned row, a folder, or the top level; pinned tabs can be dropped back into Today. Folder rows can receive a pin; existing folder move behavior stays intact. Live-feed folders are now rejected as pin destinations in both drag handling and the menu/model path.

Verification: all 75 existing BrowserKit tests passed; Mac and generic iOS builds passed. Existing folder-tree tests do not cover the new pinned-tab reorder or Today/pinned movement paths. No simulator was launched and no persistent tests were added. Mac, iPhone, iPad, and Duo drag/drop behavior needs runtime checks; the comparison row remains Partial. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Mobile automatic PiP platform check

`WebViewPool.makeConfiguration` enables `allowsPictureInPictureMediaPlayback` for the shared iOS app. Apple's WebKit API documents this as allowing HTML5 video PiP; the public automatic-start property belongs to `AVPictureInPictureController`, which Ark does not own for WebKit-managed video. This establishes permission, not Ark-controlled auto-start. Mobile automatic behavior remains site/system dependent and unverified on iPhone, iPad, and Duo. No code changed. Sources: [WKWebViewConfiguration PiP permission](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/allowspictureinpicturemediaplayback), [AVPictureInPictureController automatic start](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/canstartpictureinpictureautomaticallyfrominline). Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Portable Space profile assignment

Arc describes profiles as scoping logins, cookies, and history to one or more Spaces. Ark already assigns isolated website profiles to one or several Spaces, but its portable Space file omitted that assignment. Space links now include the profile label for full-Space shares; importing creates a distinct local WebsiteProfile with an “Imported” label. The association follows the Space while cookies, history, and sign-ins remain on the source device. Folder-only shares do not carry a profile.

Verification: all 75 existing BrowserKit tests passed; Mac, generic iOS, and docs builds passed. No persistent test file was added; the SpaceLinkArchive tests do not yet assert profile-label encoding or fresh-profile import. Duo runtime and Space share/import interaction remain open. Arc profile semantics source: [Arc for macOS 2022 release notes](https://resources.arc.net/hc/en-us/articles/20498417809815-Arc-for-macOS-2022-Release-Notes). Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Arc sunset status update

Arc's official schedule says Arc Search account sign-in, sync, and AI ended November 23, 2026; macOS and Windows services are scheduled to end December 22, 2026. The comparison now marks Arc Sync and Built-in AI Partial during this transition and records the shutdown dates. Source: [Arc Sunset: Key Dates and What to Expect](https://resources.arc.net/hc/en-us/articles/44412972248471-Arc-Sunset-Key-Dates-and-What-to-Expect). Checked November 24, 2026. Search reference SHA: `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`.

### Mac-first verification checkpoint

Mac verification resumed against the pinned Search source `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`. The local Browsa checkout is at `0ab8524378116a0416a46eecf8189dc6745fc398`; it has not been merged during this Mac pass. Search's local `origin/main` ref is at `588df6f4f2c25f1bc92b77872fc4adc41be647f4` and is 103 commits ahead of the pinned checkout. Review both streams after the Mac milestone rather than changing the active source baseline mid-pass.

The existing debug-only `SnapshotTour` ran in an isolated home against a loopback fixture. Across its completed runs it verified: named-profile cookie isolation, data clearing, Space assignment and tab handoff; last-used tab selection; side-by-side and stacked Split View focus, reopen, close, and archive behavior; full-page, region, and element capture (600×360 region PNG and element bounds matching); lazy loading and keyboard selection in Recent Tabs; Glance handoff without a duplicate page; Today-to-folder and pin-folder drag paths; Arc folder import; RSS discovery, stable IDs, failed-refresh cache retention, and paused-feed resume; export/import dialogs; and Boost CSS persistence and host/private isolation. The capture tour's original close of a temporary Settings window triggered an AppKit zombie crash; the debug tour now retains that window through capture. The Mac build passed after this fix, and the profile management preview was captured.

The local RSS fixture is process-stateful. The complete feed lifecycle passed in one isolated run; a later rerun reused the same server counter, so that run's discovery step failed before it exercised the feed path. It did not change Ark state or invalidate the earlier pass. A fresh fixture process is required for a repeat.

These checks use the app's existing debug tour and temporary local pages; no persistent test files were added. The simulated pin drags do not replace a physical mouse/trackpad drag check. DRM streaming still needs an authorized service account. The Apple native passkey flow needs a Developer ID build carrying Apple's restricted browser credential entitlement; the current ad-hoc debug build cannot establish that. The service-specific Arc Previews and Easels rows have no implementation in the pinned Search or local Browsa source, so they remain separate feature work rather than upstream copies. Mobile, iPad, Duo, and incoming upstream synchronization remain queued.

The existing `browser-kit:test-swift` target passed all 75 tests across 14 suites on this checkpoint. No tests were added. The existing `ark-spike:build-mac` target also built successfully, but its UI could not be launched from the VS Code process: Launch Services returned `kLSNoExecutableErr`, and a direct launch aborted while registering the app. Its mock-data drag harness therefore did not provide a physical Mac sidebar drag result. No simulator was booted.

The Mac comparison now marks Profiles and Air Traffic Control Yes: the existing Mac profile fixture verified isolated named stores, profile assignment, page rebuilds across profile boundaries, and clearing; `SpaceRouter` implements host, path, routing-set, and source-app rules with source-app precedence and site-rule fallback. The routing preview shows the source-app setting. Other platform ratings were left as they were.

After the user opened SpikeArk from Finder with access, its local control port returned mock `/state` during this checkpoint. Synthetic input opened the New Pin Folder prompt and entered text, but Save did not complete and the listener dropped before a folder or drag result could be confirmed. The SpikeArk window is separate from installed Ark, and no Ark user data was touched. The Mac sidebar drag remains unverified.

The existing isolated `SnapshotTour` now captures the Mac Sync settings pane after selecting a temporary local folder and completing one sync. The fixture wrote one device snapshot file and reported `synced`; this verifies the Mac coordinator and settings state for one local client, not a real shared provider or cross-device convergence. It also captures the page-bound Notes panel as an adjacent-feature reference, with explicit labeling that Notes is not an Easel. The Mac build passed; no test files were added.

The comparison now links the Sync settings and Notes panel screenshots, and the Passkeys row links the existing extension-library image. The DRM image remains ordinary playback only; Glance is labeled as generic rather than service-specific web-app preview; the extension-library images do not establish MV2 compatibility or built-in AI. Native passkeys, protected playback, physical drag, actual shared-folder selection, and two-client sync remain open.

Adapted Browsa `5ebc8c1bf1df0169d9f7b828a51794fe0a0c0136` for Ark call-audio configuration: script refreshes leave installed content-blocking rule lists in place. Full rule replacement remains the default for page registration and blocking configuration changes. The combined media batching and script-refresh batch passed `ark:build-mac`; live runtime verification remains pending.

Adapted Browsa `ed71db69e6bd0647652563ee91a573b0e593dd2b`: Ark now validates the saved Call PiP frame against currently connected displays and moves an off-screen live call window to the main display. `ark:build-mac` passed. A physical display-removal/reconnect runtime check remains pending.

### Browsa private site-permission storage — Mac

Adapted Browsa `18a9e73147a0d0a32d4e2f91b8a967dfaea92e25`: Ark now resolves camera and microphone answers and the site's **Open in App** choices through one site-permission helper. Private tabs see saved answers plus private overrides; prompt answers and site-menu overrides go to the in-memory private cache, which the existing `closePrivateSpace` path clears. This fixes direct site-menu writes that previously bypassed Ark's existing private-only media-prompt cache. `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. Runtime checks that private answers never persist and regular-tab choices still do remain pending.

### Browsa Boost import safety — Mac review

Reviewed Browsa `f27bcf16d64c98c8e11eb5bf53c9fa449e63fd93`. Ark's site styles and hidden-element rules use exact-host keys and check `location.hostname` before applying; Ark does not import `.browsa` Boost files or execute user-supplied site scripts. The imported-script review prompt and shared-file domain validation therefore have no matching Ark flow to adapt. No code change; the Boosts comparison remains based on Ark's existing CSS and element controls.

### Search native-field focus cost — Mac

Adapted Search `fe22040c014e4a0ebd7bf642434919a93b292c7b`: Ark registers `NSAutoFillHeuristicsEnabled = false` before constructing its windows, so AppKit does not walk Ark's full native/SwiftUI view tree to guess whether Ark-owned fields are password fields. Browser-page credential behavior stays in WebKit. The default is registration-only, so an explicit user's persistent preference still overrides it. `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. Search reports the original full-window scan can hold its main thread at 100% CPU for tens of seconds; Ark has not yet had a before/after latency or CPU measurement, so no Ark performance delta is claimed.

### Browsa Live Folder request privacy — Mac review

Reviewed Browsa `9703e82288d9cb41ee6b072b0700ec1cea54a468`. Ark already uses an ephemeral feed session without cookie storage, URL credential storage, or credential-bearing feed URLs, and bounds each response at 2 MB. This is stricter than Browsa's 5 MB limit; Ark has no GitHub token integration. No code change. The Live Folders row remains Yes; its existing feed lifecycle checks remain the runtime evidence.

### Browsa private extension access — Mac

Adapted Browsa `63bd758f3b73e22e8ac3a149e0b6b6c80b5f98c6`: extensions now have private-data access disabled by default. The Library extension detail offers an explicit per-extension switch; changing it updates the loaded WebKit context, and removing the extension forgets the grant. Other BrowserEngine implementations default to deny. `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. Live checks for the switch, content-script isolation, and grant removal remain pending; the Chrome extensions row stays Partial.

### Search site-permission management — Mac

Adapted Search `4746a7772c5b3edd612dd5c76c80ce5d174f12a3` in Settings → Privacy. Ark already listed saved site permissions and could forget all answers for a host; it now filters that list by host and resets one saved answer at a time, preserving other answers and the existing Forget-all action. Ark's permission store is host-keyed, not origin/port-keyed, so the UI does not invent finer boundaries. `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. Runtime UI, filtering, and reset behavior remain unverified.

### Search extension path grants — Mac

Adapted Search `505780179d400715192c1e26b507c2d22fa21789`: when a requested host pattern covers another pattern's narrower paths on the same scheme, Ark grants the broader pattern once. This avoids WebKit registering duplicate content-script injections for overlapping grants such as `https://example.com/*` and `https://example.com/embed/*`. Exact scheme boundaries are retained. `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. A real extension with overlapping path patterns still needs a runtime injection-count check; no test file was added.

Reviewed Search `86a67e118405aa09931c3d84d834c6dc6810817b`: Ark does not own saved-password or verification-code filling, so the origin-and-port security change has no Ark implementation to port. Those interactions remain with WebKit and the system password manager; Ark will not introduce a second vault.

### Browsa extension host-permission scope — Mac

Adapted the permission-scope portion of Browsa `1642b72ff49a17421b29ba3d56c70b5717a09b8c`: `WebKitExtensions` no longer grants `<all_urls>` to every extension. Broad host access is granted only when an extension's requested match patterns include `<all_urls>` or a wildcard host; otherwise Ark grants its declared patterns. This closes an overbroad WebKit permission grant without changing the extension UI. Browsa's redirect-checked, profile-aware `browsa.fetch` path was not copied because Ark does not expose that API. `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. A runtime check with narrow-host and all-host extensions remains open. The comparison's Chrome extensions rating stays Partial pending compatibility and permission-flow verification.

### Browsa certificate error handling — Mac

Adapted Browsa [`3deba26b9582546a43141f1f8f3d8155e3f2d188`](https://github.com/jmaorr/Browsa/commit/3deba26b9582546a43141f1f8f3d8155e3f2d188). The shared WebKit engine fingerprints the leaf certificate and exposes **Visit Anyway** only when it can identify the rejected certificate. Ark stores approval by normalized host and port plus that exact fingerprint; a replacement certificate remains blocked. Private-tab approvals are memory-only and clear with the private space. Settings lets users forget saved exceptions, and older settings decode with an empty exception list. The upstream's broad local-network bypass was not adopted; the explicit exception keeps the decision tied to a certificate the user saw.

Verification: `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. Xcode emitted existing actor-isolation and C-string deprecation warnings. No simulator was started and no persistent tests were added. A live self-signed certificate visit, changed-certificate rejection, private-tab cleanup, and Settings interaction remain unverified. This is supporting security behavior rather than a separate Arc feature row; the 42-row comparison remains unchanged. The upstream Browsa baseline remains `19eef7990aec8bd5491ef06ffc14928b7a73033f` until the complete incoming batch is reviewed.

### Sidebar sizing and site blocker shortcut — Mac

Partially adapted Browsa [`26afb7ba5950b260807d392df7a9d94f3d3c8770`](https://github.com/jmaorr/Browsa/commit/26afb7ba5950b260807d392df7a9d94f3d3c8770). Ark computes the minimum from its actual traffic-light frame, four 28-point sidebar controls, gaps, and horizontal insets; this avoids the upstream's mismatched five-control width. The split view and restored saved width both honor that minimum, and the top row is leading-aligned. The site menu now includes a checked **Block Ads and Trackers** action that toggles the current site's existing exception. The same upstream commit also improves dynamic Notes anchors and CSP-resistant styling; that larger, non-matrix change remains queued for a separate review.

Verification: `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. No simulator was launched and no persistent tests were added. Resizing to the minimum, checking that window controls stay in place, and using the site menu remain runtime-pending; no screenshot was captured. The 42-row comparison ratings were not changed on build evidence alone. Browsa baseline remains `19eef7990aec8bd5491ef06ffc14928b7a73033f`.
