import SwiftUI

@main
struct RhizomeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .tint(rzAccentColor(model.accent))
                .preferredColorScheme(model.theme.colorScheme)
                .task { await model.bootstrap() }
                .onOpenURL { model.handleURL($0) }   // widget → rhizome://capture
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.onForeground()               // reconnect + flush the offline queue
                Task { await model.unlock() }       // prompt Face ID if we're locked
            case .background:
                model.lockIfEnabled()               // re-lock when backgrounded
            default:
                break
            }
        }
    }
}
