# Personal Notes

This native iPad app opens a local notebook library. Unfiled and custom folders each contain a notebook cover grid and a Create card. Create Folder adds a folder at one level. Move changes a notebook's folder. Home saves and returns to its current folder. A new notebook opens with seven ordered blank pages. The notebook uses continuous vertical scroll. Add Page in the top bar inserts after the current page. The bottom control appends after the last page. Both stop at 300 pages per notebook. Finger pinch changes the page zoom; the controls keep their size. The app saves editable ink, including shapes, and text boxes in its local Application Support directory.

The combined physical canvas checks passed on the target iPad and Pencil on 9 October 2026. [ADR 0002](../../docs/adr/0002-pencilkit-app-owned-page-content.md) records the selected PencilKit and app-owned content approach. The [canvas check record](../../docs/implementation/canvas-prototype.md) contains those commands, user results, and source review limits. The [notebook check record](../../docs/implementation/local-notebooks.md) records the separate issue 3 physical pass. A simulator build alone cannot verify Pencil smoothness, palm behavior, or scratch-erase reliability.

## Build

Open `CanvasPrototype.xcodeproj` in Xcode and select the shared `CanvasPrototype` scheme. The target supports iPad and requires iPadOS 26.0 or later. It has no third-party package or paid service.

To build for an available iPad simulator from the repository root:

```sh
xcodebuild -list -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj
xcodebuild -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination 'platform=iOS Simulator,name=<iPad simulator name>' -derivedDataPath /tmp/CanvasPrototypeDerivedData build
```

Replace `<iPad simulator name>` with a name listed by Xcode. Signing is disabled in the project settings. For the authorized physical installation, Xcode uses the user's free Personal Team and enables signing through build options. The app display name is Personal Notes; the project, scheme, and bundle identifier keep their existing names so an update preserves installed app data.

## Local notebook storage

The `PersonalNotes` storage directory contains a library index, one directory per notebook, seven page files for each new notebook, and generated cover images. Page files contain editable PencilKit ink and app-owned text and shapes. The page IDs in the index define page order. Notebook creation publishes the index only after its seven page files are saved.

Page changes save automatically through a serial background queue and atomic file replacement. Cover rendering uses a separate background queue. Back waits for the notebook content to save. A page surface flushes pending ink before it leaves the scroll view. Invalid or missing saved pages produce a visible error and are preserved. The old prototype page and PDF fixture remain separate; new notebooks have no sample content or PDF background.

Local storage does not prove exclusion from device cloud backup. Trash, editable backup, and recovery remain later work.

## Manual checks

1. In Unfiled, select Create and enter a notebook name. Confirm that the notebook opens with seven blank pages. Scroll to write a different mark on pages 1, 4, and 7. Add pages at the end, mark them, and confirm their order after reopening. Return to the library and confirm its title, cover, and folder count. Reopen the app offline and confirm the membership, page count, order, and editable marks.
2. Tap Pen or Marker to use its remembered settings. Press and hold that tool to set its own manual width and color. Tap Eraser to use its remembered mode. Press and hold Eraser to choose Partial or Object. Confirm each control changes the active tool. Write while saving and while the cover updates. Compare the feel with Apple Notes on the same iPad and Pencil.
3. Draw several ink strokes. Press and hold the ink tool to open its settings and turn Scratch erase off, then on. Scratch and hold over one ink stroke, and use Undo. Confirm that the last scratch erase returns.
4. Write a crossed-out word and make a quick sketch. Check that ordinary writing does not trigger scratch erase.
5. Select Text box, then tap the page to add a text box. Tap the box to edit it. If more than one box is close to the tap, choose a preview, check the highlighted box, then select Edit text box. Confirm that only that box opens for typing and Pencil contact does not open the keyboard. Select Done to finish editing.
6. Press and hold Shapes. Choose Triangle, Square, Circle, Arrow, Rectangle, Line, or Ellipse, then drag on the page. Confirm that each shape uses the remembered width and color. Check Partial erase, Object erase, scratch-and-hold with Undo, and lasso Delete. Shapes are ordinary ink strokes. Confirm that new notebook pages stay blank behind the added content.
7. Tap Lasso to use its remembered mode. Press and hold to choose Freehand or Box lasso. Touch ink to select and drag the complete touched stroke. A partial loop also selects complete touched strokes. Enclose text boxes to select complete objects. A short tap selects one object. If text boxes overlap or are close, choose a text preview, check its highlighted box, then confirm Select text box. Drag inside selected handwriting or an object to move the selection. Drag the round handle to resize, or select Resize in the nearby bar. The bar also has Delete and Clear. Selection has movement buttons and proportional scaling controls. Confirm Delete affects only selected added content.
8. Write without a manual save action. Leave the app, close it, then open it again offline. Confirm that saved ink, text boxes, shapes, paper, and the scratch setting remain. The notebook editor has no Save or Reopen button.
9. On the physical target iPad, compare fast handwriting while saving with Apple Notes. Check palm contact, scrolling, scratch erase, Undo, keyboard-only text, and both lasso modes together. Record any behavior that fails or remains unverified.

Choose blank, lined, or grid paper for a page and a notebook default for new pages. Check light and dark modes without changing saved ink colors. Pinch out to see a centered whole page with dark space outside it, and pinch in to write at a larger scale. Check the visible zoom percentage.

The [issue 4 check record](../../docs/implementation/notebook-pages.md) separates new verification from the passed earlier checks. The [folder record](../../docs/implementation/notebook-folders.md) records the folder implementation and pending physical checks. PDF import/export, Trash, and editable backup remain later issues. The complete accepted first-version scope remains required.
