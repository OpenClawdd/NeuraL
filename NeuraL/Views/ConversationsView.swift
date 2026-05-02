//
//  ConversationsView.swift
//  NeuraL
//
//  Phase 4 — Conversation Management Sidebar
//  Frutiger Aero Edition
//
//  Provides a sidebar for managing multiple conversations:
//  - List of saved conversations with title, date, and snippet
//  - Create new conversation
//  - Bookmark/favorite conversations
//  - Search within conversation history
//  - Delete conversations with confirmation
//  - Share conversation as text
//
//  All views styled with FrutigerAeroTheme for glassy, glossy,
//  translucent aesthetic:
//  - Soft blue gradient background
//  - Frosted glass (.ultraThinMaterial) conversation cards
//  - Glowing cyan active indicator
//  - Gold bookmark accent
//  - Glossy gradient swipe actions
//  - Frosted search bar
//

import SwiftUI

// MARK: - Conversations Sidebar View

/// A sidebar view showing all saved conversations with search,
/// bookmarks, and management features. Styled with Frutiger Aero aesthetic.
struct ConversationsSidebar: View {
    @Binding var chatState: ChatState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var conversations: [ConversationListItem] = []
    @State private var showDeleteConfirmation: UUID?
    @State private var isSearching = false
    @State private var selectedConversationId: UUID?

    private let theme = FrutigerAeroTheme.shared

    var body: some View {
        NavigationStack {
            ZStack {
                // ── Soft blue gradient background ──
                theme.backgroundGradient
                    .ignoresSafeArea()

                List(filteredConversations, selection: $selectedConversationId) { item in
                    ConversationRow(
                        item: item,
                        isActive: item.id == chatState.conversation.id,
                        onSelect: { selectConversation(item) },
                        onDelete: { showDeleteConfirmation = item.id },
                        onBookmark: { toggleBookmark(item) },
                        onShare: { shareConversation(item) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // ── Glossy delete button with red gradient ──
                        Button(role: .destructive) {
                            showDeleteConfirmation = item.id
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                        .tint(.red)

                        // ── Glossy bookmark button with gold accent ──
                        Button {
                            toggleBookmark(item)
                        } label: {
                            Label(
                                item.isBookmarked ? "Unbookmark" : "Bookmark",
                                systemImage: item.isBookmarked ? "bookmark.slash.fill" : "bookmark.fill"
                            )
                        }
                        .tint(theme.goldAccent)
                    }
                    .swipeActions(edge: .leading) {
                        // ── Glossy share button with neon blue ──
                        Button {
                            shareConversation(item)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up.fill")
                        }
                        .tint(theme.neonBlue)
                    }
                    // ── Frosted glass row background ──
                    .listRowBackground(
                        FrostedRowBackground(isActive: item.id == chatState.conversation.id)
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Search conversations")
                .navigationTitle("Conversations")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            createNewConversation()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, theme.neonBlue)
                        }
                    }
                }
                .alert("Delete Conversation?", isPresented: .init(
                    get: { showDeleteConfirmation != nil },
                    set: { if !$0 { showDeleteConfirmation = nil } }
                )) {
                    Button("Cancel", role: .cancel) {
                        showDeleteConfirmation = nil
                    }
                    Button("Delete", role: .destructive) {
                        if let id = showDeleteConfirmation {
                            deleteConversation(id: id)
                        }
                        showDeleteConfirmation = nil
                    }
                } message: {
                    Text("This conversation will be permanently deleted. This action cannot be undone.")
                }
                .onAppear {
                    loadConversations()
                }
            }
        }
    }

    // MARK: - Computed

    private var filteredConversations: [ConversationListItem] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { item in
            item.title.localizedCaseInsensitiveContains(searchText) ||
            item.lastSnippet.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Actions

    private func loadConversations() {
        do {
            let ids = try ConversationStore.listAll()
            var items: [ConversationListItem] = []
            for id in ids {
                if let conv = try? ConversationStore.load(id: id) {
                    let lastMsg = conv.messages.last?.content ?? ""
                    let snippet = String(lastMsg.prefix(100))
                    let isBookmarked = UserDefaults.standard.bool(forKey: "neural.bookmark.\(id.uuidString)")
                    items.append(ConversationListItem(
                        id: conv.id,
                        title: conv.title ?? "Untitled",
                        lastSnippet: snippet,
                        lastUpdated: conv.lastUpdatedAt,
                        messageCount: conv.messages.count,
                        isBookmarked: isBookmarked
                    ))
                }
            }
            // Sort: bookmarked first, then by last updated
            conversations = items.sorted { a, b in
                if a.isBookmarked != b.isBookmarked {
                    return a.isBookmarked
                }
                return a.lastUpdated > b.lastUpdated
            }
        } catch {
            conversations = []
        }
    }

    private func selectConversation(_ item: ConversationListItem) {
        do {
            let conv = try ConversationStore.load(id: item.id)
            chatState.conversation = conv
            dismiss()
        } catch {
            // Failed to load — ignore
        }
    }

    private func createNewConversation() {
        let systemPrompt = chatState.conversation.systemPrompt?.content ?? chatState.defaultSystemPrompt
        // Save current conversation first
        if !chatState.conversation.messages.filter({ $0.role != .system }).isEmpty {
            try? ConversationStore.save(chatState.conversation)
        }
        chatState.conversation = Conversation(systemPrompt: systemPrompt)
        chatState.contextTokensUsed = 0
        dismiss()
    }

    private func deleteConversation(id: UUID) {
        try? ConversationStore.delete(id: id)
        conversations.removeAll { $0.id == id }

        // If we deleted the active conversation, create a new one
        if id == chatState.conversation.id {
            let systemPrompt = chatState.conversation.systemPrompt?.content ?? chatState.defaultSystemPrompt
            chatState.conversation = Conversation(systemPrompt: systemPrompt)
            chatState.contextTokensUsed = 0
        }
    }

    private func toggleBookmark(_ item: ConversationListItem) {
        if let index = conversations.firstIndex(where: { $0.id == item.id }) {
            conversations[index].isBookmarked.toggle()
            UserDefaults.standard.set(
                conversations[index].isBookmarked,
                forKey: "neural.bookmark.\(item.id.uuidString)"
            )
        }
    }

    private func shareConversation(_ item: ConversationListItem) {
        // Build a shareable text representation
        guard let conv = try? ConversationStore.load(id: item.id) else { return }
        var text = "# \(conv.title ?? "Conversation")\n\n"
        for message in conv.messages {
            switch message.role {
            case .system:
                text += "[System] \(message.content)\n\n"
            case .user:
                text += "[You] \(message.content)\n\n"
            case .assistant:
                text += "[Assistant] \(message.content)\n\n"
            }
        }
        // Copy to clipboard as a simple share mechanism
        UIPasteboard.general.string = text
    }
}

// MARK: - Frosted Row Background

/// A frosted glass background for conversation rows with optional
/// active-state glow highlight.
private struct FrostedRowBackground: View {
    let isActive: Bool
    private let theme = FrutigerAeroTheme.shared

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.glossHighlight.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isActive
                            ? theme.vibrantCyan.opacity(0.5)
                            : .white.opacity(0.25),
                        lineWidth: isActive ? 1.5 : 0.5
                    )
            )
            .shadow(
                color: isActive
                    ? theme.vibrantCyan.opacity(0.2)
                    : theme.buttonShadow,
                radius: isActive ? 8 : 4,
                x: 0,
                y: isActive ? 2 : 2
            )
            .padding(.vertical, 2)
    }
}

// MARK: - Conversation List Item

/// A lightweight representation of a conversation for the sidebar list.
/// This avoids loading the full conversation JSON for each row.
struct ConversationListItem: Identifiable {
    let id: UUID
    var title: String
    var lastSnippet: String
    var lastUpdated: Date
    var messageCount: Int
    var isBookmarked: Bool
}

// MARK: - Conversation Row

/// A single row in the conversations list, styled with Frutiger Aero aesthetic.
struct ConversationRow: View {
    let item: ConversationListItem
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onBookmark: () -> Void
    let onShare: () -> Void

    private let theme = FrutigerAeroTheme.shared

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                // ── Bookmark indicator (gold accent) ──
                if item.isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(theme.goldAccent)
                        .shadow(color: theme.goldAccent.opacity(0.4), radius: 3, x: 0, y: 0)
                }

                VStack(alignment: .leading, spacing: 3) {
                    // Title
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(isActive ? theme.neonBlue : .primary)
                        .lineLimit(1)

                    // Snippet (last message preview)
                    Text(item.lastSnippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    // Metadata row
                    HStack(spacing: 8) {
                        Label {
                            Text(item.lastUpdated, style: .relative)
                                .font(.caption2)
                        } icon: {
                            Image(systemName: "clock")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.neonBlue.opacity(0.6))
                        }

                        Label {
                            Text("\(item.messageCount) messages")
                                .font(.caption2)
                        } icon: {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.neonBlue.opacity(0.6))
                        }
                    }
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                // ── Glowing cyan active indicator ──
                if isActive {
                    ActiveIndicatorDot()
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to open conversation")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        var label = "\(item.title), \(item.messageCount) messages, \(item.lastUpdated.formatted(.relative(presentation: .named)))"
        if item.isBookmarked {
            label += ", bookmarked"
        }
        if isActive {
            label += ", currently active"
        }
        return label
    }
}

// MARK: - Active Indicator Dot

/// A small glowing cyan indicator dot for the active conversation.
/// Uses a layered approach: base circle + glow overlay + inner highlight.
private struct ActiveIndicatorDot: View {
    private let theme = FrutigerAeroTheme.shared

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(theme.vibrantCyan.opacity(0.3))
                .frame(width: 16, height: 16)
                .blur(radius: 3)

            // Core dot
            Circle()
                .fill(
                    RadialGradient(
                        colors: [theme.vibrantCyan, theme.neonBlue],
                        center: .center,
                        startRadius: 0,
                        endRadius: 5
                    )
                )
                .frame(width: 10, height: 10)

            // Inner gloss highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.7), .white.opacity(0.0)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 4
                    )
                )
                .frame(width: 6, height: 6)
                .offset(x: -1, y: -1)
        }
        .shadow(color: theme.vibrantCyan.opacity(0.6), radius: 4, x: 0, y: 0)
    }
}

// MARK: - Preview

#Preview("Conversations Sidebar") {
    ConversationsSidebar(chatState: .constant(ChatState()))
}
