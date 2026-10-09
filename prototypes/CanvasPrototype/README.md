# Personal Notes

This native iPad app opens a local notebook library. Unfiled contains a notebook cover grid and a Create card. A new notebook opens with seven ordered blank pages. The Pages menu opens each page. The app saves editable ink, text boxes, and rectangles in its local Application Support directory.

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

Page writes use a serial background queue and atomic file replacement. Cover rendering uses a separate background queue. Back and page changes wait for the current content to save. Invalid or missing saved pages produce a visible error and are preserved. The old prototype page and PDF fixture remain separate; new notebooks have no sample content or PDF background.

Local storage does not prove exclusion from device cloud backup. Trash, editable backup, and recovery remain later work.

## Manual checks

1. In Unfiled, select Create and enter a notebook name. Confirm that the notebook opens with seven blank pages. Use Pages to write a different mark on pages 1, 4, and 7. Return to the library and confirm its title, cover, and folder count. Reopen the app offline and confirm the membership, page count, order, and editable marks.
2. Select Pen and Marker. Open Eraser for Partial eraser and Object eraser. Set different manual widths and colors. Confirm each control changes the active tool. Write while saving and while the cover updates. Compare the feel with Apple Notes on the same iPad and Pencil.
3. Draw several ink strokes. Open Width for tool settings and turn Scratch erase off, then on. Scratch and hold over one ink stroke, and use Undo. Confirm that the last scratch erase returns.
4. Write a crossed-out word and make a quick sketch. Check that ordinary writing does not trigger scratch erase.
5. Select Text box, then tap the page to add a text box. Tap the box to edit it. If more than one box is close to the tap, choose a preview, check the highlighted box, then select Edit text box. Confirm that only that box opens for typing and Pencil contact does not open the keyboard. Select Done to finish editing.
6. Select Rectangle and drag on the page. Confirm that new notebook pages stay blank behind the added content.
7. Open Lasso for Freehand or Box lasso. Enclose complete ink strokes, text boxes, and the rectangle. A short tap selects one object. If text boxes overlap or are close, choose a text preview, check its highlighted box, then confirm Select text box. Drag inside selected handwriting or an object to move the selection. Drag the round handle to resize, or select Resize in the nearby bar. The bar also has Delete and Clear. Selection has movement buttons and proportional scaling controls. Confirm Delete affects only selected added content.
8. Select Save, close and reopen the app, then select Reopen. Confirm that saved ink, text boxes, shapes, and the scratch setting remain.
9. On the physical target iPad, compare fast handwriting while saving with Apple Notes. Check palm contact, scrolling, scratch erase, Undo, keyboard-only text, and both lasso modes together. Record any behavior that fails or remains unverified.

Custom folders, continuous page scrolling, Add Page, pinch zoom, paper choices, PDF import/export, Trash, and editable backup remain later issues. The complete accepted first-version scope remains required.
