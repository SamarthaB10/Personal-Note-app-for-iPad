# Canvas Prototype

This native iPad app contains one editable prototype page. The page combines Pencil input, keyboard text boxes, a rectangle, and a fixed PDF background. It saves page content to the app's local Application Support folder.

The combined physical canvas checks passed on the target iPad and Pencil on 9 October 2026. [ADR 0002](../../docs/adr/0002-pencilkit-app-owned-page-content.md) records the selected PencilKit and app-owned content approach. The [check record](../../docs/implementation/canvas-prototype.md) contains commands, user results, and source review limits. This one-page prototype does not reduce the approved first-version app scope. A simulator build alone cannot verify Pencil smoothness, palm behavior, or scratch-erase reliability.

## Build

Open `CanvasPrototype.xcodeproj` in Xcode and select the shared `CanvasPrototype` scheme. The target supports iPad and requires iPadOS 26.0 or later. It has no third-party package or paid service.

To build for an available iPad simulator from the repository root:

```sh
xcodebuild -list -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj
xcodebuild -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'platform=iOS Simulator,name=<iPad simulator name>' -derivedDataPath /tmp/CanvasPrototypeDerivedData build
```

Replace `<iPad simulator name>` with a name listed by Xcode. The prototype uses simulator signing disabled in the project settings. Do not install it on a physical iPad without separate authorization.

## Manual checks

1. Select Pen and Marker. Open Eraser for Partial eraser and Object eraser. Set different manual widths and colors. Confirm each control changes the active tool.
2. Draw several ink strokes. Open Width for tool settings and turn Scratch erase off, then on. Scratch and hold over one ink stroke, and use Undo. Confirm that the last scratch erase returns.
3. Write a crossed-out word and make a quick sketch. Check that ordinary writing does not trigger scratch erase.
4. Select Text box, then tap the page to add a text box. Tap the box to edit it. If more than one box is close to the tap, choose a preview, check the highlighted box, then select Edit text box. Confirm that only that box opens for typing and Pencil contact does not open the keyboard. Select Done to finish editing.
5. Select Rectangle and drag on the page. Confirm that the source PDF background remains fixed.
6. Open Lasso for Freehand or Box lasso. Enclose complete ink strokes, text boxes, and the rectangle. A short tap selects one object. If text boxes overlap or are close, choose a text preview, check its highlighted box, then confirm Select text box. Drag inside selected handwriting or an object to move the selection. Drag the round handle to resize, or select Resize in the nearby bar. The bar also has Delete and Clear. Selection has movement buttons and proportional scaling controls. Confirm Delete affects only selected added content and leaves the PDF unchanged.
7. Select Save, close and reopen the app, then select Reopen. Confirm that saved ink, text boxes, shapes, and the scratch setting remain.
8. On the physical target iPad, compare fast handwriting while saving with Apple Notes. Check palm contact, scrolling, scratch erase, Undo, keyboard-only text, and both lasso modes together. Record any behavior that fails or remains unverified.

The app does not include folders, notebooks, multiple pages, PDF import/export, Trash, or editable backup. These remain part of the approved app scope outside this one-page prototype.
