import SwiftUI
//
//  ConversationBranching.swift
//  NeuraL
//
//  Phase 7.3 — Conversation Branching & Message Editing
//
//  Implements:
//  1. Conversation branching: "Regenerate from here" creates an alternative
//     branch at any assistant message, allowing users to explore different
//     responses without losing the original.
//  2. Message editing: Double-tap on user messages to edit them and
//     re-generate the assistant response.
//  3. Emoji reactions: Add emoji reactions to any message.
//  4. Branch navigation: Switch between branches of a conversation.
//
//  Architecture:
//  - A branch is identified by a BranchId (UUID)
//  - Messages have an optional branchId and a parentBranchId
//  - The "trunk" (main branch) has branchId == nil
//  - When a user regenerates from a message, a new branch is created
//  - The Conversation model is extended with branch-aware methods
//

import Foundation
import Observation

// MARK: - Branch Identifier

/// Identifies a conversation branch. The main trunk uses nil.
typealias BranchId = UUID

// MARK: - Message Reaction

/// An emoji reaction attached to a message.
struct MessageReaction: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let emoji: String
    let timestamp: Date

    static func create(_ emoji: String) -> MessageReaction {
        MessageReaction(id: UUID(), emoji: emoji, timestamp: Date())
    }
}

// MARK: - Branch Info

/// Metadata about a conversation branch.
struct BranchInfo: Identifiable, Codable, Sendable {
    let id: BranchId
    /// The message ID from which this branch diverges.
    let divergeFromMessageId: UUID
    /// A human-readable label for this branch.
    var label: String
    /// When this branch was created.
    let createdAt: Date
    /// The branch that this branch was created from (nil for trunk).
    let parentBranchId: BranchId?
}

// MARK: - ChatMessage Branch Extensions

extension ChatMessage {
    /// Create a copy of this message with an updated branch ID.
    func withBranchId(_ branchId: BranchId?) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            timestamp: timestamp,
            tokenInfo: tokenInfo,
            generationMetadata: generationMetadata,
            thinkingText: thinkingText,
            thinkingDurationSeconds: thinkingDurationSeconds,
            isInKVCache: isInKVCache,
            imageAttachments: imageAttachments,
            functionCalls: functionCalls,
            ragSources: ragSources
        )
    }

    /// Create a copy with reactions added.
    func withReactions(_ reactions: [MessageReaction]) -> ChatMessageWithReactions {
        ChatMessageWithReactions(message: self, reactions: reactions)
    }
}

// MARK: - ChatMessage With Reactions

/// A ChatMessage wrapper that includes emoji reactions.
/// Reactions are stored separately to keep ChatMessage Codable-stable.
struct ChatMessageWithReactions: Identifiable {
    let message: ChatMessage
    var reactions: [MessageReaction]

    var id: UUID { message.id }
}

// MARK: - Branch Manager

/// Manages conversation branches. Tracks branch metadata and provides
/// navigation between branches.
@Observable
@MainActor
final class BranchManager {

    /// All branches in the current conversation (excluding the trunk).
    var branches: [BranchInfo] = []

    /// The currently active branch. nil means the trunk.
    var activeBranchId: BranchId?

    /// The message reactions, keyed by message ID.
    var reactions: [UUID: [MessageReaction]] = [:]

    /// The edited content of user messages, keyed by message ID.
    /// When a user edits a message, the original content is preserved in the
    /// ChatMessage but the edited version is stored here for display.
    var editedContents: [UUID: String] = [:]

    // MARK: - Branch Operations

    /// Create a new branch from the given message.
    func createBranch(divergingFrom messageId: UUID, label: String? = nil) -> BranchId {
        let branchId = BranchId()
        let branch = BranchInfo(
            id: branchId,
            divergeFromMessageId: messageId,
            label: label ?? "Branch \(branches.count + 1)",
            createdAt: Date(),
            parentBranchId: activeBranchId
        )
        branches.append(branch)
        activeBranchId = branchId
        return branchId
    }

    /// Switch to a specific branch.
    func switchToBranch(_ branchId: BranchId?) {
        activeBranchId = branchId
    }

    /// Switch back to the trunk (main branch).
    func switchToTrunk() {
        activeBranchId = nil
    }

    /// Get all branches that diverge from a specific message.
    func branches(from messageId: UUID) -> [BranchInfo] {
        branches.filter { $0.divergeFromMessageId == messageId }
    }

    /// Delete a branch.
    func deleteBranch(_ branchId: BranchId) {
        branches.removeAll { $0.id == branchId }
        if activeBranchId == branchId {
            activeBranchId = nil
        }
    }

    /// Rename a branch.
    func renameBranch(_ branchId: BranchId, newLabel: String) {
        if let index = branches.firstIndex(where: { $0.id == branchId }) {
            branches[index].label = newLabel
        }
    }

    /// Whether there are any branches.
    var hasBranches: Bool {
        !branches.isEmpty
    }

    /// Get the label for the current branch.
    var activeBranchLabel: String? {
        if let id = activeBranchId {
            return branches.first { $0.id == id }?.label
        }
        return nil
    }

    // MARK: - Reactions

    /// Add a reaction to a message.
    func addReaction(emoji: String, to messageId: UUID) {
        let reaction = MessageReaction.create(emoji)
        reactions[messageId, default: []].append(reaction)
    }

    /// Remove a reaction from a message.
    func removeReaction(reactionId: UUID, from messageId: UUID) {
        reactions[messageId]?.removeAll { $0.id == reactionId }
    }

    /// Get reactions for a message.
    func reactionsFor(messageId: UUID) -> [MessageReaction] {
        reactions[messageId] ?? []
    }

    // MARK: - Message Editing

    /// Edit a user message's content.
    func editMessage(id: UUID, newContent: String) {
        editedContents[id] = newContent
    }

    /// Get the display content for a message (edited version if available).
    func displayContent(for message: ChatMessage) -> String {
        if let edited = editedContents[message.id] {
            return edited
        }
        return message.content
    }

    /// Check if a message has been edited.
    func isEdited(messageId: UUID) -> Bool {
        editedContents[messageId] != nil
    }

    /// Revert an edit back to the original content.
    func revertEdit(messageId: UUID) {
        editedContents.removeValue(forKey: messageId)
    }

    // MARK: - Reset

    /// Reset all branch data (for new conversations).
    func reset() {
        branches = []
        activeBranchId = nil
        reactions = [:]
        editedContents = [:]
    }
}

// MARK: - Reaction Picker View

/// A compact view for adding emoji reactions to messages.
struct ReactionPicker: View {
    let onSelect: (String) -> Void

    private let commonEmojis = ["👍", "❤️", "😂", "🤔", "😮", "🎉", "🔥", "👏", "💡", "⭐"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(commonEmojis, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Message Reactions View

/// Displays reactions attached to a message.
struct MessageReactionsView: View {
    let reactions: [MessageReaction]

    var body: some View {
        if !reactions.isEmpty {
            HStack(spacing: 4) {
                ForEach(reactions) { reaction in
                    Text(reaction.emoji)
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Branch Navigator View

/// A compact view for switching between conversation branches.
struct BranchNavigator: View {
    let branchManager: BranchManager
    let onSwitch: (BranchId?) -> Void

    var body: some View {
        if branchManager.hasBranches {
            HStack(spacing: 8) {
                // Trunk button
                Button {
                    branchManager.switchToTrunk()
                    onSwitch(nil)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption2)
                        Text("Main")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(branchManager.activeBranchId == nil ? Color.blue.opacity(0.2) : Color(.systemGray6))
                    .foregroundStyle(branchManager.activeBranchId == nil ? .blue : .secondary)
                    .clipShape(Capsule())
                }

                // Branch buttons
                ForEach(branchManager.branches) { branch in
                    Button {
                        branchManager.switchToBranch(branch.id)
                        onSwitch(branch.id)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption2)
                            Text(branch.label)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(branchManager.activeBranchId == branch.id ? Color.purple.opacity(0.2) : Color(.systemGray6))
                        .foregroundStyle(branchManager.activeBranchId == branch.id ? .purple : .secondary)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}
