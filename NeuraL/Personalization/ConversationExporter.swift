//
//  ConversationExporter.swift
//  NeuraL
//
//  Phase 7.4 â€” Export & Archive for Conversations
//
//  Provides export capabilities for conversations:
//  1. Plain Text (.txt) â€” simple, universally readable
//  2. Markdown (.md) â€” formatted with headers and code blocks preserved
//  3. PDF (.pdf) â€” professional, shareable document
//  4. JSON (.json) â€” machine-readable, full fidelity
//
//  Also provides:
//  - Archive: Move conversations to long-term storage (hidden from main list)
//  - Unarchive: Restore archived conversations
//  - Batch export: Export multiple conversations at once
//

import SwiftUI

struct ConversationStore {
    static func storeDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Conversations")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func save(_ conv: Conversation) throws {
        let url = try storeDirectory().appendingPathComponent("\(conv.id.uuidString).json")
        try JSONEncoder().encode(conv).write(to: url)
    }
    static func load(id: UUID) throws -> Conversation {
        let data = try Data(contentsOf: storeDirectory().appendingPathComponent("\(id.uuidString).json"))
        return try JSONDecoder().decode(Conversation.self, from: data)
    }
    static func listAll() throws -> [UUID] {
        let files = try FileManager.default.contentsOfDirectory(at: storeDirectory(), includingPropertiesForKeys: nil)
        return files.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }
    static func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: storeDirectory().appendingPathComponent("\(id.uuidString).json"))
    }
}
import UIKit

// MARK: - Export Format

/// The format for conversation export.
enum ExportFormat: String, CaseIterable, CustomStringConvertible {
    case text
    case markdown
    case pdf
    case json

    var description: String {
        switch self {
        case .text:     return NSLocalizedString("Plain Text", comment: "Export format")
        case .markdown: return NSLocalizedString("Markdown", comment: "Export format")
        case .pdf:      return NSLocalizedString("PDF", comment: "Export format")
        case .json:     return NSLocalizedString("JSON", comment: "Export format")
        }
    }

    var fileExtension: String {
        switch self {
        case .text:     return "txt"
        case .markdown: return "md"
        case .pdf:      return "pdf"
        case .json:     return "json"
        }
    }

    var systemImage: String {
        switch self {
        case .text:     return "doc.plaintext"
        case .markdown: return "doc.richtext"
        case .pdf:      return "doc.fill"
        case .json:     return "curlybraces"
        }
    }
}

// MARK: - Conversation Exporter

/// Handles exporting conversations in various formats.
enum ConversationExporter {

    /// Export a conversation in the specified format and return the file data.
    static func export(conversation: Conversation, format: ExportFormat) -> Data? {
        switch format {
        case .text:     return exportAsText(conversation: conversation)
        case .markdown: return exportAsMarkdown(conversation: conversation)
        case .pdf:      return exportAsPDF(conversation: conversation)
        case .json:     return exportAsJSON(conversation: conversation)
        }
    }

    /// Generate a filename for the export.
    static func filename(for conversation: Conversation, format: ExportFormat) -> String {
        let base = conversation.title ?? "Conversation"
        let sanitized = base
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let truncated = String(sanitized.prefix(50))
        return "\(truncated).\(format.fileExtension)"
    }

    // MARK: - Text Export

    private static func exportAsText(conversation: Conversation) -> Data? {
        var text = ""

        if let title = conversation.title {
            text += "\(title)\n"
            text += String(repeating: "=", count: title.count) + "\n\n"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for message in conversation.messages {
            let timestamp = dateFormatter.string(from: message.timestamp)
            let roleLabel: String
            switch message.role {
            case .system:    roleLabel = "System"
            case .user:      roleLabel = "You"
            case .assistant: roleLabel = "Assistant"
            }

            text += "[\(roleLabel)] \(timestamp)\n"
            text += "\(message.content)\n"

            // Show function calls if any
            if let functionCalls = message.functionCalls, !functionCalls.isEmpty {
                text += "\n  Tools used:\n"
                for call in functionCalls {
                    text += "    - \(call.toolName): \(call.isSuccess ? "Success" : "Failed")\n"
                }
            }

            // Show RAG sources if any
            if let ragSources = message.ragSources, !ragSources.isEmpty {
                text += "\n  Sources:\n"
                for source in ragSources {
                    text += "    - \(source.documentName) (chunk \(source.chunkIndex + 1))\n"
                }
            }

            text += "\n"
        }

        return text.data(using: .utf8)
    }

    // MARK: - Markdown Export

    private static func exportAsMarkdown(conversation: Conversation) -> Data? {
        var md = ""

        if let title = conversation.title {
            md += "# \(title)\n\n"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for message in conversation.messages {
            let timestamp = dateFormatter.string(from: message.timestamp)

            switch message.role {
            case .system:
                md += "> **System** *\(timestamp)*\n>\n"
                md += "> \(message.content.replacingOccurrences(of: "\n", with: "\n> "))\n\n"

            case .user:
                md += "### ðŸ‘¤ You *\(timestamp)*\n\n"
                md += "\(message.content)\n\n"

            case .assistant:
                md += "### ðŸ¤– Assistant *\(timestamp)*\n\n"

                // Show thinking text if present
                if let thinking = message.thinkingText {
                    md += "<details>\n<summary>Thought for \(String(format: "%.1f", message.thinkingDurationSeconds))s</summary>\n\n"
                    md += "\(thinking)\n\n"
                    md += "</details>\n\n"
                }

                md += "\(message.content)\n\n"

                // Show function calls
                if let functionCalls = message.functionCalls, !functionCalls.isEmpty {
                    md += "**Tools used:**\n"
                    for call in functionCalls {
                        let icon = call.isSuccess ? "âœ…" : "âŒ"
                        md += "- \(icon) `\(call.toolName)` (\(String(format: "%.2f", call.durationSeconds))s)\n"
                    }
                    md += "\n"
                }

                // Show RAG sources
                if let ragSources = message.ragSources, !ragSources.isEmpty {
                    md += "**Sources:**\n"
                    for source in ragSources {
                        md += "- \(source.documentName) â€” chunk \(source.chunkIndex + 1) (similarity: \(String(format: "%.0f%%", source.similarity * 100)))\n"
                    }
                    md += "\n"
                }

                // Show generation metrics
                if let metadata = message.generationMetadata {
                    md += "*\(String(format: "%.1f", metadata.tokensPerSecond)) tok/s Â· \(metadata.tokensGenerated) tokens*\n\n"
                }
            }
        }

        md += "---\n*Exported from NeuraL on \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))*\n"

        return md.data(using: .utf8)
    }

    // MARK: - PDF Export

    private static func exportAsPDF(conversation: Conversation) -> Data? {
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - 2 * margin

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()

            var y: CGFloat = margin

            // Title
            if let title = conversation.title {
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.label
                ]
                let titleString = NSAttributedString(string: title, attributes: titleAttrs)
                let titleSize = titleString.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                titleString.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: titleSize.height))
                y += titleSize.height + 8

                // Divider
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                UIColor.separator.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                y += 12
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short

            for message in conversation.messages {
                let timestamp = dateFormatter.string(from: message.timestamp)

                // Check if we need a new page
                if y > pageHeight - margin - 80 {
                    context.beginPage()
                    y = margin
                }

                // Role header
                let roleLabel: String
                let roleColor: UIColor
                switch message.role {
                case .system:    roleLabel = "System"; roleColor = .systemOrange
                case .user:      roleLabel = "You"; roleColor = .systemBlue
                case .assistant: roleLabel = "Assistant"; roleColor = .systemGreen
                }

                let headerAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: roleColor
                ]
                let headerString = NSAttributedString(string: "\(roleLabel) Â· \(timestamp)", attributes: headerAttrs)
                headerString.draw(at: CGPoint(x: margin, y: y))
                y += 16

                // Content
                let contentAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.label
                ]
                let contentString = NSAttributedString(string: message.content, attributes: contentAttrs)
                let contentSize = contentString.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )

                // Check if content fits on current page
                if y + contentSize.height > pageHeight - margin {
                    context.beginPage()
                    y = margin
                }

                contentString.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: contentSize.height))
                y += contentSize.height + 12
            }
        }

        return data
    }

    // MARK: - JSON Export

    private static func exportAsJSON(conversation: Conversation) -> Data? {
        try? JSONEncoder().encode(conversation)
    }
}

// MARK: - Conversation Archive Manager

/// Manages archived conversations (hidden from the main list).
enum ConversationArchive {

    private static let archiveDirectoryName = "Archive"

    /// Get the archive directory URL.
    static func archiveDirectory() throws -> URL {
        let documentsDir = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let archiveDir = documentsDir.appendingPathComponent(archiveDirectoryName)

        if !FileManager.default.fileExists(atPath: archiveDir.path) {
            try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        }

        return archiveDir
    }

    /// Archive a conversation (move from main store to archive).
    static func archive(conversationId: UUID) throws {
        let sourceURL = try ConversationStore.storeDirectory()
            .appendingPathComponent("\(conversationId.uuidString).json")
        let destURL = try archiveDirectory()
            .appendingPathComponent("\(conversationId.uuidString).json")

        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        try FileManager.default.moveItem(at: sourceURL, to: destURL)
    }

    /// Unarchive a conversation (move from archive back to main store).
    static func unarchive(conversationId: UUID) throws {
        let sourceURL = try archiveDirectory()
            .appendingPathComponent("\(conversationId.uuidString).json")
        let destURL = try ConversationStore.storeDirectory()
            .appendingPathComponent("\(conversationId.uuidString).json")

        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        try FileManager.default.moveItem(at: sourceURL, to: destURL)
    }

    /// List all archived conversation IDs.
    static func listArchived() throws -> [UUID] {
        let dir = try archiveDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )
        return files.compactMap { url in
            UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        }
    }

    /// Load an archived conversation.
    static func loadArchived(id: UUID) throws -> Conversation {
        let fileURL = try archiveDirectory()
            .appendingPathComponent("\(id.uuidString).json")
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Conversation.self, from: data)
    }

    /// Permanently delete an archived conversation.
    static func deleteArchived(id: UUID) throws {
        let fileURL = try archiveDirectory()
            .appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

// MARK: - Export Sheet View

/// A sheet for choosing export format and sharing.
struct ExportSheet: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportFormat = .markdown
    @State private var isExporting = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Export Conversation")
                    .font(.title2.bold())

                Text("Choose a format for exporting \"\(conversation.title ?? "Conversation")\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Format picker
                Picker("Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Label(format.description, systemImage: format.systemImage)
                            .tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                // Format description
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(formatDescription)
                    } icon: {
                        Image(systemName: selectedFormat.systemImage)
                            .foregroundStyle(.blue)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                // Export button
                Button {
                    performExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.body.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isExporting)

                Spacer()
            }
            .padding()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: .init(
                get: { exportURL != nil },
                set: { if !$0 { exportURL = nil } }
            )) {
                if let url = exportURL {
                    ShareSheetView(item: url)
                }
            }
        }
    }

    private var formatDescription: String {
        switch selectedFormat {
        case .text:     return "Simple plain text. Best for notes and quick reading."
        case .markdown: return "Formatted with headers and code blocks. Best for documentation."
        case .pdf:      return "Professional document. Best for sharing and printing."
        case .json:     return "Machine-readable data. Best for backups and imports."
        }
    }

    private func performExport() {
        isExporting = true

        guard let data = ConversationExporter.export(conversation: conversation, format: selectedFormat) else {
            isExporting = false
            return
        }

        let filename = ConversationExporter.filename(for: conversation, format: selectedFormat)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL, options: .atomic)
            exportURL = tempURL
        } catch {
            // Handle error silently
        }

        isExporting = false
    }
}

// MARK: - Share Sheet

/// A UIActivityViewController wrapper for sharing files.
struct ShareSheetView: UIViewControllerRepresentable {
    let item: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Personalization Hub View (Phase 7 Hub)

/// A settings view that serves as the hub for all Phase 7 personalization.
/// Frutiger Aero: frosted group boxes with glossy navigation links.
struct PersonalizationHubView: View {
    let chatState: ChatState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Theme section
                    aeroSettingsGroup(header: "Personalization") {
                        aeroNavigationLink("Appearance", icon: "paintbrush.fill", iconColor: FrutigerAeroTheme.shared.neonBlue) {
                            ThemeSettingsDetail()
                        }
                    }

                    // Prompt library
                    aeroSettingsGroup(header: "System Prompts") {
                        aeroNavigationLink("Prompt Library", icon: "text.book.closed.fill", iconColor: FrutigerAeroTheme.shared.softTeal) {
                            PromptLibraryView(chatState: chatState)
                        }
                    }

                    // Export & Archive
                    aeroSettingsGroup(header: "Data Management") {
                        aeroNavigationLink("Archived Conversations", icon: "archivebox.fill", iconColor: FrutigerAeroTheme.shared.goldAccent) {
                            ArchiveView(chatState: chatState)
                        }
                    }

                    // About
                    aeroSettingsGroup(header: "About") {
                        aeroInfoRow("Version", value: "1.0.0")
                        aeroInfoRow("Build", value: "Frutiger Aero")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 224/255, green: 247/255, blue: 250/255),
                        Color(red: 178/255, green: 235/255, blue: 242/255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Frutiger Aero Helper Views

    private func aeroSettingsGroup<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(.caption, design: .rounded).bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(FrutigerAeroTheme.shared.glossHighlight)
                    .opacity(0.3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 4, x: 0, y: 2)
        }
    }

    private func aeroNavigationLink<Destination: View>(_ title: String, icon: String, iconColor: Color, destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func aeroInfoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Theme Settings Detail

/// Detailed theme customization view.
/// Frutiger Aero: frosted glass sections with custom toggles.
struct ThemeSettingsDetail: View {
    @State private var theme = ThemeManager.shared.theme

    var body: some View {
        Form {
            // Color scheme
            Section {
                Picker("Color Scheme", selection: Binding(
                    get: { theme.colorScheme },
                    set: { theme.colorScheme = $0; ThemeManager.shared.colorSchemePreference = $0; FrutigerAeroTheme.shared.selectionHaptic() }
                )) {
                    ForEach(ColorSchemePreference.allCases, id: \.self) { option in
                        Label(option.description, systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Color Scheme")
            }

            // Accent color â€” Frutiger Aero: glossy color circles
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AccentColorOption.allCases) { option in
                            Button {
                                theme.accentColor = option
                                ThemeManager.shared.accentColor = option
                                FrutigerAeroTheme.shared.selectionHaptic()
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                theme.accentColor == option
                                                    ? FrutigerAeroTheme.shared.neonBlue
                                                    : Color.white.opacity(0.3),
                                                lineWidth: theme.accentColor == option ? 2.5 : 0.5
                                            )
                                    )
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .opacity(theme.accentColor == option ? 1 : 0)
                                    )
                                    .shadow(
                                        color: theme.accentColor == option
                                            ? option.color.opacity(0.4)
                                            : Color.clear,
                                        radius: theme.accentColor == option ? 4 : 0
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Accent Color")
            }

            // Bubble style
            Section {
                Picker("Bubble Style", selection: Binding(
                    get: { theme.bubbleStyle },
                    set: { theme.bubbleStyle = $0; ThemeManager.shared.bubbleStyle = $0; FrutigerAeroTheme.shared.selectionHaptic() }
                )) {
                    ForEach(ChatBubbleStyle.allCases, id: \.self) { style in
                        Label(style.description, systemImage: style.systemImage).tag(style)
                    }
                }
            } header: {
                Text("Chat Bubbles")
            }

            // Font scaling
            Section {
                Picker("Text Size", selection: Binding(
                    get: { theme.fontScaling },
                    set: { theme.fontScaling = $0; ThemeManager.shared.fontScaling = $0; FrutigerAeroTheme.shared.selectionHaptic() }
                )) {
                    ForEach(FontScaling.allCases, id: \.self) { scaling in
                        Text(scaling.description).tag(scaling)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Text Size")
            }

            // Display options â€” Frutiger Aero: custom toggle style
            Section {
                Toggle("Show Timestamps", isOn: Binding(
                    get: { theme.showTimestamps },
                    set: { theme.showTimestamps = $0; ThemeManager.shared.theme.showTimestamps = $0; FrutigerAeroTheme.shared.selectionHaptic() }
                ))
                .toggleStyle(AeroToggleStyle())

                Toggle("Show Token Counts", isOn: Binding(
                    get: { theme.showTokenCounts },
                    set: { theme.showTokenCounts = $0; ThemeManager.shared.theme.showTokenCounts = $0; FrutigerAeroTheme.shared.selectionHaptic() }
                ))
                .toggleStyle(AeroToggleStyle())

                Toggle("Compact Mode", isOn: Binding(
                    get: { theme.compactMode },
                    set: { theme.compactMode = $0; ThemeManager.shared.theme.compactMode = $0; FrutigerAeroTheme.shared.selectionHaptic() }
                ))
                .toggleStyle(AeroToggleStyle())
            } header: {
                Text("Display Options")
            }

            // Reset
            Section {
                Button("Reset to Defaults", role: .destructive) {
                    FrutigerAeroTheme.shared.lightHaptic()
                    ThemeManager.shared.resetToDefaults()
                    theme = ThemeManager.shared.theme
                }
            }
        }
        .navigationTitle("Appearance")
    }
}

// MARK: - Archive View

/// A view for browsing and managing archived conversations.
struct ArchiveView: View {
    let chatState: ChatState
    @State private var archivedConversations: [ConversationListItem] = []

    var body: some View {
        List {
            if archivedConversations.isEmpty {
                ContentUnavailableView(
                    "No Archived Conversations",
                    systemImage: "archivebox",
                    description: Text("Archive conversations you want to keep but hide from the main list.")
                )
            } else {
                ForEach(archivedConversations) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text("\(item.messageCount) messages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            unarchive(item)
                        } label: {
                            Label("Unarchive", systemImage: "arrow.up.archive")
                                .font(.caption)
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let item = archivedConversations[index]
                        try? ConversationArchive.deleteArchived(id: item.id)
                    }
                    loadArchived()
                }
            }
        }
        .navigationTitle("Archive")
        .onAppear {
            loadArchived()
        }
    }

    private func loadArchived() {
        do {
            let ids = try ConversationArchive.listArchived()
            var items: [ConversationListItem] = []
            for id in ids {
                if let conv = try? ConversationArchive.loadArchived(id: id) {
                    let lastMsg = conv.messages.last?.content ?? ""
                    items.append(ConversationListItem(
                        id: conv.id,
                        title: conv.title ?? "Untitled",
                        lastSnippet: String(lastMsg.prefix(100)),
                        lastUpdated: conv.lastUpdatedAt,
                        messageCount: conv.messages.count,
                        isBookmarked: false
                    ))
                }
            }
            archivedConversations = items.sorted { $0.lastUpdated > $1.lastUpdated }
        } catch {
            archivedConversations = []
        }
    }

    private func unarchive(_ item: ConversationListItem) {
        try? ConversationArchive.unarchive(conversationId: item.id)
        loadArchived()
    }
}

