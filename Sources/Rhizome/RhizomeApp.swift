import SwiftUI

@main
struct RhizomeApp: App {
    @State private var model = AppModel()

    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .tint(.rzAccent)
                .preferredColorScheme(.light)
                .task { await model.bootstrap() }
        }
    }
}
