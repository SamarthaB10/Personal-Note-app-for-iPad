# Sidebar Trash and folder colors

Samartha requested these changes on 10 October 2026. The [accepted design](../design/notes-app.md#accepted-library-ui-changes-on-10-october-2026) records the UI choices.

Trash is a 44-point icon control at the bottom of the folder sidebar. Its accessible name is Trash, with an item count. Folder content has no Delete folder button. Press and hold a custom folder for Change color or Delete. Native confirmation names the folder and moves it and its notebooks to Trash together. Unfiled has no Delete action. Deleting another folder keeps the current folder selected.

The notebook header puts a 44-point trash icon beside Home. A native alert says Delete current page and asks Are you sure? The request keeps the page's stable ID while the alert is open. Cancel keeps the page. The store still checks the final-page rule, active input, and successful saving before changing Trash. Notebook Delete and Move remain together in the cover context menu. Import and export remain available.

Ten named colors use the existing fixed palette, with readable sidebar shades for light and dark modes. The selected color has a visible Selected label and an accessibility selected trait. Folder names and counts remain visible. The color write waits for the FIFO library mutation permit, takes a fresh index snapshot, and publishes the color only after the atomic save succeeds. Existing folder JSON without a color decodes as blue, including older folder Trash records. The whole folder value goes to Trash and returns on restore. No saved ink or text color changes.

## Checks

- `xcode-select -p`: `/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild -version`: Xcode 27.0, build 27A266a.
- `xcrun swiftc -typecheck -swift-version 5 -warnings-as-errors -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.0.sdk -target arm64-apple-ios26.0-simulator -module-cache-path /private/tmp/ipad-notes-main-module-cache prototypes/CanvasPrototype/CanvasPrototype/*.swift`: exit 0 after the UI implementation.
- `python3 /private/tmp/ipad-notes-issue4-build.py`: signed incremental build, exit 0. The inspected helper uses `CanvasPrototype.xcodeproj`, scheme `CanvasPrototype`, the connected iPad, deployment 26.0, and the existing free Personal Team. Private device and signing values stay out of this record.
- `python3 /private/tmp/ipad-notes-issue4-device.py install`: exit 0. The installed app keeps bundle `com.samarthab.CanvasPrototype`; no uninstall or data erase was used.
- `python3 /private/tmp/ipad-notes-issue4-device.py launch`: exit 0.
- `python3 /private/tmp/ipad-notes-issue4-device.py capture`: exit 0. The actual capture was copied to `/private/tmp/ipad-notes-sidebar-trash-colors-physical.png`. It shows bottom-sidebar Trash, a gold custom folder icon, and no Delete folder in the content. It does not show the page confirmation or prove recovery and persistence.
- The final source typecheck command above ran again after the last source edits: exit 0.
- `git diff --check`: passed after removing a blank line at the end of `CanvasTrashView.swift`.
- `git diff --no-index --check /dev/null FILE` for each of `CanvasFolderColor.swift`, `CanvasFolderColorView.swift`, and this record: no whitespace errors. Exit 1 reflects new content against `/dev/null`.
- A Python local-link check on the accepted design, Trash record, this record, and prototype README found no missing local targets.
- T3 `device_list` listed iOS simulators only. Android was unavailable because the Android SDK was absent. The authorized physical update used the inspected platform helper.

The current source was checked directly without subagents. Tracing confirms the missing-color default, group color preservation, serialized index writes, captured page identity, final-page refusal, and existing mounted-input/save guards. This does not establish physical behavior.

Required manual checks are folder press-and-hold Delete/Cancel and Change color; color after offline reopen and group restore; page confirmation/Cancel and final-page refusal; notebook cover Delete/Move; and light/dark readability. Import/export, Trash recovery, and physical Pencil checks recorded in the prior feature documents remain open. No real note was deleted by automation.

No unit or integration tests were written or run. No new dependency, database, note cloud service, or production deployment was used. GitHub was used for issue reads and authorized draft PR work. Screenshots remain outside the repository. The GitHub browser session was previously signed out, so PR image upload remains pending.
