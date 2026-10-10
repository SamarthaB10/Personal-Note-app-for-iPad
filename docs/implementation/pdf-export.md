# Export notes to Files

Issue: [10](https://github.com/SamarthaB10/Personal-Note-app-for-iPad/issues/10).

Export to Files offers Current page and Complete notebook. It takes a fixed snapshot of page order, appearance, current text, and completed ink before it reads source backgrounds. Later writing remains outside that PDF copy. Active Pencil input or a page gesture produces an explicit retry message. The canvas remains available during background rendering.

The PDF includes blank, lined, or grid paper, fixed imported content, text boxes, handwriting, and shape ink. Source crop and rotation use the canonical import assets. Image export uses the bounded, oriented image. Source bytes are reused across pages. Export reads immutable values on utility queues and does not replace the live drawing, save into source PDFs, or remove note data. The native Files picker saves a copy. Its temporary PDF is removed after completion or cancellation.

The isolated complete source typecheck passed with warnings as errors. Main read all export code and integrated its incremental changes with the corrected import source. The integrated full source typecheck passed with warnings treated as errors, exit 0. The signed combined build, source reviews, and installation remain in progress. No new physical export pass is claimed.

Required new checks are PDF page count and order, positions and colors, current typed text and completed ink, current-page export, complete-notebook export, Files save and cancel, and writing during a large export. The original imported source must remain unchanged.

No unit or integration tests were written or run. No new dependency, database, app cloud service, paid service, or production deployment was used. Editable backup is a separate feature.
