import SwiftUI

struct DreamboardView: View {
    @ObservedObject var store: DreamStore
    var useAsPrompt: (String) -> Void
    var pinMemory: (DreamCard) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dreamboard").font(.title3.bold())
            if store.cards.isEmpty {
                Text("Dreams form after NeuraL answers locally.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.cards) { card in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title).font(.headline)
                        Text(card.summary).font(.subheadline)
                        Text("Next: \(card.nextAction)").font(.caption)
                        Text("Confidence \(Int(card.confidence*100))% • \(card.createdAt.formatted())")
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Button("Use as prompt") { useAsPrompt(card.nextAction) }
                            Button("Pin memory") { pinMemory(card) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
