# Ark upstream intake — November 26, 2026

These locally available refs are an intake inventory, not a completed diff review or a synced baseline. The previous ledger still has 62 pending reviews. Entries below require diff review, an Ark disposition, and appropriate verification before advancing any baseline. No network fetch or upstream checkout change was made.

## Browsa: 46fe04b → a39e03e (8 commits)

| Commit | Subject | Status |
| --- | --- | --- |
| `f7fb5ae5bb302fdcd9f46f686bd859422e0f4af1` | Keep the Agent Stage window off screen (#140) [skip ci] | Pending diff review |
| `b337f69d5ef4aae6b11e3c196ee8c6f02a7c7b61` | Mac: export Spaces as a bookmarks file (#139) [skip ci] | Pending diff review |
| `afc2c39fc2e1a083050056fe9477b20d593d1a61` | Mac: keep videos in their Space (optional); clearer local certificate setting (#136) [skip ci] | Pending diff review |
| `a4c95ae518b28f40902256a498e06fdf568be627` | Downloads: drag files out, open when one finishes, screenshots land there (#137) [skip ci] | Pending diff review |
| `332fd52c30080743222b2dd1bae2f86f20a200e5` | Mac: ⌃Tab switches to recently used tabs (#138) [skip ci] | Pending diff review |
| `6463465333a652b28b403c667ffbfb7615fa9b59` | Page-menu downloads work; export and screenshots leave out private tabs and non-web addresses (#141) [skip ci] | Pending diff review |
| `64ae49e981dc4a5da4aa28910f74f3b79b6e8e7f` | Mac 1.3.1: release notes (#142) [skip ci] | Pending diff review |
| `a39e03e985b3caa69eabfa5af2e1ef7195a7517e` | 1.3.1: What's New entries, feature list, llms.txt and the releases table [skip ci] | Pending diff review |

## Search: b9fcbb4 → d5948c4 (60 commits)

| Commit | Subject | Status |
| --- | --- | --- |
| `181486f3bcb3541bd2abd174c0c2e6a9d8a1342f` | A #fragment jump on the same page keeps the click for its sign-in window (idea 1200) | Pending diff review |
| `e62decaa29ab6b4297bacba788156827b85387b1` | Tests: HiddenPanelTests hides with a Veil (Curtain.hide's signature changed in 464240bb) | Pending diff review |
| `a93a4379a090dfae756bb35b162b71664cea3b32` | A download never closes a tab whose page came in while in another space | Pending diff review |
| `9b609d4c28d5bfa60ca57fed09e403b968df0818` | A typed address that redirects to another site finishes from its own name | Pending diff review |
| `84a4bede6ac5e3d3e5d6ebc124920483fc2fc2f4` | ⌘Tab back to a page in full screen brings the full screen, not its placeholder | Pending diff review |
| `363d3fb7f420532b94453f51180552d40b93e640` | Apple Passwords rows under a sign-in box name their entry (idea 1206) | Pending diff review |
| `d0c292d2f7c2f553de5a3893a2da952880fc69da` | Developer Mode, site by site: whole address and a bar of tools for local sites | Pending diff review |
| `b2ce7eb3c729de864005e3bf544c1c6bda6e5934` | Screenshots in Downloads: new screenshots listed as they land, ready to drag | Pending diff review |
| `8efb16da44b3b8a3966523f6a9f3f43cfd0d5675` | Previews of pinned tabs on hover: picture, title and unread count (idea 1205) | Pending diff review |
| `7bc04c085b1e95af9a55c5cfa78613cc3000867c` | Export Spaces: every space, its pins, folders and open tabs, to a file | Pending diff review |
| `d458f0f2247b2a70050b930b3475c1d0470f3c83` | Spaces from Ardia, Yab and Dia: each space with its pins and folders | Pending diff review |
| `8c05ff2d3c39e8a7b09cac32757ccdb2d504a70d` | Tests: Set Up Like Arc writes swipe back closes off before it starts | Pending diff review |
| `f473713352217ef75035580816a7e37ec78ece76` | Probes: settings_layout's row budget goes from 150 to 175 | Pending diff review |
| `9a52321d2619857057668804f2ed2b1710ea2cff` | A picture inside a link keeps Open Link in New Tab (idea 1208) | Pending diff review |
| `934f2a61a0d04262db3b6bc6370657bb20dc497e` | A double-click on a wandered pin's square takes it home from any square (idea 1216) | Pending diff review |
| `f938f614c9e6b0de0b74c44380fd7eefeeb06160` | Downloads: Replace in the save panel replaces the file instead of failing (#1598) | Pending diff review |
| `c0d375ebb3322d1deb71c62f19f92cc36cad4661` | The global address field honours Return takes the top suggestion (#1608) | Pending diff review |
| `3586f0825a29f4827c7fb7c8ac1d4d9df44276b7` | Traffic lights: the zoom button stays in line under a window manager (#1595) | Pending diff review |
| `a7c83274ec9e0cd900645800df311a7affe2033e` | Hidden sidebar: a 28-point edge brings it out instead of 10 (#1583) | Pending diff review |
| `04a05e67a99b8c0f700817f5b6bc1295e14b8e90` | webRequest listeners get Chrome's statusLine, for Neat Download Manager (#1574) | Pending diff review |
| `f7638feb827669b10a3c21610196b594204c899c` | Settings: arrows to reorder profiles (#1571) | Pending diff review |
| `657dc6a5cec326bc70a8c1d5cd41599bf91d3696` | Screen sharing pill: a ✕ hides a website's share line (#1592) | Pending diff review |
| `e46378cc6634ca649a32861932a942888068b1e4` | Settings › Tabs › Double click to rename, off by default (#1601) | Pending diff review |
| `c6e7a9848229150ce8792514ad53ce695263e8db` | Paste and Go in the address fields' right-click menu (#1615) | Pending diff review |
| `8f405c9fb4a0e81d45e7f7c7280b262caf5a177e` | Bench: perf_many_tabs.py, PerfLog and perfwatch/perftimed/perfselect for many-tab timings (SEARCH_PERF=1 test runs only) | Pending diff review |
| `72daee5a192db136e4fc371ac26e5d61c4f9d0a2` | Bench: perf_profile.py (Time Profiler on a hidden probe's many-tab scenario) and its summary | Pending diff review |
| `8733c02ee158a17db43f52acc9865ff79a11400f` | Column: a row's groups and the tab in front worked out once per change, not per group or per call | Pending diff review |
| `a421a7495490aeecf39c65a9eec60817d1e10b14` | Bench: perfkeyspace, a space switch from ⌃N / ⌘N / Next Space timed from the key press (idea 1024) | Pending diff review |
| `04971c7b6db88cc259db054ff6aebc90a406f49e` | PERF-NOTES: many-tab measurements and leads (branch only, not for main) | Pending diff review |
| `0f48afbf94d6f39226b94cab126f4a3204f127fc` | Column: only the rows in sight are made, placed by what their heights add up to (ideas 1051, 1024) | Pending diff review |
| `4b5073fc1ce89b0e9cff9a42399997714c93bf4e` | Column: no row reads where it is drawn until it is carried (idea 1051) | Pending diff review |
| `f30484455af547a7e17a34c0a590744e4ee906a6` | Bench: perfkeyspace presses any key; perf_many_tabs times Next/Previous Space on ⌥⌘K/⌥⌘J (idea 1024) | Pending diff review |
| `dcc48c2458ddaeb837309d410ead056f5386ae23` | PERF-NOTES: phase 2 (windowed column, drag tracking, Next Space by key) | Pending diff review |
| `21b172a1763b75d77d9db6108a54ad977330f237` | Column: the window of rows drawn keeps its own band, moved a sixth of a room at a time (idea 1051) | Pending diff review |
| `fabe5e31ea15dd73d24a7d3eba5671551f454b0f` | Column: a space come in draws its tab in front's rows, not the band the last space's scroll left (idea 1051) | Pending diff review |
| `db37eef68ecaa8a1b536193e2602fc8e89f12f28` | Column: the scroll's mark drawn with the column, not in its window; space_switch finds the landing by the space's name | Pending diff review |
| `097efc3e449a1babfa3285377ba60bf08fab2762` | CHANGELOG: the column's many-tab work under Unreleased (it had slid into 1.0.21's list on the rebase); PERF-NOTES phase 3 | Pending diff review |
| `c27da19e460ead4fd27a0ac4b1abc3a711994dff` | Tests: mem_many_tabs.py, Search's own footprint at 50/200/400 tabs after restore and idle | Pending diff review |
| `7114625874107a16425a56e34f8b66d5630513a8` | Tab: a restored tab's WKWebViewConfiguration made with its page, not at launch | Pending diff review |
| `ea8e9998bdc0899c0715807226bad660b2b374b4` | Window: no snapshot for macOS's state restoration (16 MB at 1280 points, ~60 at 5K) | Pending diff review |
| `799d5ecd4e99ccba91ce2f29c7b44cf1695b1255` | Store.testing read with getenv: no dictionary of the whole environment per call | Pending diff review |
| `4b0dc4d440dd86419b34f03c4ee66ad76ab98716` | PERF-NOTES: memory with many tabs, where it goes and what was cut; CHANGELOG line | Pending diff review |
| `b1ebaccda40db288e43d8cd1c856a9e423882406` | Tests: mem_at_rest.py, memory and processes 30 s after a fresh hidden launch, and the first page after it | Pending diff review |
| `7a515054feb61a05854256281a9d33bb021dd598` | New tab: its page made at the first key typed, not a second after launch (no GPU process at rest) | Pending diff review |
| `f11bfe26e3fc8150bd4edd7b168a8fd2e14bb7a9` | Tests: mem_at_rest.py --page times the first page on the page's own clock | Pending diff review |
| `336d37565d1cbcd47c6935a6e4617b5ef2c111b7` | No WebKit network process at rest: the stores' cookie policy told when something first needs it | Pending diff review |
| `74502ec73d244076bcae25600a41f964365c36f5` | CHANGELOG and PERF-NOTES: Search at rest, one process and 41 MB | Pending diff review |
| `43e5940b47e4139ce0ad5c489855094fed9b5223` | SidebarPressTests clicks through the app, as a real click comes | Pending diff review |
| `54d1b206405bf4887cc6a2dbd83ace8d08b2313b` | address_at_rest.py turns Try HTTPS first off for its plain-http checks | Pending diff review |
| `58bb46624a294c61bff061c8fd1365274d1b5d9e` | The bench's screen watch ends when the bench stops | Pending diff review |
| `e8c4d04099ca538a325a3f7c998e9e3d81327a15` | SharePoint's Open in Desktop App reaches Excel and Word (idea 1215) | Pending diff review |
| `fb5040023a4ac5672067a7c1d19d15be7e9878f3` | Float the video on its own from any site's player (idea 1248) | Pending diff review |
| `cf27201e4d33faf44feb2607f5e5623ada285048` | A page handed off from the iPhone keeps the window's tabs (idea 1247) | Pending diff review |
| `6d531e94e6998253de6aaf673d4478cc63eda718` | Capture: Copy captures only, off by default (idea 1250) | Pending diff review |
| `c136c347bc06332d33bebabdeec320aff8833533` | Split View: a page keeps its caret and selection when the keys go to the other page (idea 1176) | Pending diff review |
| `06041055d1be85766ea36d97dcc8a8f6cf68401e` | Swipe: a root with overscroll-behavior none both ways still swipes back (idea 1249) | Pending diff review |
| `201d9a5343ac9550510d8948318d9929ed1ac2af` | Hidden tabs across the top come down as quickly as the hidden sidebar (idea 1253) | Pending diff review |
| `8f09d8b0b84bf662d7a400aa967d938ea4101111` | Reduce animations: hiding the sidebar leaves no blank band, and covers every motion (idea 1254) | Pending diff review |
| `8edee85aba289acadeab75402841cab246bc66cd` | Sidebar: one line between the bookmarks and the tabs with a pinned square (idea 1255) | Pending diff review |
| `d5948c456a47d4686066e7cd93fca6703cdb77f7` | Developer Tools Full: Settings fits inside the docked panel (idea 1257) | Pending diff review |
