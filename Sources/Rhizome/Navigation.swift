import SwiftUI
import RhizomeKit

extension View {
    /// A small status/diagnostic alert for the geo button (permission, no fix, success, …).
    /// `presenting: model.geoMessage` is read here in the body so the view tracks the
    /// @Observable change and the alert actually appears.
    @MainActor
    func geoAlert(_ model: AppModel) -> some View {
        alert(
            "Standort",
            isPresented: Binding(get: { model.geoMessage != nil }, set: { if !$0 { model.geoMessage = nil } }),
            presenting: model.geoMessage
        ) { _ in
            Button("OK", role: .cancel) { model.geoMessage = nil }
        } message: { Text($0) }
    }

    /// A generic transient alert (upload/quota errors, …), title-neutral so it fits any context.
    @MainActor
    func noticeAlert(_ model: AppModel) -> some View {
        alert(
            "Rhizome",
            isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
            presenting: model.notice
        ) { _ in
            Button("OK", role: .cancel) { model.notice = nil }
        } message: { Text($0) }
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
