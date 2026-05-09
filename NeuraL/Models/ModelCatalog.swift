import Foundation
struct CatalogEntry: Identifiable { var id: String { displayName }; let displayName: String }
let catalogEntries: [CatalogEntry] = [CatalogEntry(displayName: "Llama 3.2 1B"), CatalogEntry(displayName: "Llama 3.2 3B")]
