import SwiftUI
import WebKit

struct ArtifactSandboxView: View {
    let artifact: GeneratedArtifact
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(artifact.title, systemImage: "macwindow.on.rectangle")
                    .font(.caption.bold())
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(artifact.estimatedMemoryBytes), countStyle: .memory))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                if artifact.isRenderable {
                    SandboxedWebView(html: htmlDocument(for: artifact))
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
                        }
                } else {
                    ScrollView(.horizontal) {
                        Text(artifact.source)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(maxHeight: 180)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func htmlDocument(for artifact: GeneratedArtifact) -> String {
        switch artifact.kind {
        case .html, .sandbox:
            return artifact.source
        case .javascript:
            return """
            <!doctype html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <style>
                html, body { margin: 0; min-height: 100%; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f6f7f9; color: #111; }
                body { padding: 16px; }
                canvas { max-width: 100%; border-radius: 12px; background: white; }
                #log { white-space: pre-wrap; font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; }
              </style>
            </head>
            <body>
              <div id="app"></div>
              <pre id="log"></pre>
              <script>
                const log = (...items) => {
                  document.getElementById('log').textContent += items.join(' ') + '\\n';
                };
                window.onerror = (message, source, line, column) => {
                  log('Runtime error:', message, 'at', line + ':' + column);
                };
              </script>
              <script>
              \(artifact.source)
              </script>
            </body>
            </html>
            """
        case .css:
            return ""
        }
    }
}

private struct SandboxedWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = false
        configuration.suppressesIncrementalRendering = false

        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = webpagePreferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
