import Foundation

/// Build under the store's index mutation permit, using its latest ordered page IDs.
/// Save full source + new page JSON before writing orderedPageIDs to library.json.
struct CanvasImportInsertionPlan: Sendable {
    struct NewPage: Sendable {
        let id: UUID
        let background: CanvasImportedBackground
    }
    let orderedPageIDs: [UUID]
    let newPages: [NewPage]
    let omittedPageCount: Int

    static func make(prepared: CanvasPreparedImport, currentPageIDs: [UUID],
                     after anchor: UUID?) throws -> CanvasImportInsertionPlan {
        guard prepared.sourcePageCount >= prepared.pages.count, !prepared.pages.isEmpty,
              prepared.pages.count <= CanvasImportAdapter.maximumPageCount,
              prepared.pages.enumerated().allSatisfy({ index, page in
                  page.sourceID == prepared.staged.source.id && page.sourcePageIndex == index
              }) else { throw CanvasImportError.ioFailure }
        guard Set(currentPageIDs).count == currentPageIDs.count,
              currentPageIDs.count <= CanvasImportAdapter.maximumPageCount else {
            throw CanvasImportError.ioFailure
        }
        let insertionIndex: Int
        if let anchor {
            guard let index = currentPageIDs.firstIndex(of: anchor) else {
                throw CanvasImportError.ioFailure
            }
            insertionIndex = index + 1
        } else {
            insertionIndex = currentPageIDs.count
        }
        let capacity = CanvasImportAdapter.maximumPageCount - currentPageIDs.count
        guard capacity > 0 else { throw CanvasImportError.noCapacity }
        let newPages = prepared.pages.prefix(capacity).map { NewPage(id: UUID(), background: $0) }
        guard !newPages.isEmpty else { throw CanvasImportError.emptyFile }
        var orderedPageIDs = currentPageIDs
        orderedPageIDs.insert(contentsOf: newPages.map(\.id), at: insertionIndex)
        return CanvasImportInsertionPlan(orderedPageIDs: orderedPageIDs, newPages: newPages,
            omittedPageCount: prepared.sourcePageCount - newPages.count)
    }
}
