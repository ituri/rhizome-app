import SwiftUI
import RhizomeKit

/// Account menu (user, reload, sign out) — shared by the Journal and Outline tabs.
struct AccountMenu: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Menu {
            if let user = model.user {
                Text("Signed in as \(user.username)")
            }
            Button("Reload", systemImage: "arrow.clockwise") {
                Task { await model.loadDoc() }
            }
            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                Task { await model.signOut() }
            }
        } label: {
            Image(systemName: "person.crop.circle")
        }
    }
}

/// Graph switcher — only shown when the user has more than one graph.
struct GraphSwitcher: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.graphs.count > 1 {
            Menu {
                ForEach(model.graphs) { graph in
                    Button {
                        Task { await model.selectGraph(graph.id) }
                    } label: {
                        if graph.id == model.activeGraphID {
                            Label(graph.name, systemImage: "checkmark")
                        } else {
                            Text(graph.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "square.stack.3d.up")
            }
        }
    }
}
