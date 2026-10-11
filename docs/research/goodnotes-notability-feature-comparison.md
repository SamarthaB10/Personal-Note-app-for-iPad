# Goodnotes and Notability feature comparison

Date: 11 October 2026.

App source: `7f5aadeacfdf7299a9a4d64a6ce4ee049395c5ed` on `main`.

## Main finding

The app already has the main writing and PDF annotation tools. The final targets are clear organization, good PDF reading, complete copy and paste, strong lasso controls, clean UI/UX, smooth file transfer, and free personal use. DX is treated as developer experience. Audio, quizzes, and other study tools are excluded at the user’s request.

All recommended designs can keep the master notebook local and use no paid service. The user also permits optional import and export through Google Drive. A copy sent to Drive is stored in the cloud by that explicit choice; ordinary writing remains local. These are proposals, not changes to the accepted scope or proof of completed behavior.

## Evidence and limits

This comparison uses the app's source code and the competitors' official feature guides. It is not a binary decompilation or a runtime comparison. No Goodnotes or Notability package was supplied. The Goodnotes filename search and the application-directory check found no local Goodnotes app. Neither competitor was installed or run.

The invoked REA skill requires separate treatment of observations, inferences, and unknowns. No REA analysis tool is connected in this session. `npx -y rea-agents@6.3.0 doctor --client codex --json` returned exit code 1. It reported missing Codex registration and missing native analysis engines. No configuration was changed. Thus, there are no REA Evidence IDs. The source and guide references below are the evidence for this report.

“Missing” means that no implementation was found in the 39 tracked Swift source files, their models and controls, and the scene configuration. The installed iPad build was not compared with this commit. Competitor guides can describe features that vary by version, platform, plan, or phased release.

## Features already present

Source inspection found Pencil ink, manual widths and colors, highlighter, object and partial erasers, scratch-and-hold erase, Undo, keyboard-only text boxes, seven explicit shape types, and freehand and boxed lasso. Mixed selections can move, resize, and delete. Photos images can be added, moved, resized, deleted, copied, and pasted.

The app also has PDF and image-background import, insertion of PDF pages into a notebook, current-page and full-notebook PDF export, vertical scrolling, pinch zoom, blank/lined/grid paper, light/dark appearance, custom folders and colors, and Trash restoration. These are not feature gaps. Sources: C1–C6 below.

## Recommended order for the final targets

### 1. Library organization and a page manager

**Source observation:** Folders, colors, a notebook cover grid, Move, and Trash exist. The cover menu has Move and Delete. No notebook or folder Rename action, notebook Duplicate action, visible sort control, list-view option, pinned view, or recent-notebook view was found. The notebook model has a creation date, but no last-opened or last-edited field. Sources: C3, C4, and C9.

**Competitor evidence:** Notability offers folder rename, note sorting, list/grid layouts, and drag movement. Goodnotes and Notability both provide page managers. Current Notability uses Folders; old Subjects and Dividers guides apply to earlier versions. [Notability organization](https://support.gingerlabs.com/en-us/articles/16300020-organize-notes-with-folders), [Notability page manager](https://support.gingerlabs.com/en-us/articles/16300226-content-manager-and-bulk-actions).

**Proposed local design:** Keep folders → notebooks → pages. Add notebook and folder Rename, notebook Duplicate, visible sorting, and bulk Move. Provide All Notebooks, Recent, and Pinned as views of existing notebooks; these do not make duplicate storage or another folder hierarchy. Offer list and grid layouts. Show a clear title, page count, and last edit date. Keep Create and Import visible. Add tags only if folders, search, and pinned notebooks do not meet a real need.

#### Page controls within a notebook

**Source observation:** The Pages control contains numbered buttons. Notebook cover images exist, but no page-thumbnail browser was found. No page reorder, duplicate, rotate, bookmark, or custom outline action was found. Sources: C3 and C4.

**Competitor evidence:** Goodnotes provides page thumbnails, drag reorder, bookmark filtering, and multiple-page actions. It also supports named outline entries that jump to a page. [Goodnotes Sidebar](https://support.goodnotes.com/hc/en-us/articles/9497798035983-Use-the-Sidebar-to-navigate-your-document), [Goodnotes outlines](https://support.goodnotes.com/hc/en-us/articles/7353757101071-Create-and-manage-document-outlines).

Notability also provides page copy between notes, duplicate, bookmarks, and PDF-page rotation. [Notability page actions](https://support.gingerlabs.com/en-us/articles/16300226-content-manager-and-bulk-actions).

**Proposed local design:** Start with thumbnails, drag reorder, Duplicate Page, page copy between notebooks, and bookmarks. Later add named sections, such as “Chapter 4”. Use stable page IDs for navigation. Preserve the current 300-page limit; it is an accepted choice. Also add notebook Rename and Duplicate, which were not found in the cover menu.

### 2. Complete copy and paste, strong lasso, and Redo

**Source observation:** The shared history keeps seven Undo entries and has no Redo action. The lasso supports mixed movement and scaling, but its Copy action copies images only. No complete ink/text/image selection copy, cut, recolor, or rotation action was found. Sources: C5 and C6.

**Competitor evidence:** Goodnotes provides Undo and Redo, plus lasso cut, copy, duplicate, recolor, and rotation actions. [Goodnotes Undo and Redo](https://support.goodnotes.com/hc/en-us/articles/14069931315983-Quick-gestures-for-Undo-and-Redo), [Goodnotes lasso actions](https://support.goodnotes.com/hc/en-us/articles/7353695644175-Select-Move-and-Edit-Content-With-the-Lasso-Tool).

Notability also supports selected-ink copy, cut, paste, style changes, rotation, and grouping. Its guide does not establish every action for mixed ink, typed text, and images. [Notability ink editing](https://support.gingerlabs.com/en-us/articles/16300114-handwriting-and-math-conversion).

**Proposed local design:** Add Redo and an app-owned clipboard for selected ink, text boxes, and images. Permit paste onto another page. Then add Duplicate, recolor, rotation, and selection filters for ink, text boxes, and images. Keep a quick action bar beside the selection: Copy, Cut, Paste, Duplicate, Delete, and More. Keep movement immediate and resize handles clear. Grouping and alignment guides can follow if needed. Keep imported PDF content fixed. A copied image is not a copy of the complete editable selection.

### 3. PDF reading quality

**Source observation:** PDF import, fixed source backgrounds, annotation, pinch zoom, and PDF export exist. Source PDFs are retained. Screen display uses a bounded image of the PDF page at 1224 × 1584 pixels. No PDF text-selection/search layer, PDF outline view, or clickable PDF-link layer was found. Sources: C1, C3, and C7.

**Inference:** Fine PDF text may lose clarity when zoomed far into that image. This is a reason for a device check, not a measured defect. Evaluate resolution-aware page rendering or tiles while keeping Pencil input responsive. Keep annotations separate from the original PDF.

**Competitor evidence:** Goodnotes supports PDF hyperlinks and outlines. Notability displays imported PDF outlines on iPad, iPhone, and Mac. [Goodnotes PDF links](https://support.goodnotes.com/hc/en-us/articles/13623343439631-Open-hyperlinks-in-imported-PDFs), [Goodnotes outlines](https://support.goodnotes.com/hc/en-us/articles/7353757101071-Create-and-manage-document-outlines), [Notability PDF outlines](https://support.gingerlabs.com/en-us/articles/16300018-pdf-outlines).

**Proposed local design:** Add in-PDF search, text selection and copy, outline navigation, internal page links, and page bookmarks. Add a reading mode that permits scrolling, zoom, text copy, and link use without accidental annotation. Validate small text at high zoom before changing the renderer. PDF text copy is separate from lasso copy of the user's ink.

### 4. Clean UI/UX for the library and editor

**Source observation:** The app already has folder colors, notebook previews, accessible 44-point controls, and a movable, collapsible toolbar. The toolbar can dock on an edge. Its scroll region combines navigation, destructive page actions, import/export, writing tools, paper, and appearance. Selected content opens an additional action panel. Sources: C3, C5, and C9. No current app screenshot was captured; these are source observations, not a visual or usability score.

**Competitor evidence:** Goodnotes lets users show, hide, and reorder many tools and dock floating menus. Notability's page manager places page navigation, search, bookmarks, and page actions together. [Goodnotes toolbar settings](https://support.goodnotes.com/hc/en-us/articles/8900755183631-Customize-the-toolbar), [Notability page manager](https://support.gingerlabs.com/en-us/articles/16300226-content-manager-and-bulk-actions).

**Proposed design:** Use one calm visual system with consistent type, spacing, icon size, selection color, and menu treatment. Make the folder and notebook location clear. Show notebook Rename, Move, Duplicate, and Export in an accessible action menu. Keep frequently used Pen, Eraser, Lasso, Undo/Redo, color, and width easy to reach. Move less frequent page and file actions into clear menus. Preserve existing docking, keyboard-only text, tap targets, and immediate lasso movement. Any change to the accepted compact-header layout is a proposal for a later design task.

Judge the result with real tasks: find an old notebook, open a bookmarked PDF page, copy a diagram to another notebook, change selected ink color, and export selected pages. Verify landscape, portrait, narrow windows, long names, dark mode, and selection controls that do not hide the content. A visual audit needs screenshots or a running app in a later task.

### 5. Search for notebooks and content

**Source observation:** No search UI, search index, PDF text extraction, or recognition code was found. Sources: C3 and C7.

**Competitor evidence:** Goodnotes searches titles, typed text, handwriting, outlines, and PDF text. It does not add OCR to imported PDFs that lack searchable text. Notability also lists handwriting search. [Goodnotes search guide](https://support.goodnotes.com/hc/en-us/articles/7353743594127-How-to-Search-Your-Notes), [Notability search](https://support.gingerlabs.com/en-us/articles/16300170-search), [Notability handwriting search](https://support.gingerlabs.com/en-us/articles/16300114-handwriting-and-math-conversion).

**Proposed local design:** First search notebook titles and stored text-box text. Then extract searchable PDF text with PDFKit. Add page results that open the correct location. Evaluate local OCR for handwriting and image-only pages after the first search stage works. Keep recognized text as a separate index; keep Pencil writing as ink.

Apple states that Vision APIs run on the device and can extract text from images. This supports a local approach, but it does not prove Goodnotes-level handwriting accuracy. Recognition of the user's handwriting and equations needs a physical-device check. [Apple Vision session](https://developer.apple.com/videos/play/wwdc2025/272/), [PDFPage text APIs](https://developer.apple.com/documentation/PDFKit/PDFPage).

### 6. File portability and editable archives

**Source observation:** Native Files import already copies PDF or image sources into local storage. Native Files export already saves a PDF copy through `UIDocumentPickerViewController(forExporting:asCopy:)`. This is a useful existing base. It has current-page and whole-notebook scopes, but no selected-page range, editable archive, batch notebook export, or system share-sheet action was found. Sources: C1, C2, and C10.

**External evidence:** Apple supports Google Drive and other third-party providers in Files after their apps are installed and enabled. Thus, a Files-provider route is the first option to verify. It does not require a separate Drive API or app-owned sign-in system. Actual import/export through the user's Drive provider was not tested. [Apple Files providers](https://support.apple.com/en-us/102238), [Apple export picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(forexporting:ascopy:)).

**Proposed local design:** Provide PDF for use in other apps and an editable archive for restore in this app. Add selected-page export, batch export from the library, useful filenames, progress, cancellation, and clear results. Offer Save to Files and Share. Preserve readable text, page order, appearance, and PDF navigation metadata where supported. Keep the original imported file unchanged. After import, reopen the local notebook offline. Treat a Drive destination as an optional copy; do not add continuous sync.

The current PDF exporter draws ink as images. Searchable handwriting and PDF-link preservation in the output are not established. Validate the exported file in another PDF viewer. An app archive preserves app editability; it does not imply that Goodnotes or Notability can import that archive. Their proprietary formats require separate compatibility work.

#### Editable archive and restore

**Source observation:** Export uses `NotebookPDFExporter`. Trash Restore recovers items already in the app's storage. No editable-backup writer or backup-import reader was found. The README also says that editable backup remains later work. This is already a requirement in the accepted design. Sources: C1 and C2.

**Competitor evidence:** Goodnotes can export a full-library backup ZIP and import it for restoration. Notability's Note format preserves editable content; its PDF format serves a different purpose. [Goodnotes manual backup](https://support.goodnotes.com/hc/en-us/articles/7353694866831-Back-up-and-restore-your-library-manually), [Notability backup formats](https://support.gingerlabs.com/en-us/articles/16300117-auto-backup-third-party-backup-guide).

**Proposed local design:** Save a versioned archive to On My iPad. Include notebook order, folder membership and colors, editable ink, text boxes, images, and original imported files. Restore as separate copies, as the accepted design requires. A copy on the same iPad helps recovery from app errors; it cannot recover a lost iPad. An optional copy to a Mac or USB drive also avoids cloud storage.

### Later: a PDF and a notebook shown together

**Source observation:** The library holds one open notebook. The scene plist explicitly disables multiple app scenes. Sources: C3 and C8.

**Competitor evidence:** Goodnotes supports multiple iPad windows and document tabs. Notability's Multi-Note can show two notes together in horizontal or vertical layouts. [Goodnotes windows](https://support.goodnotes.com/hc/en-us/articles/7353757107215-Open-Goodnotes-in-multiple-windows-on-iPadOS), [Notability getting started](https://intercom.help/notability/en-us/articles/16042362-getting-started-with-notability).

**Proposed local design:** Show a textbook PDF beside a working notebook. This needs no server. Start with two notebooks in one app window if that meets the need. Multiple app windows require shared-store coordination, especially when both show the same notebook; changing the plist alone is not a complete solution.

## Other useful additions

| Addition | Current source finding | Useful local version |
| --- | --- | --- |
| Zoom writing panel | Pinch zoom exists; no separate panel or automatic advance found. | Magnify a small writing region and advance it across a line. Goodnotes documents this behavior in its [Zoom Window guide](https://support.goodnotes.com/hc/en-us/articles/7353756826383-Write-with-the-Zoom-Window). |
| Reusable elements and templates | Three paper types and imported backgrounds exist; no saved collection found. | Save a graph, formula, diagram, or page layout for local reuse. [Goodnotes Elements](https://www.goodnotes.com/blog/elements-stickers-sticky-notes). |
| Internal links and PDF navigation | PDFs are displayed as rendered images; no clickable PDF layer or internal link model found. | Link to another notebook page and honor imported PDF page links. External website links need a network only when opened. [Goodnotes internal links](https://support.goodnotes.com/hc/en-us/articles/7353743248143-Create-external-and-internal-links), [PDF hyperlinks](https://support.goodnotes.com/hc/en-us/articles/13623343439631-Open-hyperlinks-in-imported-PDFs). |
| Draw-and-hold shapes | Explicit shape tools exist; no shape recognizer found. | Make a clean line or shape after a hold. Keep shapes as ordinary ink if that preserves the current erase behavior. [Goodnotes shapes](https://support.goodnotes.com/hc/en-us/articles/13682939148943-Draw-shapes-and-build-diagrams-in-Goodnotes). |

Goodnotes' latest diagram guide includes features that can be released in stages. This report does not claim that every Goodnotes installation has them.

Audio, quizzes, tape-based study tools, cloud sync, live collaboration, paid AI services, and a marketplace are outside the final targets. Handwriting-to-text conversion also conflicts with the accepted keyboard-only text choice. Read-only recognition for search is a separate proposal. Keep the one-level folder design unless the user changes that choice.

## Free use and DX

Keep the app's writing, organization, search, and restore functions independent of a paid service. Use native frameworks and optional Files providers. The current project has no third-party package dependency. This can avoid recurring feature fees, but it is not a promise that Apple's installation rules will never change.

Apple's current free Personal Team profiles expire after seven days and require rebuild and reinstall. That is an installation constraint already accepted in ADR 0001; adding the proposed features does not remove it. [Apple Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account/), [ADR 0001](../adr/0001-free-native-local-app.md).

For DX, preserve the existing import adapter, export snapshot, serial write, and app-owned content boundaries. Add focused interfaces for page order, editable archives, the app clipboard, and a rebuildable search index only when each feature needs them. Keep file-provider calls at the adapter boundary. UI components should issue actions and display progress or errors, rather than write the library directly. Record archive format versions and migration rules. Keep the Xcode scheme and build instructions accurate. Update stale guide statements during a separate authorized documentation task.

Keep the current ink engine unless evidence shows it cannot meet the new behavior. The first implementation pass should establish navigation and data actions before adding new animations or a large dependency. Physical checks must cover smooth writing while saving, rendering, searching, and exporting. No unit or integration tests were added because the user did not request them.

## Source ledger

Paths are relative to this report. Line numbers refer to the inspected commit.

- **C1:** [PDF export control](../../prototypes/CanvasPrototype/CanvasPrototype/NotebookExportToFilesControl.swift), lines 11–35; [PDF renderer](../../prototypes/CanvasPrototype/CanvasPrototype/NotebookPDFExporter.swift), lines 244–255. Ink is rendered as images for export.
- **C2:** [Notebook store](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasNotebookStore.swift), lines 796–842, for Trash restoration; [README](../../prototypes/CanvasPrototype/README.md), for the stated backup limit; [accepted design](../design/notes-app.md), for editable local backup and restore as separate copies.
- **C3:** [Library](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasLibraryView.swift), lines 8–34 and 182–211; [editor controls](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasPrototypeRootView.swift), lines 124–153.
- **C4:** [Notebook models](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasNotebookModels.swift), lines 50–87; [page actions](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasNotebookView.swift), lines 148–241.
- **C5:** [Selection controls](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasSelectionActionsView.swift), lines 13–60; [selection transforms](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasSelectionGeometry.swift), lines 148–197; [page store](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasPageStore.swift), lines 358–398.
- **C6:** [Undo history](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasUndoHistory.swift), lines 4–46; [page tool and shape models](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasPageModels.swift), lines 6–36 and 119–171.
- **C7:** Whole-source search, UI inspection, and model inspection. Negative findings are limited to the inspected app source. [PDF background renderer](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasImportedContent.swift), lines 104–125, confirms image display.
- **C8:** [Scene configuration](../../prototypes/CanvasPrototype/Configuration/Info.plist), lines 7–8.
- **C9:** [Folder controls](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasFolderListView.swift), lines 16–35; [floating toolbar](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasFloatingToolbar.swift), lines 12–75; [notebook filter](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasNotebookStore.swift), line 285.
- **C10:** [Files import picker](../../prototypes/CanvasPrototype/CanvasPrototype/CanvasImportFilesView.swift), lines 146–180; [Files export picker](../../prototypes/CanvasPrototype/CanvasPrototype/NotebookExportToFilesControl.swift), lines 98–132.

## Investigation status

- Existing app feature inventory: answered from source; runtime behavior remains unverified.
- Important Goodnotes gaps: answered from official guides and the inspected source.
- Important Notability gaps: answered from its page manager, search, ink editing, PDF outline, folder, export, and Multi-Note guides.
- Organization, UI/UX, portability, free use, and DX: answered as source-backed proposals. Actual appearance, task usability, and Drive-provider behavior remain unverified.
- Audio and study tools: excluded by the user; no implementation recommendation remains.
- Local and free implementation choices: proposed; no new API implementation was tested.
- Competitor binary behavior, recognition quality, and installed-build parity: unresolved. These need supplied app artifacts or an observed iPad session.

## Checks and changes

The user authorized the clone into the empty workspace. Instruction discovery found the global guide and repository `AGENTS.md`; no parent or nested guide applied. No selected instruction file was unreadable. Some guides still describe a documents-only repository; the current source was used instead.

Commands run included:

```sh
git clone https://github.com/SamarthaB10/Personal-Note-app-for-iPad .
git rev-parse --show-toplevel
git rev-parse --path-format=absolute --git-common-dir
git -C /Users/samarthab/Dev/IpadNotes rev-parse --show-toplevel
git status --short --branch
git rev-parse HEAD
git ls-files '*.swift'
rg --files
rg --files -g 'AGENTS.md' -g 'AGENTS.override.md'
rg -n -i '\b(search|searchable|bookmark|rename|reorder|duplicate|backup|AVAudio|AVFoundation|flashcard|tape|openWindow|PDFView|VNRecognizeTextRequest|Vision|template|redo)\b' prototypes/CanvasPrototype/CanvasPrototype -g '*.swift'
npx -y rea-agents@6.3.0 doctor --client codex --json
```

Git confirmed the repository and commit. The bounded feature search returned only a comment about future backup. Focused `cat`, `sed`, and `rg -n` reads checked the functions and controls listed in the source ledger. The REA diagnosis failed for the stated environment limits. An old Goodnotes Zoom Window URL failed to fetch; the current URL linked from its support index worked.

No app code, tests, project settings, accepted design, or ADR was changed. No build or physical-device check was needed for this document; no runtime claims are made. Public GitHub, Goodnotes, Notability, and Apple websites were used. No database, private cloud service, production data, or deployment was used. A modified tracked `.DS_Store` appeared during read-only work and was preserved.

Generated artifacts: this research report and an inline HTML comparison. The report is the only intended repository addition.

Final document checks:

```sh
git diff --check
git diff --no-index --check /dev/null docs/research/goodnotes-notability-feature-comparison.md
git diff --stat
git status --short --branch
```

Both whitespace checks passed with exit code 0. A Python link check resolved all 22 local Markdown links; none was missing. `git diff --stat` showed only the unrelated tracked `.DS_Store` change. `git status` also showed the new research report. Source files, project settings, and existing documents were unchanged.

The HTML comparison was rendered with `html_preview` at widths 728 and 360 pixels. Both previews showed six rows with no console errors. Manual image review found readable table columns on the wide view and stacked rows on the narrow view. These are checks of the report visual, not checks of the iPad app. `html_render` publishes the final comparison in the thread.
