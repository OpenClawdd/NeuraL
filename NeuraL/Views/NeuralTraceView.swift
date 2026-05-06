import SwiftUI

struct NeuralTraceView: View {
    let message: ChatMessage
    let isTracing: Bool
    let rawTraceAccess: Bool
    let isInitiallyExpanded: Bool
    @State private var expanded = false

    init(message: ChatMessage, isTracing: Bool, rawTraceAccess: Bool, isInitiallyExpanded: Bool = false) {
        self.message = message
        self.isTracing = isTracing
        self.rawTraceAccess = rawTraceAccess
        self.isInitiallyExpanded = isInitiallyExpanded
        _expanded = State(initialValue: isInitiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Neural Trace")
                    Spacer()
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("~\(message.traceTokenEstimate) tok")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(rawTraceAccess ? (message.reasoningTrace ?? "No trace") : (message.traceSummary ?? "Remembered locally"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var status: String {
        if isTracing { return "Tracing reasoning…" }
        if message.traceWasTruncated { return "Partial trace" }
        if message.reasoningTrace?.isEmpty == false { return "Trace sealed" }
        return "Local-only"
    }
}
