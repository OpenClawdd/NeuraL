import SwiftUI
struct ModelsView: View {
    var body: some View {
        NavigationView {
            List(["Llama 3.2 1B", "Llama 3.2 3B"], id: \.self) { name in
                Text(name)
            }
            .navigationTitle("Models")
        }
    }
}
