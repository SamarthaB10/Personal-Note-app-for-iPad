# Notebook pages, paper, and zoom

Issue: [4](https://github.com/SamarthaB10/Personal-Note-app-for-iPad/issues/4).

The notebook uses continuous vertical scrolling. Add Page follows the last page. The user also requested Add Page in the top bar to insert a page immediately after the current page. New blank notebooks still start with seven pages. The user changed the maximum to 300 pages per notebook during this work; this replaces the ticket's earlier no-limit rule. Both controls stop adding at 300.

Each page has blank, lined, or grid paper. A notebook default applies to new pages. Existing JSON files without these fields open with blank paper. A new page is saved before its ID is published in the library index. Creation, page insertion, append, and default-paper changes share a serial mutation permit. Failed writes preserve existing files and show an error. An unpublished new page can remain for later recovery.

Finger pinch changes the zoom from 25% to 300%. The initial view fills the available width at 100%. Smaller pages are centered horizontally with dark space outside them. The header, toolbar, Add Page control, and selection controls keep their physical size. The current zoom percentage stays visible. The scroll view keeps nearby page surfaces and retains page stores when those surfaces leave the view. It flushes pending ink before safe removal and retains a surface during active Pencil or page-path input.

Light and dark appearance are saved locally. Dark mode uses dark writing paper. The user requested black as the default for new writing in light mode and white in dark mode. The active neutral writing color follows that change; other selected colors remain. The shared palette uses fixed colors, and appearance changes do not rewrite saved ink. Source PDF content remains fixed; PDF import and its color checks remain issue 9.

Short tool taps use remembered settings. Press and hold opens settings for that tool. Pen and Marker have separate widths and colors. Eraser remembers Object or Partial mode, and Lasso remembers Freehand or Box mode. The scrollable panel has 32 labeled colors and a selected mark. Tool settings are saved in local UserDefaults and shared across notebook pages. Page changes save automatically; Save and Reopen controls are removed from the requested editor flow. Home uses the save-gated return to the library; custom folder routing remains issue 5.

Initial lasso contact can select and immediately move one complete touched ink stroke. Partial loops can select complete touched strokes without full enclosure. There is no word recognition or stroke grouping. Visible text boxes keep object hit priority, and text boxes remain separate complete objects. The text-box chooser, explicit keyboard entry, mixed movement, proportional resize, Delete, and fixed PDF boundary remain required.

Triangle, Square, Circle, Arrow, Rectangle, Line, and Ellipse are precomputed PencilKit ink strokes. Each uses the chosen width and color. Partial erase, Object erase, scratch-and-hold with Undo, and lasso Delete use the same paths as handwriting. Existing rectangle objects convert together after page validation. Conversion preserves their position, color, width, existing ink, and text. A conversion failure preserves the saved page and disables writing with an error.

## Checks

- `xcode-select -p`: `/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild -version`: Xcode 27.0, build 27A266a.
- `xcodebuild -list -json -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj`: identified project and scheme `CanvasPrototype`.
- `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.0-simulator -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.0.sdk prototypes/CanvasPrototype/CanvasPrototype/*.swift`: passed after the final source changes, with no warnings. The surface now uses native trait-change registration.
- `plutil -lint prototypes/CanvasPrototype/Configuration/Info.plist prototypes/CanvasPrototype/CanvasPrototype.xcodeproj/project.pbxproj`: passed.
- `git diff --check`: passed. Whitespace checks for all seven new text files also passed.
- Local Markdown link check: all ten links passed.
- `xcodebuild -quiet -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination id=<device> -derivedDataPath /private/tmp/CanvasPrototypeSignedBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<team> -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`: passed, exit 0. Device and team values were read privately.
- Two fresh parallel GPT-6.1-Sol Medium reviews checked standards and issue scope. Round 1 found crossing-stroke drag, text-box tap tolerance, and finger-path conflicts with scrolling. These were corrected. Round 2 found no issues.

Signed installation, launch, and screenshot capture passed, each with exit 0:

- `xcrun devicectl device install app --device <device> /private/tmp/CanvasPrototypeSignedBuild/Build/Products/Debug-iphoneos/CanvasPrototype.app --timeout 60`
- `xcrun devicectl device process launch --device <device> com.samarthab.CanvasPrototype --timeout 30 --terminate-existing --activate`
- `xcrun devicectl device capture screenshot --device <device> --destination /private/tmp/ipad-notes-issue4-physical.png --timeout 30`

The screenshot stays outside the repository. The user reported that the other native features work, but tool settings could not be opened to change colors, widths, or modes. The user also requested removal of Save and Reopen in favor of automatic saving. This is a partial physical result, not an issue 4 All pass. The hold-action correction and automatic-save flow need a focused physical check after the next installation. The issue 2 and issue 3 physical passes remain recorded in [the canvas record](canvas-prototype.md) and [the notebook record](local-notebooks.md).

The user passed the other native features in the first issue 4 physical check. The next check is limited to the tool hold correction, the expanded palette and neutral color change, automatic saving without manual controls, Home to the containing folder, insertion after the current page, and shapes with their erase actions. These changes are implemented. The complete updated Swift source typecheck passed with no warnings, and the signed physical build passed with exit 0. Fresh round-3 Standards and Spec reviews found no errors. The updated build was installed and launched, each with exit 0, while later feature workers continued. Screenshot capture also passed. The new physical behavior check remains pending; the earlier round-2 reviews cover the earlier source snapshot.

No unit or integration tests were written or run. No runtime dependency was added. GitHub and public Apple documentation were read. No database, note cloud service, paid service, production deployment, or device setting change is part of this work. Local app storage does not prove exclusion from device cloud backup.

Multiple custom folders remain issue 5. The user's request to delete each notebook is covered by issue 11: move to Trash, restore, or explicitly delete permanently. Keep numeric issue order.
