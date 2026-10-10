import Combine
import Foundation

/// Keep the last seven completed edits in order, including edits on other pages.
@MainActor
final class CanvasUndoHistory: ObservableObject {
    @Published private(set) var count = 0
    @Published private(set) var isUndoing = false
    @Published private(set) var errorMessage: String?
    private struct Entry {
        let id = UUID()
        let group: UUID?
        let undo: @MainActor () async -> Bool
    }
    private var entries: [Entry] = []

    func explainActiveInput() { errorMessage = "Lift the Pencil and finish the page gesture, then tap Undo." }

    func record(group: UUID? = nil, undo: @escaping @MainActor () async -> Bool) {
        guard !isUndoing else { return }
        if let group, entries.last?.group == group { return }
        entries.append(Entry(group: group, undo: undo))
        if entries.count > 7 { entries.removeFirst(entries.count - 7) }
        count = entries.count
        errorMessage = nil
    }

    /// Permanent deletion makes stored restoration actions unavailable.
    func clearAfterPermanentDeletion() {
        entries.removeAll()
        count = 0
        errorMessage = "Undo history cleared after permanent deletion."
    }

    func undo() async {
        guard !isUndoing, let entry = entries.last else { return }
        isUndoing = true
        defer { isUndoing = false }
        if await entry.undo() {
            entries.removeAll { $0.id == entry.id }
            count = entries.count
            errorMessage = nil
        } else {
            errorMessage = "Undo could not finish. Lift the Pencil and try again. Saved content is preserved."
        }
    }
}
