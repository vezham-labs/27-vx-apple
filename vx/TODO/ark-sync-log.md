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

The iOS build and all 106 BrowserKit tests passed. The model test checks selection, resize bounds, restoration, and handling a missing member. Active members stay out of both session eviction and auto-archive. The first iPhone run stopped while locating the More button, before Split View opened. The iPhone 18 Pro retry opened Split View through the gallery context menu, confirmed both pages were live, and switched focus by tapping a pane heading and then a page. iPad and Duo runtime checks, pairing pinned tabs, and support for more than two panes remain open. The implementation follows Search’s split grouping in `Split.swift` and `PaneStage.swift`, and uses Ark’s mobile WebKit host for both pages.

### Profiles per Space

Source audit confirmed that Mac `WebKitEngine` and mobile `WebViewPool` share the default WebKit website data store across regular Spaces and use a temporary store for Private. Search’s `Profiles.swift` keeps the default store for the existing profile and creates persistent WebKit stores keyed by UUID for additional profiles. The comparison records the current gap on all four platforms. Profile assignment, history and extension isolation, and runtime verification remain open.

The Mac engine now accepts a named browsing profile and reuses the persistent WebKit store for its UUID. Named pages have no extension controller while profile-aware extension isolation is open. The Mac build passed. A local debug fixture verified that two pages with the same profile share a cookie, other named, default, and private stores cannot read it, and clearing the named profile removes the cookie. Space assignments, mobile stores, scoped history and extension support remain open.
