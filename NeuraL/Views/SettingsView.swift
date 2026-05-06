import SwiftUI

struct SettingsView: View {
    @ObservedObject var chatState: ChatState

    var body: some View {
        Form {
            Section("DreamState") {
                Picker("Show Neural Trace", selection: $chatState.dreamSettings.traceVisibility) {
                    ForEach(DreamStateSettings.TraceVisibility.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Raw Trace Access", isOn: $chatState.dreamSettings.rawTraceAccess)
                Toggle("Auto-create Dreams", isOn: $chatState.dreamSettings.autoCreateDreams)
                Picker("Dreamboard Retention", selection: $chatState.dreamSettings.retention) {
                    ForEach(DreamStateSettings.Retention.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: chatState.dreamSettings.retention) { _, _ in
                    chatState.applyRetention()
                }
            }
        }
    }
}
