# Todos for Apple

From this repo run `pnpm vx`, then `pnpm nx run todo-apple:build-ios` or `pnpm nx run todo-apple:build-mac`. XcodeGen and Xcode with the iOS 27.1+ SDK are required. Open apps/todo-apple/Todos.xcodeproj and run TodoMobile on an iPhone/iPad simulator or TodoMac on My Mac. Both target OS 26+. The demo API runs on the same Mac at 127.0.0.1:47831. Physical devices require a reachable authenticated deployment or tunnel.

Edits, queued writes, conflicts and the feed cursor are saved together in Application Support. To run the integration test, start the backend with TODO_PORT=47832 and a disposable TODO_DB, then run `pnpm nx run todo-apple:test`. TODO_TEST_API may override the test API base URL including /api/.

## Cross-platform reference

`TodoMobile` builds for iPhone and iPad. `TodoMac` builds for macOS. Their entry points live in `App/` and `Mac/`. Both compile `Shared/TodoScreen.swift` for the UI and `Shared/TodoStore.swift` for persistence and sync. New apps follow the [Apple CLI template](../../vx/handbooks/cli-template-baseline.md#apple-applications). Each installation owns its local data. The Go API synchronizes them using a permanent client-generated `resource_id`, a separate `operation_id` per edit, and a revision check. The React PWA implements the same protocol with IndexedDB.

The todo screen stacks active and completed tasks in narrow windows and at accessibility text sizes. At 620 points of available width, it can show the groups side by side. Sync and New Todo use native toolbar placements with a vertical preference on iOS 27.1 and later. Tap a title to edit it or use its actions menu to delete it. The editor sheet lives above the responsive layout so a width change preserves the draft. [Apple’s Duo layout guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

### Repeat the cross-client check

Use a disposable workspace with the Go API on `127.0.0.1:47831` and the built PWA served on `127.0.0.1:4173`. From `27-vx-apple`, with the other repositories checked out alongside it, run these commands on the Mac.

```sh
TODO_TEST_API=http://127.0.0.1:47831/api/ pnpm nx run todo-apple:test
cd ../27-vx-fe
TODO_SWIFT_SMOKE="$PWD/../27-vx-apple/dist/todo-smoke" pnpm nx run todo-e2e:e2e --skip-nx-cache
```

The browser suite tests offline creation and reload, a lost acknowledgement, editing and deletion. With `TODO_SWIFT_SMOKE` set, it also creates a browser todo, completes it through the actual Swift store, and checks the updated checkbox in the browser. Run `pnpm nx run todo-api:test` from `27-vx-be` to exercise concurrent retries, API restart and pagination separately.

### Device acceptance

For a pose check, open the same todo for editing and type an unsaved title. In Device Hub cycle through Closed, Partially Open, Open, and back to Closed. Check that the draft survives, the controls remain reachable, and saving updates the same row on a second client. Record the simulator runtime and each tested pose. A successful build or launch covers a different check. [Device Hub pose controls](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub)

The baseline uses a single unauthenticated local workspace. Production account isolation, a physical Android PWA run, physical Apple devices, and execution on the minimum OS 26 require separate verification. Also exercise remote edits arriving while an edit sheet is already open: the current Swift store chooses its base revision at save time, so a stale form can overwrite a freshly pulled update.

### Verification record, November 22, 2026

| Surface               | Observed result                                                                                                                                                                                                                                                                                                      |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| React PWA and Go      | Chromium passed offline reload, queued CRUD and retry after a dropped acknowledgement. Go race tests passed for concurrent replay, conflicts and pagination.                                                                                                                                                         |
| React PWA and Swift   | Browser-created todo was completed by the Swift store and displayed as complete in the browser.                                                                                                                                                                                                                      |
| Android-sized browser | A Pixel 7 touch viewport in Chromium reloaded offline at 412 CSS pixels with no horizontal overflow. Physical Android installation remains untested.                                                                                                                                                                 |
| Mac, iPhone and iPad  | The native app launched on macOS, iPhone 18 Pro and iPad Pro 11-inch. Mobile simulators used runtime 27.2.                                                                                                                                                                                                           |
| iPhone Duo            | Passed on simulator runtime 27.2. With the edit sheet open, Device Hub cycled Closed → Partially Open → Open → Closed. XCTest checked the same unsaved draft and a reachable Save button after each transition. Saving advanced the same resource UUID from revision 2 to 3, and Chromium displayed the saved title. |
