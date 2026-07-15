import SwiftUI

struct ContentView: View {
    @State private var isLoading = true

    private var paper: Color {
        Color(red: Config.background.red, green: Config.background.green, blue: Config.background.blue)
    }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            #if os(iOS)
            WebView(url: Config.serverURL, isLoading: $isLoading)
                .ignoresSafeArea(edges: .bottom) // extend under the home indicator; keep the top inset
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.secondary)
            }
            #else
            VStack(spacing: 12) {
                Image(systemName: "leaf")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Rhizome runs on iOS.")
                Link(Config.serverURL.absoluteString, destination: Config.serverURL)
            }
            .padding()
            #endif
        }
    }
}
