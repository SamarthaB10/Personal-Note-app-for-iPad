# Issue #2: native canvas prototype

Date: 9 October 2026.

## Result

The prototype source uses PencilKit for ink. It keeps text boxes and shapes in app-owned data. A local PDF page supplies the fixed background. The source saves the editable page in the app's local Application Support folder.

The combined physical gate passed on 9 October 2026. Use PencilKit ink with app-owned text boxes, shapes, selection, and scratch erase for the app canvas. [ADR 0002](../adr/0002-pencilkit-app-owned-page-content.md) records this choice and its trade-off. The final notebook storage format and recovery design remain future work. The complete first-version scope remains required.

## API facts

- `PKCanvasView.drawingPolicy` supports Pencil-only input. Apple added this policy in iOS 14. The prototype does not change `drawingGestureRecognizer.allowedTouchTypes`. [PencilKit input policy](https://developer.apple.com/videos/play/wwdc2020/10107/)
- `PKStroke.renderBounds` includes line width and the stroke transform. Stroke path interpolation, stroke transforms, and `maskedPathRanges` are available before iPadOS 26. The lasso and scratch code use these APIs. Apple describes `maskedPathRanges` in its PencilKit inspection session. [Stroke bounds](https://developer.apple.com/documentation/pencilkit/pkstroke-swift.struct/renderbounds), [stroke path interpolation](https://developer.apple.com/documentation/pencilkit/pkstrokepath-swift.struct/interpolatedpoints%28in%3Aby%3A%29), [PencilKit stroke inspection](https://developer.apple.com/videos/play/wwdc2020/10148/)
- `UIScribbleInteractionDelegate.scribbleInteraction(_:shouldBeginAt:)` can refuse Scribble. The app must also require a direct finger tap before it opens keyboard editing. [Scribble delegate](https://developer.apple.com/documentation/uikit/uiscribbleinteractiondelegate)
- PDFKit can provide a page overlay from iOS 16. The current prototype renders a local PDF fixture as the fixed page background and stores added content separately. It does not edit the source PDF. [PDF page overlays](https://developer.apple.com/documentation/pdfkit/pdfpageoverlayviewprovider)
- PencilKit provides bitmap and vector erasers. Apple does not document a scratch-and-hold erase API. The prototype uses a custom Pencil gesture recognizer. The user passed the physical scratch-and-hold and ordinary writing checks recorded below; latency and false-erase rates were not measured as numeric values. [PencilKit eraser types](https://developer.apple.com/documentation/pencilkit/pkerasertype)
- PaperKit is available from iPadOS 26, but its combined behavior is not verified here. Do not use `PaperMarkup.subelements`, PaperKit's element-ID selection, or `PKCanvasView.selection`; those APIs require or are marked for iPadOS 27. [PaperKit](https://developer.apple.com/documentation/paperkit), [PaperMarkup subelements](https://developer.apple.com/documentation/paperkit/papermarkup/subelements), [PaperKit selection](https://developer.apple.com/documentation/paperkit/papermarkupviewcontroller/selection), [PencilKit selection](https://developer.apple.com/documentation/pencilkit/pkcanvasview/selection)

## Device and tool facts

The Mac first used Command Line Tools at `/Library/Developer/CommandLineTools`. `xcodebuild -version` failed because Xcode was not selected. The user later downloaded and selected Xcode 27.0, build 27A266a. The iOS 26.5 simulator runtime is installed. The app has no verified simulator UI workflow yet.

`devicectl` confirmed the connected iPad is an iPad (10th generation) on iPadOS 26.7.1. Developer Mode is enabled. The Apple Pencil USB-C model is user-reported; the connected Pencil model was not independently verified. The user authorized physical prototype installation and checks. The free Personal Team build is signed, installed, trusted, and running on the iPad.

## Physical check record: 9 October 2026

- The first installed build showed a black page. The custom item overlay was opaque. The saved correction makes that overlay transparent and clears its dirty drawing area.
- A signed incremental build of the correction, physical installation, foreground launch, and screen capture all returned exit 0. The corrected screen shows the white fixed PDF background and saved ink, text boxes, and a rectangle. Capture: `/private/tmp/ipad-notes-fixed-app-preview.png`. This file is outside the repository and was shown in the main thread.
- The user selected Pen and drew a new line with the Pencil. The user reported: “The line appears normally.” This passes basic visible Pencil input. It does not establish writing quality, palm handling, or the complete canvas gate.
- The user rejected the small centered page and large controls. The user requires the writing page to use the available iPad screen. The source now uses the full available width, a 44-point header, and a 52-point tool strip. Settings and selection actions use popovers. The signed build, installation, launch, and settled physical capture returned exit 0. Capture: `/private/tmp/ipad-notes-fullwidth-app-preview.png`, shown in the main thread with its display orientation corrected by CSS. The first immediate capture showed a launch transition; a settled capture was used as evidence.
- The user reported that Save/Reopen appeared to do nothing. No missing ink or error was reported. The source now supplies separate visible action messages. Reopen preserves the live page if its snapshot cannot be saved, instead of reporting success after a failed write. Current storage errors take precedence over an earlier success message.
- A read-only copy of the app's editable JSON before and after a stable process relaunch was identical. Both copies and the launch returned exit 0. An earlier comparison changed while the user used the app; that comparison did not establish persistence. The stable result proves the saved data stayed intact across that relaunch. The user later confirmed typing and the new-content Save/Reopen workflow passed.
- The source flushes pending live ink when the app becomes inactive or enters the background. This boundary needs a physical immediate-background check.
- The user confirmed scratch-and-hold removes only ink, one Undo restores it, and normal cross-outs and sketches stay intact. These requested physical scenarios passed.
- The user first confirmed text-box creation keeps the keyboard closed until the next explicit finger tap, and Pencil contact neither opens the keyboard nor becomes typed text. The user later reported that typing fails because the keyboard repeatedly closes. Source inspection found that a UIKit editing-end callback cleared the app's editing session. The correction retains explicit editing intent, rejects stale editor focus callbacks, and avoids redundant active-editor style changes. The latest user check passed typing and Save/Reopen after this correction.
- Lasso failed. The user could not select the wanted text box and reported jumbled results. The user also requested Delete for selected objects. Source inspection found invisible text-box bounds and movement from the broad union of an old mixed selection. The saved correction adds tap selection, visible box bounds, clear Move/resize handles, and selected-content Delete. A new loop replaces the old selection. Pencil and finger paths have separate ownership. The latest user checks passed both lasso modes, complete-item selection, exclusion of partly enclosed ink, mixed movement, proportional resize, selected-content Delete, and fixed PDF behavior with these handles. The user then requested direct smooth drag inside selected handwriting without a required Move handle or menu, and clearer choice of stacked or nearby text boxes. The final physical pass for these new changes is recorded below.
- The user first said writing works without separate results. In the later direct-drag build, the user answered All checked and pass for the Apple Notes comparison while saving, palm contact, scrolling, manual widths, both erasers, and immediate scratch Undo after new writing.
- Earlier final review attempts failed because of provider usage limits. Do not report a passed final review from those attempts.

At this earlier stage, issue 2 remained open and issue 3 had to wait. The final pass is recorded below.

The user requires the GitHub issues to be completed in order. The user has now authorized focused PRs for completed issues. The requested library home screen is in issue 3, page growth and paper choices are in issue 4, custom folders are in issue 5, and full text-box editing is in issue 6. The user reported the current text boxes cannot be deleted and explicitly requested selected-content Delete in the lasso correction. Do not report the later library or folder workflows as implemented by this one-page prototype.

The signed build used this command, with local personal values omitted:

```sh
xcodebuild -quiet -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'id=<connected-ipad>' -derivedDataPath /private/tmp/CanvasPrototypeSignedBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM='<local-personal-team>' -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <connected-ipad> /private/tmp/CanvasPrototypeSignedBuild/Build/Products/Debug-iphoneos/CanvasPrototype.app --timeout 60
xcrun devicectl device process launch --device <connected-ipad> com.samarthab.CanvasPrototype --timeout 30 --terminate-existing
xcrun devicectl device capture screenshot --device <connected-ipad> --destination /private/tmp/ipad-notes-fixed-app-preview.png --timeout 30
```

The actual commands read the team and device values from existing temporary files. Personal values were not added to source or this record. Logs remain in the OS temporary directory. Apple signing services were used for the authorized free installation. No database, cloud note storage, paid service, production deployment, PR, push, or GitHub issue change was used.

## Manual checks

Required checks for this prototype:

- Save and reopen the editable page from local storage.
- Draw with each manual width and color. Use bitmap and vector erasers.
- Scratch and hold over ink. Confirm that text, shapes, and the PDF background stay unchanged. Use one Undo for each scratch erase.
- Write normally, cross out words, shade, and sketch. Confirm that scratch erase does not remove ink by mistake.
- Create a text box. Confirm that creating it does not open the keyboard. Tap the text box with a finger. Confirm that this action opens the keyboard. Confirm that Pencil input does not open the keyboard or become typed text.
- Use freehand and boxed lasso around complete and partial strokes, text boxes, and shapes. Move a mixed selection and resize it. Confirm that text size and shape line width change with the selection. Confirm that the fixed PDF background does not move.
- Compare quick writing with Apple Notes on the same iPad and Pencil. Check palm contact, scrolling, and saving during writing.

The source now flushes live canvas ink before it restores a scratch erase. The surface keeps an incoming drawing revision pending while local ink is active, then applies it after those changes are committed. These source corrections preserve newer ink during Undo. The user later passed immediate scratch Undo after new writing, as recorded below.

Simulator checks can confirm controls and saved results. They cannot prove Pencil writing quality, palm handling, or reliable scratch erase on the iPad.

## Check record

- `git rev-parse --show-toplevel` and `git rev-parse --path-format=absolute --git-common-dir` found the active and original root at `/Users/samarthab/Dev/Personal-Note-app-for-iPad`.
- `git -C /Users/samarthab/Dev/Personal-Note-app-for-iPad rev-parse --show-toplevel` confirmed the original root.
- `git status --short --branch` showed branch `issue-2-implementation`, no commits, and the existing untracked `.DS_Store`, `AGENTS.md`, `CONTEXT.md`, and `docs/`. These files were preserved.
- `gh issue view 1 --repo SamarthaB10/Personal-Note-app-for-iPad --json number,title,body,state,url,comments` and the same command for issue 2 read the complete issue bodies and comments. Issue 2 is open and has no blocking issue.
- `xcode-select -p`, `xcodebuild -version`, `swiftc --version`, and `xcrun --sdk iphoneos --show-sdk-path` and `xcrun --sdk iphonesimulator --show-sdk-path` were run. The first check used Command Line Tools and had no iOS SDK. The user later downloaded and selected Xcode 27.0.
- `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.0-simulator -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk prototypes/CanvasPrototype/CanvasPrototype/CanvasPageModels.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasSelectionGeometry.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasPageStore.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasKeyboardTextView.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasScratchGestureRecognizer.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasFingerGestureRecognizer.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasSurfaceView.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasPrototypeRootView.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasPrototypeApp.swift` passed with exit code 0.
- `swiftc -parse prototypes/CanvasPrototype/CanvasPrototype/CanvasPageModels.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasSelectionGeometry.swift prototypes/CanvasPrototype/CanvasPrototype/CanvasPageStore.swift` passed.
- `plutil -lint prototypes/CanvasPrototype/CanvasPrototype.xcodeproj/project.pbxproj` passed. Python `xml.etree.ElementTree` parsed `prototypes/CanvasPrototype/CanvasPrototype.xcodeproj/xcshareddata/xcschemes/CanvasPrototype.xcscheme` without an error.
- `git diff --check` printed no errors. `git diff --no-index --check /dev/null docs/implementation/canvas-prototype.md` printed no whitespace errors and returned 1 because the new file differs from `/dev/null`.

The initial iOS 26 simulator SDK typecheck passed for all prototype Swift files. The generic simulator build passed with this command: `xcodebuild -quiet -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/CanvasSurfaceDerived build CODE_SIGNING_ALLOWED=NO`. This build used the iOS 27 simulator SDK and iOS 26 deployment target. The app has no verified simulator UI workflow yet. No unit or integration tests were written. GitHub and Apple Developer documentation were read through external websites. These initial source and simulator checks preceded the authorized physical installation recorded above.

The combined lasso and keyboard correction passed the all-file native check: `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.0-simulator -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.0.sdk prototypes/CanvasPrototype/CanvasPrototype/*.swift`. The signed incremental build used the physical command above. Build, install, launch, and capture returned exit 0. Capture: `/private/tmp/ipad-notes-lasso-keyboard-preview.png`, shown in the main thread. The user later passed typing, Save/Reopen, both lasso modes, mixed movement and proportional resize, complete-item selection, selected-content Delete, and fixed PDF checks. Direct drag and clearer text-box choice were requested after these passes and are not covered by them.

`plutil -lint prototypes/CanvasPrototype/CanvasPrototype.xcodeproj/project.pbxproj` and `git diff --check` passed. No-index whitespace checks passed for the 11 Swift/evidence text files; exit 1 without output is expected for comparison of a new file with `/dev/null`. Native Lucide paths add no runtime dependency.

During this session an external process committed and pushed `9be65c9` on `issue-2-implementation`. The user then authorized `main` at that existing commit as the PR base. `git push origin 9be65c9:refs/heads/main` and `gh repo edit SamarthaB10/Personal-Note-app-for-iPad --default-branch main` passed. The active checkout stayed on `issue-2-implementation`. Existing committed documents and `.DS_Store` files were preserved. No PR has been created yet.

Apple signing services were used for the authorized free iPad installation. No database, cloud note storage, paid service, or production deployment was used. GitHub was read and the authorized base branch was created; no issue was assigned, labeled, commented on, or closed.

The physical checks were open at this earlier record. The final pass below permits the canvas choice.

## Direct drag and text-box choice update

The user requires movement by a drag inside selected handwriting after a freehand lasso. The dashed loop stays visible. A nearby bar supplies Resize, Delete, and Clear. The surface renders a temporary UIKit preview during movement and changes the editable page once at the end. It restores the prior drawing if the gesture is cancelled. The PDF background stays outside the transform.

Stacked and nearby text boxes use an explicit list with text previews, box numbers, and position hints. A preview highlights its box. Edit or Select confirms one box. Preview does not start keyboard editing.

The settled all-source native typecheck passed with the command recorded above. Earlier concurrent checks returned an error because the geometry source changed while the compiler read it; the settled check returned exit 0. The signed incremental physical build, read-only local snapshot, installation, foreground launch, and capture all returned exit 0. The first capture showed a launch transition; the next showed the Home Screen. A second explicit foreground launch and capture showed the app and its saved content. A process check found the app running. This does not establish a passed gesture check.

Commands used the physical forms above. The second launch added `--activate`. Captures are `/private/tmp/ipad-notes-direct-drag-preview.png`, `/private/tmp/ipad-notes-direct-drag-settled-preview.png`, and `/private/tmp/ipad-notes-direct-drag-relaunch-preview.png`. The last was shown in the thread with display orientation corrected by HTML. The raw images stay outside commits. The read-only editable snapshot is `/private/tmp/ipad-notes-direct-drag-before-install.json`; its contents were not printed.

Two native review workers stopped at provider usage limits and produced no review. Fresh Sol Medium T3 review workers completed source reviews of the full staged and working diff from `9be65c9`. Standards found one highlight case: an active editor could cover the target highlight. Spec found three cases: a resize target could overlap small selected ink; a tap on already selected stacked boxes could move both; and a nearby blank tap could open the keyboard for a single candidate. These findings were corrected before the final reviews and physical pass recorded below. The source reports alone did not approve the physical gate.

New manual requests cover direct finger and Pencil drag, space between strokes, fresh selection beside old content, individual text-box choice and stable typing, mixed resize, fixed PDF content, and the remaining writing comparison, palm, scrolling, eraser, and immediate scratch Undo checks. The user then reported that freehand lasso moves written words, and passed individual text-box choice, typing, and Save/Reopen. The user also answered All checked and pass for the writing comparison while saving, palm contact, scrolling, manual widths, both erasers, and immediate scratch Undo after new writing. Ink Delete failed: the selected S and whole written words remained. The user also rejected large controls and empty box guides. These failures required a correction and another physical check; the earlier selected-content Delete pass did not cover this ink Delete failure. Issue 2 remained active at that stage. Issue 3 has not started. Finger pinch zoom and the user's zoom references are saved for issue 4, with the current full-width view as the default.

No unit or integration tests were written or run. No new dependency was added. GitHub was read and Apple signing services were used for the authorized local iPad installation. No database, cloud note storage, paid service, or production deployment was used. No new commit, push, PR, or issue mutation was made in this continuation.

The next surface correction gives selected content priority over resize targets, moves the resize handle outside content when possible, treats movement below 8 logical points as a tap before opening an overlapping-box chooser, and draws candidate highlights above the editor. The nearby action bar now uses screen-size controls, and unselected text/shape guides are removed. A single nearby text-box candidate needs chooser confirmation unless the tap actually hits its frame. Ink Delete now removes valid selected indices when stored ink is unchanged during the flush. If the flush changes ink, it preserves that ink and shows a visible reselect message. The single-stroke serialization guard was a suspected cause; its behavior was not measured separately. These source changes were installed in the final correction recorded below.

The corrected all-source native typecheck returned exit 0. Parser checks and whitespace checks passed for the worker changes. `plutil -lint prototypes/CanvasPrototype/CanvasPrototype.xcodeproj/project.pbxproj` returned exit 0. Two fresh Sol Medium final source reviews then covered all review corrections and the ink Delete correction. Their completed results are recorded below.

## Final combined physical pass

On 9 October 2026, the user answered All pass for the installed correction: both lasso modes select and Delete an S or whole word; Save/Reopen keeps the result; unselected ink and fixed PDF content stay intact; direct drag, mixed resize, individual text-box choice, smaller nearby controls, and removal of empty guides work. This resolves the latest ink Delete failure. The earlier explicit user passes for stable typing, the Apple Notes comparison while saving, palm contact, scrolling, widths, both erasers, scratch-and-hold, ordinary cross-outs/sketches, and immediate scratch Undo remain recorded above.

The latest settled all-source typecheck and signed incremental build returned exit 0. Installation, explicit foreground launch, and capture returned exit 0. The actual capture is `/private/tmp/ipad-notes-delete-fix-preview.png` and was shown in the thread. The before capture and read-only editable snapshot are `/private/tmp/ipad-notes-delete-before-preview.png` and `/private/tmp/ipad-notes-delete-before-install.json`. No note data was printed or overwritten through a device copy command. Logs have the `ipad-notes-delete-fix-` prefix in the temporary directory.

Both fresh Sol Medium round-5 source reviews found no remaining findings. Reports: `/private/tmp/ipad-notes-direct-drag-standards-final-review-round5.md` and `/private/tmp/ipad-notes-direct-drag-spec-final-review-round5.md`. They include the new direct-drag, chooser, resize priority, tap threshold, highlight, control-size, guide, and ink Delete changes. Earlier failed review turns are not counted as passed reviews.

`git diff --check`, `git diff --cached --check`, project plist lint, and local Markdown link checks passed. The combined physical gate for issue 2 is complete. The prototype supplies the verified canvas basis; it does not implement the later library, notebook, PDF import/export, Trash, or editable backup workflows. No unit or integration tests were written or run.
