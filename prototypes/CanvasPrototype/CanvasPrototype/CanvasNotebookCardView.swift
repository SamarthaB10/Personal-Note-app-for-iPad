import SwiftUI

struct CanvasNotebookCardView: View {
    let notebook: CanvasNotebook
    let coverURL: URL?
    @State private var cover: UIImage?

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    if let cover {
                        Image(uiImage: cover).resizable().scaledToFit().padding(12)
                    } else {
                        CanvasLucideIcon(kind: .notebook)
                            .scaleEffect(2)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: 6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Color(uiColor: .separator))
                }
                .aspectRatio(0.72, contentMode: .fit)
            Text(notebook.title).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                .frame(minHeight: 44, alignment: .top)
            Text("\(notebook.pageIDs.count) pages").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .task(id: notebook.coverRevision) {
            guard let coverURL else { cover = nil; return }
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: coverURL) }.value
            guard !Task.isCancelled else { return }
            cover = data.flatMap { UIImage(data: $0) }
        }
    }
}
