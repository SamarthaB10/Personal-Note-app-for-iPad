# Personal iPad Notes

This guide contains project rules. Use the inherited global guide for personal preferences, task workflow, safety, branches, and PR procedures.

## Read before work

- Read [CONTEXT.md](CONTEXT.md) for domain terms. Use these terms in code, UI, and documentation.
- Read [the accepted design](docs/design/notes-app.md) before feature or architecture work. Its complete first-version scope and accepted decisions define the required behavior. The interview is complete; distinguish an implementation question from an already accepted product choice.
- Read [ADR 0001](docs/adr/0001-free-native-local-app.md) before changing platform, cost, installation, or storage choices. Read other relevant files in `docs/adr/` when they exist.
- Read [the initial research](docs/research/free-local-ipad-notes.md) for source evidence when evaluating frameworks, installation, or backup. Its early proposal for separate text and ink sections was replaced by the accepted text-box design. Use the accepted design when the documents differ.


#icons:
For icons use the lucide icons -> I have an mcp here : /Users/samarthab/Dev/lucide-icons-mcp

## Current state

The repository contains design and research documents only. There is no app code, Xcode project, package manifest, build script, test suite, or CI configuration. Check the current files before using this statement in later tasks. Do not invent commands, source directories, or an implemented architecture.

The app is for one person on one iPad. It must use native Apple tools, store notes locally, and have no fees or paid services. ADR 0001 records the accepted standalone app and weekly free Personal Team installation method. Offline note use and installation are separate concerns.

## Implementation boundaries

- Use the glossary's folder → notebook → page hierarchy. Keep product folders distinct from storage directories. Unfiled is the built-in folder; custom folders have one level.
- Keep the complete accepted scope in the design document. A small prototype can verify a technical choice, but it does not reduce the first-version scope. Features visible in reference images are required only when the design accepts them.
- SwiftUI, UIKit, PencilKit, PDFKit, and PaperKit are candidates described in the documents. The final canvas and storage format are not selected. Verify the required behavior before recording a framework choice as settled.
- The reported target is an iPad 10th generation, iPadOS 26.7.1, and Apple Pencil USB-C. Confirm the actual device and SDK for implementation. Keep manual ink widths; the design must not depend on pressure input.
- For canvas work, read the design's scratch erase, keyboard-only text, and lasso findings. Verify these behaviors together on the target iPad before committing to the canvas. Check Apple API availability against the target OS; do not use iPadOS 27-only model access for the reported iPadOS 26 target.
- Preserve direct Pencil input during saving, thumbnail generation, and PDF rendering. Smooth writing and reliable scratch erase are core requirements. Do not claim that Scribble or a framework's default lasso supplies all accepted behavior without verification.

## Content and recovery boundaries

- Keep imported source PDFs unchanged. Original PDF content is a fixed background; user-added ink, text boxes, and shapes remain separate editable content.
- PDF export and editable backup serve different purposes. Export includes the visible page content and appearance. Restore an editable backup as separate copies, preserving existing notebooks.
- Keep deletion and recovery consistent with the design: Trash supports restoration, a folder and its notebooks move together, and a notebook retains at least one page.
- Keep note storage and manual backups local. App-local storage alone does not prove exclusion from device cloud backup. Use the research's backup findings when evaluating this boundary; do not promise device-only storage from a backup-exclusion flag.

## Verification by change

- **Documents only:** check statements against the source documents, check local links, and run `git diff --check`. For a new untracked file, also run `git diff --no-index --check /dev/null AGENTS.md`, replacing `AGENTS.md` with the new file's path. Code builds are not required for document edits.
- **App code, once present:** use the actual project's build and check commands. First inspect `xcode-select -p` and `xcodebuild -version` when Xcode is needed. Command Line Tools alone do not provide an iPad app build. Identify the real project and scheme before giving an `xcodebuild` command.
- **Behavior changes:** use the relevant manual scenarios under “Required behavior checks for a future build” in the accepted design. Cover persistence and recovery when storage changes, and source preservation and visible content when PDF handling changes.
- **Pencil or gesture changes:** verify on the physical target iPad and Pencil. Compare writing with Apple Notes on that device. A build or simulator check cannot establish handwriting quality or reliable scratch erase. Report missing device verification as a limit.

## Maintain this guide

Keep this guide within 900 words. Replace obsolete facts when code, commands, or decisions become available. Keep detailed acceptance criteria in the design, terminology in CONTEXT.md, and decision reasons in ADRs. Add behavior lessons only with evidence from two separate sessions, an explicit user decision, or a confirmed safety risk. Propose guide changes during unrelated tasks instead of adding rules silently.
