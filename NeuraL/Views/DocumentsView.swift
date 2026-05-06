import SwiftUI

struct DocumentsView: View {
    let chatState: ChatState
    @State private var docs: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Knowledge Base") {
                    if docs.isEmpty {
                        ContentUnavailableView("No Documents", systemImage: "doc.text.magnifyingglass", description: Text("Import local documents for grounded responses."))
                    } else {
                        ForEach(docs, id: \.self) { Text($0) }
                    }
                }
                Section("Local-only") {
                    Text("Documents remain on-device unless you explicitly export.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Documents")
        }
    }
}
