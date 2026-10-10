# Personal iPad notes: first-version design

Status: Confirmed by Samartha on 9 October 2026, with the issue 4 changes recorded below. The design interview is complete. The canvas and local notebook implementation passed the recorded physical checks in [the canvas record](../implementation/canvas-prototype.md) and [the notebook record](../implementation/local-notebooks.md).

Repository: https://github.com/SamarthaB10/Personal-Note-app-for-iPad

## Complete first-version scope

- Native app for one iPad, with no fees or paid services. All notes stay local. The user accepts the weekly free build and installation task.
- Custom folders plus built-in Unfiled. Each contains notebooks; each notebook contains pages. Show notebooks in a cover grid.
- New blank notebooks open with seven pages. Scroll vertically and add pages at the end, up to 300 pages per notebook.
- Smooth Pencil writing with Apple-style ink tools, manual widths, colors, partial erase, and object erase.
- Scratch-and-hold erase for handwritten ink, enabled by default with an on/off option and one-step Undo.
- Text Box option with movable and resizable boxes. Open the keyboard only after the user explicitly taps a box. Never convert Pencil writing to text.
- Basic line, arrow, rectangle, and ellipse tools.
- Freehand and boxed lasso for complete ink strokes, text boxes, and shapes. Touching ink or drawing a partial loop selects the touched complete stroke. Mixed selections move and resize together proportionally. Original PDF content stays fixed.
- Import each PDF as a separate notebook, with its actual page count. Write, type, and add shapes over its pages without changing the source file.
- Export the current page or an entire notebook as PDF, with visible ink, text, and shapes in page order. Preserve the displayed paper appearance and the source PDF's colors.
- Blank, lined, and grid paper. Light and dark modes.
- Trash and restore for deleted content. A folder and its notebooks are deleted and restored together. Keep at least one page per notebook.
- Manual editable local backup and restore. Restore as separate copies, preserving existing notebooks.

The detailed accepted decisions and source findings follow. The canvas technology remains to be verified against the combined input requirements; this does not change the required behavior.

## Stated requirements

- One user, on an Apple iPad.
- Use native iOS/iPadOS tools.
- No app fee, subscription, paid server, paid API, or paid developer membership.
- Store notes locally on the iPad.
- Support smooth Apple Pencil handwriting and keyboard text entry.
- Create a notebook and open it.
- Start each new blank notebook with seven pages.
- Permit more pages to be added to each notebook, up to 300 pages. Device storage remains a real limit.
- Create folders to organize notebooks.
- Provide drawing tools similar to those in Apple Notes, including an eraser.
- Provide object erasing and partial erasing.
- Provide ink colors.
- Provide light and dark modes.
- Delete items when requested.
- Import PDFs and write on their pages.
- Export a complete notebook as a PDF, including handwriting, typed text, and shapes, in page order.
- Extremely smooth handwriting is a key requirement.
- Scratch-to-erase is a key requirement, with a user option to control it. Its accepted targets and trigger are recorded below.
- Keep regular partial erasing and object erasing alongside scratch erase.
- Provide a Text Box option in the toolbar. Select it to add a box, then explicitly tap that box to open the keyboard and type.
- Text entry is keyboard-only. Do not convert Apple Pencil handwriting to typed text, and do not open the keyboard merely because the Pencil touches a page.
- Provide a lasso tool. The user selects it, circles page content, and can move or resize the selection. Ink, typed text boxes, and shapes must be supported. Original PDF content remains a fixed background.

## Reference images

The two Freenotes images show a folder sidebar and notebook/PDF cover grid. They are visual references, not requirements for login, payment, a store, an academy, or a whiteboard.

The FinderSearch image shows a different app. Its role in this design is not established.

Two later Freenotes images show a lasso settings panel with freehand and boxed modes, and a circled handwritten selection with Resize and other actions. Use them to define lasso behavior. AI, tape, and image import are not added to the scope solely because they appear in the screenshots.

## Accepted decisions: round one

The user accepted all recommendations from the first round.

- A separate native app with its own icon. The user accepts the weekly free build and installation task.
- Continuous vertical page scrolling. An Add Page control follows the last page.
- Movable text boxes, including on PDF pages.
- Each imported PDF creates a separate notebook. Its initial page count matches the PDF, rather than the seven-page rule for blank notebooks.
- One folder level, with notebooks movable between folders.
- Delete moves an item to Trash. Restore and Delete Permanently are available.
- Dark mode uses dark blank writing pages. PDFs retain their original colors. A mode change preserves saved ink colors.
- Both different ink tools and basic geometric shapes.
- Target device: iPad, 10th generation. The user reports iPadOS 26.7.1 and confirms Apple Pencil USB-C.

## Accepted decisions: round two

The user accepted all seven recommendations.

- Keep imported source PDFs unchanged; export a separate copy with visible added content.
- Provide manual editable backup and restore through On My iPad. Do not add cloud backup.
- Move a deleted folder and its notebooks to Trash together. Show a confirmation first. Restore brings them back together.
- Deleted pages can be restored through Trash. Keep at least one page per notebook.
- Offer blank, lined, and grid paper. Each notebook has a default paper type for new pages.
- Offer font size and color, with text box move, resize, edit, and delete actions.
- Offer explicit line, arrow, rectangle, and ellipse tools. Draw-and-hold shape recognition can wait.

## Folder structure

Use the hierarchy shown in the reference images: folders contain notebooks, and notebooks contain pages. A folder can contain several notebooks. Selecting a folder shows its notebook cover grid. Creating a notebook in that folder adds it to the grid and opens it.

The user can create custom folders. Unfiled is the built-in folder for notebooks that are not placed in a custom folder. It replaces the proposed General folder. Every notebook belongs to either Unfiled or one custom folder. Creating a custom folder is not required before creating a notebook.

## Accepted decisions: round three

The user accepted Q18 through Q21 and replaced the Q22 recommendation.

- Scratch erase removes handwritten ink only. Text boxes, geometric shapes, and original PDF content remain unchanged.
- Scratch erase is on by default, with a settings toggle. Scratch then hold triggers it. One Undo restores each erase.
- Export either the current page or the complete notebook. Preserve the displayed page appearance and all visible content; original PDF page colors stay unchanged.
- Restore editable backups as separate copies. Do not overwrite existing notebooks.
- Use Unfiled rather than an initial General folder, with custom folders created by the user.

## Accepted decisions: round four

The user accepted Q23 through Q27.

- Lasso selects user-added page content. Original PDF text and images remain the fixed page background.
- Typed text is selected as a complete text box, rather than individual words. Editing text still requires an explicit text-box tap.
- Provide both freehand and boxed selection.
- Select complete strokes and objects enclosed by the lasso. Crossing a stroke does not cut it at the selection boundary.
- Move ink, text boxes, and shapes together. Resize a mixed selection proportionally, including the typed text size.

## Final review

Samartha confirmed that the complete first-version scope above matches the intended app on 9 October 2026. No interview choices remain open. The design interview is complete. This confirmation does not authorize deployment or changes to device settings.

## Accepted changes during issue 4

These explicit user changes replace the earlier page-limit and ink-enclosure rules. Other accepted content boundaries remain in effect.

- Put Add Page after the last page, including the initial seventh page. Append pages in order, up to 300 pages per notebook. Show the limit when the notebook reaches 300 pages.
- Also put Add Page in the top bar. This control inserts a new page immediately after the current page, so writing can be added between existing pages. Keep the bottom control for appending. Both use the notebook default paper and the 300-page maximum.
- Use finger pinch to zoom. The default view fills the available width. Zoom out to show a centered whole page with dark space outside it. Zoom in to enlarge writing. Keep controls the same size and show the zoom percentage.
- Lasso contact or a quick partial loop selects the touched complete ink stroke. Do not select a whole word through recognition or stroke grouping. Do not cut a stroke. Attach direct movement immediately, without a Move action or menu wait. Text boxes remain separate complete objects.
- A short tool tap activates its remembered settings. Press and hold opens settings for that tool. The eraser remembers Object or Partial mode. Each ink tool remembers its own width and color. Provide more color choices.
- Save page changes automatically. Do not show Save or Reopen controls in the notebook editor. Show a save error when a write fails. In the user's physical feedback, "hard-click" on a tool means press and hold to open its settings.
- Provide a broad color palette. Default to black for new writing in light mode and white in dark mode. When the writing color is black in light mode, switch it to white on entering dark mode. Use the reverse change on returning to light mode. Keep other selected colors and all saved marks unchanged.
- Offer triangle, square, circle, and arrow shapes. Shapes are precomputed ink strokes, with the chosen width and color. Partial erase, object erase, scratch-and-hold, and lasso Delete act on these strokes like handwriting. Preserve existing added shapes when converting them to ink. This replaces the earlier rule that kept added shapes separate from scratch erase. Text boxes and original PDF content stay protected from scratch erase.
- For the later import work, show Create or Import File in the library. Permit PDF and image backgrounds with editable annotations. The notebook's plus control also offers Import PDF into the existing notebook. Import only the pages that fit within its remaining 300-page capacity, in source order. Keep the original file unchanged and report the imported count when pages are omitted. Parallel preparation does not change numeric issue order.
- Show explicit Import from Files and Export to Files controls. Import uses the native Files picker. Export saves the current page or complete notebook as a PDF with visible content and appearance. The native Files destination choice lets the user save the exported copy.
- Show a small Home button at the top of each notebook. It returns to that notebook's containing folder after saving. For an Unfiled notebook, return to Unfiled. From a custom folder, the user can then return to the folder list.
- Keep multiple custom folders in issue 5, after issue 4. Each folder shows its own notebook grid.

The issue 4 ticket still states no fixed page limit. The later explicit instruction sets a maximum of 300 pages for each notebook. This document records the current requirement without changing the ticket.

## Accepted library UI changes on 10 October 2026

- Put a Trash icon at the bottom of the folder sidebar. Keep its accessible name and access to recovery.
- Put the current-page trash icon beside Home. A tap opens Delete current page and asks Are you sure? Delete moves that page to Trash. Keep the final page.
- Put custom folder Delete in the sidebar folder's press-and-hold menu. Confirm before moving the folder and its notebooks to Trash. Remove Delete folder from the notebook grid header.
- Offer a named color palette for custom folders. Save the color locally and preserve it during folder Trash restore. Old folders without a color use blue. Keep saved writing colors unchanged.
- Keep notebook Delete and Move in the same press-and-hold menu on the notebook cover.

## Required behavior checks for a future build

These are manual scenarios, not automated tests. No unit or integration tests are requested.

- Create a custom folder and a notebook. Confirm that it opens with seven pages and appears in that folder's grid. Create a notebook without a custom folder and confirm it appears in Unfiled.
- Reach the last page and add another page. Reopen the notebook and confirm its page order and content remain intact.
- Write quickly while the app saves. Compare the writing feel with Apple Notes using the same iPad and Pencil. Check palm contact and scrolling without unintended ink.
- Use each eraser mode. Scratch and hold over handwriting, then Undo. Confirm that normal crossed-out words and sketches do not trigger unintended erase actions.
- Use the Text Box option, then tap a box to type. Confirm that Pencil writing never becomes typed text and never opens the keyboard by itself.
- Lasso mixed ink, text boxes, and shapes. Move and resize them together. Confirm that original PDF content stays fixed and text editing does not start during selection.
- Import a PDF, add content, and export both one page and the notebook. Inspect page order, positions, colors, and inclusion of all visible added content. Confirm the imported source file is unchanged.
- Delete and restore pages, notebooks, and a folder with notebooks. Confirm that the final page cannot be deleted on its own.
- Make an editable backup and restore it as copies. Confirm existing notebooks are unchanged and restored ink and text remain editable.
- Reopen notes without internet access. Confirm local persistence and inspect backup settings for the device-only requirement.

Passing a build or simulator check cannot establish Pencil smoothness or reliable scratch erase on the physical iPad. These requirements remain unverified until the device checks pass.

## Smooth writing and scratch erase

Treat smooth writing and scratch erase as core behavior, not optional extras. Preserve direct Pencil input while saving, generating page thumbnails, and rendering PDFs. Do not make a successful app build stand in for a handwriting check on the user's physical iPad.

Verify normal handwriting, crossing out text, shading, and fast sketches against scratch recognition. False erase actions must be recoverable through the accepted one-step Undo behavior.

No numeric latency target or native scratch-erase capability has been confirmed yet. Do not promise that Apple's Scribble text gestures erase PencilKit drawing strokes. Compare normal writing against Apple Notes on the same iPad and Pencil during physical-device checks.

## Design tree

- Free, native, local app
  - Run method -> installation and update process
  - Storage boundaries -> backup and recovery behavior
- Notebook
  - Navigation -> add-page control and page position
  - Page content
    - Typed text layout -> editing and selection
    - Lasso -> PDF boundary, selection units, and mixed-content transforms
    - Drawing tools -> shapes, tool settings, and erasing
      - Scratch erase -> recognition, target content, and recovery
  - PDF import -> page ownership, annotation storage, and export
- Folder
  - Folder structure -> moving notebooks and folder deletion
- Deletion
  - Recovery choice -> page, notebook, and folder rules
- Appearance
  - Writing surface colors -> ink and PDF readability

## Documentation and verification

The glossary is in [CONTEXT.md](../../CONTEXT.md). Earlier source research is in [the research report](../research/free-local-ipad-notes.md).

No app code or tests have been created. No device settings, database, cloud service, or deployment has been changed. Public Apple documentation is being checked for tool and installation facts.

- `git rev-parse --show-toplevel` and `git rev-parse --path-format=absolute --git-common-dir`: active and original repository are the same folder.
- `git -C /Users/samarthab/Dev/Personal-Note-app-for-iPad rev-parse --show-toplevel`: confirmed the original root.
- `git remote get-url origin`: matches the GitHub URL supplied by the user.
- `git status --short --branch`: existing research preserved; glossary and interview notes are new, untracked files.
- `git diff --check`: passed for tracked files; the new untracked documents were read and checked manually.
- `xcode-select -p`: returned `/Library/Developer/CommandLineTools`.
- `xcodebuild -version`: failed because the active tools are Command Line Tools, not Xcode. This is an environment check, not an app build failure.
- T3 `device_list`: found no devices. The tool reported failures from `xcrun simctl list devices --json` and `avdmanager list avd`. The user later supplied the target iPad model and iPadOS version; they were not verified on a connected device.

## Confirmed installation facts

Apple's free Personal Team provisioning profiles expire after seven days. A standalone app then needs a new build and installation. [Apple account limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

Swift Playground can run an app playground in its own window on the iPad. This is a different use method from a separately installed app. [Apple run instructions](https://support.apple.com/guide/playgrounds-ipad/run-your-app-itc650868b1f/ipados).

## Confirmed drawing and PDF facts

PencilKit provides ink tools, colors, and widths. Tool availability depends on the iPadOS version. Its vector eraser removes whole ink strokes. Its bitmap eraser removes portions of ink. These erasers do not remove typed text or original PDF content. [Ink tools](https://developer.apple.com/documentation/pencilkit/pkinkingtool-swift.struct/inktype-swift.enum), [Eraser modes](https://developer.apple.com/documentation/pencilkit/pkerasertype?language=objc).

Apple's PaperKit adds shapes and text boxes alongside drawing. The base framework was introduced for iPadOS 26. Newer APIs have separate availability limits. The reported target OS permits evaluation of the base framework; it does not authorize use of newer beta APIs. PencilKit alone does not provide every Apple Notes feature. [Meet PaperKit](https://developer.apple.com/videos/play/wwdc2025/285/), [PaperKit documentation](https://developer.apple.com/documentation/paperkit).

PDFKit supports drawing views over PDF pages from iOS 16. An overlay does not automatically save its ink into the PDF. We must select a storage and export design. A PDF with marks permanently added to its page content serves a different purpose from an editable notebook. [Apple PDFKit session](https://developer.apple.com/videos/play/wwdc2022/10089/).

The iPad 10th generation supports Apple Pencil 1st generation and Apple Pencil USB-C. The user confirms the USB-C model. It supports tilt, but does not support pressure sensitivity. The app must permit manual ink width selection and must not depend on pressure input. [Apple compatibility](https://support.apple.com/en-us/108937), [Pencil comparison](https://www.apple.com/uk/apple-pencil/).

## Scratch erase: source findings

Apple Notes supports scratching and holding the Pencil down to delete handwriting. This is distinct from the Scribble gesture that deletes typed text. [Apple Notes handwriting guide](https://support.apple.com/en-us/121259), [Apple Scribble session](https://developer.apple.com/videos/play/wwdc2020/10106/).

The source check did not find a documented scratch-erase setting in PencilKit's canvas or PaperKit's controller and feature list. This does not prove the feature is unavailable. Verify the behavior in a small native prototype on the target iPad before promising framework support. [PencilKit canvas](https://developer.apple.com/documentation/pencilkit/pkcanvasview), [PaperKit controller](https://developer.apple.com/documentation/paperkit/papermarkupviewcontroller), [PaperKit feature list](https://developer.apple.com/documentation/paperkit/featureset/feature).

PencilKit exposes drawing gestures and completed ink strokes. These may support a custom recognizer, but that is an implementation approach to verify, not a complete Apple scratch-erase API. UIKit's touch cancellation and recognizer rules can affect latency or leave temporary scratch ink. These risks are inferences from the APIs. [Drawing gesture](https://developer.apple.com/documentation/pencilkit/pkcanvasview/drawinggesturerecognizer), [Drawing strokes](https://developer.apple.com/documentation/pencilkit/pkdrawing-swift.struct/strokes), [Touch cancellation](https://developer.apple.com/documentation/uikit/uigesturerecognizer/cancelstouchesinview).

PaperKit's direct subelement model access requires iPadOS 27. Do not select that API for the reported iPadOS 26 target. [PaperKit model access](https://developer.apple.com/documentation/paperkit/papermarkup/subelements).

## Keyboard-only text: source findings

For an app-owned UIKit text input view, UIScribbleInteraction's delegate can refuse Scribble through `scribbleInteraction(_:shouldBeginAt:)`. Do not rely on an undocumented `isEnabled` property. Explicit focus control is also needed so that only a text-box tap starts keyboard editing. [Apple Scribble delegate](https://developer.apple.com/documentation/uikit/uiscribbleinteractiondelegate), [Apple example](https://developer.apple.com/videos/play/wwdc2020/10106/).

The PaperKit feature source check did not find a separate Scribble switch for its internal text editor. Verify keyboard-only behavior before selecting PaperKit's built-in text boxes. The user's input rule takes priority over a framework choice. [PaperKit features](https://developer.apple.com/documentation/paperkit/featureset/feature).

## Lasso: source findings

PaperKit's selection touch mode selects strokes and elements. Its selectedMarkup and transformContent APIs are available on iPadOS 26. This makes it a candidate for mixed-content selection. It does not confirm the requested freehand gesture, selection boundary rules, or shared resize handles without a device check. [Selection mode](https://developer.apple.com/documentation/paperkit/papermarkupviewcontroller/touchmode/selection), [Selected markup](https://developer.apple.com/documentation/paperkit/papermarkupviewcontroller/selectedmarkup), [Content transform](https://developer.apple.com/documentation/paperkit/papermarkup/transformcontent(_:)).

The element-ID selection property and subelements access require iPadOS 27. They are different from the iPadOS 26 selectedMarkup API. [Selection IDs](https://developer.apple.com/documentation/paperkit/papermarkupviewcontroller/selection), [Subelements](https://developer.apple.com/documentation/paperkit/papermarkup/subelements).

PencilKit's lasso operates on its canvas content. Do not assume it selects separate app-owned text boxes and shapes. An app-owned mixed-content lasso would need common selection and transform behavior for those items and ink. [PencilKit lasso](https://developer.apple.com/documentation/pencilkit/pklassotool-swift.struct), [Drawing model](https://developer.apple.com/documentation/pencilkit/pkdrawing-swift.struct).

PDFSelection supports selection of original PDF text, but it is not an API for moving or resizing original printed text and images. Editing those objects would add a different PDF editing requirement. The user must confirm this boundary. [PDFSelection](https://developer.apple.com/documentation/pdfkit/pdfselection), [PDF interactions](https://developer.apple.com/documentation/pdfkit/document-interactions).

Before choosing the final canvas, verify mixed-content lasso, keyboard-only text entry, and scratch erase together on the target iPad. Neither a successful build nor confirmation of one feature proves all three work together.
