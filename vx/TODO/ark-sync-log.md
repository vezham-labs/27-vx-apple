# Ark upstream sync log

Start each upstream review at the last synced commit. After applying and verifying a sync, add a log entry with the new upstream SHA, the Ark commit, and the changes adopted or skipped.

### Download and redirect intake — November 26, 2026

Reviewed the product diffs for Search `a93a437` and `9b609d4`. Ark does not automatically close download-source tabs, so Search's empty-tab closure guard has no matching path. Its typed cross-host redirect completion behavior is an applicable gap: Ark currently records the final destination, and its broad `.typed` source also covers non-address navigation. A focused implementation must distinguish explicit typed addresses and preserve profile/private isolation. Separately, Ark's download bridge now clears a requested filename when a download finishes or fails, including before destination selection. The existing BrowserKit suite passed, including 90 BrowserCore tests; it does not specifically exercise early download cancellation. Cross-Space download runtime and redirect completion remain unverified. No simulator was started.

### Named-profile bookmark export — November 26, 2026

An isolated Mac fixture exported distinct favorites for two named profiles and verified each appeared only in its own named folder, including escaped profile names. The existing Default, folder, private-link and credential-filter checks also passed, as did the Mac Nx build. The save dialog and importing into external browsers remain unverified; Export Spaces stays Partial. No simulator was started.

### Profile favorites in bookmark export — November 26, 2026

The all-Spaces HTML export now includes a separate Favorites folder for Default and each named profile, retaining order and filtering to credential-free HTTP(S) URLs. This fills a gap found while comparing Browsa `b337f69` and Search `7bc04c0`. The Mac Nx build and isolated fixture passed for Default favorites, escaping, and credential exclusion alongside the existing Space checks. Named-profile separation, the save dialog, and imports into other browsers remain runtime-unverified; Export Spaces stays Partial. No simulator was started.

### All-Spaces bookmarks export in progress — November 26, 2026

Started adapting the all-Space bookmarks capability from Browsa `b337f69` / `6463465` and Search `7bc04c0`. Mac now has an HTML export entry in the File menu and command bar; it uses Ark's portable Space link filtering, excludes the agent Space, nests pin folders, and uses pinned home URLs. The Mac Nx build passed. The initial fixture checked live tabs before WebKit populated their URLs; a corrected isolated fixture using explicit tab records verified escaped Space/folder names, pinned and open links, and exclusion of private and credentialed URLs. Save-dialog behavior, multiple browser import, and complete round-trip remain unverified. The existing single-Space JSON path remains separate. Do not advance upstream baselines or the Export Spaces rating.

### New upstream intake — November 26, 2026

Recorded the locally known Browsa commits `46fe04b..a39e03e` (8) and Search commits `b9fcbb4..d5948c4` (60) in the [intake inventory](ark-upstream-intake-2026-11-26.md). These are pending full diff review, not synced changes; the prior 270/332 review count excludes them. Initial inspection identified all-Space export as an applicable gap: Ark exports one Space as JSON, while the references add interoperable bookmarks and, in Search, a richer multi-Space format. No product code or feature rating changed, and no upstream baseline advanced.

### Mac batch intake and Easel drawing — November 26, 2026

Created the [Mac batch queue](ark-mac-batch.md) to group the remaining feature, compatibility, and verification work. Easel page cards now reject non-HTTP(S), hostless, and credential-bearing URLs; an isolated fixture confirmed these rejections. The Mac Nx build passed. An isolated image-card audit found existing input-posting access and used a system-posted drag: both a plain SwiftUI control and the annotation gesture responded, a stroke was stored, and the Clear button removed it. The [drawn-stroke preview](../../preview/ark/mac/features/easel-image-annotation-drawn.png) captures that run. This supersedes the earlier inconclusive synthetic-drag attempts; physical pointer and VoiceOver checks remain open. The file-URL fixture cannot verify adding an HTTP page, so its unrelated aggregate check failed. No simulator was started.

### Easel image annotations — November 26, 2026

Mac image cards now have an annotation mode and clear control. Strokes are stored on the existing card model in normalized coordinates, rendered over the image in the board and PNG export, and represented as SVG in the HTML ZIP export. The Mac Nx build passed. An isolated Mac fixture set image strokes through the model: the resulting PNG visibly contained the annotation and the exported HTML included its SVG path. A separate store fixture reopened saved strokes, cleared them, and verified the clear after another reload. Pointer drawing and the clear button, full-app relaunch, and visual ZIP rendering still require runtime verification; Easels remains Partial and no simulator was started.

An isolated image-card window entered annotation mode via a synthetic button click, but posted drag events produced no stored stroke, including after using an explicit transparent hit surface. Process-targeted drag events also failed to trigger a plain SwiftUI drag control in the same window, so this audit cannot distinguish the feature's behavior. The synthetic clear result is inconclusive because no stroke was drawn; pointer drawing must not be considered verified. The file-URL fixture also could not exercise adding an HTTP page, so its unrelated Easel lifecycle aggregate failed.

Review found that normalizing annotations to the entire card content area could misalign them with a fitted image when export dimensions differ. The image overlay now follows the fitted image, and ZIP export puts the image and paths in a shared image-sized SVG coordinate system. The Mac Nx build passed, and an isolated export contains the expected scaled path and image dimensions. Pointer drawing and visual alignment across board, PNG, and ZIP remain unverified.

An isolated image-card fixture rendered a model-provided stroke at the expected relative positions over the fitted image; see the [Mac annotation preview](../../preview/ark/mac/features/easel-image-annotation.png). This verifies the card's rendered placement for that fixture, not the physical drawing gesture or visual alignment across export formats.

The isolated fixture also reopened its ZIP's HTML in WebKit. Its image and stroke bounds matched the expected relative coordinates, and the [export preview](../../preview/ark/mac/features/easel-annotation-export.png) shows the annotation over the image. This covers one model-provided stroke and image; physical drawing, the clear button, and broad cross-format alignment remain unverified.

Single-point image strokes previously had no visible segment. They now render with a round cap in the card and ZIP SVG; the isolated model fixture captured both a line and a dot in the card and ZIP previews. Mac build passed. The fixture does not prove a physical click can create the dot, and pointer interaction remains unverified.

The image-card toolbar now separates Undo Last Annotation from Clear Annotations and gives both explicit accessibility labels. An isolated Mac fixture posted clicks on a card with two model-provided strokes: Undo left one and Clear removed the other. The Mac build passed and the card preview was refreshed. Actual drawing gestures and physical/VoiceOver interaction remain unverified.

### Boost related-element hide and restore — November 26, 2026

The isolated Mac Debug fixture posted Option-hover and Option-click events over a local page with three matching elements. It verified that the preview counted three, all three became hidden, and restoring the rule made all three visible again. The Mac Nx build passed. Physical pointer and VoiceOver interaction, dynamic real sites, and mobile remain unverified; Boosts stays Partial. No simulator was started.

### Boost related-element count preview — November 26, 2026

The Mac Boost picker now displays a count while Option is held over an element, before the existing Option-click hide action. The lookup is debounced and cancelled on pointer changes or picker dismissal, and checks that the original tab, URL, host, and WebView are still active. The count is exposed as accessibility value; the picker restores the window's mouse-move setting when removed. Mac Nx build passed. An isolated Mac fixture posted an Option-hover through AppKit over a local page with three related elements, confirmed the accessibility value, captured the [count preview](../../preview/ark/mac/features/boost-related-count.png), and confirmed mouse-move settings were restored on dismissal. Physical pointer and VoiceOver interaction, and count accuracy on a changing page remain open; Boosts stays Partial. No simulator was started.

The first isolated audit exited with status 139 while synchronously dispatching a synthetic mouse event from its own task. A debugger retry stalled before startup and was stopped. Posting the synthetic event through AppKit's event queue allowed the subsequent fixture to complete; this does not establish the precise cause of the earlier exit.

### Glance promotion with a pending permission — November 26, 2026

An isolated Mac Debug fixture promoted a fully loaded Glance while a synthetic screen-permission request was pending. The request was cancelled and the same page was retained in the new tab. The initial fixture checked before the page had finished loading and therefore exercised Ark's intentional reload fallback; after waiting for completion and matching the active profile, the handoff passed. Mac Nx build passed. Actual WebKit screen-sharing and system-picker interaction remain unverified; Peek remains Partial and no simulator was started.

### Glance screen-permission cancellation — November 26, 2026

An isolated Mac Debug fixture requested screen permission through the Glance delegate, verified the prompt was queued, and confirmed both closing Glance and invoking its navigation-commit callback cancel the request. Mac Nx build passed. The fixture did not invoke WebKit screen capture, display a system recording picker, or verify real navigation or promotion; Peek remains Partial. No simulator was started.

### Cross-profile synced pin move — November 26, 2026

An isolated Mac Debug fixture used two coordinators and a local sync folder to move a pinned tab from a named-profile Space to a Default-profile Space. After sync, the same tab belonged to the destination and used a replacement WebView with the Default store and no old interaction state. Mac Nx build passed. iOS runtime and physical-device propagation remain unverified; no simulator was started. Correction: the prior two Link Preview notes incorrectly said Little Arc was Partial; the comparison rates Mac Little Arc Yes, and that rating did not change.

### Script-opened Link Preview close — November 26, 2026

The isolated Mac Debug fixture opened an `about:blank` child from a Link Preview using `window.open`, then called `window.close()` in the child. The child closed and the opener stayed open; the fixture enabled automatic popup permission locally to make the scripted opening possible. The Mac Nx build passed. This does not establish compatibility with a real sign-in site's navigation or popup policy, and Little Arc remains Partial. No simulator was started.

### Link Preview close callback — November 26, 2026

Reviewed Search `70eeea92ecde7e871eb6182ffa66237e64375850`: its small-window fix routes WebKit's close callback to the window. Ark already has that route. An isolated Mac Debug fixture invoked the actual WebKit UI delegate callback and confirmed the Link Preview was removed without adding a tab; Mac build passed. The fixture did not exercise a site calling `window.close()` in a script-opened sign-in flow, so that runtime case and Little Arc parity remain open. No simulator was started.

### Synced profile session reset — November 26, 2026

Applying a remote Space profile change previously reused existing WebViews when tab IDs and URLs stayed the same. Mac and iOS sync application now retire sessions and clear session state when a retained tab's old and destination Space profiles differ, including moves between Spaces. Profile-bound overlays close on an affected selected Space. Mac and generic iOS Nx builds passed. An isolated Mac Debug fixture used two coordinators and a local sync folder to change a Space profile, then verified the old WebView was replaced by one using the new named store and its old interaction state cleared. Cross-Space sync moves, asynchronous timing beyond that fixture, and iOS runtime remain unverified; no simulator was started and the comparison rating is unchanged.

### Upstream ledger correction — November 26, 2026

Updated stale Browsa dispositions that still described GitHub Live Folders and owner filters as absent, and an older Boosts entry that claimed Mac parity. The entries now reflect the implemented command, profile-cookie flow, folder-menu filters, and manual accent, while preserving the signed-in, UI, and palette-engine gaps. Source review count and comparison ratings are unchanged; no runtime verification was performed.

### iOS WebKit delegate signatures — November 26, 2026

The generic iOS build exposed that the camera/microphone permission and link long-press menu methods did not match the current Swift `WKUIDelegate` requirements, so WebKit could use its default behavior instead of Ark's handlers. Corrected both signatures; the generic iOS Nx build passed and the signature warnings disappeared. Existing unrelated compiler warnings remain. Permission prompts and link-menu actions still require device runtime verification; no simulator was started and no comparison rating changed.

### GitHub cache on profile reassignment — November 26, 2026

Explicitly assigning a different website profile now clears cached GitHub pull requests and account-specific owner filters, and pauses the folder until a user refreshes it with the new profile. This applies to Mac and iOS assignment paths. Sync merge likewise retains local feed data only for the same source and GitHub profile; a changed profile clears it and pauses the folder. Existing fixtures verify both paths and that sync projection excludes account data; all 90 BrowserCore tests and Mac and generic iOS builds passed. Live sync-driven interaction and signed-in refresh still need runtime verification; no simulator was started.

### GitHub refresh rapid profile changes — November 26, 2026

A profile ID comparison alone allowed an old in-flight response if a Space switched profiles and then switched back before the response arrived. Space now tracks an in-memory profile-change revision, and both the app's cookie retrieval and the GitHub refresh require that revision to remain unchanged. The existing asynchronous fixture verifies the feed-response away-and-back case; all 88 BrowserKit tests and Mac and generic iOS builds passed. Cookie-fetch timing and signed-in network behavior remain unverified; no simulator was started.

### GitHub refresh in-flight changes — November 26, 2026

An existing-suite asynchronous fixture delays the GitHub feed result while changing an owner filter, removing the folder, reassigning the Space profile, and cancelling the refresh. It verifies that the filter remains applied, the removed folder is not recreated, and neither an old-profile response nor a response returned after cancellation replaces the cached feed. All 88 BrowserKit tests passed. The fixture injects a feed result; actual signed-in GitHub networking remains unverified.

### GitHub owner matching — November 26, 2026

The existing BrowserKit suite now verifies that owner filtering recognizes GitHub pull-request URLs without treating lookalike hosts or issue URLs as pull requests. All 87 tests passed. Source review also confirms that a refresh uses the current folder state after the request, preserving filter changes and avoiding recreation of a removed existing folder; an in-flight network fixture remains open.

### GitHub owner migration — November 26, 2026

Older GitHub folders can contain cached entries without a remembered-owner list. Changing an owner filter now records the currently known owners before saving, so an owner remains available if it disappears on the next refresh. The existing BrowserKit test now covers that migration, persistence, disappearance, and restoration; all 86 tests passed. Signed-in refresh and menu interaction remain open.

### GitHub organization filters — November 26, 2026

Adapted Browsa `910f5a4d6ee5a43b8a239e38e2c2ddef20bd8221`: GitHub Live Folder menus can hide owners per Space without discarding cached items or making a request. Previously seen owners remain available after refresh, and account-specific filter data is stripped from shared Space archives. GitHub folder refresh/resume now uses the Space profile's cookie flow instead of the RSS loader. Existing BrowserKit tests cover Space isolation, restoration, persistence and archive privacy; Mac and generic iOS builds passed. An isolated Mac fixture programmatically filtered and restored two sample entries and captured [the filtered folder](../../preview/ark/mac/features/github-filter-hidden.png). Menu interaction, signed-in GitHub refresh and mobile device checks remain open; no simulator was started.

### GitHub Live Folder request safety — November 26, 2026

Reviewing Browsa `910f5a4d6ee5a43b8a239e38e2c2ddef20bd8221` corrected a stale inventory entry: Ark already has a GitHub Pull Requests folder, but not the per-Space organization filters. The review found that its manual Cookie header used an unrestricted redirecting session and buffered an unbounded response. The request now sends only unexpired GitHub root-path cookies, rejects redirects outside HTTPS `github.com` on its standard port, and reads at most 2 MB. Existing BrowserKit tests verify cookie selection and redirect-delegate decisions; the Mac and generic iOS builds passed without starting a simulator. Signed-in GitHub compatibility, real redirect behavior, and filters remain open.

### Extension blank-tab behavior — November 26, 2026

Reviewed Search `b3bd4e35c53dbb17625c9b707aae7561250fb740`. An active, unpinned extension request without a URL now returns the real blank page WebKit requires and opens Ark's command bar in edit mode, so submitting fills that same tab. A local MV3 fixture verified the editor and same-tab navigation, and that background and active pinned blank requests do not open the editor. Ark also passes the requested pinned state to its host, exposes pin state and extension-driven updates to WebKit, rejects pinning private tabs, and notifies extensions when the browser changes pin state. The fixture verified `tabs.create`, `tabs.update` and an `onUpdated` pin event. With private access enabled, the extension received errors from both private pin API requests and no private pin was created. The Mac build and existing BrowserKit suite passed. Broader extension compatibility remains open; Chrome Extensions stays Partial.

### Mac capture session guard — November 26, 2026

Full-page, region, element, and Easel capture now also confirm that the original WebView and browsing profile remain active after asynchronous work. Profile reassignment starts asynchronous page cleanup while tab identity and URL stay the same; an old capture must not be copied or added to an Easel during that transition. An isolated Mac fixture started a full-page capture, reassigned the profile immediately, and verified the tab stayed selected and the clipboard remained unchanged. It repeated the transition during an Easel capture and verified no image card was added. For area and element capture it switched profiles both between picker mouse-down and mouse-up and immediately after capture began; the clipboard stayed unchanged. The Mac Nx build passed. Existing normal capture fixture evidence is unchanged.

### Hung-page keyboard review — November 26, 2026

Reviewed Browsa `99ff3fd4fd7b04869ac8a5134a7bd2851d017ad9`: its recovery releases focus from a failed or unresponsive WebKit view, using private process properties for hangs. Ark intercepts some shortcuts before WebKit, but not all menu commands; the earlier inventory claim of complete independence was incorrect. Ark now releases a WebKit first responder behind a known load-error overlay before dispatching a key, without private APIs. An isolated Mac fixture set a load error, focused the page, verified focus was released after a key event, and observed Command-T opening the command bar. This simulated error does not reproduce a crashed or hung WebKit process; those cases remain open. Mac build passed.

### Favorite preview profile reassignment — November 26, 2026

A Space's profile can change without its Space ID changing. Favorite previews now dismiss and clear on profile reassignment, and a pending history lookup checks both Space and profile before publishing. The Mac Nx build passed; live reassignment and hover checks remain open. Previews remains Partial.

### Mac favorite preview handoff — November 26, 2026

The hover-exit guard made the delayed close branch unreachable, so moving from a favorite tile into its web-app preview immediately dismissed the popover. The delay is now reachable. Space changes dismiss and clear the preview, cancelled or stale history lookups cannot publish into another Space, and selecting a preview page explicitly opens it in the current Space like the favorite itself. The Mac Nx build passed; pointer handoff, routing, and Space-switch behavior still need live UI verification. Previews remains Partial.

### Mobile Favorites evidence correction — November 26, 2026

The comparison marked iPhone, iPad, and Duo Favorites as Yes while the same row said their runtime checks were open. The three ratings are now Partial until those device interactions are verified. Existing Mac and shared-model evidence is unchanged; no implementation regression is implied.

### Search keyboard and command-field options — November 26, 2026

Reviewed product diffs for Search `6a008d9` and `7baabeb`. The first adds optional Backspace navigation with editable-field protection; Ark has no matching preference, and it needs a separate shortcut decision and runtime check. The second adds an optional opaque page cover behind the command field; Ark has a translucent overlay, so the previous disposition did not describe the difference. Compare Arc's command-field appearance before changing it. No product code or matrix rating changed.

### Agent-origin Glance isolation — November 26, 2026

Glance now retains the originating tab's Boost eligibility rather than checking the selected tab later; same-profile tab or Space switches can leave a preview open. An isolated Mac audit opened a Glance from an Agent-space tab while a normal tab was selected and verified that a subsequent Boost update did not style it. The same audit passed initial, live-update, navigation, cross-window, private, and unrelated-host checks using loopback fixtures. The Mac build passed with an existing concurrency warning. Real-site checks remain open.

### Boosts in Glance — November 26, 2026

Search `72dba5be4fc8680187ed183782d4a4280a2140f9` exposed a gap in the prior review: Ark's Glance page is not a tab controller. Mac Glance now applies saved site styles after load and receives matching rule updates across browser windows, excluding private and agent pages. The Mac Nx build passed. A separately identified temporary Debug app verified load, updates, navigation, cross-window propagation, and private, agent-origin and unrelated-host exclusion using loopback fixtures. Boosts remains Partial pending real-site and broader UI checks.

### ID-based hidden elements — November 26, 2026

The picker returned an empty fingerprint for an ID selector, while the style engine applied only nil fingerprints as plain selectors. Such selections could therefore fail to hide. New selections normalize an empty fingerprint to nil, and the engine also handles previously saved empty values. Removing one guarded rule now clears its marker without disturbing other rules, and previewing the only hidden rule retains its outline. WebKit fixtures verify these paths; all 83 BrowserKit tests pass. Boosts remains Partial pending real-site and broader UI checks.

### Class-only hidden elements — November 26, 2026

Reviewing Search `baea49d571b8642a277c90f76560692e4ae50e9e` exposed an incorrect earlier disposition: selector de-duplication alone does not prevent a future page from matching several elements. New class-only selections now use Ark's existing fingerprint guard; previously saved selectors remain unchanged. An existing-suite WebKit fixture picks an element, adds another matching class, and verifies only the original hides; when both have identical content it verifies neither hides. All 81 BrowserKit tests pass. A real-site interaction remains open; Boosts remains Partial.

### Space export pin homes — November 26, 2026

Space link exports now retain each pinned tab's original home URL, so a pin that has navigated elsewhere can still return home after import. Version 1 files without this optional field remain readable; imported home URLs are checked as credential-free HTTP(S) links. The existing BrowserKit suite passed all 80 tests, including a new round-trip case in the existing archive test file, and the Mac Nx build passed. File-dialog interaction and mobile runtime verification remain open; the Export Spaces rating stays Partial.

## Current Mac sync pass — November 24–25, 2026

The [incoming review inventory](ark-upstream-review.md) lists 149 Browsa and 123 Search commits between the recorded baselines and the pulled heads, with a refined execution order that preserves the full goal. Browsa's clean worktree matches `origin/main` at `e981df56`. Search's clean worktree is at `33ec7aea`, with nine additional commits available on `origin/main` at `659f74dc`; those diffs were assessed without changing the upstream checkout. Review dispositions do not advance the last-synced baseline until adoption and verification are complete.

November 26 intake recorded Search `b9fcbb45deecddcdc4a6f1f8b8aa38dcfde6d788` with nine incoming commits. Browsa remains at `46fe04bedb0f13521328c69d0f1f6814a18e6188`. The ledger now records 270/332 reviewed (81.3%): all nine new Search commits have dispositions, with dynamic Boosts ported from `464240b` and Mac-only related-element hiding from `b9fcbb45`. Earlier 100% figures counted title/path triage as full review. Mac remains at 20/42 rows rated Yes (47.6%).

Reviewed the remaining November 26 Search commits without a code port. `a35ea54` changes Search’s own defaults and AppKit inline-prediction policy, not Ark or an Arc matrix row. `4f3228a` hardens Search’s distinct sidebar-audio player with WebKit media suspension; Ark uses Mini Player and system PiP instead. `3dffd16` changes Search’s put-away tab-group cycle; Ark pin folders and Split View are not that model. These are intentional compatibility decisions, not unreviewed gaps.

SnapshotTour audit attempt — November 26: the current Debug Ark bundle launched only through the already-running `app.vezham.ark.dev` process, which had been live for more than three hours. The new process did not receive an isolated `ARK_SNAPSHOT` environment, so the existing instance wrote partial output through the second-window stage and remained open. Its report reconfirmed reader mode, moving a tab to a second window, and restoring a sleeping page’s inner scroll at 1,200 px, but it cannot prove a full fresh-tour pass. Do not terminate the existing user app; rerun after it is quit, or build an isolated bundle identifier for the harness.

SnapshotTour follow-up — November 26: copied the current Debug bundle to a temporary, ad-hoc-signed app with the distinct identifier `app.vezham.ark.snapshot.audit`, so it could run without disturbing the existing Ark window. The isolated tour exited normally and generated all fourteen standard screen previews: launch, page, command bar, reader, second-window move, Space switch, light/dark appearance, sidebar hidden/peeking, and light/dark Audio settings. Its report verified reader presentation, opening/moving/closing the second window, and inner-scroll restoration at 1,200 px after a sleeping-page unload. This is current Mac runtime evidence; it does not cover the separate feature-preview branch or device checks.

HTTP feature SnapshotTour — November 26: the same isolated bundle ran the existing feature branch against the loopback-only fixture at `127.0.0.1`. It verified Today and Glance destinations from a pinned page while retaining the source pin; Split View focus, both orientations, reopening, partner close, and archive protection; full-page, 600×360 region, and element-bounds capture; Recent Tabs keyboard selection; Link Preview promotion/close; nested-folder drag, bulk move/undo, range selection, and Open All order; Arc folder import; Boost font/CSS persistence, host/private isolation, and clearing; Easels page/note/capture data; export/import dialogs; and the local Sync coordinator’s arrive/retain/withdraw cycle. Fresh versions of the affected Mac previews are now tracked under `preview/ark/mac/features/`.

The same run left two concrete failures open: the static local feed did not produce a changed article set, so Live Folder discovery/refresh did not establish stable-ID evidence; and the fixture’s Space-profile reassignment/transfer assertions returned false after the base named-profile cookie checks passed. Live Folders and mobile/device profile flows remain Partial. No simulator was launched.

Adapted Search `464240b` for Ark’s own Boost implementation. New element picks whose selector can move now persist a bounded DOM fingerprint and stable class family. An isolated WebKit-world observer reapplies the hide only when exactly one matching element exists after a site constructs or rearranges its content; it will not hide a different item that occupies the old position. Existing saved selectors intentionally remain plain CSS for backward compatibility. The existing BrowserKit test target passed all 79 tests, including persistence and deterministic-marker coverage. This is implementation evidence, not dynamic-page runtime parity; the Boosts row stays Partial.

Partially adapted Search `b9fcbb45` without copying its UI: in Ark’s existing Mac picker, Option-click hides a stable class family only when more than one related element exists; plain click continues to hide one selected element. The saved pattern uses the existing host-scoped Boost CSS and restores through the same list. `ark:build-mac --skip-nx-cache` passed. The picker does not yet preview the related count and mobile requires a dedicated touch interaction, so the Boosts row remains Partial.

Started the GitHub Live Folder implementation foundation. `BrowserEngine` now exposes a narrow async cookie query scoped to a browsing profile and destination URL; WebKit returns only cookies whose domain/path/security flags match that URL. The API supplies no persistence or logging path and is intended only to let an explicit site integration make a same-origin request with the Space’s existing sign-in. `ark:build-mac --skip-nx-cache` passed. GitHub Pull Requests UI/fetch/refresh behavior is still unimplemented, so Live Folders remains Partial.

Added the first Mac GitHub Pull Requests Live Folder path. **GitHub Pull Requests Live Folder** in the command bar reads the active Space profile’s matching GitHub cookies, makes an in-memory same-origin request to GitHub’s Pull Requests page, and creates or refreshes one local **Pull Requests** folder. It never saves cookies or a GitHub token. The shared folder model keeps it separate from generic RSS refresh; manual command-bar refresh is the current supported refresh path. `ark:build-mac --skip-nx-cache` passed. Filter controls, background refresh, signed-in runtime confirmation, and a preview remain open, so Live Folders stays Partial.

Completed the initial 323-commit inventory and title/path triage. The ledger tracks which entries still need diff review. The batch includes Search release prompts, changelog and test isolation changes, its password-vault heuristics, and its agent and column UI.

Fixed the GitHub Live Folder scheduler on Mac and iOS. Polls are tied to an active folder ID, skip paused imports, and recheck folder and profile identity before applying a response. Explicit refresh can activate an imported folder. Both Nx builds succeeded, and the existing BrowserKit target passed the paused/deleted-folder regression in `LiveFolderFeedTests.swift`. Signed-in GitHub behavior remains open, and the Live Folders rating remains Partial.

Reviewed the remaining Browsa Performance-glow and Library-media chain, plus profile copy. The glow commits are visual iterations for Browsa’s unadopted private-process monitor and do not establish a performance gain. The Library commits are its own promotional surfaces, assets, and player optimization; they do not map to an Arc feature row, and importing them would contradict the established Arc UI direction. The profile commit is explanatory copy only. Review progress is 308/323 (95.4%), with 15 pending.

Reviewed twelve Browsa Library, side-panel, and Performance-panel presentation commits. The Library changes restructure Browsa’s own card/pages and the side-panel changes target its different tools surface; neither is Arc parity evidence, so Ark keeps its current Arc-directed UI. The Performance commits only alter a monitor that maps tabs using private process information and includes simulated status/shader behavior. Ark has no supported counterpart and no representative workload measurement justifying a port. The two merge commits add no independent behavior. Review progress is 285/323 (88.2%), with 38 pending.

Reviewed the adjacent Boosts/performance integration commits [`2bece7b`](https://github.com/jmaorr/Browsa/commit/2bece7ba881b8734a1805fa5fdfada1ff3e81760), [`a5d6489`](https://github.com/jmaorr/Browsa/commit/a5d648988a8c704f70ff311a0ee1ecd5def81b79), [`4765482`](https://github.com/jmaorr/Browsa/commit/4765482b73d11fc283eada2c6c5ad04f30ec8901), and [`5363edd`](https://github.com/jmaorr/Browsa/commit/5363edd26789f822966f3f4d2f8925859f2e8277). Ark's manual accent picker covers the user-visible color choice without copying Browsa's computed-palette rewriting. The process-sampler warning cleanup and its monitor rely on private process APIs and remain unadopted; no performance claim follows. The two integration commits add no independent behavior beyond individually reviewed feature changes. Review progress is 273/323 (84.5%), with 50 pending.

Adapted the safe sharing portion of Browsa Boosts import/export [`23184c0`](https://github.com/jmaorr/Browsa/commit/23184c0b9bdf68134665fa70960a6c056031b1e3) as an Ark-owned `.arkboost` file. Ark serializes only an exact host's CSS, font, validated accent, and hidden elements; it rejects incompatible versions/hosts and cannot carry scripts, dates, IDs, cookies, history, or account data. Import replaces that host's presentation settings and reapplies them to matching open tabs. The Mac editor offers Import and Export actions. `ark:build-mac --skip-nx-cache` passed; save/open-panel and live reapplication checks remain open. The Boosts matrix rating remains Partial pending runtime evidence.

Closed the implementation portion of the Mac Boosts colour gap without adopting Browsa's UI. `SiteStyles` now stores a validated `#RRGGBB` accent separately per host, applies it to links, controls, and selection, and treats an accent as a saved Boost. The Mac editor exposes an Ark-native colour picker and explicit removal; prior CSS/font-only saves retain an existing accent. `ark:build-mac --skip-nx-cache` passed. The live picker, persisted application after reload, and a Mac preview remain required before the row can be rated Yes. This complements the reviewed Browsa accent work [`a5d6489`](https://github.com/jmaorr/Browsa/commit/a5d648988a8c704f70ff311a0ee1ecd5def81b79); no upstream UI was copied.

Reviewed Browsa's 1.2.1 release aggregation and nearby merges [`f25a75a`](https://github.com/jmaorr/Browsa/commit/f25a75af1bb120f5973da0cfbddf3e23933adc39), [`23802c8`](https://github.com/jmaorr/Browsa/commit/23802c8bbb2a222ecf3ee6501a77eed14bec4db3), [`6f1e6d2`](https://github.com/jmaorr/Browsa/commit/6f1e6d2cc3a3a18fdc6be64d92cabb8d171c492f), [`f34b47e`](https://github.com/jmaorr/Browsa/commit/f34b47e03fe3688097b5e733da2161ad4d37ab41), [`d635c76`](https://github.com/jmaorr/Browsa/commit/d635c764932b09e8d9b401fe308e8ff1024196ff), [`d50c599`](https://github.com/jmaorr/Browsa/commit/d50c599e23290877bd4609d0b1f2758ea25460a3), and [`562bee8`](https://github.com/jmaorr/Browsa/commit/562bee853d665407132e70443af3890f88d605fa). The first three are documentation/release-copy only. The notification aggregate and its merge repeat the previously assessed WebKit-to-UNUserNotificationCenter subsystem; Ark has no corresponding web-notification bridge yet. The HostPipe availability annotation applies only to Browsa's external native-host implementation, which Ark does not have. The remaining merge preselects a newly created profile name; Ark already provides profile creation, and this Settings-only refinement is deferred with profile UX. No product code, tests, or matrix ratings changed. Review progress is 268/323 (83.0%), with 55 pending.

Reviewed the next four Browsa merge commits against their first parents: [`95e984d`](https://github.com/jmaorr/Browsa/commit/95e984d88b5053ccdc89b9413dbc43da44c2d17f), [`f290465`](https://github.com/jmaorr/Browsa/commit/f290465375c93cea89abf14cff2133576a350a69), [`4aba346`](https://github.com/jmaorr/Browsa/commit/4aba34670ec0f2860889bd523c8f600b5120f967), and [`b858dfa`](https://github.com/jmaorr/Browsa/commit/b858dfab60cb64c5832717dd31f44f29f82b711a). The first and last merge previously reviewed PiP and current-Space Favorites changes; Ark already has those Mac/iOS behaviors, with cross-origin video selection still open. The Live Folders merge adds the RSS/Atom implementation Ark already has, including paused imports, bounded credential-free refresh, stable feed items, and change-only persistence; newer authenticated GitHub folder follow-ups remain pending. The Always Open merge matches Ark's existing Always Open / Open Once / Not Now choices; its later persistent Don't Open refinement remains pending. No duplicate merge code was copied, no Arc matrix ratings changed, and no new tests were added.

Adapted Browsa [`7013dc1`](https://github.com/jmaorr/Browsa/commit/7013dc172e3a10c84100b250e24cffcd63164dee) for Mac. Ark's Open in App prompt now separates temporary Not Now from saved Don't Open, using a new `open:<scheme>` answer key so legacy `app:<scheme>=false` values continue to mean “ask again.” Legacy Always Open values remain honored. A denied explicit link offers Ask Again; the site menu can switch among Ask, Always Open, and Don't Open; Privacy settings show and reset saved answers. `ark:build-mac` passed with existing Swift concurrency warnings. Runtime prompt, menu, and persistence checks remain open; no simulator or test file was added. This is supporting navigation behavior outside the 42 Arc comparison rows, so matrix ratings did not change.

Reviewed Browsa merges [`19651fb`](https://github.com/jmaorr/Browsa/commit/19651fbebec3c5695271d5d6d1ad9c59394be7c7), [`caba8d6`](https://github.com/jmaorr/Browsa/commit/caba8d6498a92179038bb44de3e6c9daea7b64ba), and [`482d5e9`](https://github.com/jmaorr/Browsa/commit/482d5e9c763b66511b3a71e2af08217fdc13f5d9). The first has no changes beyond the already reviewed Boosts rename; the second merges the four-choice Open in App flow now adapted above. The Boosts merge adds tint and user-authored isolated-world scripts beside CSS, font controls, presets, and Zap. Ark already supports per-host CSS/font customization and Zap-style hide/restore; Search's pinned model intentionally remains CSS-only. Since Tint and script editing are not needed to close the current Yes-rated Mac Boosts row and add a separate styling/script surface, they were not copied during parity work. No matrix rating changed; no tests were added.

Reviewed Browsa PiP and Live Folder follow-ups [`7f2d3de`](https://github.com/jmaorr/Browsa/commit/7f2d3de90c748cbd655ff115b1576381d65472f4), [`0b5b54c`](https://github.com/jmaorr/Browsa/commit/0b5b54c9e90b3b542145800104d31b3ed99b2f65), and [`26e7e48`](https://github.com/jmaorr/Browsa/commit/26e7e48353f02187bb9631e2a3f90545efb3228d). Ark already selects and fronts the source tab before WebKit returns PiP inline; the merge repeats that change. Ark's pinned-list root already offers New Live Folder, and folder context menus offer New Live Subfolder where a source article is available; the extra per-tab shortcut is not a missing feed capability. No code or rating change; Arc remains the sidebar visual target.

Reviewed Browsa [`f14ce65`](https://github.com/jmaorr/Browsa/commit/f14ce657e7b5f0cf3af9ff64d4b4648620f7ed1a), [`235f24b`](https://github.com/jmaorr/Browsa/commit/235f24ba0479e5fe5f9c40a17a492f6159d84ffc), and [`3d87df8`](https://github.com/jmaorr/Browsa/commit/3d87df8d2b0b98284f740c3ac11da13ccc0ef732) with their process sampler, monitor, panel and shader changes. The monitor samples CPU/memory for app processes and maps WebKit processes to tabs via private `_webProcessIdentifier`, adds stuck-tab actions, and uses faster sampling while visible. Ark has an idle app/helper baseline but no per-tab panel or representative workload comparison. The private process identifier creates OS/WebKit compatibility risk; no code was adopted and no performance gain is claimed. Mac performance instrumentation remains a candidate gap requiring a supported process-to-tab mapping and repeatable workload evidence. The follow-up sort behavior defaults to memory until CPU load or a stuck tab makes CPU more useful. Simulated stuck-tab values are demo-only and are not performance evidence. The 307bd99 background shader pause and 66107da Library media optimizations remain pending separate diff review. Matrix ratings unchanged.

Reviewed Browsa [`307bd99`](https://github.com/jmaorr/Browsa/commit/307bd9950e3878a7050563dd8b611b7bef1f7fa7) and [`66107da`](https://github.com/jmaorr/Browsa/commit/66107dac87433c4dff937fc7335831a55b3b79d9), plus Library merges [`476317e`](https://github.com/jmaorr/Browsa/commit/476317ead01493288b35877fa2e818f4808ad374), [`5fb3996`](https://github.com/jmaorr/Browsa/commit/5fb3996dc812a2ea82dad7969ef7ce221595f566), [`d0536c8`](https://github.com/jmaorr/Browsa/commit/d0536c8e02c364c47e61dfefd6156329da978b91), and [`19e610b`](https://github.com/jmaorr/Browsa/commit/19e610b419b6c6aecbc95498dd4b296cd2eea0ff). The background shader pause has no Ark Performance panel to attach to. The Library commits add Browsa-specific feature clips, plugin promotion, and shared wallpaper; Ark has no matching comparison-row gap, and importing these assets would require a separate Library design decision. No code or ratings changed. Updated implementation review: 258/323 commits (79.9%), 65 pending. Mac Yes rows remain 20/42 (47.6%).

Reviewed the YouTube ad change chain: Browsa [`166fa00`](https://github.com/jmaorr/Browsa/commit/166fa001905b98f42957ade325e18962a2cd4e36), revert [`7cab120`](https://github.com/jmaorr/Browsa/commit/7cab120ce626305e2c8c976d5a6d441cc3d10a79), and reintroduction [`e981df5`](https://github.com/jmaorr/Browsa/commit/e981df56c551fc83efc39efe1b7d61cd7abe3071). The final diff adds YouTube-scoped filter rules, page-world rewriting of player responses to remove ad schedules, stand-in responses for blocked ad probes, an isolated-world mute/speed fallback, and a retry after SPA navigation when SABR backoff delays a video whose pre-roll was removed. Scripts install only when Ads blocking is on and skip allowlisted hosts. Ark has no equivalent and the generic filter rules alone cannot remove player-announced ad schedules. No code was copied yet. Any Search-derived code must retain its MIT attribution; Ark playback, direct-load and in-page-navigation cases remain unverified. Review progress is 261/323 (80.8%), 62 pending; Mac Yes rows remain 20/42 (47.6%).

Arc is the reference for the entire sidebar's layout, styling, interactions, and animations. Browsa and Search supply implementation references; their UI is not the visual acceptance target. Prioritize Mac fixes while mobile runtime verification remains deferred.

Before reviewing incoming commits, Ark added insertion positions and a visible insertion marker for dragging pins within a folder. The previous drag resolver only calculated individual positions among root pins. `ark:build-mac` passed; interactive verification of this new folder reorder path is still pending. Earlier SpikeArk checks established pinning, moving into a folder, and returning to Today, but did not establish reordering.

### Mac pinned-tab reorder verification — November 25, 2026

Re-tested the existing sidebar drag interaction in SpikeArk's isolated mock profile. The control endpoint initially targeted a non-key window and did not deliver the drag; after activating SpikeArk, dragging **Checkout · Northwind** below **Northwind Shop** changed the mock tab order in `/state`. This verifies root pinned-tab reorder in the shared Mac UI source without touching Ark's installed profile or adding test files. The comparison row remains Partial: this check does not cover pin-folder reorder, Mac multi-selection/undo, or iPhone/iPad/Duo behavior. Existing Mac preview for this feature remains [pinned folders](../../preview/ark/mac/features/pinned-folders.png).

Fetched upstream heads: Browsa `e981df56c551fc83efc39efe1b7d61cd7abe3071`; Search `33ec7aea1823c81c77a2be196e442dd54e36efa7`. These are review targets, not fully synced baselines. Neither reference checkout was switched or merged.

### Search extension popup behavior — November 25, 2026

Reviewed Search [`d123cdc909f7a423e26cc89c6b664a26324c323b`](https://github.com/driceroland/Search/commit/d123cdc909f7a423e26cc89c6b664a26324c323b) and [`2214b1263b6a04334a06f6152468336fb4cac526`](https://github.com/driceroland/Search/commit/2214b1263b6a04334a06f6152468336fb4cac526). Search owns its extension popup WebView and custom fetch bridge, so it can size popups itself and choose cookies from the popup's originating Browser. Ark uses WebKit-managed native action popovers; copying the custom observer/fetch marker would not have a compatible Ark consumer and could conflict with WebKit's popup lifecycle. No source change was made. Cross-profile extension-popup sign-in behavior remains unverified, so Chrome Extensions stays Partial. Incoming review is now 119/272 commits (43.8%); the Mac matrix remains 21/42 rows rated Yes (50%).

Reviewed Browsa [`c81876f6f62b7bcae9e979152c7d059144659ed9`](https://github.com/jmaorr/Browsa/commit/c81876f6f62b7bcae9e979152c7d059144659ed9). Ark already supports four panes, side-by-side and stacked layouts, per-pane focus and resizing, and pane ownership through pin/move/close flows; existing Mac fixtures cover the layouts. Browsa keeps split state in Mac preferences and supports at most three panes, so its implementation adds no Ark capability. No code or matrix change; Split View stays Yes on Mac and Partial on mobile pending device interaction checks. Incoming review is now 120/272 commits (44.1%); the Mac matrix remains 21/42 rows rated Yes (50%).

Reviewed Browsa [`a9e2a61679b0a974fa32142aabf43ca43bc8a17b`](https://github.com/jmaorr/Browsa/commit/a9e2a61679b0a974fa32142aabf43ca43bc8a17b) and merge [`b7a312dce7aa9f05875dbf41a8d4fe9f43a36884`](https://github.com/jmaorr/Browsa/commit/b7a312dce7aa9f05875dbf41a8d4fe9f43a36884). Ark already isolates website data per Space profile and preserves profile IDs beside pin-folder layouts in saved state, including restoration and backward-compatible optional fields. No source change or Ark commit was needed. The Profiles row stays Yes on Mac; Pinned tabs and folders remains Partial pending interaction evidence. Upstream review is now 122/272 (44.9%); the Mac matrix remains 21/42 Yes (50%).

### Split panes as one pinned row — November 25, 2026

Adapted Browsa [`2b772addf4e56a295a1c2d5140c72908bcc019f6`](https://github.com/jmaorr/Browsa/commit/2b772addf4e56a295a1c2d5140c72908bcc019f6). BrowserCore now identifies a complete split group separately from the narrower condition for collapsing rows: the sidebar collapses panes only when every member is visible in the same pinned section and folder. Mac sidebar rows and iOS pin-folder/gallery rows show one representative with a pane count. Moving a Today split into a pin folder carries every pane; reordering a pinned split keeps its panes together. Mac build passes. Live drag behavior and iPhone, iPad, and Duo remain unverified; no simulator was launched. The Pinned tabs and folders rating remains Partial. Upstream review is now 123/272 (45.2%); the Mac matrix remains 21/42 Yes (50%).

Reviewed Browsa [`aac7ed9991fa39a44120c43bef3d85edfedd59cc`](https://github.com/jmaorr/Browsa/commit/aac7ed9991fa39a44120c43bef3d85edfedd59cc). Ark's Mac divider already stores live width changes in view-local `GestureState` and commits them once at drag end, while supporting horizontal and vertical splits with up to four panes. The upstream's AppKit resize cursor/grabber and pane-menu reveal are visual choices; Ark keeps its Arc-aligned controls. No code or comparison change. Upstream review is now 124/272 (45.6%); the Mac matrix remains 21/42 Yes (50%).

Reviewed Browsa [`24377a9db55c13d6844ab017b7ea25b6a5454b71`](https://github.com/jmaorr/Browsa/commit/24377a9db55c13d6844ab017b7ea25b6a5454b71). Its split-wide hover tracker and glass toolbar are custom Browsa UI. Ark already keeps split proportions local during a drag and exposes actions through the focused pane; this commit adds no Arc feature row, and there is no measured performance case for adopting the broad UI rewrite. No code or comparison change. Upstream review is now 125/272 (46.0%); the Mac matrix remains 21/42 Yes (50%).

Adapted Browsa [`7627957dd8a09cdf0237faa08b651b11762ed91f`](https://github.com/jmaorr/Browsa/commit/7627957dd8a09cdf0237faa08b651b11762ed91f). Mac Favourite tiles/context actions and iOS start/New Tab Sheet selections now bypass Space Routing while preserving current-tab behavior. The Routing setting text clarifies that Favorites stay in the current Space. This brings global Favorites in line with Arc's current-Space behavior. Mac build passed; the iOS target and live routing interaction remain unverified. Upstream review is now 126/272 (46.3%); the Mac matrix remains 21/42 Yes (50%).

### Mac Easels first pass — November 25, 2026

Added `EaselStore` and `EaselView` in `apps/ark/Mac/Sources/Library/Easels.swift`. The Library opens local boards; page context menus add the current page as a card, and the canvas supports editable notes, movable cards, and PNG cards imported from the clipboard. Image files stay beside the local board data under Ark's support folder; Easels are not synced. The existing `SnapshotTour` now seeds a page card, note, and captured page image and writes an `easels.png` preview when its feature tour runs. `pnpm nx run ark:build-mac --output-style=static` passed. Runtime behavior and the generated preview are not yet verified because the tour has not been run against the rebuilt app. The matrix moves Mac Easels from No to Partial; drawing/markup, direct canvas capture, export, sharing, sync, and mobile remain open.

Extended Mac Easels with **Capture Current Page**, which sends a full-page PNG directly to the active local board without using the clipboard. It reuses `PageCaptureImage`, rejects private tabs, and retains the 15 MB image limit. The Mac build passed. The running Finder app still maps an older executable, so this action and the Easels preview image are not runtime-verified. Drawing/markup, export/share, sync, and mobile remain open; no upstream commit was available for this Ark-only gap closure.

Added persistent freehand doodle cards to the Mac Easel canvas. Strokes are stored on the board and remain attached when the card moves. The Mac build passed; runtime checks and the feature screenshot remain pending. Image markup/editing, export/share, sync, and mobile are still open.

Added single-board PNG export through a native save panel. `ImageRenderer` exports the static 2400×1800 board, including notes, page cards, captures, and doodles. Doodle sampling now ignores points within two points of the prior sample and caps each stroke at 4,096 points to bound stored path size and redraw work. The Mac build passed; export output and drawing behavior have not yet been exercised in the rebuilt app. Bulk ZIP export and share integration remain open.

Added **Export All** as a ZIP containing one browsable HTML file per local board, an index, and referenced PNG assets. HTML output escapes user text and links only HTTP(S) page cards; archive creation runs off the UI thread with macOS `ditto`. The Mac build passed. The generated archive and feature UI have not been exercised in the rebuilt app; direct share-sheet integration, image annotation/editing, sync, and mobile remain open.

Added a Mac **Share…** action for the active Easel. It renders the same lossless board PNG used by Export PNG into a uniquely named temporary file and gives that file to the native macOS share sheet. Ark itself does not upload the board or create a hosted collection. `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. The share interaction remains runtime-unverified; image annotation/editing, sync, and mobile remain open.

GitHub Pull Requests Live Folders now use the same visible-sidebar 15-minute refresh cadence as regular feeds. A background pass only runs for a Space that already contains the signed-in GitHub folder, reads that Space's in-memory GitHub cookies, saves only the refreshed folder, and is deliberately silent. Manual refresh still reports a missing GitHub sign-in. This closes the prior background-refresh implementation gap; signed-in response parsing, filters, and live interaction evidence remain open.

The shared iPhone, iPad, and Duo app now exposes the same GitHub Pull Requests folder in its plus-menu and uses the selected Space's WebKit cookie store only for that request. Its visible sidebar also refreshes an existing GitHub folder every 15 minutes without a background toast. The generic iOS Simulator build passed without booting a simulator; signed-in and device runtime verification remain open.

### Mac favorite web-app previews — November 25, 2026

Added a Mac hover preview for Notion, Figma, and Linear favourites. It reads up to five recent visits from the active website profile's local history and opens a selected page in a new tab; Private Space is excluded. The pinned Search source and reviewed Browsa history have no service-specific preview implementation, so this is an Ark-native first pass based on Arc's behavior rather than a copied upstream feature. `pnpm nx run ark:build-mac --output-style=static` passed. The running Finder app still maps the pre-build executable, so interaction and screenshot checks are pending. Mac Previews moves from No to Partial; service APIs/actions, mobile, and the dedicated feature screenshot remain open.

Adapted Browsa `85f6092a072347c472cc7e841ecbced7707e5ba5` in Ark's `PageActivity.swift`: coalesce media events over 200 ms instead of rescanning media for every event. Ark additionally cancels the pending report on `pagehide` so an old timer cannot overwrite the inactive report. Input and submit reporting remain immediate. An in-memory Node check of the extracted script verified that 100 media events scheduled one scan and page hide cancelled the pending timer. This uses a mock DOM, not live WebKit, and does not establish a measured CPU improvement. Live timing verification remains pending.

Adapted Search `cc3ee712f8e6b6e2ed5131fbfd904e0097d0b824` in BrowserKit's Chrome Web Store updater. Installed extensions now send their current version, Chrome platform/product fields, and foreground update headers; first-time downloads keep their existing discovery request. The existing BrowserKit Swift test target and `ark:build-mac` passed. A live staged-rollout update remains unverified. Arc's Chrome extensions row and its compatibility evidence are unchanged.

Ark implementation checkpoints: [`d6c96345`](../../commit/d6c96345) adapts Search `cc3ee712f8e6b6e2ed5131fbfd904e0097d0b824` by sending Chrome-compatible foreground update requests. [`f4d83a07`](../../commit/f4d83a07) adapts Search `987da47510c80df6c7d3d648caae375aee4dc909` by persisting retry timing per extension (1, 2, 4, 8, 16 hours, capped at 20 hours) while allowing manual checks to bypass it. BrowserKit tests and the Mac build passed. A live staged rollout and simulated outage/recovery remain unverified.

Review-only dispositions: Search `2f99ea479579582ff6eaf63f6596aef7ca78b26b` adds hidden test-bench seams, not browser behavior; `75eb6728a20e4f91a8465ce8bb2a91812058b4dc` adds a bookmarks-bar icon-only preference that does not match Arc's sidebar. Search `20942bc01fe5a96f63b3490e5f9cf643f133b996` is now adapted in Ark's native extension-action popover; the real Raindrop sign-in flow remains a runtime check.

Search `344088842d4fb67b8340aba5e7b799589eb2a0b3` changes a worker `window` shim that Ark does not have: Ark leaves `window` undefined in extension workers, allowing Readwise to define it as `globalThis`. No port is needed unless Ark reproduces a failure.

Reviewed Browsa `53eebb6fd5b97f403077adb0a509a384b4fe8ad0`: Ark's link-open path already inserts a child tab after its source, while manually created tabs use Ark's existing placement and WebKit popups become tabs. The upstream's opener-return history, small sign-in windows, and new-tab placement preference are separate Mac behaviors with no direct Arc matrix gap. Deferred for a focused compatibility decision; no code or matrix rating changed.

Reviewed Browsa `989e0c7119281a0297389728cd8bc189f54d1817`: Ark already implements per-site Boosts with custom CSS, font choice, element hiding/restoring, and live application. Browsa adds a bundled LinkedIn preset and a one-time animated suggestion; these do not close a capability gap in the 42-row Boosts comparison. No code or matrix rating changed.

Reviewed Browsa `198f9de27ad744eb1a3398a94264047b8fa016e1`: Ark already offers one-click Claude Code setup, exact Codex/Cursor config snippets, connected-agent status, and Claude token refresh. Browsa additionally writes Codex/Cursor/VS Code config files and unifies their setup/status UI. This is a separate Agents workflow improvement outside the 42 Arc rows and pinned Search gaps; defer to a dedicated Agents pass. No code or matrix rating changed.

Reviewed Browsa `05163ec1fd691ae7ed07f9a1ffd5038cd2dbcb5f`: third-party native messaging would start local executables and needs strict `allowed_origins` validation, extension permission checks, bounded framing, process cleanup, and clear errors. The same commit changes Chrome Web Store extensions from Ark's current `webkit-extension` identity to `chrome-extension`; existing storage/cookies depend on the old identity, so a migration must preserve sign-ins. Defer the code until the security and migration design has focused verification. Chrome extensions remains Partial; no code or matrix rating changed.

### Search pinned-link behavior — Mac

Reviewed Search [`cf21241b244cd4af9b77013ce7d453b93843df50`](https://github.com/driceroland/Search/commit/cf21241b244cd4af9b77013ce7d453b93843df50). Ark originally added an off-by-default General setting that opens a plain, unmodified main-frame HTTP(S) link from a pinned page in a Today tab while keeping the pin at its current page. Same-page fragment changes, common sign-in routes, forms, modified clicks, and non-link navigations stay on the pinned page. On November 25, that setting expanded to a three-way destination while preserving the old boolean preference: Stay in pin, Today tab, or Glance. Search's [`0d18ae9`](https://github.com/driceroland/Search/commit/0d18ae95dd54a410c443334f1c5e4e3a6f87c9d9) adds optional cross-site pin peeks; Ark routes eligible plain cross-host clicks to its existing Glance and retains its own native settings UI. Exact-host comparison is conservative because Ark has no public-suffix service; subdomains of one registrable site may open Glance where Search would keep navigation in the pin. The existing SnapshotTour exercises both Today and Glance destinations without adding a test file. Its earlier `EXC_BAD_ACCESS` traces pointed to actor-isolated work inside `Browser.currentSpace` and SwiftUI view-builder closures. Ark now resolves the space with a direct loop, builds concrete background/overlay views, and uses the observable prompt binding with cancellation handled by `Browser`; both `ark-spike:build-mac` and `ark:build-mac` pass, as do strict bundle-signature and `git diff --check` validation. The tour has not reached either link check: the raw executable aborts in AppKit registration, while Launch Services reports `kLSNoExecutableErr` for the rebuilt bundle and the Spike control port is unavailable. The WebKit click path remains unverified, so Peek and Pinned tabs stay Partial. The verified picker screenshot is [pinned-link destinations](../../preview/ark/mac/features/pinned-link-actions.png). No simulator was launched.

Reviewed Search [`bceedf3735165648d85e96663b60abf215f31db9`](https://github.com/driceroland/Search/commit/bceedf3735165648d85e96663b60abf215f31db9), which keeps AdGuard extension `declarativeNetRequest.updateSessionRules` from compiling the same session rules twice during startup. Ark does not expose this extension API. Ark's separate WebKit content blocker asks `WKContentRuleListStore` for stable compiled identifiers before compiling. No code change was justified, and no Ark startup-performance gain is claimed. The Bloat matrix evidence now records this disposition; Ark remains unscored.

### Search close-to-previous behavior — Mac

Adapted Search [`824664a4291b8d99fe00ecfb1857d1b2796fc4f3`](https://github.com/driceroland/Search/commit/824664a4291b8d99fe00ecfb1857d1b2796fc4f3) as a new off-by-default setting, **Closing a tab goes back to the one before**. Actual closes can select Ark's previously viewed tab; a Split View partner still wins, and moving a tab does not use the close preference. The existing SnapshotTour gained a pin-close scenario alongside the pinned-link scenario. `ark:build-mac` passed. SnapshotTour still cannot reach either check: a Launch Services launch also crashes with `EXC_BAD_ACCESS` in SwiftUI's main-actor executor path while evaluating `BrowserWindow.background`. No simulator or test file was added; Pinned tabs remains Partial pending interaction evidence.

Reviewed Search [`d0a1aa77cdc2403cbe4b89d98507dc919a1be1ae`](https://github.com/driceroland/Search/commit/d0a1aa77cdc2403cbe4b89d98507dc919a1be1ae). Ark's `SiteStyleEditor` already removes a row from its local list immediately after an individual restore succeeds, and **Restore All** clears the list after persistence succeeds. Search's floating, draggable panel is Search-specific UI and does not match Ark's current editor or Arc's visual reference, so it was not adopted. The Boosts row remains as recorded; this was a source review, not a new runtime check.

Adapted Search [`8c1b9cab3ee25d6a33d6f6e1b4c4d16ee149a23f`](https://github.com/driceroland/Search/commit/8c1b9cab3ee25d6a33d6f6e1b4c4d16ee149a23f) in `ExtensionCompat.prepare`: Ark now injects its prelude after the doctype and opening `<html>` when an extension page omits `<head>`, uses a `<head>` expression that does not match `<header>`, handles both `.html` and `.htm`, and preserves an existing UTF-8 BOM. Ark prepares a private copy of the extension each load, so no installed-source migration was needed. `ark:build-mac` passed. Runtime validation of standards mode (`document.compatMode`) in a real extension page is open; the SnapshotTour launch crash prevents the existing app harness from running. No new test file was added.

Reviewed Search [`542276c69bac8ce927a23fa0b89d15ca28b4f530`](https://github.com/driceroland/Search/commit/542276c69bac8ce927a23fa0b89d15ca28b4f530), which intercepts WebKit pointer events beneath a folded sidebar and during its entrance animation. Ark has a different implementation: its floating sidebar and edge trigger are overlay views, and `PageArea.pageUnderPointer` forwards inactive-window hover only to the WKWebView returned by AppKit hit-testing. That source suggests the overlay already shields forwarded hover; active-WebKit hover during the transition remains unverified. Search's `PageView` override was not copied into Ark's different WebKit setup. No code change; the runtime harness crash prevents the pointer check.

Reviewed Search [`eba1ebf2efa6bb7f5204e70bd600ece7ae7360cd`](https://github.com/driceroland/Search/commit/eba1ebf2efa6bb7f5204e70bd600ece7ae7360cd). Search's change protects its forced-kill watchdog from killing a reused PID or an extension's shared WebKit process. Ark has no stuck-process watchdog or page-process kill path, so there is no corresponding behavior to fix. No code was copied and no Arc matrix row changes.

Reviewed Search [`7bfd3fb840934bd1adc4ce74e70d812a14d80002`](https://github.com/driceroland/Search/commit/7bfd3fb840934bd1adc4ce74e70d812a14d80002). Its hidden-app probe measures frame gaps, main-loop work, CPU, row creation, and scroll offsets during Space swipes and sidebar scrolling. Ark has no baseline for those interactions, so there is no evidence-based optimization to make yet. The existing SnapshotTour currently crashes in `BrowserWindow.background` before reaching interactions, and the user asked not to add test files. Keep performance measurement open; do not infer a win from Search's instrumentation.

Reviewed Search [`2b14540a7d2bc99f4861f02b0f4126dbdb16b726`](https://github.com/driceroland/Search/commit/2b14540a7d2bc99f4861f02b0f4126dbdb16b726). It adds only a test probe for typing immediately after ⌘T/⌘L while a page captures single keys. Ark exposes these shortcuts as menu commands and focuses its command field, but the race case needs runtime evidence. No test file was copied; the SnapshotTour crash blocks that check.

Adapted Search [`695fac9b505b9d018a99fd96ab7db30d5139fdc6`](https://github.com/driceroland/Search/commit/695fac9b505b9d018a99fd96ab7db30d5139fdc6) in Ark's `KeyLayout.swift` and `Shortcuts.swift`. Shortcut events now resolve through the active layout's ⌘ layer, so Dvorak–QWERTY ⌘ follows the QWERTY shortcut keys; non-Latin layouts use their paired Latin keyboard layout. The Mac build passed. No test file was added; verification with actual Dvorak, AZERTY, and Cyrillic/Greek layouts remains open.

Adapted Search [`9a54ad2002b4e81506a074e8226eebe55115717e`](https://github.com/driceroland/Search/commit/9a54ad2002b4e81506a074e8226eebe55115717e) as a new off-by-default Mac General setting, **Space and arrow keys control videos**. Ark's isolated WebKit world handles Space and five-second arrow seeks only when a native media element is focused, leaves full-screen handling to WebKit, and yields when a page already prevented the key. The setting updates existing pages and is injected for new pages. `ark:build-mac` passed. Runtime checks remain open because SnapshotTour crashes before interactions. No test file or Arc matrix row was added; the 42-row matrix remains 21/42 Mac Yes.

Adapted Search [`fdc43d312ed891a22b431105e92a77e13bcbb14d`](https://github.com/driceroland/Search/commit/fdc43d312ed891a22b431105e92a77e13bcbb14d) for Ark's Mac error state. While `LoadError` is visible, the address field, Reload, Copy Link, and Copy Markdown use its failed HTTP(S) URL instead of WebKit's still-committed page. Copy preserves the complete query, including OAuth callback parameters; retry loads the failed URL through Ark's normal tab controller. Build verification and runtime checks for a refused localhost callback, query copying, retry, and Back remain open. No test file was added.

Reviewed Search [`94dc33141605f0f949b3d7aa6d0455eb910b48fc`](https://github.com/driceroland/Search/commit/94dc33141605f0f949b3d7aa6d0455eb910b48fc), which adds an in-window update card for Search's own staged installer. Ark currently delegates update prompts and restart/install actions to Sparkle's standard windows. Its release config still has a TODO for the Team ID and Sparkle feed, so a ready event cannot yet be exercised and the update card has no stable lifecycle to attach to. No code change; revisit once release hosting and Sparkle update flow are configured. No Arc matrix row changes.

Adapted Search [`2951fe38a208952c15431cb432413131fc01a5da`](https://github.com/driceroland/Search/commit/2951fe38a208952c15431cb432413131fc01a5da) in Ark's Mac incoming-link flow. After Ark shows an external Link Preview or fronts a regular browser window, it requests activation normally and retries with `ignoringOtherApps` after 250 ms only if macOS left Ark inactive. This avoids changing activation behavior when Ark is already frontmost. Build and real external-app frontmost verification remain open. No test file was added; the Little Arc matrix rating remains as recorded.

Reviewed Search [`b81693586068a2daefca5d2440c33fadebbd1d37`](https://github.com/driceroland/Search/commit/b81693586068a2daefca5d2440c33fadebbd1d37). Ark's ⇧⌘D Add to Favourites action uses `toggleFavoriteForCurrentTab()` and always shows an added/removed toast; it does not depend on the visibility of any sidebar button. No Ark change or matrix rating update is needed.

Reviewed Search [`fa555191c98e47e44855dfe43e75aa0adcc6a804`](https://github.com/driceroland/Search/commit/fa555191c98e47e44855dfe43e75aa0adcc6a804). Search adds a Site Information card anchored to a pinned icon and offers it in the pin menu. Ark's per-site Site Menu already supplies blocker, permission, zoom, and extension controls for the selected tab; a pin can reach the same menu after selection. This is a one-step convenience gap rather than missing site controls. No code change in this pass; direct pin-context access should be considered alongside the full sidebar interaction review, with Arc as the visual reference. No matrix rating change.

Reviewed Search [`f43a570bedf9d7a5e34490feed1a90bfe4f635c9`](https://github.com/driceroland/Search/commit/f43a570bedf9d7a5e34490feed1a90bfe4f635c9), which introduces signed optional DevTools packages and a Lite package with Lighthouse, Recorder, and device emulation. Ark's Developer mode already exposes Apple's Web Inspector and has no package feed or dynamic devtools runtime. These capabilities form a separate product subsystem and do not map to a missing Arc matrix item; no code or rating change.

Reviewed Search [`a48465be6cda93873982a6ff26402bcbd61d20e9`](https://github.com/driceroland/Search/commit/a48465be6cda93873982a6ff26402bcbd61d20e9). Its optional Full package adds a large Web Inspector replacement spanning Sources, Console, Elements, Network, Performance, Memory, and debugging. Ark uses WebKit's native inspector; adopting this would require owning the signed package system and inspector bridge/runtime. It is not a scoped Arc feature gap, so no code or matrix change.

Reviewed Search [`ed8f05f085dc6c04ac4a0e75939d1a31646da01d`](https://github.com/driceroland/Search/commit/ed8f05f085dc6c04ac4a0e75939d1a31646da01d), which selects the latest installed optional developer-tools package when the user has not selected one. Ark has one built-in Web Inspector and no package-selection state; no corresponding code or matrix change.

Reviewed Search [`5e87d1924d2db681042b56ef8d69d8f74b1ee9ef`](https://github.com/driceroland/Search/commit/5e87d1924d2db681042b56ef8d69d8f74b1ee9ef). It allows insecure HTTP only for Search's explicitly overridden developer-tools package feed during test runs and adds a publisher for those packages. Ark's release publisher already reads app-specific Sparkle settings from `vx.deploy.yaml`; there is no Ark optional package feed or matching upload. No code or matrix change.

Reviewed Search [`3cb5f87c951c2b554e8920c5a2d1f91fdca9e9f0`](https://github.com/driceroland/Search/commit/3cb5f87c951c2b554e8920c5a2d1f91fdca9e9f0). It constrains the optional DevTools Network HTML preview with a restrictive Content Security Policy and cancels navigation away from the preview document. Ark has no Network response preview; its inspector is WebKit's native implementation. No Ark code or matrix change.

Reviewed Search [`c145ae6cfd3860406b977f9f796262ceb8245f94`](https://github.com/driceroland/Search/commit/c145ae6cfd3860406b977f9f796262ceb8245f94). It caps optional DevTools resource responses at 64 MiB and 60 seconds. Ark has no source-map, `devtools.json`, or `robots.txt` fetcher and no optional DevTools host, so there is no matching network path to harden. No code or matrix change.

Reviewed Search [`1c9f3af2064fc7360017daf835e5a3a742543510`](https://github.com/driceroland/Search/commit/1c9f3af2064fc7360017daf835e5a3a742543510). It keeps optional inspector watch expressions ephemeral for private tabs. Ark has no persisted inspector watch state; private browsing data already uses separate ephemeral handling. No code or matrix change.

Reviewed Search [`d2e6ece4469d69a6e8d88f551d597d9606b7f039`](https://github.com/driceroland/Search/commit/d2e6ece4469d69a6e8d88f551d597d9606b7f039). It validates an optional DevTools package's API version from its signed bundle metadata rather than adjacent mutable JSON. Ark has no separately installed signed developer packages or package API version. No code or matrix change.

Reviewed Search [`1fd49891eb229ef098b3b77b5ec8925c879a92e7`](https://github.com/driceroland/Search/commit/1fd49891eb229ef098b3b77b5ec8925c879a92e7). It refuses hidden ZIP entries and strips resource forks, extended attributes, and ACLs while unpacking optional DevTools packages. Ark has no matching developer package installer or Arc matrix row. No code or matrix change.

Reviewed Search [`b9d22e937331d28a714df8eef672d3a92dbbbb7c`](https://github.com/driceroland/Search/commit/b9d22e937331d28a714df8eef672d3a92dbbbb7c). It streams optional DevTools packages to disk and cancels when the signed feed's size limit is exceeded. Ark has no optional package feed or installer; this does not apply to normal user downloads. No code or matrix change.

Reviewed Search [`073288758d09fd0d0343fb658c57946a2496f0f7`](https://github.com/driceroland/Search/commit/073288758d09fd0d0343fb658c57946a2496f0f7). It removes leftover optional package staging/temp folders and restricts DevTools media previews to local, non-private contexts. Ark has no matching optional DevTools/media preview subsystem. No code or matrix change.

Reviewed Search [`ec6e9370717170224f6eb5d18966cb3a054b26bd`](https://github.com/driceroland/Search/commit/ec6e9370717170224f6eb5d18966cb3a054b26bd). It keeps optional developer package settings in a memory-only UserDefaults fallback until the package's own suite is available. Ark has no optional DevTools settings domain; private browser data already uses separate ephemeral stores. No code or matrix change.

Reviewed Search [`e11c3cac5ac00b37076465c6aab67e223989af6d`](https://github.com/driceroland/Search/commit/e11c3cac5ac00b37076465c6aab67e223989af6d). It requires Developer ID signing for release DevTools packages and ensures the feed only lists packages built in that run. Ark's release scripts already validate signing and package the app through `vx.deploy.yaml`; it has no DevTools feed. No code or matrix change.

Reviewed Search [`6f8ecd64ce7238d808804c35e78be5935e840919`](https://github.com/driceroland/Search/commit/6f8ecd64ce7238d808804c35e78be5935e840919). It lets Search's optional Lighthouse/Recorder tooling session close so the page can sleep. Ark has no equivalent auxiliary DevTools session; regular inactive-page unloading is handled separately. No code or matrix change.

Reviewed Search [`111cf442374f9b3b1be9ed3f463c0873d75550a6`](https://github.com/driceroland/Search/commit/111cf442374f9b3b1be9ed3f463c0873d75550a6). It changes only Search's optional DevTools test skip/setup behavior. No tests or code were added to Ark; no matrix change.

Reviewed Search [`0750c1a7fcca55e81940b29177708f3055d95faf`](https://github.com/driceroland/Search/commit/0750c1a7fcca55e81940b29177708f3055d95faf). It adds custom engine suggestion URLs, validation, settings, and sync. Ark currently supports Google and DuckDuckGo only and has no custom-engine model; this is outside the Arc comparison and requires a broader search-settings feature. No code or matrix change.

Reviewed Search [`bd021c42d53821b7de472f0671a58384e778bb90`](https://github.com/driceroland/Search/commit/bd021c42d53821b7de472f0671a58384e778bb90). It adds an optional bookmarks toolbar that appears only on blank tabs, following Chrome/Edge. Ark's Arc-inspired layout puts favourites in the sidebar and has no toolbar; this would add a different navigation surface without closing an Arc row. No code or matrix change.

Reviewed Search [`a122961702e415c16994c1823500ad5c6104309d`](https://github.com/driceroland/Search/commit/a122961702e415c16994c1823500ad5c6104309d). It adds a preference so clicking the selected tab does not replace its title with the address when Search's address bar is always shown. Ark keeps its address pill separate from the sidebar tab row; a single click on the selected tab already leaves the title intact. No matching behavior gap or code change.

Reviewed Search [`3e1efc6a14c69f4810018db34f83c03d417355e5`](https://github.com/driceroland/Search/commit/3e1efc6a14c69f4810018db34f83c03d417355e5). It moves a multiselection of tabs into a pin folder or group and restores the prior row/group/folder state with one ⌘Z. Ark currently moves one tab at a time and has no sidebar multiselect or move undo. This applies to the existing Pinned tabs and folders row; implementation needs an Ark/Arc-consistent selection interaction rather than Search's separate selection model. Mac follow-up remains open; no code or rating change yet.

Adapted Search [`838d238c39bb807a386b4ffcf43b5b3a0271f857`](https://github.com/driceroland/Search/commit/838d238c39bb807a386b4ffcf43b5b3a0271f857). Ark now records a pinned tab's original URL, includes it in snapshot and cross-device sync records, and adds a Mac sidebar icon return action plus a Mac/iOS tab-menu action. `ark:build-mac` passed. The selected interaction remains runtime-unverified, and the shared iOS UI code has not been compiled yet; no simulator or test file was added. The Mac pinned-tabs row is now Yes based on the November 25 sidebar interaction checks; iPhone, iPad, and Duo remain Partial.

Reviewed Search [`5c3dfece73dd9ae69efe265ab71d4ce310b1e2e3`](https://github.com/driceroland/Search/commit/5c3dfece73dd9ae69efe265ab71d4ce310b1e2e3). It separates iCloud sync and Mac-only folder sync in settings because the two methods are mutually exclusive. Ark has one sync method: a user-selected folder shared across devices, and no iCloud sync toggle. Its current Sync settings already describe the transport and what stays local; no code or matrix change.

Reviewed Search test-only commits [`616abb9`](https://github.com/driceroland/Search/commit/616abb9c7eea6a77d0c5e2fae999e4f5bd059729), [`1284e4a`](https://github.com/driceroland/Search/commit/1284e4af67b0b6e299acd8e84c4c328d964bf242), and [`588df6f`](https://github.com/driceroland/Search/commit/588df6f4f2c25f1bc92b77872fc4adc41be647f4). They adjust Search fixtures and a split-drag automation wait only. No Ark test files or behavior changes were added, per the current constraint.

Reviewed Browsa [`58f6c41f704e3fb449c4cf015384eb45a0d87cab`](https://github.com/driceroland/Browsa/commit/58f6c41f704e3fb449c4cf015384eb45a0d87cab). It implements web notifications through WebKit engine hooks, a Mac `UNUserNotificationCenter` delegate, remembered site permissions, and click-to-tab/page routing. Ark has saved camera/microphone/motion permissions but no Web Notifications permission type or notification backend. This is a substantial Mac-only subsystem with no direct Arc comparison row, so it is deferred while working through the 42-row matrix. No code or matrix change.

Reviewed Browsa notification follow-ups [`2e7723a`](https://github.com/driceroland/Browsa/commit/2e7723a00f8c3094a27d99a4fbcfb2b2204487ee), [`0174855`](https://github.com/driceroland/Browsa/commit/017485534e38d14d55563fb7076c9b0214a26dab), [`0668064`](https://github.com/driceroland/Browsa/commit/0668064cb39941e8f2d3d85c301f881683ff34de), and [`e454603`](https://github.com/driceroland/Browsa/commit/e45460383f3cc28dec1e732f3fd3b4e4679fd3a5). They fix a framework import, keep WebKit handlers stable while pages are alive, and surface macOS notification authorization state and System Settings. All depend on the deferred Web Notifications subsystem; no Ark code or matrix change.

Ark commit [`b357c402`](../../commit/b357c402) adapts Browsa `5150b3c83fb7d0aadec46707a2e802c495942fa2` with Ark's `ark.identity` bridge. Only extensions declaring the `identity` permission can start a Chrome Web Store OAuth flow. Interactive sign-in opens a tab; quiet sign-in uses a hidden WebKit view with the active profile's website data store. Matching redirects are returned to the extension and never loaded from `chromiumapp.org`; redirects from flow-owned popups close with the flow. BrowserKit tests and `ark:build-mac` passed. Provider sign-in, callback behavior, and direct extension-tab redirect observation remain unverified; Ark does not use Search's private `loadSimulatedRequest` API.

### Boost fonts — Mac implementation

Compared Browsa `c3395378003da051a43fdc71b586ddcd57ea3a47` and pinned Search `6f2b186bfa862d282ee9f424be1dfd5eb8ddc316` with Ark's existing site-style feature. Search explicitly limits its site styles to user CSS and does not run authored page scripts. Ark already had exact-host CSS plus Zap-style element hiding, persistence, restore, and preview. Added per-host Original, System, Serif, Rounded, and Mono font choices to the Mac editor and shared BrowserKit style application, stored separately in `site-fonts.json` to preserve existing style and hidden-element files. Browsa's page-tint overlay and arbitrary user scripts were not adopted: the former needs a deliberate visual/accessibility design, while the latter adds an execution surface beyond Search's CSS-only model.

Verification: all 75 existing BrowserKit tests passed, including font persistence and host isolation; `ark:build-mac` passed. The existing isolated SnapshotTour then opened the built Mac app against a temporary local HTML fixture, selected Serif, and read WebKit's computed `New York, ui-serif, Georgia, serif` both before and after reload. It also confirmed style absence on another host and in a private tab. The [Boosts editor](../../preview/ark/mac/features/boosts-editor.png) and [applied style](../../preview/ark/mac/features/boosts-applied.png) captures were added in [`c6496925`](../../commit/c6496925). No new test file or simulator was added. Ark implementation: [`25c7b5d5`](../../commit/25c7b5d5).

### Boosts naming — Mac

Reviewed Browsa `7a494d094c349da5ad5b6ca470e4d154635d7ae2` and duplicate merge result `0ab8524378116a0416a46eecf8189dc6745fc398`. Ark now labels its site customization command and editor **Edit Boosts… / Boosts**, consistent with Arc. Ark's stable internal command ID and storage paths remain unchanged to avoid breaking saved CSS or debug automation. `ark:build-mac` passed; the isolated Mac SnapshotTour displayed and captured the renamed editor in [`34b7b742`](../../commit/34b7b742). Matrix ratings are unchanged.

### Mac runtime pass for Boosts

The existing SnapshotTour ran the current Mac build in isolated state against a temporary local fixture. It confirmed the Serif font and custom CSS computed on the fixture page before and after reload, no application to a different host or private tab, and successful clearing. Fresh screenshots were committed at `preview/ark/mac/features/boosts-editor.png` and `boosts-applied.png` in [`c6496925`](../../commit/c6496925). Folder moves passed in the same tour; the static Live Folder fixture did not change its feed between requests, so its refresh assertion was inconclusive and does not replace the earlier stateful-fixture pass. The captured tour ended normally; no simulator was launched.

### Pinned-page ordering regression coverage — Mac

Added an ordering regression case to the existing `PinFolderTests.swift` file. It exercises moving a pin before/after another pin, moving between root and folder membership, and maintaining each visible group order. The BrowserKit suite passed all 76 tests across 14 suites. This validates the model used by the drop handler but does not verify that a physical Mac drag reaches the intended drop row; the matrix remains Partial until that interaction is observed in the app. Ark implementation: [`b1bc11c6`](../../commit/b1bc11c6).

Ark commit [`2c274b22`](../../commit/2c274b22) now highlights a pinned-page row while a dragged pin is over it, giving visible feedback on the target. The BrowserKit suite passed all 76 tests and `ark:build-mac` passed. The test still does not establish that the native Mac drop completes or changes the order; the UI rating remains Partial pending a physical drag check.

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

Compared Browsa [`a4de8f2cf9d98a0d633c05bb6762105175c16ba7`](https://github.com/jmaorr/Browsa/commit/a4de8f2cf9d98a0d633c05bb6762105175c16ba7), adapted in Ark commit [`84207079`](../../commit/84207079): Ark already matches its nested-folder layout, ordered pins, safe traversal, and Arc import behavior. Ark now also imports Arc’s `isExpanded` flag into its native collapsed-folder state; the existing SnapshotTour fixture includes expanded and collapsed folders and asserts both. `ark:build-mac` passed. The built app’s import flow has not yet been manually rechecked. No new test file or simulator was used; the Arc import row stays Yes.

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

Reviewed Search `8b5ca1bdfcf021cc6158255dcb6cb0bc37d0d9e3`: Search reads icons declared by the current document and rejects a probe result if navigation changed first. Ark currently uses its host favicon provider and does not probe page-declared icons, so the race guard has no Ark probe to protect. A document-favicon feature would need a separate design and privacy review.

Reviewed Search `663cb237b48c0c423d5727cd9d5567cf002f6ec6`: it keeps Search's hidden auto-hide column visible while dragging its edge. Ark's sidebar floats on edge hover and is resizable only while docked; it has no matching hidden-column drag path, so no code was ported.

Reviewed Search `ceaec9b8c7544df19745579d343551ce8cb51fef`: its bench sends page CSS coordinates as native mouse events, so page zoom must scale the point. Ark's `page_click` resolves a DOM reference or selector and invokes `.click()` directly; it has no coordinate click path to fix.

Adapted Search `c17c0fa9345c4ce9f27d7e50eb6b78156cc4bc49` to Ark's nested pinned folders: a Mac folder context menu now offers **Open All Tabs in Folder**. It opens pinned pages from the folder and nested folders in sidebar order, behind the current tab, while leaving live-feed articles out. The Mac build passed. Runtime checks for order, selected-tab stability, and nested folders remain open; mobile still has no action.

Partially adapted Search `71992504d6e5ce9ab72032ce53c8b559b4aeb202`: Ark's shortcut settings and Profiles menu now expose customizable Next/Previous Profile actions when at least two website profiles are assigned to regular Spaces. Cycling follows the configured profile order and selects the first Space assigned to the target. Profile 1–9 is omitted because Ark already uses number shortcuts for tabs and Spaces, and its profiles are Space-scoped. The Mac build passed; menu and keyboard runtime checks remain open.

Reviewed Search `2b44d44be86cf0181d8e7368216aba1d49a2a7de`: Ark already opens a live-folder article as a Today tab in the Space that owns the folder. Ark pinned folders do not form tab groups, so the Search-specific `loose` placement behavior has no separate equivalent to port.

Adapted Search `cc1cae9a316f2b3fe6322ca682285b4c34bbf49f`: WebKit's system PiP return callback now selects the PiP page's Ark tab (switching to its owning Space when needed), brings that window forward, and activates Ark. This uses a private WebKit delegate selector, following the upstream behavior. Mac build passed; runtime verification needs an actual system PiP session returned from another Space.

Adapted Search `1c84b99d7127c7c26065c66653cac309f914ebe9`: automatic PiP no longer starts merely because Ark loses focus while its window remains visible. Ark watches the active window's occlusion state on the same screen and starts PiP only after it goes out of sight; a window visible on another display stays inline. Returning to Ark removes the watcher. Mac build passed; display, occlusion, and activation runtime checks remain open.

Adapted Search `f9d7a747a9802f21e174a4221a8e5c287169530f` in Ark's extension compatibility prelude: `i18n.getMessage("")` now answers `""` while other names and substitutions still call through to WebKit. This addresses a WebKit/Chrome API difference that can abort extension popup initialization. JavaScript syntax and Mac build passed; a uBlock popup runtime check remains open.

### SpikeArk pin-reorder retry — Mac

The isolated SpikeArk app was relaunched and its control API responded with mock state. Its window still reported `isKey: false`; synthetic drags across the two pinned rows did not change their order. This is inconclusive input evidence and does not change the Mac comparison rating. The actual reorder interaction still needs a pointer-driven check in the visible app. No simulator was started; installed Ark data was not accessed.

### Search Peek screen sharing — Mac

Adapted Search `39ab8c5db4af5d2c37838ae22ec121c9ccc352bd`: WebKit display-capture requests now use Ark's existing per-request `.screen` consent sheet. A visible Glance can answer without pretending to be the selected tab; navigating, closing, replacing, or promoting it cancels any outstanding request. The Mac build passed. A live `getDisplayMedia` request and the system's screen/window selection behavior remain unverified, so Peek remains Partial.

### Browsa extension compatibility APIs — Mac

Partially adapted Browsa `5d9e2701eef9f5281d3d467cf1f06c2cad84baec` and its cited Search shims: Ark supplies `Symbol.dispose`/`Symbol.asyncDispose`, a cancellable `requestIdleCallback`, `storage.local/sync/session.onChanged` forwarded from WebKit's `storage.onChanged`, and explicit no-groups/unsupported-debugger APIs. Ark pin folders are not Chrome tab groups; DevTools Protocol access remains unsupported. The global `chrome`/`browser` accessor replacement was not copied because it can change extension global assignment semantics without a target-specific reproduction. `node --check`, a one-off in-memory API/event harness, and the existing 76-test BrowserKit suite passed. A real extension startup and storage-event runtime check remain open; Chrome extensions stays Partial.

### Browsa extension host-permission scope — Mac

Adapted the permission-scope portion of Browsa `1642b72ff49a17421b29ba3d56c70b5717a09b8c`: `WebKitExtensions` no longer grants `<all_urls>` to every extension. Broad host access is granted only when an extension's requested match patterns include `<all_urls>` or a wildcard host; otherwise Ark grants its declared patterns. This closes an overbroad WebKit permission grant without changing the extension UI. Browsa's redirect-checked, profile-aware `browsa.fetch` path was not copied because Ark does not expose that API. `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. A runtime check with narrow-host and all-host extensions remains open. The comparison's Chrome extensions rating stays Partial pending compatibility and permission-flow verification.

### Browsa certificate error handling — Mac

Adapted Browsa [`3deba26b9582546a43141f1f8f3d8155e3f2d188`](https://github.com/jmaorr/Browsa/commit/3deba26b9582546a43141f1f8f3d8155e3f2d188). The shared WebKit engine fingerprints the leaf certificate and exposes **Visit Anyway** only when it can identify the rejected certificate. Ark stores approval by normalized host and port plus that exact fingerprint; a replacement certificate remains blocked. Private-tab approvals are memory-only and clear with the private space. Settings lets users forget saved exceptions, and older settings decode with an empty exception list. The upstream's broad local-network bypass was not adopted; the explicit exception keeps the decision tied to a certificate the user saw.

Verification: `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. Xcode emitted existing actor-isolation and C-string deprecation warnings. No simulator was started and no persistent tests were added. A live self-signed certificate visit, changed-certificate rejection, private-tab cleanup, and Settings interaction remain unverified. This is supporting security behavior rather than a separate Arc feature row; the 42-row comparison remains unchanged. The upstream Browsa baseline remains `19eef7990aec8bd5491ef06ffc14928b7a73033f` until the complete incoming batch is reviewed.

### Sidebar sizing and site blocker shortcut — Mac

Partially adapted Browsa [`26afb7ba5950b260807d392df7a9d94f3d3c8770`](https://github.com/jmaorr/Browsa/commit/26afb7ba5950b260807d392df7a9d94f3d3c8770). Ark computes the minimum from its actual traffic-light frame, four 28-point sidebar controls, gaps, and horizontal insets; this avoids the upstream's mismatched five-control width. The split view and restored saved width both honor that minimum, and the top row is leading-aligned. The site menu now includes a checked **Block Ads and Trackers** action that toggles the current site's existing exception. The same upstream commit also improves dynamic Notes anchors and CSP-resistant styling; that larger, non-matrix change remains queued for a separate review.

Verification: `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. No simulator was launched and no persistent tests were added. Resizing to the minimum, checking that window controls stay in place, and using the site menu remain runtime-pending; no screenshot was captured. The 42-row comparison ratings were not changed on build evidence alone. Browsa baseline remains `19eef7990aec8bd5491ef06ffc14928b7a73033f`.

### Bulk pinned-folder moves — Mac

Adapted Search [`3e1efc6a14c69f4810018db34f83c03d417355e5`](https://github.com/driceroland/Search/commit/3e1efc6a14c69f4810018db34f83c03d417355e5) in Ark commit [`5508436b`](../../commit/5508436b). Command-click toggles pinned rows in a selection; Shift-click selects the visible range and Escape clears it. The context menu moves selected pins into an existing folder, removes them from a folder, or creates a folder around them. Bulk operations preserve the visible sidebar order and form one undoable change; ⌘Z is available until another key or pointer action. Live folders and Private spaces reject the operation.

Verification: `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. The existing `browser-kit:test-swift` target passed all 77 tests, including the added case in `PinFolderTests.swift` for order preservation and restoration of previous folder assignments. No simulator was started and no new test file was created. Command/Shift-click selection, context menus, Escape, and ⌘Z still need a live Ark UI check, so Pinned Tabs and Folders remains Partial.

### Site Information from pinned tabs — Mac

Adapted Search [`fa555191c98e47e44855dfe43e75aa0adcc6a804`](https://github.com/driceroland/Search/commit/fa555191c98e47e44855dfe43e75aa0adcc6a804) in Ark commit [`355adfdf`](../../commit/355adfdf). Ark adds a native **Site Information…** submenu to regular pinned-tab context menus, showing the host and exposing the existing per-site ad/tracker blocker plus combined camera/microphone permission choices. Search's card anchored below the pin was not adopted; this keeps Ark's existing sidebar structure while removing the selection step.

Verification: `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. No simulator was started and no new test file was created. Context-menu presentation, blocker toggling, and saved permission behavior still need a live UI check. The comparison rating remains unchanged pending that check.

### Search `origin/main` update — November 25, 2026

Reviewed the nine Search commits from `33ec7aea` through `659f74dc`. Adapted `c08ffb5a9d69f31bb45cd03a7111d7d4d14afbe2` in Ark commit [`19ca7bb7`](../../commit/19ca7bb7): the extension compatibility shim now exposes Chrome's frozen `identity.AccountStatus.SYNC` and `.ANY` constants without replacing WebKit's existing `getProfileUserInfo` method. `node --check`, an inline VM harness that verifies both constants and preservation of the existing API, and `pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. No test file or simulator was added; a real Fathom extension call remains open and Chrome extensions stays Partial.

The remaining eight commits were reviewed and documented in the [upstream inventory](ark-upstream-review.md): release/docs changes only; no equivalent deferred Arc-import cache in Ark; no Ark sized sign-in popup or Apple Passwords pairing; a test-only iCloud-group probe; Zen import deferred outside the 42-row matrix; and no matching profile-window join behavior. No other code or comparison rating changed.

### BrowserWindow background actor access — Mac

Ark commit [`ce2612ad`](../../commit/ce2612ad) now reads the Space surface, selected Space ID, and intro state in `BrowserWindow.body` before constructing the deferred `.background` builder. This targets the location in the previously captured SwiftUI main-executor crash stack and preserves the existing tint and animation inputs. The incremental Mac build passed on rerun; its first invocation emitted a Swift compile subprocess error with exit code 0, so the clean rerun is the build evidence. The existing BrowserKit suite also passed all 77 tests; it does not exercise this SwiftUI path. Runtime confirmation is pending: the Finder-open step was completed, but the command-line SnapshotTour retry still returns `kLSNoExecutableErr`. Do not treat this as a confirmed crash fix until a window renders and the affected interactions run.

### SnapshotTour launch retry — November 25, 2026

The Debug Ark bundle at `dist/ark/Build/Products/Debug/Ark.app` passed `codesign --verify --deep --strict` after a clean Nx rebuild. Launch Services still returns `kLSNoExecutableErr` (`-10827`) when opening that bundle, and returns the same error for a copy in `/private/tmp`. `lsregister -f` cannot scan the bundle from the workspace (`-10822`). Starting the Mach-O directly aborts in AppKit's `___RegisterApplication` before any Ark window appears, so that result does not verify the prior `BrowserWindow.background` crash. The user completed the Finder-open step, but a subsequent command-line SnapshotTour launch still returned `-10827`; no fresh runtime interaction was observable in this session. No installed app or user data was changed, and no simulator or new test file was used.

### Typed external app addresses — Mac

Adapted Search [`f2873fd0b51b8cf19c28e99dd848c81d20c18c46`](https://github.com/driceroland/Search/commit/f2873fd0b51b8cf19c28e99dd848c81d20c18c46) in Ark commit [`9f2c7587`](../../commit/9f2c7587). When the user explicitly types a custom `scheme://` address in Ark's ⌘L/⌘T field, Ark now hands it to a different installed app only if Launch Services resolves a handler and confirms the open request. Unknown schemes retain Ark's search fallback. WebKit/internal/script schemes are excluded, and web-page initiated handoffs continue to use Ark's existing consent flow. This is a Mac-specific integration; mobile behavior is unchanged.

Verification: `NX_ISOLATE_PLUGINS=false pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. Xcode emitted existing warnings; no simulator or test file was added. The built app still cannot be launched through Launch Services in this environment, so a real `vnc://` or `ssh://` handoff is unverified. The comparison's Address Bar placement remains Mac Sidebar; no matrix rating changed based on build evidence.

### Search routing and close-tab review — November 25, 2026

Search [`c502d18b67bd557c2a5267f723577e0acf93f427`](https://github.com/driceroland/Search/commit/c502d18b67bd557c2a5267f723577e0acf93f427) adds a default destination for external links that match no site rule. Ark already has this in shared Browser Settings as `externalLinksSpaceID`; Mac `Library.externalLinkDestination` applies source-app and site routes first, then that default, and iOS `BrowserState.openExternal` applies site routes then the same fallback. No code change was needed.

Search [`488b61c77de604b4c866d48e3ff2f3aa737ad028`](https://github.com/driceroland/Search/commit/488b61c77de604b4c866d48e3ff2f3aa737ad028) fixes ⌘W cycling between a blank tab and a just-parked pin. Ark's close path unloads the active pin and clears the window's selection; it does not create a blank tab that automatically wakes the pin. No equivalent loop was found, so no code change was made. The existing behavior of ⌘W with no selected tab was not runtime-checked.

These reviews do not change comparison ratings. Combined Browsa/Search incoming commits reviewed so far: 116/272 (42.6%); Mac matrix remains 21/42 Yes (50%).

### Chrome extension management API — Mac

Adapted Search [`61cc8e136b409227967c3749f0e250187836e66a`](https://github.com/driceroland/Search/commit/61cc8e136b409227967c3749f0e250187836e66a) in Ark commit [`bde81b9f`](../../commit/bde81b9f). Ark now provides `chrome.management.getSelf`, `get`, and `getAll` through its in-process WebKit extension delegate. `getAll` merges loaded extension contexts with Ark's Mac extension catalog so disabled installs are reported without loading them. `getAll` and reads of another extension require the caller's active `management` permission; optional declarations alone do not grant access. The bridge does not start external native hosts. The compatibility shim supports Promise and callback forms while keeping Chrome and Browser namespace runtimes separate.

Verification: `node --check` and an inline VM harness for Promise/callback calls, disabled catalog results, and separate namespace routing passed. `NX_ISOLATE_PLUGINS=false pnpm nx run ark:build-mac --skip-nx-cache --output-style=static`, the existing BrowserKit suite (77 tests), and strict code-signature verification passed. The suite does not directly cover the new management delegate. No test file or simulator was added. The authenticated Debug MCP endpoint responds to initialization and `notes_list`, but `tabs_list` timed out at both 5 and 15 seconds. The running process was launched before the latest rebuild. A graceful quit by bundle ID returned Launch Services error `-1728` without closing the process; runtime invocation against the rebuilt code remains unverified until the Debug app reloads. Chrome extensions remains Partial.

Search [`fad583956b551f38366193d86ec5407cb71a839a`](https://github.com/driceroland/Search/commit/fad583956b551f38366193d86ec5407cb71a839a) reserves a 40-point window-drag strip after the plus at the end of a full horizontal tab row. Ark uses the Arc-style vertical sidebar and has no horizontal tab row, so this geometry does not map to the Ark layout. No code or comparison-rating change.

### Search scrollbars — Mac

Reviewed Search [`0d1d80a2b7cb0772c40b9a6e162b21c1ebbab604`](https://github.com/driceroland/Search/commit/0d1d80a2b7cb0772c40b9a6e162b21c1ebbab604) and [`283cd2d4069302e034f5eb4dba73624546a7dfcf`](https://github.com/driceroland/Search/commit/283cd2d4069302e034f5eb4dba73624546a7dfcf). Ark's native Library and Settings scroll views use SwiftUI's default system indicators; the Arc-style vertical sidebar and command results hide them. The separate Search fade preference replaces `NSScroller.preferredScrollerStyle` for the whole process and has no direct Arc comparison row. Defer that override until the actual Arc scrollbar behavior is visually checked. No code or matrix rating changed.

### Existing tabs for incoming links — Mac

Adapted Search [`ed129504cdde3ee09da0967e12e48fb16d85ead8`](https://github.com/driceroland/Search/commit/ed129504cdde3ee09da0967e12e48fb16d85ead8) in Ark commit [`25e4dc3e`](../../commit/25e4dc3e). The new off-by-default General preference switches an incoming HTTP(S) link to an exact matching page in a regular window's current Space, or fronts its matching Link Preview, instead of making another copy. Explicit Space routes remain first. Private tabs are excluded. Search's behavior and fixture were reviewed; no test file was copied or added. The Mac build and strict signature check passed. Live external-app interaction remains unverified because the running Debug process predates this build and Launch Services still returns `kLSNoExecutableErr` when reopening the bundle.

### Search stuck WebKit process reaper — Bloat / performance

Reviewed Search [`b601de0e5ffd229d00c6bf857ba1f81fbdbf49dd`](https://github.com/driceroland/Search/commit/b601de0e5ffd229d00c6bf857ba1f81fbdbf49dd). Its reaper waits ten seconds after a view unloads, measures process CPU, confirms a WebKit WebContent executable, and checks that no other Search view shares the PID before sending SIGKILL. The report attributes the stuck loop to Accessibility tree updates and notes Safari is affected too.

Ark has no equivalent incident or reproduction. Do not port the private `_webProcessIdentifier` lookup and force-kill path without an Ark-specific reproduction and a way to prove the process has no other WebKit clients. No runtime performance claim or matrix rating changes; Ark's CPU/RAM baseline remains unmeasured.

### Search Find, themes, and sidebar review — Mac

Reviewed Search [`0c600c185cd253228ad58c445b184cd2f8129534`](https://github.com/driceroland/Search/commit/0c600c185cd253228ad58c445b184cd2f8129534). Its open-shadow-tree and soft-hyphen support is part of a replacement custom Find engine with mapped ranges, selection navigation, and native fallback when its DOM walk reaches the page budget. Ark delegates selection, navigation, and scrolling to WebKit; copying only Search's counting/highlight traversal would report matches Ark cannot navigate to. Keep Ark's current native behavior and track shadow-DOM/invisible-character matching as a limitation for a dedicated Find redesign. This is outside the 42 Arc rows; no code or matrix rating changed.

Reviewed Search [`2548fa504d33960d6a88751628dfdb5a8058e8b2`](https://github.com/driceroland/Search/commit/2548fa504d33960d6a88751628dfdb5a8058e8b2). It makes Search's New Tab Themes page fit narrow windows through a menu picker and wrapping grid. Ark's Theme picker row describes Space colors in the Arc-style sidebar, not new-tab backgrounds; Ark has no corresponding page or matching layout defect. No code or matrix rating changed.

Reviewed Search [`c2c6d9281f60531e7eb0109b59f0f5a86d9575e2`](https://github.com/driceroland/Search/commit/c2c6d9281f60531e7eb0109b59f0f5a86d9575e2), which adds a shared **Set Up Like Arc** preference preset, Undo snapshot, welcome-card offer, and post-import prompt. Ark already exposes Arc import in Welcome and Settings, archives Today tabs after 12 hours by default, and offers automatic PiP, pinned-link destination, and link-preview modifier as separate choices. The bundled preset is an onboarding improvement rather than a missing feature in the 42-row Arc matrix; defer it to a dedicated Ark migration UX decision. No code or matrix rating changed. Upstream review is now 115/272 commits (42.3%); Mac remains 21/42 rows rated Yes (50%).

Reviewed Search [`f647b3160561512f22970bf101bcbd77f34cf00d`](https://github.com/driceroland/Search/commit/f647b3160561512f22970bf101bcbd77f34cf00d). Search updates its custom Mac swipe watcher so root `overscroll-behavior-x: none/contain` claims a sideways gesture before navigation. Ark uses WebKit's native back/forward gesture recognizer (`allowsBackForwardNavigationGestures = true`) on Mac and iOS and has no comparable watcher to patch; copying the script would not control WebKit's recognizer. No source or Arc-row change. Test a Sheets page on Mac when SpikeArk launches and include it in the later iPhone/iPad/Duo pass, one simulator at a time. Upstream review is now 116/272 commits (42.6%); the Mac matrix remains 21/42 rows rated Yes (50%).

Reviewed Search [`270f82f7de7774354903d230eee6ce4a558f3b58`](https://github.com/driceroland/Search/commit/270f82f7de7774354903d230eee6ce4a558f3b58). Search prevents its stage marker from treating a folded, overlaying tab strip as the page's split-drop target. Ark's sidebar drag resolver only produces tab-order, folder, favourite, and Space targets; it has no drag-to-split target. The reported drop cannot occur in Ark's current drag flow; no code or matrix change.

Adapted Search [`4548b37320f77d2775487888b5533ad95da37fd5`](https://github.com/driceroland/Search/commit/4548b37320f77d2775487888b5533ad95da37fd5) in Ark commit [`d29ee99c`](../../commit/d29ee99c): a tab row's title now takes the remaining width directly, avoiding the implicit HStack gap before a trailing Spacer while retaining Ark's call/note badges and close control. `NX_ISOLATE_PLUGINS=false pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. The first sandbox attempt could not access existing SwiftPM/Clang caches; the authorized retry completed successfully. The running Debug app has not reloaded, so visual truncation against Arc remains unverified. No simulator or new test file was used; the Pinned tabs and folders rating is unchanged.

Reviewed Search [`b8cb0c20d3f14e046ee2cdeee6721009fea3168e`](https://github.com/driceroland/Search/commit/b8cb0c20d3f14e046ee2cdeee6721009fea3168e). Ark's footer has Downloads, the Space switcher, and a general menu, not Search's Bookmarks door. The Search fix changes hover ink and backgrounds across its custom greys palette; adopting it without checking Arc's corresponding footer treatment could move Ark away from its visual target. Defer until Arc hover states are compared; no code or matrix rating changed.

Reviewed Search [`ee719dca2604ba2bccfc7e18151e50bdad0c8ce5`](https://github.com/driceroland/Search/commit/ee719dca2604ba2bccfc7e18151e50bdad0c8ce5): Ark's preset and hue bindings update `SpacePalette.surface` in the live browser window while the Space theme editor remains open. The window itself previews the selected color and shade, unlike Search's separate mismatched preview card. No code or rating change.

Adapted Search [`60248b85d41ab55b19c057fd68b47e56f6ad9949`](https://github.com/driceroland/Search/commit/60248b85d41ab55b19c057fd68b47e56f6ad9949) in Ark commit [`8948a8fa`](../../commit/8948a8fa). The AppKit reopen delegate now bases Dock behavior on registered Ark browser windows, so an auxiliary Mini Player or Link Preview cannot make the Dock click appear satisfied while every browser window is minimized or out of sight. It restores an existing browser window or requests a new WindowGroup window when none remains. Ark browser windows are also included in the Window menu. The Mac build passed; live Dock and Window-menu checks remain open. This behavior is outside the 42 comparison rows.

Reviewed Search [`241966e70c3072a8eaac0360429acfae6bf9f404`](https://github.com/driceroland/Search/commit/241966e70c3072a8eaac0360429acfae6bf9f404): Ark has one extension-action menu in the address pill, with no duplicated hidden puzzle-button row at the sidebar footer. Search's shared-open-state bug has no corresponding Ark path; no code or matrix change.

Reviewed Search [`cfeed018cfbea714abd831b58571b8c5c0340fa5`](https://github.com/driceroland/Search/commit/cfeed018cfbea714abd831b58571b8c5c0340fa5): Ark presents extension popups through WebKit's native `WKWebExtension.Action.popupPopover` and does not persist popup dimensions. Search's custom size cache and uninstall cleanup have no Ark counterpart; no code or matrix change.

### Search Find and theme layout review — Mac

Reviewed Search [`0c600c185cd253228ad58c445b184cd2f8129534`](https://github.com/driceroland/Search/commit/0c600c185cd253228ad58c445b184cd2f8129534). Its open-shadow-tree and soft-hyphen support is part of a replacement custom Find engine with mapped ranges, selection navigation, and native fallback when its DOM walk reaches the page budget. Ark delegates selection, navigation, and scrolling to WebKit; copying only Search's counting/highlight traversal would report matches Ark cannot navigate to. Keep Ark's current native behavior and track shadow-DOM/invisible-character matching as a limitation for a dedicated Find redesign. This is outside the 42 Arc rows; no code or matrix rating changed.

Reviewed Search [`2548fa504d33960d6a88751628dfdb5a8058e8b2`](https://github.com/driceroland/Search/commit/2548fa504d33960d6a88751628dfdb5a8058e8b2). It makes Search's New Tab Themes page fit narrow windows through a menu picker and wrapping grid. Ark's Theme picker row describes Space colors in the Arc-style sidebar, not new-tab backgrounds; Ark has no corresponding page or matching layout defect. No code or matrix rating changed.

### Extension popup `_blank` links — November 25, 2026

Adapted Search [`20942bc01fe5a96f63b3490e5f9cf643f133b996`](https://github.com/driceroland/Search/commit/20942bc01fe5a96f63b3490e5f9cf643f133b996) in `packages-apple/browser-kit/Sources/WebKitEngine/WebKitExtensions.swift`. WebKit exposes the native action popup’s `popupWebView`; Ark now intercepts only navigations without a target frame, opens allowed links through its existing extension-tab host in the focused window, and closes the popup. `javascript:` and `file:` URLs are rejected. `pnpm nx run ark:build-mac` passed after the sandbox retry required for SwiftPM/Clang cache access. No test file was added. Runtime confirmation with Raindrop remains open, so Chrome extensions stays Partial and the upstream baseline is unchanged.

### Mac feature-tour crash follow-up — November 25, 2026

The existing `SnapshotTour` ran from the rebuilt Debug bundle against the temporary loopback fixture. It verified named Website Profile cookie isolation and clearing, then verified Space assignment, same-profile tab transfer, and cross-profile reset. It wrote `sidebar-and-tabs.png` and `space-profiles.png` under `/private/tmp/ark-feature-run`. The app then terminated with `EXC_BAD_ACCESS` / `SIGSEGV` at a null address while SwiftUI evaluated `SpaceEditor.body` (`apps/ark/Mac/Sources/Views/SettingsView.swift:345`); the stack enters `swift_task_isMainExecutorImpl` from a closure in that body. The crash report is `/Users/vezham-lab/Library/Logs/DiagnosticReports/Ark-2026-11-25-125243.ips`. This is distinct from the earlier `BrowserWindow.background` crash and needs its own diagnosis before the tour can validate later features. The remaining tour, interaction screenshots, and frame/CPU measurements were not completed; no performance improvement is claimed. No simulator or new test file was used. Upstream review is 126/272 (46.3%); Mac remains 21/42 rows rated Yes (50%).

The next run isolated that temporary Spaces settings preview after capture, retaining its AppKit window but detaching its live SwiftUI tree before the fixture deletes the temporary Spaces. The Mac build passed. The tour then terminated with the same `EXC_BAD_ACCESS` / `SIGSEGV` signature while evaluating the `.alert` builder in `apps/ark/Mac/Sources/Views/BrowserWindow.swift:69`; the stack again passes through `swift_task_isMainExecutorImpl`, now from `closure #13 in BrowserWindow.body.getter`. The report is `/Users/vezham-lab/Library/Logs/DiagnosticReports/Ark-2026-11-25-130212.ips`. The tour-only detachment avoids the prior `SpaceEditor` failure but does not resolve this separate SwiftUI executor crash. Later feature checks and performance measurements remain blocked; no simulator or test file was added.

### Main-executor crash diagnosis — November 25, 2026

Follow-up changes were guided by successive symbolicated app frames: the root pin-folder `.alert` became a native window sheet; the derived site-style sheet `Binding(get:set:)` became direct observable presentation state; `Browser.currentTab` and `visibleTabIDs` no longer pass actor-isolated predicates/closures through `Sequence.first` and `Optional.map`; `CookieBannerHandler` now uses the same nonisolated WebKit callback entry pattern as `PageActivity.Handler`, followed by an explicit `MainActor` handoff; the temporary Spaces preview is detached after capture so the tour does not mutate its live view while removing fixture Spaces. Mac builds passed after these changes.

The latest existing-tour run still terminated before later feature checks. Report `/Users/vezham-lab/Library/Logs/DiagnosticReports/Ark-2026-11-25-133338.ips` is `EXC_BAD_ACCESS` / `SIGBUS` on macOS 27.2 (26B123), main thread, in `SerialExecutor._isSameExecutor` → `swift_task_isMainExecutorImpl` → `closure #1 in Sidebar.body.getter` at `apps/ark/Mac/Sources/Views/Sidebar.swift:20`. Previous reports from the same runs landed in `SpaceEditor.body`, `BrowserWindow` presentation builders, `Browser.currentTab`, `CookieBannerHandler`, and `MarginPanel.body`. The crash location has moved across unrelated SwiftUI builders and the WebKit callback; that suggests a broader SwiftUI/concurrency runtime interaction but does not prove an OS bug or rule out an Ark isolation error. Keep all affected runtime ratings unchanged until the existing tour completes. No simulator or new test file was used, and no performance improvement is claimed.

### Mac feature tour recovery and pinned-link verification — November 25, 2026

LLDB captured the failure in the focused pinned-link tour: `SnapshotTour` passed a plain `String` to `JSONSerialization.data(withJSONObject:)`. Foundation raised `NSInvalidArgumentException` because top-level values are not permitted by default, and the exception escaped the async tour. Replaced both URL-string encodings in the existing `SnapshotTour` with `JSONEncoder`; no test file was added. The Sidebar top-row now also resolves browser-backed values and button views before its deferred `HStack` builder. A rebuilt Mac Debug app completed the focused local fixture run with exit status 0: a link from a pinned page opened in Today while preserving the source pin; a cross-host pinned-page link opened in Glance while preserving the source; and closing the active pinned tab returned to the previous tab. The earlier main-executor crash did not recur in this completed path, but other runtime paths remain to be checked before considering that class of issue closed.

The full existing feature tour then completed with exit status 0 against `/private/tmp/ark-feature-fixture` at `127.0.0.1:47931`; its report and 30 Mac screenshots are in `/private/tmp/ark-feature-run-18`. It recorded successful named-profile cookie isolation/clearing, Space profile assignment and tab transfer, pinned-link Today/Glance handling, last-used-tab command, horizontal and stacked split layouts with resize/focus/close behavior, full-page and selected-region capture, dormant-tab unloading and keyboard selection, Link Preview promotion/cleanup, pin-folder drag/reparent/collapse, Arc folder import order, Boost CSS/font persistence and host/private isolation, Easels page/note/image capture, and a sync-settings folder fixture reaching Synced. These are fixture-level Mac checks; the latest report did not record a successful page-element capture. It also reported Live Folder discovery failure because the fixture currently returns `North Shore Survey` and `Coastal Map` while the tour expects `Atlas` and `Field Notes`; earlier reports `/private/tmp/ark-mac-feature-audit-2/report.txt` and `/private/tmp/ark-mac-feature-audit-3/report.txt` recorded the feed refresh/cache/import-resume checks as passing. The export/import tour opened the save/open dialogs but did not finish a file round-trip. Do not mark those gaps closed from this run.

### Feature-tour fixture repair — November 25, 2026

Updated the existing temporary feed at `/private/tmp/ark-feature-fixture/field-feed.xml` so its article titles match the existing tour expectations (`Atlas`, `Field Notes`). This addresses the known fixture mismatch only. The Debug app still aborts before the full tour starts, so Live Folder refresh behavior and page-element capture remain unverified; no matrix rating changed.

`NX_SOCKET_DIR=/private/tmp/nx-ark-sockets pnpm nx run ark:build-mac --output-style=static` passed after the JSON fix. No simulator or new test file was used. The Mac matrix remains 21/42 rows rated Yes (50%) and incoming review remains 126/272 unique commits (46.3%); neither percentage changed from this verification. Page-element capture reliability, the stale Live Folder fixture, export/import file round-trip, remaining focused Mac rows, and runtime performance baselines are still open.

Reviewed Search [`c0bb3bfcabc882002b420accdef49b572de28513`](https://github.com/driceroland/Search/commit/c0bb3bfcabc882002b420accdef49b572de28513): a punctuation correction in the Search changelog only. It adds no implementation to compare or port. Upstream review is now 127/272 unique commits (46.7%); the Mac feature matrix remains 21/42 rows rated Yes (50%).

Reviewed Search [`a2c0de4c98d08217b3749da8f1707bf76311df40`](https://github.com/driceroland/Search/commit/a2c0de4c98d08217b3749da8f1707bf76311df40). It adds per-device open-tab lists and group menus to Search's iCloud/CloudKit sync. Ark's current transport is a user-chosen shared folder and has no Browser tab-group model; its existing sync projection deliberately keeps Today tabs local. The CloudKit implementation is not a direct port, but the comparison confirms a real gap: an Ark-specific per-device tab index, grouped by Space, could use the existing cross-platform file transport. The Sync row remains Partial while that feature is open. Upstream review is now 128/272 unique commits (47.1%); Mac matrix remains 21/42 rows rated Yes (50%).

Rechecked Browsa [`03d0f82dc0393537e5a9f0cca96005bb6f06df2a`](https://github.com/jmaorr/Browsa/commit/03d0f82dc0393537e5a9f0cca96005bb6f06df2a) against `Space.refreshLiveFolder` and its callers. Ark already keeps refresh timestamps in an observation-ignored cache, returns false for unchanged feeds, and saves the library only when a refresh changes feed state. The upstream performance fix is already covered; no code change or extra measurement is warranted from this source comparison. Earlier Mac fixtures verified no-op/cache behavior; the November 25 tour's feed mismatch is in the temporary fixture content, not evidence against the implementation.

### Mac idle process baseline — November 25, 2026

Recorded five read-only `ps` samples at two-second intervals for the open Debug app at `dist/ark/Build/Products/Debug/Ark.app` and its attached WebKit helpers. Ark reported 0.0% CPU and 15.1–15.5 MiB RSS; WebKit WebContent reported 0.0–0.4% CPU and 7.9–8.0 MiB RSS; WebKit Networking reported 0.0% CPU and 2.3–2.5 MiB RSS. The sample was an idle process baseline only: no controlled navigation, tab-count, extension, or capture workload was measured, so it does not establish overall browser performance. No Ark-specific regression is indicated by this sample, and no code change is justified. Follow-up work should measure the same process set under a repeatable multi-tab workload before comparing or optimizing.

### Page-element capture tour correction — November 25, 2026

The full tour's `element fixture did not copy a PNG` result came from its synthetic click targeting the fixture's first `h2`, which sits below the visible WebKit viewport in the long Atlas page. The picker accepts viewport coordinates and correctly ignored that out-of-bounds click; the captured tour screenshot confirms the overlay remained active without a click selection. Updated the existing `SnapshotTour` to target the visible `h1`; no new test file was added. `NX_ISOLATE_PLUGINS=false pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. A fresh runtime pass is still required: opening the rebuilt Debug bundle through Launch Services returned `kLSNoExecutableErr` (`-10827`), while the already-running process was started before this build. The prior Mac capture evidence remains valid, but this tour increment is build-verified only.

### Optional per-device open tabs in folder sync — November 25, 2026

Adapted the applicable behavior from Search [`a2c0de4c98d08217b3749da8f1707bf76311df40`](https://github.com/driceroland/Search/commit/a2c0de4c98d08217b3749da8f1707bf76311df40) without adopting its CloudKit store or tab-group model. Ark now offers an opt-in in Mac and iOS Sync settings. Consent is scoped to the selected folder and resets when a sync destination is selected. Each device publishes a stable `deviceTabs:<device-id>` record through the existing folder transport, grouping safe HTTP(S) Today links by shared Space. The record carries titles and URLs only; Private tabs, history, pinned state and WebKit session data remain excluded. Choosing a listed page opens it in the matching local Space (or the current Space if that ID is absent). Disabling sharing publishes an empty record at the next successful sync; peers remove it on their next sync. Switching folders before withdrawal leaves the old record visible until its 30-day UI expiry, now disclosed in Sync settings. Peer tab-index records are treated as unknown to the local writer, so normal merge/deletion logic cannot tombstone another device's list. Tab metadata refreshes on content changes or every 15 minutes, and records older than 30 days are hidden.

Verification: `pnpm nx run ark:build-mac` and `pnpm nx run ark:build-ios` passed; the existing BrowserKit suite passed all 77 tests. No test files were added and no simulator was started. Two-device folder propagation, toggle removal after a successful sync, and opening a remote page on-device remain runtime checks. The Sync comparison stays Partial.

### Folded-sidebar page-card reference review — November 25, 2026

Reviewed Search [`df8f3a4c9fa3a1ebf5f67fa20bdf4df8be62e3bf`](https://github.com/driceroland/Search/commit/df8f3a4c9fa3a1ebf5f67fa20bdf4df8be62e3bf), which coordinates an edge-to-edge square page card with Search's SwiftUI sidebar-fold animation and pixel-snapped offsets. Ark's corresponding path is structurally different: `NSSplitView` collapses the sidebar while `PageHost` holds the WebKit size through live resize; `PageArea` stays inset with rounded corners. No code was copied. The comparison now records this as a Sidebar visual-parity question, not a missing capability. Before changing the transition, capture/compare Arc and Ark in the folded state and during the animation; current app-launch/screenshot evidence does not establish that visual match.

Also reviewed Search [`d8aaba27086332b477b71553cb9e725959c2d1e3`](https://github.com/driceroland/Search/commit/d8aaba27086332b477b71553cb9e725959c2d1e3). Its `LightsRide` keeps title-bar buttons aligned with its custom SwiftUI sidebar animation. Ark creates AppKit window-control buttons inside `WindowButtonsView` in the sidebar itself, so they travel with the collapsing/peeking column; the floating sidebar is already inset and rounded. No code was copied. Compare the live motion with Arc before treating the row's visual parity as closed.

The related Search commits [`c48dd6aacbde1cee34b80943db425b522a96d540`](https://github.com/driceroland/Search/commit/c48dd6aacbde1cee34b80943db425b522a96d540) and [`33ec7aea1823c81c77a2be196e442dd54e36efa7`](https://github.com/driceroland/Search/commit/33ec7aea1823c81c77a2be196e442dd54e36efa7) were also reviewed. Ark's floating sidebar already uses a rounded inset card with an extended hit zone; its extension side panel uses a separate inset `NSSplitView` column. No code was copied. Compare the panel's folded state and the edge hit behavior against Arc before closing the Sidebar visual-parity item.

### Web-app preview history lookup — November 25, 2026

The Mac favourite hover preview requested five recent pages by filtering and sorting every matching history record on each hover. `HistoryStore.recentVisits` now maintains only the newest requested records during its scan for limits up to 32, while retaining the full sort for larger result sets. A release benchmark used a temporary `/private/tmp` harness and 100,000 imported history records (50,000 for `notion.so`), warmed the query four times, then recorded 21 samples. Median fell from 215.424 ms to 49.619 ms (77.0% lower); p95 fell from 219.184 ms to 61.582 ms (71.9% lower). The baseline checked the result count and newest URL; the optimized run additionally asserted all five ordered URLs against the synthetic dataset. This supports the lookup optimization, not the hover UI's runtime parity; that check remains open. No repository test file was added.

Follow-up in the same Mac sidebar path: unsupported favorite tiles now skip app-preview task creation, and a tile disappearing cancels any pending lookup and closes its preview. `NX_ISOLATE_PLUGINS=false pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed on November 25, 2026. This removes unnecessary delayed work for ordinary favorites, but no hover interaction or end-to-end performance measurement was made; the Mac Previews row stays Partial.


### Sync fixture runtime verification — November 25, 2026

Launching the rebuilt Debug executable directly with `ARK_SNAPSHOT=/private/tmp/ark-sync-runtime-preview-2` and `ARK_SETTINGS_PREVIEW_ONLY=1` completed with exit status 0. Its report records: `shared-folder tab index arrived, survived another device sync, and cleared on opt-out: true`. This verifies two coordinators exchanging records through one local folder in the Mac process, including peer-record retention and withdrawal. It does not establish remote file-provider propagation or physical-device convergence. The existing SnapshotTour now hosts the real `SettingsView` in a retained window for captures; the resulting Sync image shows Synced status, sharing off after withdrawal, and the empty remote-tabs state. This is a settings presentation fixture, not a click-through test of the Settings command, toggle, or opening a remote page. Physical-device convergence and those UI interactions remain open. Direct executable launch provides a working path for further isolated Mac fixtures despite the earlier Launch Services failure.

### Dynamic extension side-panel page — November 25, 2026

Adapted Browsa `803b3ddf481bb87678f2eead8b81db85233ddcfa`: Ark's `chrome.sidePanel.setOptions({path, enabled})` bridge resolves the path against that extension's base URL, stores the selected URL/enabled state, and sends it through `EngineExtensionHost` when opening the panel. `getOptions` returns the selected extension-wide values, and a disabled panel does not open. The Mac `Workbench` observes the selected URL and `ExtensionPanelView` reloads its existing WebKit page when it changes. BrowserKit built and its existing 77-test suite passed on November 25, 2026. This covers extensions that already register a manifest panel; dynamic registration for extensions with no declared panel, per-tab Chrome semantics, and live extension runtime behavior remain open. No test file or simulator was added.

Adapted Browsa `a86a19ad884c247eb677e3af1396b233fed678e3`: `runtime.getContexts` now reports Ark's tracked open extension side panel pages as `SIDE_PANEL` alongside offscreen documents and applies the requested context-type and document-URL filters. The existing 77-test BrowserKit suite and Mac build passed. Ark still does not report other Chrome context types, and live extension runtime behavior remains unverified.

### Side-panel disabled placeholder and relay guard — November 25, 2026

Reviewed Browsa [`bd783a37d28e4ae43f2d88d56997b4b1dc2bb0b4`](https://github.com/jmaorr/Browsa/commit/bd783a37d28e4ae43f2d88d56997b4b1dc2bb0b4). Ark now ignores a manifest side-panel placeholder whose path contains “disabled”, so an extension that has switched its panel off is not shown as having a usable panel. Browsa's `sendMessage` try/catch protects a BroadcastChannel relay that Ark does not implement; no matching relay code was copied. The Ark adjustment is staged and not yet committed. The existing BrowserKit 77-test suite and Ark Mac build passed. The Chrome extensions row remains Partial because live extension behavior and broader API coverage are still unverified.

### Extension action popup replacement review — November 25, 2026

Reviewed Browsa [`02b0b9dbdbd4273f96800c80a79e454b337e6db5`](https://github.com/jmaorr/Browsa/commit/02b0b9dbdbd4273f96800c80a79e454b337e6db5) and [`e9e8c1c20cea5f59b4c733f1445e4d6922fef6fe`](https://github.com/jmaorr/Browsa/commit/e9e8c1c20cea5f59b4c733f1445e4d6922fef6fe). They replace WebKit's native extension-action popup with a custom `WKWebView` from the extension configuration, register it as a synthetic tab for message routing, and size it from page JavaScript. Ark currently delegates popup presentation and lifecycle to WebKit. This is a plausible compatibility gap, but Ark has not reproduced the reported popup/background message failure with a real extension; replacing native lifecycle without that evidence risks regressions. No code was copied. The Chrome extensions row stays Partial pending an extension-driven runtime check.

### Split View control-panel reference review — November 25, 2026

Reviewed Browsa [`9d52b8b4ff8f7d70abcad1e34f53abf9495b24d2`](https://github.com/jmaorr/Browsa/commit/9d52b8b4ff8f7d70abcad1e34f53abf9495b24d2). It changes Browsa's pane overlay into a glass action panel and delays its close so it animates back into a pane pill. Ark has no matching overlay state; each pane uses a compact title row with a Split View menu. No code was copied. Arc comparison is needed before adopting this visual treatment; no Split View rating change.

### Split View panel control styling review — November 25, 2026

Reviewed Browsa [`c7d5636d670f7063b799b4119b73c7cdc152676d`](https://github.com/jmaorr/Browsa/commit/c7d5636d670f7063b799b4119b73c7cdc152676d). This follow-up condenses labels and actions inside Browsa's glass panel and softens pane outlines. Ark has no equivalent floating panel, and the change adds no Split View capability. No code or rating change; compare the running Arc and Ark interfaces before changing the pane controls.

### Split View panel button fill review — November 25, 2026

Reviewed Browsa [`35266c54957217104702ce15a581716f9272fa2e`](https://github.com/jmaorr/Browsa/commit/35266c54957217104702ce15a581716f9272fa2e). It adds a custom solid button style for controls inside Browsa's floating Split View panel. Ark has no equivalent panel, so this styling has no independent target. No code or rating change.

### Safari user-agent version shared with extension contexts — November 25, 2026

Adapted Browsa [`083a2354b92c24d684d7301fe9834b1dc252e296`](https://github.com/jmaorr/Browsa/commit/083a2354b92c24d684d7301fe9834b1dc252e296). Ark now reads Safari's installed `CFBundleShortVersionString` for its Safari-compatible UA token and applies that same token to extension WebKit contexts as well as tabs. The host Safari bundle reports `27.2`; when its bundle cannot be read, Ark preserves the prior OS-version fallback. Existing BrowserKit tests passed (77 tests, 14 suites), and `ark:build-mac` passed. Live extension background behavior remains unverified; no simulator or new test file was added.

### Safari autoplay policy on Mac — November 25, 2026

Adapted Browsa [`3cade1db310ffb9fc3501cc50f08fc54577c4ed7`](https://github.com/jmaorr/Browsa/commit/3cade1db310ffb9fc3501cc50f08fc54577c4ed7). Ark's Mac WebKit configuration now requires user action for audio but not muted video, matching Safari behavior and allowing silent previews/loops. The iOS WebView pool keeps its separate all-media gesture requirement. Existing BrowserKit tests passed (77 tests, 14 suites), and `ark:build-mac` passed. Real-site autoplay and PiP behavior remain runtime checks; no simulator or new test file was added.

### Isolated call-audio page bridge — November 25, 2026

Partially adapted Browsa [`4a8d7f71ebb1953335d3ac71979f85d257b7f8c1`](https://github.com/jmaorr/Browsa/commit/4a8d7f71ebb1953335d3ac71979f85d257b7f8c1). Ark now exposes only `arkCallAudio` through a named WebKit content world and a page-message relay, removing the page-world `window.webkit.messageHandlers.arkCallAudio` reference. Ark has no website Notification shim matching Browsa's second handler, so that part was not copied. Existing BrowserKit tests passed (77 tests, 14 suites); Mac and iOS Nx builds passed. The builds emitted pre-existing compiler diagnostics about build commands returning exit code 0 without further output and existing Swift warnings; Nx reported both targets successful. Site-visible `window.webkit` absence and live call-audio behavior remain to verify. No simulator or new test file was added.

### Native Global Privacy Control request preference — November 25, 2026

Partially adapted Browsa [`29dacd0c3ff8060f2ab46f77bb8bedf82b054e62`](https://github.com/jmaorr/Browsa/commit/29dacd0c3ff8060f2ab46f77bb8bedf82b054e62) and compared Search's `Privacy.swift`. Ark's existing GPC setting now sets WebKit's native per-navigation preference when that selector is available; the page-property script remains the fallback for older WebKit. The existing BrowserKit suite passed (77 tests, 14 suites), and `ark:build-mac` passed. Actual `Sec-GPC` header delivery remains a runtime check. Click-ID cleaning was not adopted because Search's safer version preserves signed URLs and has a separate user setting; Ark currently has no matching setting. Backspace navigation is outside the 42 Arc rows. No simulator or new test file was added.

### Website-profile name editor reference review — November 25, 2026

Reviewed Browsa [`db67f0ae618a007487ac3a0b23adb282f1f86951`](https://github.com/jmaorr/Browsa/commit/db67f0ae618a007487ac3a0b23adb282f1f86951) and [`2bf346e3b270bc77e2916a1fe447fd93edf084d5`](https://github.com/jmaorr/Browsa/commit/2bf346e3b270bc77e2916a1fe447fd93edf084d5). Browsa edits profile names inline in a settings list and selects a new generated name on creation. Ark creates/renames profiles from a SwiftUI alert inside the Space editor; its field starts blank and Return activates Save/Create, closing the alert. The inline field behavior has no direct Ark counterpart, so no code was copied. Profile create/rename runtime interaction remains unverified; no matrix rating changed.

### Credentialed extension fetch review — November 25, 2026

Reviewed Browsa [`d987fd28221c5dd4ed483bde40f51a9a933a71ce`](https://github.com/jmaorr/Browsa/commit/d987fd28221c5dd4ed483bde40f51a9a933a71ce). It adds permission-scoped access to Browsa's proprietary `browsa.fetch` API, which sends an extension's site cookies. Ark does not expose this API or another native cookie-fetch bridge; standard extension networking is handled by WebKit. No Ark change or Arc matrix rating change.

### 1Password native-host release runbook review — November 25, 2026

Reviewed Browsa [`155cf7720d950998238b0527a53eb74e59041b85`](https://github.com/jmaorr/Browsa/commit/155cf7720d950998238b0527a53eb74e59041b85). This documents onboarding and release requirements for Browsa's 1Password native-host unlock integration. Ark has no matching native-host launch flow, so no product or release change applies.

### Always Open in app choice — November 25, 2026

Adapted Browsa [`85da646a13f2d262d451c518ddbd5608eb9c408c`](https://github.com/jmaorr/Browsa/commit/85da646a13f2d262d451c518ddbd5608eb9c408c). Ark's Mac Open in App prompt now offers Always Open, Open Once, and Not Now. Only Always Open is saved per site and URI scheme; legacy saved denials are cleared and asked again. Repeated automatic app-link prompts are suppressed for the tab, while explicit link clicks can ask again. Existing Privacy site-permission controls can reset saved choices. `ark:build-mac` passed; live prompt behavior remains unverified. No simulator or test file was added.

### GitHub-backed Live Folder review — November 25, 2026

Reviewed Browsa [`d60f7ee081ff4eb6b16ec7666de22ad5f68b696c`](https://github.com/jmaorr/Browsa/commit/d60f7ee081ff4eb6b16ec7666de22ad5f68b696c) against Ark's `LiveFolderFeed`/`PinFolder` and Search's pinned `LiveFolders.swift`. Ark already supports RSS/Atom discovery, cookie- and credential-free fetches, capped responses, and cached no-op refreshes. Browsa adds GitHub search sources with token-backed presets and per-item unread/dismissal behavior; Search's pinned implementation remains feed-based. This is a broader capability rather than a direct missing Arc-row implementation, and secure token storage plus cross-platform behavior need design. No source copied; Live Folders remains Partial.

### Frame-aware video PiP comparison — November 25, 2026

Reviewed Browsa [`39eb4ad4a6fce8e49497071e3c5d86e26ec85e51`](https://github.com/jmaorr/Browsa/commit/39eb4ad4a6fce8e49497071e3c5d86e26ec85e51). Ark already has manual system PiP and automatic PiP in its custom Mac player; its local-video fixture verifies entry, return, muted-video exclusion, and source-tab cleanup. Ark's manual selector scans videos in the top document, while Browsa tracks each frame and exposes controls for the selected media. Cross-origin iframe video selection remains a gap to verify and potentially implement. No Browsa controls/UI were copied; the Auto PiP rating remains Yes on Mac and unverified on iPhone, iPad, and Duo.

### Browsa Live Folder test compiler workaround — November 25, 2026

Reviewed Browsa [`f18053dc3d648296ea0a370bd55213b85e598f33`](https://github.com/jmaorr/Browsa/commit/f18053dc3d648296ea0a370bd55213b85e598f33). It spells out a closure in an `allSatisfy` assertion so Swift Testing's `#expect` macro compiles. This is test-only and has no Ark product behavior to adapt; no test or source file was copied.

### Cross-origin iframe video PiP — November 25, 2026

Closed the Mac frame-selection gap found while reviewing Browsa [`39eb4ad4a6fce8e49497071e3c5d86e26ec85e51`](https://github.com/jmaorr/Browsa/commit/39eb4ad4a6fce8e49497071e3c5d86e26ec85e51). BrowserKit's isolated page-activity script now registers live `WKFrameInfo` handles; Ark evaluates its existing video-selection and PiP control scripts in each registered frame, including cross-origin frames. A local two-origin video fixture run in the Debug Mac app verified that the iframe video entered system PiP (`registered 2 frames; cross-origin video entered system PiP: true`). `pagehide` also unregisters frame handles to prevent stale iframe references and registry growth; this cleanup is build-verified but was not separately confirmed at runtime. `ark:build-mac` passed. This verifies manual selection/entry on Mac only; mobile PiP and automatic iframe-video selection remain unverified. No new test file or simulator was used.

### Mac pin-folder drag and bulk selection — November 25, 2026

Adapted the relevant pin organization behavior from Search [`3e1efc6a14c69f4810018db34f83c03d417355e5`](https://github.com/driceroland/Search/commit/3e1efc6a14c69f4810018db34f83c03d417355e5) to Ark's Space and nested-folder model. The existing Debug tour now verifies Today-to-nested-folder moves, within-folder reorder, moves between folders, Command-click and Shift-click range selection, bulk-move ordering, ⌘Z restoring the pre-move order and folder assignments, and Open All loading nested-folder pages in sidebar order without changing selection. This exposed that the row tap handler read global modifier flags; it now reads `NSApp.currentEvent` so modified selection works. The Mac Debug run passed these checks; the report is `/private/tmp/ark-pin-folder-run/report.txt`. `ark:build-mac` passed. Mac Pinned tabs and folders is Yes; iPhone, iPad, and iPhone Duo remain Partial. Folder-heading reorder remains open. No new test file or simulator was added.

### Local host address parsing — November 25, 2026

Adapted the relevant part of Search [`77c275e94eb63e47a569bed55741528f10884063`](https://github.com/driceroland/Search/commit/77c275e94eb63e47a569bed55741528f10884063). Ark now recognizes `LOCALHOST:3000` case-insensitively and defaults localhost, `.localhost`, `.local`, loopback, and private IPv4 addresses to HTTP, while public hostnames keep HTTPS. Existing address-parser tests were extended in place; no new test file was added. Mac navigation verification is queued for the consolidated final pass, so the Address bar row rating is unchanged.

### Extension service-worker CryptoKey storage — November 25, 2026

Adapted Search [`235015456b3796e003f9b17a27545353bb892072`](https://github.com/driceroland/Search/commit/235015456b3796e003f9b17a27545353bb892072) in Ark's existing `extension-compat.js`. When an extension service worker tries to store a CryptoKey in IndexedDB, Ark now detects the key (including nested values) and rejects with `DataCloneError` instead of entering WebKit's reported same-thread serialization deadlock. The traversal is cycle-safe and bounded at 20,000 objects. No test file was added; an extension-specific runtime reproduction remains queued for the consolidated Mac pass, and MV3 remains Partial.

### Nested page scroll after waking an unloaded tab — November 25, 2026

Adapted Search [`8b20dcde02370b2f5ed6e2bc1fd8b745923cba31`](https://github.com/driceroland/Search/commit/8b20dcde02370b2f5ed6e2bc1fd8b745923cba31) for Ark's Mac-only WebView eviction path. Before closing an idle page, Ark records the largest scrolled inner element, its URL and selector, and its offsets. It keeps a size-limited in-memory record only for open tabs and restores it after that same URL commits, waiting for web apps to recreate the scroll area; trusted user input cancels the restore. Private tabs are excluded. `ark:build-mac` passed, and the existing Debug snapshot tour verified a forced unload/recreate preserved the inner scroll at 1,200 px. No test file was added; iOS eviction is unchanged.

### Newly pulled upstream review — November 25, 2026

Inventoried all 323 unique incoming commits across Search through `origin/main` [`9b67323c559c758b902a8edacdb23a027903353c`](https://github.com/driceroland/Search/commit/9b67323c559c758b902a8edacdb23a027903353c) and Browsa through `origin/main` [`46fe04bedb0f13521328c69d0f1f6814a18e6188`](https://github.com/jmaorr/Browsa/commit/46fe04bedb0f13521328c69d0f1f6814a18e6188). 240 commits have implementation review; the other 83 have title/path triage only and remain pending in [the upstream review](ark-upstream-review.md). Search's local-host parser, service-worker CryptoKey guard, and inner-page scroll restore were adapted above. Its hidden-element updates already apply to all Ark sessions, update prompts already wait for added extension permissions, and Ark already uses the visible implicit suggestion as Return's target. The reported `::first-line` WebKit cache crash fix is already present in Ark's `webkit.patch`, so no duplicate patch was added. Search's latest fold-fling work targets its persistent folded-column state, which Ark does not have; Ark's separate edge-peek path stays as-is pending the Arc comparison. Search's sized authentication popups, Zen import, iCloud device identity, optional Backspace navigation, search-engine darkening, and app-owned floating player have no direct missing Arc-row implementation in Ark. Browsa's renewed YouTube ad-skip work is service-specific, was previously reverted and then reintroduced, and is not copied without a reproducible Ark playback case. Its release notes, website assets, test-only probes, notification subsystem, 1Password native hosts, announcement cards, and WebKit build workflow changes are outside this 42-row pass or lack a matching Ark gap. Browsa's signed-in GitHub Pull Requests folder is a direct subfeature of Live Folders, not an out-of-scope feature: Ark's current data model stores RSS/Atom feeds only, so its Mac Live Folders rating is now Partial. The GitHub source needs a compatible model and Space-profile cookie bridge before it can be implemented safely; no cookie-authenticated test was run. Search's page-internal scroll restoration after WebView eviction is adapted and verified for Mac Archive; iOS eviction remains deferred. No other matrix rating changed from source review alone. The consolidated Mac build and snapshot tour now pass; local-host navigation and extension-runtime checks remain queued.

### Fetched feature-branch review — November 26, 2026

The newest fetch did not advance either pinned `origin/main` head (Browsa remains
`46fe04b`; Search remains `b9fcbb4`), but it did make four relevant feature branches available.
They are tracked separately from the `270 / 332` main-commit inventory. Search's
`origin/perf-many-tabs` is a substantial custom sidebar architecture and branch-only benchmark
suite; it provides useful workload/measurement ideas but no compatible, measured Ark change.
`origin/ext-1198` adds persisted optional host permissions and
`declarativeContent.RequestContentScript`: Ark already grants WebKit's requested/optional
permissions at load, but lacks Search's persistent declarative-rule and injection bridge, so the
Chrome extensions row remains Partial rather than importing a large unverified shim. The
`origin/meet-pip` experiments are site-specific Google Meet behavior; Ark keeps its current
system-PiP path until a signed-in reproduction identifies a scoped need. Browsa's
`origin/claude/org-filter-pr-off` only hides organisation controls for its authenticated GitHub
Pull Requests source, which Ark has not designed as a matching settings surface. No source,
matrix rating, test, simulator, or performance claim changed from this review.

### Mac Space-profile reset lifecycle — November 26, 2026

The isolated Mac audit found and fixed a profile-transition race. Changing a Space profile starts
an asynchronous WebView unload for PiP/session cleanup, but a view could resolve the old controller
before that cleanup completed. The late session snapshot could also restore the former profile
identifier after reset cleared it. `resetBrowsingSession` now clears that transient state again
when unload completes and bumps the existing page-swap signal so the view resolves a controller
made with the destination profile. The existing `SnapshotTour` waits for that lifecycle turn.

A separately identified temporary Debug bundle verified named-store cookie isolation and clearing;
profile assignment rebuilding the page on the named store; same-profile movement retaining the
page; and cross-profile movement rebuilding with cleared session state.
`NX_ISOLATE_PLUGINS=false pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed.
No simulator, new test file, installed-Ark change, or performance claim was involved.

### Mac Live Folder lifecycle audit — November 26, 2026

The prior failure was a fixture limitation, not a Live Folder implementation failure: its static
feed could not satisfy a check that expected a changed refresh. A separately identified temporary
Debug bundle ran against a loopback-only dynamic feed. It verified RSS discovery, an article title
change with stable article URLs/IDs, cached data remaining after an intentional HTTP 500 refresh,
and an imported folder remaining paused until an explicit resume. The new Mac feature capture is
[`preview/ark/mac/features/live-folder.png`](../../preview/ark/mac/features/live-folder.png).
No source behavior changed, no simulator was started, and the installed Ark was untouched.

### Mac Easels lifecycle and placement — November 26, 2026

The existing Debug `SnapshotTour` now has an isolated Easels mode and reuses the same routine in
the full feature tour. It verified page-card creation, note text editing and movement, doodle
stroke persistence, page capture, PNG export, ZIP export, and preparation of a system-share PNG.
The audit also found that a long-lived board could place a new card below the board's 1,650-point
movement boundary, making its first move jump upward when clamped. New cards now use the same
vertical bound as dragging. The temporary isolated bundle reported every operation true; its PNG
and ZIP artifacts were written under `/private/tmp/ark-easel-verified`. `ark:build-mac` passed.
No simulator or new test file was used.

## Final synced Mac pass — November 25, 2026

After inventorying all 323 incoming commits, `NX_ISOLATE_PLUGINS=false pnpm nx run ark:build-mac --skip-nx-cache --output-style=static` passed. The first sandboxed attempt was blocked before compilation by SwiftPM/Clang cache permissions; the same Nx build passed with the required cache access. A fresh post-build `open -n` of `dist/ark/Build/Products/Debug/Ark.app` returned Launch Services `kLSNoExecutableErr` (`-10827`); direct execution of its signed `Contents/MacOS/Ark` exited with `134` before writing tour output. The earlier existing SnapshotTour pass remains the current UI evidence, including restoration of the inner page scroll at 1,200 px. No simulator or new test file was used. A fresh UI pass needs the Debug bundle opened from Finder if Launch Services continues rejecting it.


### Retry and review correction

The Debug app launches via Launch Services when run outside the tool sandbox; the previous launcher errors were not evidence of a missing executable. Retry screenshots and report are under `/private/tmp/ark-final-mac-pass-7`. The unfinished GitHub Live Folder increment was removed before final verification; its parser, profile-switch behavior, and signed-in runtime checks still need work. Existing staged changes are retained. The previously reported 100% referred to title/path triage; actual implementation review remains 240/323 (74.3%), with 83 pending diff reviews.


### Successful final retry

After removing the unfinished GitHub increment, the Nx Mac build passed (52.8 seconds). Launch Services ran the rebuilt Debug app outside the tool sandbox and the existing SnapshotTour exited with status 0. It produced 19 screenshots and confirmed the sleeping page recovered its inner scroll at 1,200 px. The report and captures are saved in [preview/ark/mac/audit/upstream-sync](../../preview/ark/mac/audit/upstream-sync/). This is the general UI tour; it does not establish signed-in GitHub, extension compatibility, or full 42-row parity. No new test files or simulators were used.

Follow-up retry: the same Debug build completed the existing Mac SnapshotTour again with exit status 0. `/private/tmp/ark-final-mac-pass-9/report.txt` records Reader, window movement/cleanup, and inner-scroll restoration at 1,200 px; 19 screenshots were generated. No source changes were needed for this retry.


### Unchanged tab rename and next Search diff reviews

Adapted Search `a3ad9c1bac338688e435475811dea4b6f70447de`: accepting an unchanged inline tab name now preserves the original custom-name state even if the page title changes during the edit. The Mac Nx build passed; actual Rename interaction still needs focused verification. Reviewed the complete product diffs for unread pin counts (`5896709f`), profile-menu wording (`b467bb24`), and finished-download dragging (`80f8f136`). Ark already displays pin titles and assigns profiles per Space, so the first two changes do not map directly to its current UI. Download dragging is an applicable missing interaction and remains queued. Implementation review is 244/323 (75.5%); this does not increase the Mac parity rating. No new test files or simulators were used.


### Finished-download dragging

Adapted Search `80f8f1364c6471131e88544a7cb7ea773af6cdfb` in the Mac DownloadRow. A completed download can supply its local file URL via NSItemProvider with its filename and file-icon preview. Running, failed, cancelled, or missing downloads have no drag source; existence is checked again when dragging begins. The Nx Mac build passed in 16.6 seconds. Finder and webpage upload drops still require runtime verification; no feature rating changed. Reviewed the companion ROADMAP-only commit `8755ef84` and Search’s duplicate-Omnibox focus fix `6a10b64c`; Ark has a single BrowserWindow command overlay, so the latter has no matching duplicate-field path. Review progress is 246/323 (76.2%), with 77 pending diff reviews. No new test files or simulators were used.

### Contact app prompts and agent display changes

Adapted Browsa `b9cb5102a909dc2e11090378c3850fdbc0490d6f`: script-triggered tel, FaceTime and SMS navigation now follows Ark's existing per-site permission flow; clicked contact links remain direct. Adapted Search `bb0d3160fd5a7e1972f6dcfdce9412aae5df6034`: AgentStage returns to its offscreen origin on screen-parameter changes and again after one second, retaining its existing mouse-event exclusion. Both changes passed the Nx Mac build; the final build log is `/private/tmp/ark-agent-stage-build.log`. Contact prompt runtime checks and physical display-disconnect verification remain pending. No new test files or simulators. Review progress: 248/323 (76.8%), 75 pending. Mac matrix remains 21/42 Yes; build evidence does not raise runtime ratings.

### Boost editor and password-authentication diff review

Reviewed Browsa `7da1d3a0531bb8602f52d387dbb0df4147707bfb` and `98bf5ca89eea76031d020c5d821a730deb240d6b` against Ark SiteStyleEditor. Ark has no optional draft binding crash path. Its font/CSS/element editor also has no visual accent engine: the repeated-color measurement fix is a dependency for future adoption, not existing Ark behavior. Corrected Boosts to Partial to expose that missing visual control rather than treating custom CSS as full parity. Existing verified CSS/font/hiding evidence is retained.

Reviewed Search `6376d84a4d259e1db1862caca0dd2264cce7f440` and `faec5fc7ad1743c264e7bd0eb4d37d187dd8bfaa`, including product changes and accompanying checks. They address authentication failures and cross-site/private authentication-grace reuse in Search's managed password vault. Ark has no matching Vault/LocalAuthentication fill implementation; no direct code patch was made. These requirements remain relevant if that subsystem is adopted. Source review is now 261/323 (80.8%), with 62 pending; Mac Yes rows are 20/42 (47.6%) after the audit correction. No build rerun was needed for documentation-only changes.
