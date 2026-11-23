# Ark upstream sync log

Start each upstream review at the last synced commit. After applying and verifying a sync, add a log entry with the new upstream SHA, the Ark commit, and the changes adopted or skipped.

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

The Developer Mode row references Search’s `Inspector.swift` at `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`. Ark’s WebKit engine now applies the current developer extras preference when creating a named profile configuration and updates cached configurations when it changes. Before the fix, enabling Developer Mode before opening the first named-profile tab left that tab’s preference disabled. The same Mac fixture passed after the fix for named, Default, and Private pages. It also verified disabling the preference on live pages and reopening a named-profile page after re-enabling it. This check read the actual WKWebView preferences. It did not interact with the inspector window.
