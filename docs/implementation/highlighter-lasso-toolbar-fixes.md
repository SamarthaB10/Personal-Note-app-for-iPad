# Highlighter, lasso, and floating toolbar corrections

Date: 10 October 2026. Source review and local checks passed. A new physical check is required for the reported Pencil and movement faults.

## Changes and causes

The highlighter now has a remembered opacity setting from 10% to 80%, with a 25% default. Press and hold Highlighter to change it. The palette and manual widths stay available. Only new strokes use a changed opacity; existing ink keeps its saved appearance. The tool uses the color alpha described in [Apple's PencilKit documentation](https://developer.apple.com/documentation/pencilkit/pkinkingtool-swift.struct/color-5xmlo).

Changing the PencilKit tool can enable its drawing recognizer. The old stored flag could still say drawing was disabled after switching between lasso modes. The surface now checks the actual recognizer state after configuring the tool. Lasso input must select and move content without adding ink.

The floating toolbar used an unclamped saved position as the start of its movement preview. At the top edge, the first 10 points of a downward drag produced zero movement. Its preview now starts at the displayed position. Release saves the clamped end position. The drag transaction has no animation.

## Reproduction and verification

Temporary files are outside the repository. No unit or integration tests were written or run. There is no repository test suite to run.

- `xcode-select -p`: selected `/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild -version`: Xcode 27.0, build 27A266a.
- `xcodebuild -list -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj`: found the `CanvasPrototype` target and scheme.
- `xcodebuild -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'platform=iOS Simulator,id=2A1BD5CC-3E79-481C-933C-B7063CDBB3B3' -derivedDataPath /tmp/NotesToolBugDerivedData build`: exit 0 before the changes.
- `/tmp/run-notes-tool-repro.sh`: before the fix, failed both lasso mode switches and highlight transparency. After the fix, exit 0; all seven checks passed. The temporary app uses the actual surface and store. It calls the page recognizer's event handler to enclose one ink stroke and move it by 40 points. It checks complete-stroke selection, movement, drawing enablement after tool changes, and highlight color alpha. It does not simulate physical Pencil touch delivery or measure frame latency.
- `swift /tmp/notes-toolbar-repro.swift`: before the fix, exit 1, movement 0 for a 10-point drag. After the fix, exit 0, movement 10. This temporary command runs the toolbar's position calculation. It does not measure touch latency or frame rate.
- `xcodebuild -project /tmp/notes-tool-baseline/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'platform=iOS Simulator,id=2A1BD5CC-3E79-481C-933C-B7063CDBB3B3' -derivedDataPath /tmp/NotesToolReproDerivedData ONLY_ACTIVE_ARCH=YES build`: exit 0 after the changes. The temporary copy contains the reproduction entry point; the real app entry point was not changed.
- `xcrun swiftc -typecheck -swift-version 5 -warnings-as-errors -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.0.sdk -target arm64-apple-ios26.0-simulator -module-cache-path /private/tmp/ipad-notes-main-module-cache prototypes/CanvasPrototype/CanvasPrototype/*.swift`: exit 0.
- Signed build: `xcodebuild -quiet -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'id=<connected-ipad>' -derivedDataPath /private/tmp/CanvasPrototypeSignedBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM='<local-personal-team>' -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`: exit 0. Device and team values came from existing local installation files and are omitted here.
- `python3 /private/tmp/ipad-notes-issue4-device.py install`: exit 0. Updated the existing app without an uninstall.
- `python3 /private/tmp/ipad-notes-issue4-device.py launch`: exit 0. Opened the updated app on the connected iPad.
- `git diff --check` and `git diff --cached --check`: exit 0.
- `git diff --no-index --check /dev/null docs/implementation/highlighter-lasso-toolbar-fixes.md`: exit 0.

The two independent Standards and Spec reviews of `/tmp/notes-tool-fix.diff` found no issues. They covered only this task's changes against the initial working files. The branch already had uncommitted image, undo, canvas, library, and toolbar work. That work is preserved. The tracked highlighter and lasso changes are isolated for the task commit. The dock correction remains in the existing untracked `CanvasFloatingToolbar.swift`; committing that complete file would also include the earlier toolbar work and require its uncommitted dependencies.

The device-panel CLI snapshot failed with `Daemon request timed out`. The temporary simulator reproduction used `xcrun simctl` for installation and launch. Xcode's device list confirmed a connected physical iPad 10th generation. Apple documentation and local Apple signing services were used. No database, cloud note storage, paid service, production deployment, issue change, PR, or push was used.

## Required physical check

1. Press and hold Highlighter. Set a bright color and low opacity. Highlight handwriting and imported PDF text. Change opacity, then write another highlight. Check that text remains visible and each new stroke uses the selected opacity.
2. Switch Pen → Freehand lasso → Box lasso → Freehand lasso. Circle a small handwritten item and drag it. Repeat with the Pencil and a finger. Check that the item moves and the lasso adds no ink. Also check mixed movement, resize, and unchanged source PDF content.
3. Collapse the toolbar and move it with the handle, starting at each edge. Check that it follows the finger and does not jump on release. Expand it and check both horizontal and vertical docking.
4. Reopen the notebook. Check moved ink, saved highlights, and remembered opacity. Compare fast writing with Apple Notes and check scratch erase and Undo.

A build and the temporary checks cannot establish physical Pencil quality or smooth movement. Record the user's result separately.

## Dock follow-up

The user passed the highlighter and lasso update, but reported that the dock still moved with friction and shook with both finger and Pencil input. The user also reproduced the shaking in the simulator. The earlier 10-point arithmetic check covered clamping only; it did not verify the gesture's coordinate space or smooth movement.

The follow-up changes `DragGesture` from its default local coordinate space to `.global`. The handle moves with the dock. A fixed screen coordinate space prevents that movement from changing the drag measurement. This is the source-level cause being checked, not a measured latency result. [Apple documents the gesture coordinate-space setting](https://developer.apple.com/documentation/swiftui/draggesture/coordinatespace). The drag remains on the handle and retains the existing collapse, docking, and position saving behavior.

Follow-up commands and results:

- `printf '%s\n' y | bash /tmp/notes-dock-hitl.sh`: exit 1, `OBSERVED_SHAKE=y`. The `y` records the user's repeated completed physical and simulator checks. It is not an automated observation.
- `python3 /tmp/check-notes-dock-drag.py`: did not capture a completed drag. The accessibility handle rectangle did not match the visible handle. Later screen and geometry-based attempts also did not produce a usable trace. These commands establish no pointer-distance or frame-rate result.
- Device-panel CLI snapshot: initially failed with `Daemon request timed out`; a later retry returned a snapshot through its private accessibility fallback.
- `xcodebuild -project /tmp/notes-tool-baseline/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'platform=iOS Simulator,id=2A1BD5CC-3E79-481C-933C-B7063CDBB3B3' -derivedDataPath /tmp/NotesToolReproDerivedData ONLY_ACTIVE_ARCH=YES build`: exit 0. The dock-only temporary app includes trace code outside the repository.
- The full-source `xcrun swiftc -typecheck` command recorded above: exit 0 after the follow-up.
- The signed physical `xcodebuild` command recorded above: exit 0 after the follow-up.
- `xcodebuild -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'platform=iOS Simulator,id=2A1BD5CC-3E79-481C-933C-B7063CDBB3B3' -derivedDataPath /tmp/NotesToolBugDerivedData ONLY_ACTIVE_ARCH=YES build`: exit 0 for the full app.
- `python3 /private/tmp/ipad-notes-issue4-device.py install` and `python3 /private/tmp/ipad-notes-issue4-device.py launch`: exit 0 after the follow-up.
- Standards and Spec follow-up reviews: no findings. Both require a new live drag check.

The updated source remains in the existing untracked toolbar file. Other pending work is preserved. No new unit or integration tests, dependencies, note-storage changes, or production deployment were added. The physical check must cover long drags, direction changes, collapse and expansion, edge release, and both finger and Pencil input. Smooth movement is not yet confirmed.

## Fast lasso and zoom follow-up

The user confirmed that the dock correction works. The user then reported a quick lasso circle followed by a drag that stops or flashes. The user also reported excessive zoom out, a fixed zoom percentage, displaced content, and scratch erase that fails at random during bursts of writing.

A temporary app exercised the actual notebook host, surface, and page store. It closed a loop, started a drag before the queued selection display update, let that update run, and moved the ink by 40 page points. `/tmp/run-notes-zoom-scratch-repro.sh` reported `FAIL quick loop and immediate drag move the ink`. Synchronizing the selection display at the common movement entry point changed that result to `PASS`. The queued display update had canceled the drag because its selection was still empty. This correction covers both a completed loop and direct contact with ink.

The notebook now stops zoom out at whole-page fit and disables zoom bounce. The initial width-fit view and maximum zoom stay the same. The minimum is updated when the viewport changes. The temporary check reported both zoom-limit checks as failures before this correction.

The temporary basic scratch check passed: scratch over one known stroke removed both the stroke and scratch. The notebook zoom percentage callback also passed. These checks did not reproduce the reported random scratch fault or fixed percentage. Those reports and displaced content remain open. They must not be treated as corrected by the lasso or zoom-limit changes. An additional window-attached probe was prepared, but the simulator did not complete its boot and launch commands after restart. No physical Pencil result is claimed.

Commands and results for this follow-up:

- `git rev-parse --show-toplevel` and `git rev-parse --path-format=absolute --git-common-dir`: confirmed the original repository and active worktree are the same.
- `git status --short --branch`: checked pending changes before editing; unrelated image, undo, library, and toolbar work is preserved.
- `xcode-select -p` and `xcodebuild -version`: same Xcode path and version recorded above.
- `xcodebuild -quiet -project /tmp/notes-tool-baseline/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'platform=iOS Simulator,id=2A1BD5CC-3E79-481C-933C-B7063CDBB3B3' -derivedDataPath /tmp/NotesToolReproDerivedData ONLY_ACTIVE_ARCH=YES build`: exit 0. Temporary app code stays outside the repository. This is a diagnosis command, not a new repository test suite.
- `/tmp/run-notes-zoom-scratch-repro.sh`: exit 1 before the lasso correction; quick movement failed. With only the selection synchronization changed, quick movement passed, and the two pre-existing zoom-limit checks still failed. A later run with all current corrections could not complete because simulator commands waited for boot or termination. It supplies no final all-green result.
- Full-source `xcrun swiftc -typecheck` command recorded above: exit 0 with warnings treated as errors.
- Signed physical `xcodebuild` command recorded above: exit 0. Xcode reported the existing interface-orientation warning.
- Independent Standards review: no breaches or code smells requiring changes. Independent Spec review: no findings in the lasso and zoom-limit changes. Both leave the other reports open.

No unit or integration tests, dependencies, storage-format changes, database, cloud note storage, PR, push, or production deployment were added. Apple developer documentation and local Apple signing services were used. [Apple documents the ink canvas as a scroll view](https://developer.apple.com/documentation/pencilkit/pkcanvasview); the additional diagnosis checks its input controls after window attachment.

Required physical check: circle a small handwritten item and start movement at once. Repeat fast circles and direction changes with Pencil and finger input. Check that the whole stroke moves, no new ink appears, Undo restores its old position, and reopening preserves the moved position. Pinch out to whole-page fit and back in. Check the percentage and alignment of ink, typed text, and the page background. Repeat scratch-and-hold during bursts of handwriting and check one-step Undo.

- `python3 /private/tmp/ipad-notes-issue4-device.py install`: exit 0 for this update. The existing app and local notes were kept.
- `python3 /private/tmp/ipad-notes-issue4-device.py launch`: exit 0 for this update. Opened it on the connected iPad.
