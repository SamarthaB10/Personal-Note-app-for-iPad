# Local notebooks in Unfiled

Issue: [3](https://github.com/SamarthaB10/Personal-Note-app-for-iPad/issues/3). Build date: 9 October 2026.

The app opens a native library with an Unfiled sidebar, notebook count, cover grid, and Create card. Create saves seven ordered blank pages and opens the notebook. Pages, Previous, and Next provide access to all seven pages. Back waits for saving before the library appears. A save failure keeps the editor open.

The editor uses the canvas accepted in [ADR 0002](../adr/0002-pencilkit-app-owned-page-content.md). It retains the ink tools, manual widths, colors, both erasers, scratch erase, text boxes, and lasso. New notebook pages contain no sample marks or PDF fixture. The old prototype page remains in its original storage directory.

## Storage and input

`CanvasNotebookStore` owns notebook creation, ordered page loading, and local storage. `CanvasPageStore` owns editable page state. SwiftUI views call these stores for creation and saving. The library index records Unfiled membership and ordered page IDs. Page files contain PencilKit drawing data and app-owned text boxes and shapes.

Creation saves all seven page files before publishing the library index. Page writes use a serial utility queue and atomic replacement. Saved files are validated before they are replaced. Invalid or missing pages remain preserved and produce a visible error. Partial creation files also remain preserved. This is not the complete backup or recovery workflow.

Cover rendering uses a separate utility queue. Repeated identical content does not request another cover. Completed first-page saves are joined during a short quiet period. Interrupted cover updates can be regenerated when the notebook opens. Cover failure does not replace saved page content. Lifecycle saving requests background time from iPadOS; forced termination can still stop unfinished work.

The app uses one window. Source review found that separate window stores could replace a library index from stale memory. The source Info.plist now disables multiple scenes. The built app's `UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes` value was checked and is `false`.

## Recorded checks

- `xcode-select -p`: `/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild -version`: Xcode 27.0, build 27A266a.
- `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.0-simulator -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.0.sdk prototypes/CanvasPrototype/CanvasPrototype/*.swift`: passed after the source edits stopped.
- `plutil -lint prototypes/CanvasPrototype/Configuration/Info.plist prototypes/CanvasPrototype/CanvasPrototype.xcodeproj/project.pbxproj`: passed.
- Signed physical incremental build: passed, including the single-window correction.
- `xcodebuild -quiet -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'platform=iOS Simulator,id=<simulator>' -derivedDataPath /private/tmp/CanvasPrototypeIssue3Simulator build`: passed. The simulator does not establish Pencil quality.
- `git diff --check` and new-file whitespace checks: passed. Four local Markdown links passed.

The signed build command used the locally stored device and Personal Team values. They are omitted here:

```sh
xcodebuild -quiet -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'id=<device>' -derivedDataPath /private/tmp/CanvasPrototypeSignedBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<team> -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

The device commands were `xcrun devicectl device install app --device <device> /private/tmp/CanvasPrototypeSignedBuild/Build/Products/Debug-iphoneos/CanvasPrototype.app --timeout 60`, `xcrun devicectl device process launch --device <device> com.samarthab.CanvasPrototype --timeout 30 --terminate-existing --activate`, and `xcrun devicectl device capture screenshot --device <device> --destination <screenshot.png> --timeout 30`.

The initial build was installed and launched on the connected iPad. Its actual screenshot showed the empty Unfiled library and Create card. The corrected single-window build was installed, launched, and captured with all commands at exit 0. Its actual screenshot showed the user-created notebook on page 1 of 7. Screenshots and signing logs stay outside the repository.

## Physical check boundary

Issue 2's combined physical gate remains passed. Issue 3 adds notebook persistence and cover generation. Its physical checks are separate: create a notebook, verify seven blank ordered pages, write distinct marks, return to the cover grid, reopen offline, and compare writing during saves and cover generation with Apple Notes. The user answered “All pass” for this complete issue 3 bundle on 9 October 2026. This confirms the seven blank pages, distinct saved marks on pages 1, 4, and 7, Unfiled title/cover/count, offline reopen, page order, editable ink, writing during Save and cover updates compared with Apple Notes, manual widths, colors, and both erasers. No numeric latency was measured. Fresh Sol Medium round-2 Standards and Spec reviews found no remaining source findings after the single-window correction.

No unit or integration tests were written or run. No database, note cloud service, paid service, or production deployment was used. GitHub and public Lucide icon sources were read. Apple signing services were used for the authorized free Personal Team installation. Local storage does not prove exclusion from device cloud backup.

Continuous scrolling, Add Page, paper choices, and finger pinch zoom belong to issue 4. Custom folder behavior belongs to issue 5. The [complete accepted scope](../design/notes-app.md) remains required.
