import SwiftUI
import RhizomeKit

extension View {
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
