import Foundation

@MainActor
final class DreamStore: ObservableObject {
    @Published private(set) var cards: [DreamCard] = []
    private let url: URL

    init(fileManager: FileManager = .default, retention: DreamStateSettings.Retention = .hundred) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DreamState", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("dreamcards.json")
        load(retention: retention)
    }

    func load(retention: DreamStateSettings.Retention = .hundred) {
        guard let data = try? Data(contentsOf: url) else { cards = []; return }
        guard let decoded = try? JSONDecoder().decode([DreamCard].self, from: data) else {
            cards = []
            return
        }
        cards = decoded
        enforceRetention(retention)
    }

    func append(_ card: DreamCard, retention: DreamStateSettings.Retention) {
        cards.insert(card, at: 0)
        enforceRetention(retention)
        save()
    }

    func enforceRetention(_ retention: DreamStateSettings.Retention) {
        if let limit = retention.limit, cards.count > limit {
            cards = Array(cards.prefix(limit))
            save()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
