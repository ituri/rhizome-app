import SwiftUI
import RhizomeKit

extension View {
    /// A small status/diagnostic alert for the geo button (permission, no fix, success, …).
    @MainActor
    func geoAlert(_ model: AppModel) -> some View {
        alert("Standort", isPresented: Binding(
            get: { model.geoMessage != nil },
            set: { if !$0 { model.geoMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.geoMessage = nil }
        } message: {
            Text(model.geoMessage ?? "")
        }
    }

    /// Intercept taps on internal `rhizome://n/<id>` links and push the target
    /// page onto the stack instead of trying to open a URL.
    @MainActor
    func handleNodeLinks(path: Binding<[String]>, model: AppModel) -> some View {
        environment(\.openURL, OpenURLAction { url in
            if let id = RichText.nodeID(from: url) {
                path.wrappedValue.append(id)   // go to the linked node itself
                return .handled
            }
            return .systemAction
        })
    }
}
