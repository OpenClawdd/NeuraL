import SwiftUI
import UniformTypeIdentifiers

struct DocumentsView: View {
    @ObservedObject var chatState: ChatState
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section("Knowledge Base") {
                    if chatState.importedDocuments.isEmpty {
                        ContentUnavailableView(
                            "No Documents",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Import local documents for grounded responses.")
                        )
                    } else {
                        ForEach(chatState.importedDocuments) { doc in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(doc.filename)
                                    .font(.body)
                                HStack {
                                    Text(doc.fileType.uppercased())
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text("\(doc.chunkCount) chunks")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text("~\(doc.totalEstimatedTokens) tokens")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Section("Local-only") {
                    Text("Documents remain on-device unless you explicitly export.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Import", systemImage: "doc.badge.plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.text, .pdf, .plainText, UTType(filenameExtension: "md") ?? .text],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    chatState.importDocument(from: url)
                case .failure:
                    break
                }
            }
        }
    }
}
