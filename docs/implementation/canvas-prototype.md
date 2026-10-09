# Issue #2: native canvas prototype

Date: 9 October 2026.

## Result

The prototype source uses PencilKit for ink. It keeps text boxes and shapes in app-owned data. A local PDF page supplies the fixed background. The source saves the editable page in the app's local Application Support folder.

This is a candidate implementation. It does not select the final canvas or storage format. The design requires the scratch erase, keyboard-only text, and mixed-content lasso checks together on the target iPad before that choice is settled.

## API facts

- `PKCanvasView.drawingPolicy` supports Pencil-only input. Apple added this policy in iOS 14. The prototype does not change `drawingGestureRecognizer.allowedTouchTypes`. [PencilKit input policy](https://developer.apple.com/videos/play/wwdc2020/10107/)
- `PKStroke.renderBounds` includes line width and the stroke transform. Stroke path interpolation, stroke transforms, and `maskedPathRanges` are available before iPadOS 26. The lasso and scratch code use these APIs. Apple describes `maskedPathRanges` in its PencilKit inspection session. [Stroke bounds](https://developer.apple.com/documentation/pencilkit/pkstroke-swift.struct/renderbounds), [stroke path interpolation](https://developer.apple.com/documentation/pencilkit/pkstrokepath-swift.struct/interpolatedpoints%28in%3Aby%3A%29), [PencilKit stroke inspection](https://developer.apple.com/videos/play/wwdc2020/10148/)
- `UIScribbleInteractionDelegate.scribbleInteraction(_:shouldBeginAt:)` can refuse Scribble. The app must also require a direct finger tap before it opens keyboard editing. [Scribble delegate](https://developer.apple.com/documentation/uikit/uiscribbleinteractiondelegate)
- PDFKit can provide a page overlay from iOS 16. The current prototype renders a local PDF fixture as the fixed page background and stores added content separately. It does not edit the source PDF. [PDF page overlays](https://developer.apple.com/documentation/pdfkit/pdfpageoverlayviewprovider)
- PencilKit provides bitmap and vector erasers. Apple does not document a scratch-and-hold erase API. The prototype uses a custom Pencil gesture recognizer. Its latency and false-erase rate need a physical-device check. [PencilKit eraser types](https://developer.apple.com/documentation/pencilkit/pkerasertype)
- PaperKit is available from iPadOS 26, but its combined behavior is not verified here. Do not use `PaperMarkup.subelements`, PaperKit's element-ID selection, or `PKCanvasView.selection`; those APIs require or are marked for iPadOS 27. [PaperKit](https://developer.apple.com/documentation/paperkit), [PaperMarkup subelements](https://developer.apple.com/documentation/paperkit/papermarkup/subelements), [PaperKit selection](https://developer.apple.com/documentation/paperkit/papermarkupviewcontroller/selection), [PencilKit selection](https://developer.apple.com/documentation/pencilkit/pkcanvasview/selection)

## Device and tool facts

The Mac first used Command Line Tools at `/Library/Developer/CommandLineTools`. `xcodebuild -version` failed because Xcode was not selected. The user later downloaded and selected Xcode 27.0, build 27A266a. The iOS 26.5 simulator runtime is installed. The app has no verified simulator UI workflow yet.

`devicectl` confirmed the connected iPad is an iPad (10th generation) on iPadOS 26.7.1. Developer Mode is enabled. The Apple Pencil USB-C model is user-reported; the connected Pencil model was not independently verified. The user authorized physical prototype installation and checks. The free Personal Team build is signed, installed, trusted, and running on the iPad.

## Physical check record: 9 October 2026

- The first installed build showed a black page. The custom item overlay was opaque. The saved correction makes that overlay transparent and clears its dirty drawing area.
- A signed incremental build of the correction, physical installation, foreground launch, and screen capture all returned exit 0. The corrected screen shows the white fixed PDF background and saved ink, text boxes, and a rectangle. Capture: `/private/tmp/ipad-notes-fixed-app-preview.png`. This file is outside the repository and was shown in the main thread.
- The user selected Pen and drew a new line with the Pencil. The user reported: “The line appears normally.” This passes basic visible Pencil input. It does not establish writing quality, palm handling, or the complete canvas gate.
- The user rejected the small centered page and large controls. The user requires the writing page to use the available iPad screen. The editor layout correction is in progress. The current page fits to viewport height and is too small.
- Save/Reopen with the new line, app relaunch, scratch erase and Undo, keyboard-only text, both mixed lasso modes, and the Apple Notes writing comparison remain unverified in this session.
- Earlier final review attempts failed because of provider usage limits. Do not report a passed final review from those attempts.

Issue 2 remains open. Issue 3 must wait for the combined physical canvas checks to pass.

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

The source now flushes live canvas ink before it restores a scratch erase. The surface keeps an incoming drawing revision pending while local ink is active, then applies it after those changes are committed. These source corrections preserve newer ink during Undo. They are not passed manual checks.

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

The iOS 26 simulator SDK typecheck passed for all prototype Swift files. The latest generic simulator build passed with this command: `xcodebuild -quiet -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/CanvasSurfaceDerived build CODE_SIGNING_ALLOWED=NO`. This build used the iOS 27 simulator SDK and iOS 26 deployment target. The app has no verified simulator UI workflow yet. No unit or integration tests were written. GitHub and Apple Developer documentation were read through external websites. No database, cloud service, deployment, paid tool, or app installation was used. The user enabled Developer Mode after authorizing physical prototype checks.

The physical iPad and Pencil checks remain open. Do not record a final canvas choice until these checks pass.
