# Complete-stroke lasso and mixed content

Issue: [8](https://github.com/SamarthaB10/Personal-Note-app-for-iPad/issues/8).

Freehand and Box lasso are already present. Their remembered mode opens on a short tap; hold opens settings. The later explicit user rule replaces full ink enclosure: contact or a partial loop selects touched complete ink strokes. A stroke is not cut or grouped into a recognized word. Text boxes remain complete objects. Precomputed shapes are ink strokes. Fixed source content stays outside selection.

Initial ink contact starts movement in the same gesture, including at a crossing. Text boxes retain tap tolerance and an explicit chooser when candidates overlap. Finger lasso and shape paths prevent one-finger notebook pan; two-finger navigation and finger pinch remain available. Movement uses a UIKit preview. The page model receives one completed transform. Cancellation restores the initial content. Mixed resize scales text frames and font size together with ink. Selection actions include movement, proportional resize, Delete, and Clear. They do not open the keyboard. Explicit text Edit is a separate action.

Editable transformed content saves locally. Delete retains unrelated content and rejects stale stroke indices after a drawing flush. Source PDF content is fixed; importing real PDFs is separate issue 9 work.

The issue 2 combined physical pass covers both lasso modes, mixed movement and resize, text-box choice, selected ink Delete, and fixed-background behavior. The issue 4 user feedback passed other native features after contact selection and scrolling, but tool hold failed. Later source corrections passed fresh round-3 Standards and Spec reviews, typecheck, signed build, and installation. This does not establish a fresh full physical pass for the new shapes and tool controls.

Main read the full issue and complete SelectionGeometry, PageStore transform/Delete paths, SurfaceView preview/input paths, and SelectionActionsView. Fresh parallel issue 6 Standards and Spec source reviews included these paths and reported No Findings. The full source typecheck, signed physical build, install, and launch passed, exit 0. No new selection algorithm was required. No unit or integration tests were written or run. No dependency, database, cloud service, paid service, or production deployment is added. GitHub was used to read the issue.
