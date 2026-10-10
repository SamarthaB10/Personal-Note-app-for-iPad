# Scratch erase and Undo

Issue: [7](https://github.com/SamarthaB10/Personal-Note-app-for-iPad/issues/7).

The accepted scratch implementation is already present in the notebook canvas. New pages enable it. The tool settings show a page option; its value saves with page data and remains after reopening. The Pencil recognizer observes rapid direction changes followed by a hold. It does not take the normal drawing touch. With the option off, the scratch recognizer is disabled. Partial and Object erasers remain separate remembered modes.

Scratch erase removes complete touched ink strokes and records those removed strokes for Undo. Undo flushes new ink first, then inserts the removed strokes into the current drawing. It keeps later writing. Text boxes and fixed backgrounds are outside the drawing target. The later explicit user instruction makes precomputed shapes ordinary ink, so they support scratch erase too. This replaces the ticket's earlier shape exclusion.

The issue 2 physical pass covers scratch-and-hold, Undo after new writing, ordinary crossed-out words and sketches, eraser modes, palm contact, and the Apple Notes comparison. The user later passed other native issue 4 features but reported tool hold settings as failed. The hold correction and new shape strokes were subsequently installed. Their focused physical behavior check remains pending. A source review, build, or installation does not prove a new Pencil pass.

Main read the full issue and the current ScratchGestureRecognizer, SurfaceView, PageStore, ToolSettingsView, and SelectionGeometry paths. No new recognition algorithm was required. The issue 6 full typecheck and signed physical build passed, exit 0. Fresh parallel Standards and Spec source reviews included these paths and reported No Findings. The combined update installed and launched on the iPad, exit 0. These results do not prove a new physical Pencil pass. No unit or integration tests were written or run. No dependency, database, cloud service, paid service, or production deployment is added. GitHub was used to read the issue.
