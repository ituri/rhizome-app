import SwiftUI
import RhizomeKit

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
