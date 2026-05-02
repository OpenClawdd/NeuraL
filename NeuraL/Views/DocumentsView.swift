//
//  DocumentsView.swift
//  NeuraL
//
//  Phase 6.3 — Document Management UI for RAG
//
//  Provides a view for importing, browsing, and managing documents
//  used for retrieval-augmented generation. Users can import PDF,
//  TXT, and MD files, see chunk counts and storage usage, and
//  delete documents they no longer need.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentsView: View {
    let chatState: ChatState

    @State private var documents: [ImportedDocument] = []
    @State private var isImporting = false
    @State private var isLoading = false
    @State private var importError: String?
    @State private var totalChunks: Int = 0
    @State private var totalTokens: Int = 0

    var body: some View {
        List {
            // Summary section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(documents.count) document\(documents.count == 1 ? "" : "s")")
                            .font(.headline)
                        Text("\(totalChunks) chunks, ~\(totalTokens) tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Text("Knowledge Base")
            }

            // Error display
            if let error = importError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Dismiss") {
                            importError = nil
                        }
                        .font(.caption)
                    }
                }
            }

            // Documents list
            Section {
                if documents.isEmpty {
                    ContentUnavailableView(
                        "No Documents",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Import PDF, TXT, or Markdown files to enable document-based Q&A.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(documents) { doc in
                        DocumentRow(document: doc) {
                            deleteDocument(doc)
                        }
                    }
                }
            } header: {
                if !documents.isEmpty {
                    Text("Imported Documents")
                }
            }

            // Info section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Supported Formats", systemImage: "doc.text")
                        .font(.subheadline.bold())
                    Text("PDF, Plain Text (.txt), Markdown (.md)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("How It Works", systemImage: "gearshape")
                        .font(.subheadline.bold())
                    Text("Documents are split into chunks and indexed locally. When you ask a question, relevant chunks are retrieved and used as context for the model's response. All processing happens on your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("Privacy", systemImage: "lock.shield")
                        .font(.subheadline.bold())
                    Text("All documents are processed and stored entirely on your device. No data is sent to any server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("About RAG")
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [
                UTType(filenameExtension: "pdf") ?? .pdf,
                UTType(filenameExtension: "txt") ?? .plainText,
                UTType(filenameExtension: "md") ?? .plainText
            ],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .task {
            await loadDocuments()
        }
        .overlay {
            if isLoading {
                ProgressView("Importing...")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func loadDocuments() async {
        documents = await chatState.ragDocuments()
        totalChunks = await VectorStore.shared.totalChunks
        totalTokens = await VectorStore.shared.totalEstimatedTokens
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            isLoading = true
            Task {
                for url in urls {
                    // Access security-scoped resource
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }

                    do {
                        _ = try await chatState.importDocument(at: url)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
                isLoading = false
                await loadDocuments()
            }

        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func deleteDocument(_ doc: ImportedDocument) {
        Task {
            await chatState.removeRAGDocument(id: doc.id)
            await loadDocuments()
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: ImportedDocument
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fileTypeIcon)
                .font(.title3)
                .foregroundStyle(fileTypeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.filename)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(document.chunkCount) chunk\(document.chunkCount == 1 ? "" : "s")")
                    Text("\u{00b7}")
                    Text(formatFileSize(document.fileSize))
                    Text("\u{00b7}")
                    Text(document.fileType.uppercased())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private var fileTypeIcon: String {
        switch document.fileType {
        case "pdf": return "doc.fill"
        case "txt": return "doc.text.fill"
        case "md":  return "doc.richtext.fill"
        default:    return "doc.fill"
        }
    }

    private var fileTypeColor: Color {
        switch document.fileType {
        case "pdf": return .red
        case "txt": return .blue
        case "md":  return .purple
        default:    return .gray
        }
    }

    private func formatFileSize(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
    }
}
