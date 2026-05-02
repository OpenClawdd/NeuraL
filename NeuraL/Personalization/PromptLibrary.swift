//
//  PromptLibrary.swift
//  NeuraL
//
//  Phase 7.2 — System Prompt Library
//
//  Manages a library of saved system prompts that users can:
//  - Save custom prompts with names and descriptions
//  - Edit and delete saved prompts
//  - Apply a prompt to the current conversation
//  - Choose a default prompt for new conversations
//  - Browse built-in prompt templates
//
//  Architecture:
//  - PromptLibrary is @Observable + @MainActor for SwiftUI binding
//  - Prompts are persisted to UserDefaults as Codable JSON
//  - Built-in templates are always available alongside user-created ones
//

import SwiftUI
import Observation

// MARK: - Saved Prompt

/// A saved system prompt with metadata.
struct SavedPrompt: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var content: String
    var category: PromptCategory
    var createdAt: Date
    var updatedAt: Date
    var isBuiltIn: Bool

    /// Create a new user prompt.
    static func create(name: String, content: String, category: PromptCategory = .general) -> SavedPrompt {
        SavedPrompt(
            id: UUID(),
            name: name,
            content: content,
            category: category,
            createdAt: Date(),
            updatedAt: Date(),
            isBuiltIn: false
        )
    }

    /// Create a built-in prompt template.
    static func builtIn(name: String, content: String, category: PromptCategory = .general) -> SavedPrompt {
        SavedPrompt(
            id: UUID(), // Stable ID would be better, but for simplicity...
            name: name,
            content: content,
            category: category,
            createdAt: Date.distantPast,
            updatedAt: Date.distantPast,
            isBuiltIn: true
        )
    }
}

// MARK: - Prompt Category

/// Categories for organizing system prompts.
enum PromptCategory: String, CaseIterable, Codable, CustomStringConvertible {
    case general
    case creative
    case technical
    case educational
    case professional
    case custom

    var description: String {
        switch self {
        case .general:      return NSLocalizedString("General", comment: "Prompt category")
        case .creative:     return NSLocalizedString("Creative", comment: "Prompt category")
        case .technical:    return NSLocalizedString("Technical", comment: "Prompt category")
        case .educational:  return NSLocalizedString("Educational", comment: "Prompt category")
        case .professional: return NSLocalizedString("Professional", comment: "Prompt category")
        case .custom:       return NSLocalizedString("Custom", comment: "Prompt category")
        }
    }

    var systemImage: String {
        switch self {
        case .general:      return "bubble.left.and.bubble.right"
        case .creative:     return "paintbrush.fill"
        case .technical:    return "gearshape.2.fill"
        case .educational:  return "book.fill"
        case .professional: return "briefcase.fill"
        case .custom:       return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .general:      return .blue
        case .creative:     return .purple
        case .technical:    return .orange
        case .educational:  return .green
        case .professional: return .teal
        case .custom:       return .pink
        }
    }
}

// MARK: - Prompt Library

/// Manages the collection of saved system prompts.
@Observable
@MainActor
final class PromptLibrary {

    static let shared = PromptLibrary()

    /// All saved prompts (both built-in and user-created).
    var prompts: [SavedPrompt] = []

    /// The ID of the prompt selected as default for new conversations.
    var defaultPromptID: UUID? {
        didSet {
            UserDefaults.standard.set(defaultPromptID?.uuidString, forKey: Self.defaultPromptKey)
        }
    }

    /// The default system prompt content (either from the selected default or the app default).
    var defaultPromptContent: String {
        if let id = defaultPromptID,
           let prompt = prompts.first(where: { $0.id == id }) {
            return prompt.content
        }
        return Self.appDefaultPrompt
    }

    static let appDefaultPrompt = "You are a helpful, respectful, and honest assistant. Always answer as helpfully as possible. If you don't know the answer, say so."

    // MARK: - Built-In Templates

    private static let builtInTemplates: [SavedPrompt] = [
        .builtIn(name: "Default Assistant", content: appDefaultPrompt, category: .general),
        .builtIn(
            name: "Creative Writer",
            content: "You are a creative and imaginative writer. Help the user with storytelling, poetry, creative writing, and artistic expression. Be vivid, evocative, and original in your responses. Use rich metaphors and descriptive language.",
            category: .creative
        ),
        .builtIn(
            name: "Code Expert",
            content: "You are an expert software developer and coding assistant. Provide clear, well-documented code solutions. Explain your reasoning, mention edge cases, and follow best practices. When showing code, always include comments and prefer readable code over clever tricks.",
            category: .technical
        ),
        .builtIn(
            name: "Study Buddy",
            content: "You are a patient and encouraging tutor. Help the user understand concepts by explaining them step by step. Use analogies and examples to make complex topics accessible. Ask follow-up questions to check understanding. Never just give the answer without explaining the reasoning.",
            category: .educational
        ),
        .builtIn(
            name: "Professional Assistant",
            content: "You are a professional business assistant. Help with emails, reports, presentations, and professional communication. Be concise, formal, and structured in your responses. Use professional language and tone. Organize information with clear headings and bullet points when appropriate.",
            category: .professional
        ),
        .builtIn(
            name: "Concise Responder",
            content: "You are a concise assistant. Provide brief, direct answers without unnecessary elaboration. If a simple yes/no or short answer suffices, give it. Avoid filler words and get straight to the point.",
            category: .general
        ),
        .builtIn(
            name: "Socratic Teacher",
            content: "You are a Socratic teacher. Instead of directly answering questions, guide the user to discover answers through a series of thoughtful questions. Help them think critically and develop their own understanding. Only provide direct answers as a last resort.",
            category: .educational
        ),
        .builtIn(
            name: "Debate Partner",
            content: "You are a skilled debate partner. Take the opposing view on any topic the user presents, regardless of your actual position. Argue forcefully but fairly, using logic, evidence, and sound reasoning. The goal is to strengthen the user's arguments through constructive opposition.",
            category: .creative
        ),
    ]

    // MARK: - Initialization

    private init() {
        loadPrompts()
        defaultPromptID = UserDefaults.standard.string(forKey: Self.defaultPromptKey).flatMap { UUID(uuidString: $0) }
    }

    // MARK: - CRUD Operations

    /// Add a new user-created prompt.
    func addPrompt(_ prompt: SavedPrompt) {
        prompts.append(prompt)
        savePrompts()
    }

    /// Update an existing prompt.
    func updatePrompt(_ prompt: SavedPrompt) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        var updated = prompt
        updated.updatedAt = Date()
        prompts[index] = updated
        savePrompts()
    }

    /// Delete a prompt. Built-in prompts cannot be deleted.
    func deletePrompt(id: UUID) {
        guard let prompt = prompts.first(where: { $0.id == id }) else { return }
        guard !prompt.isBuiltIn else { return }
        prompts.removeAll { $0.id == id }

        // If this was the default, clear the default
        if defaultPromptID == id {
            defaultPromptID = nil
        }

        savePrompts()
    }

    /// Get a prompt by ID.
    func prompt(withId id: UUID) -> SavedPrompt? {
        prompts.first { $0.id == id }
    }

    /// Get prompts filtered by category.
    func prompts(inCategory category: PromptCategory) -> [SavedPrompt] {
        prompts.filter { $0.category == category }
    }

    /// Get only user-created prompts.
    var userPrompts: [SavedPrompt] {
        prompts.filter { !$0.isBuiltIn }
    }

    /// Get only built-in templates.
    var builtInPrompts: [SavedPrompt] {
        prompts.filter { $0.isBuiltIn }
    }

    /// Set a prompt as the default for new conversations.
    func setDefault(_ promptId: UUID?) {
        defaultPromptID = promptId
    }

    // MARK: - Persistence

    private static let promptsKey = "neural.prompts"
    private static let defaultPromptKey = "neural.defaultPrompt"

    private func loadPrompts() {
        // Always start with built-in templates
        var loaded: [SavedPrompt] = Self.builtInTemplates

        // Add user-created prompts from persistence
        if let data = UserDefaults.standard.data(forKey: Self.promptsKey),
           let userPrompts = try? JSONDecoder().decode([SavedPrompt].self, from: data) {
            loaded.append(contentsOf: userPrompts)
        }

        prompts = loaded
    }

    private func savePrompts() {
        // Only persist user-created prompts (built-ins are always regenerated)
        let userOnly = prompts.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(userOnly) {
            UserDefaults.standard.set(data, forKey: Self.promptsKey)
        }
    }
}

// MARK: - Prompt Library View

/// A view for browsing and managing system prompts.
struct PromptLibraryView: View {
    let chatState: ChatState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: PromptCategory = .general
    @State private var isCreatingNew = false
    @State private var editingPrompt: SavedPrompt?
    @State private var searchText = ""

    private var library: PromptLibrary { PromptLibrary.shared }

    var body: some View {
        NavigationStack {
            List {
                // Default prompt section
                Section {
                    DefaultPromptPicker(chatState: chatState)
                } header: {
                    Text("Default Prompt for New Chats")
                }

                // Category filter
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PromptCategory.allCases, id: \.self) { category in
                                CategoryPill(
                                    category: category,
                                    isSelected: selectedCategory == category,
                                    onTap: { selectedCategory = category }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Categories")
                }

                // Built-in templates
                let builtIns = filteredPrompts.filter { $0.isBuiltIn }
                if !builtIns.isEmpty {
                    Section {
                        ForEach(builtIns) { prompt in
                            PromptRow(
                                prompt: prompt,
                                isDefault: prompt.id == library.defaultPromptID,
                                onApply: { applyPrompt(prompt) },
                                onSetDefault: { library.setDefault(prompt.id) }
                            )
                        }
                    } header: {
                        Text("Templates")
                    }
                }

                // User-created prompts
                let userCreated = filteredPrompts.filter { !$0.isBuiltIn }
                if !userCreated.isEmpty {
                    Section {
                        ForEach(userCreated) { prompt in
                            PromptRow(
                                prompt: prompt,
                                isDefault: prompt.id == library.defaultPromptID,
                                onApply: { applyPrompt(prompt) },
                                onSetDefault: { library.setDefault(prompt.id) },
                                onEdit: { editingPrompt = prompt },
                                onDelete: { library.deletePrompt(id: prompt.id) }
                            )
                        }
                    } header: {
                        Text("My Prompts")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search prompts")
            .navigationTitle("Prompt Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreatingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreatingNew) {
                PromptEditorView(mode: .create) { prompt in
                    library.addPrompt(prompt)
                }
            }
            .sheet(item: $editingPrompt) { prompt in
                PromptEditorView(mode: .edit(prompt)) { updated in
                    library.updatePrompt(updated)
                }
            }
        }
    }

    private var filteredPrompts: [SavedPrompt] {
        let categoryFiltered: [SavedPrompt]
        if searchText.isEmpty {
            categoryFiltered = library.prompts.filter { $0.category == selectedCategory }
        } else {
            categoryFiltered = library.prompts.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        return categoryFiltered.sorted { $0.isBuiltIn && !$1.isBuiltIn }
    }

    private func applyPrompt(_ prompt: SavedPrompt) {
        // Apply to the current conversation
        if let sysIdx = chatState.conversation.messages.firstIndex(where: { $0.role == .system }) {
            chatState.conversation.messages[sysIdx] = .systemPrompt(prompt.content)
        }
        dismiss()
    }
}

// MARK: - Default Prompt Picker

/// A compact picker for selecting the default system prompt.
struct DefaultPromptPicker: View {
    let chatState: ChatState
    private var library: PromptLibrary { PromptLibrary.shared }

    var body: some View {
        Picker("Default Prompt", selection: Binding(
            get: { library.defaultPromptID },
            set: { library.setDefault($0) }
        )) {
            Text("App Default").tag(UUID?.nil)
            ForEach(library.prompts) { prompt in
                Text(prompt.name).tag(Optional(prompt.id))
            }
        }
    }
}

// MARK: - Category Pill

/// A small pill-shaped button for filtering by category.
struct CategoryPill: View {
    let category: PromptCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: category.systemImage)
                    .font(.caption2)
                Text(category.description)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? category.color.opacity(0.2) : Color(.systemGray6)
            )
            .foregroundStyle(isSelected ? category.color : .secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prompt Row

/// A single row in the prompt library list.
struct PromptRow: View {
    let prompt: SavedPrompt
    let isDefault: Bool
    let onApply: () -> Void
    let onSetDefault: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: prompt.category.systemImage)
                    .foregroundStyle(prompt.category.color)
                    .font(.caption)

                Text(prompt.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                if isDefault {
                    Text("Default")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.clipShape(Capsule()))
                }

                if prompt.isBuiltIn {
                    Text("Built-in")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            Text(prompt.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Button {
                    onApply()
                } label: {
                    Label("Apply", systemImage: "text.badge.checkmark")
                        .font(.caption)
                }
                .tint(.blue)

                Button {
                    onSetDefault()
                } label: {
                    Label("Set Default", systemImage: "star")
                        .font(.caption)
                }
                .tint(.orange)

                if let onEdit = onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.caption)
                    }
                    .tint(.teal)
                }

                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Prompt Editor Mode

/// The mode for the prompt editor sheet.
enum PromptEditorMode {
    case create
    case edit(SavedPrompt)
}

// MARK: - Prompt Editor View

/// A view for creating or editing a system prompt.
struct PromptEditorView: View {
    let mode: PromptEditorMode
    let onSave: (SavedPrompt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var content = ""
    @State private var category: PromptCategory = .custom

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Prompt name", text: $name)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(PromptCategory.allCases, id: \.self) { cat in
                            Label(cat.description, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                }

                Section("Prompt Content") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                }

                Section {
                    Button("Save Prompt") {
                        savePrompt()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle(isEditing ? "Edit Prompt" : "New Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if case .edit(let prompt) = mode {
                    name = prompt.name
                    content = prompt.content
                    category = prompt.category
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func savePrompt() {
        switch mode {
        case .create:
            let prompt = SavedPrompt.create(name: name, content: content, category: category)
            onSave(prompt)
        case .edit(let original):
            var updated = original
            updated.name = name
            updated.content = content
            updated.category = category
            onSave(updated)
        }
        dismiss()
    }
}
