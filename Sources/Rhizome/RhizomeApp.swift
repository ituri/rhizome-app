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
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.onForeground() }   // reconnect + flush the offline queue
        }
    }
}
