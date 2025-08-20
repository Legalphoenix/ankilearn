import SwiftUI

@main
struct MnemonicMakerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandMenu("MnemonicMaker") {
                Button("Set OpenAI API Key…") {
                    appState.showApiKeySheet = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
