# Delete and Trash recovery

Issue: [11](https://github.com/SamarthaB10/Personal-Note-app-for-iPad/issues/11).

Press and hold a notebook cover to see Delete Notebook and Move to folder in the same native context menu. Covers align with Create or Import File. Extra buttons below the covers are removed. Normal Delete moves content to Trash. Custom folder Delete has a group confirmation and moves its notebooks together. Unfiled cannot be deleted. Page Delete keeps at least one page in the notebook.

Trash provides Restore and confirmed Delete Permanently. A notebook returns to its former folder when available, otherwise Unfiled. Folder restore returns the saved group. Name conflicts receive a Restored suffix. A restored page returns near its saved position, within the 300-page limit. Restore validates editable page files and imported resources before publication.

All membership writes preserve Trash through the same FIFO index permit and revision check. Before deletion, cached content is saved. Active Pencil, typing, scratch, and selection input refuse destructive changes with a visible message. Removed page stores retire so delayed saves cannot recreate their files. Cover requests are invalidated and drained before permanent cleanup.

Permanent deletion first records a durable pending manifest. It removes only exact owned page, cover, source, metadata, and display asset files with no remaining page reference. A shared imported source remains while an active or recoverable page needs it. Original Files-picker sources are not cleanup targets. Unknown and unpublished files are preserved. A failed cleanup stays pending and permits an explicit retry after reopening. It cannot restore partially removed content.

The full combined source typecheck passed with warnings treated as errors, exit 0. The signed physical iPad build passed, exit 0. The update installed, exit 0. Fresh parallel Standards and Spec source reviews are running. Launch passed, exit 0. Capture and new physical behavior checks remain pending. No full new physical pass is claimed.

Required focused checks are notebook and folder Delete/restore, page Delete and final-page protection, press-and-hold Move/Delete menus, offline reopen, imported source retention and final-reference cleanup, permanent failure/retry, and restored covers. Permanent deletion checks must use disposable content. No real note was deleted by automation.

No unit or integration tests were written or run. No new dependency, database, app cloud service, paid service, or production deployment was used. Editable backup remains separate work.
