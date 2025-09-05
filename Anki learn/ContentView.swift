import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationView {
            Sidebar()
            MainView()
        }
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $app.showApiKeySheet) {
            APIKeySheet()
        }
        .sheet(isPresented: $app.showSettingsSheet) {
            SettingsView()
        }
        .onAppear {
            app.loadSavedLists()
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List {
            Section("Project") {
                NavigationLink(destination: ImportView()) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                NavigationLink(destination: ImageSettingsView()) {
                    Label("Image", systemImage: "photo")
                }
                NavigationLink(destination: AudioSettingsView()) {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
                NavigationLink(destination: BuildView()) {
                    Label("Build", systemImage: "hammer")
                }
                NavigationLink(destination: MnemonicsView()) {
                    Label("Mnemonics", systemImage: "brain.head.profile")
                }
            }
        }
        .listStyle(SidebarListStyle())
    }
}

struct MainView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(spacing: 16) {
            Text("MnemonicMaker")
                .font(.largeTitle.bold())
            Text("Create mnemonic images and audio for phrase/translation pairs, then export an Anki-ready deck.")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}

struct APIKeySheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var key: String = Keychain.loadAPIKey() ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OpenAI API Key")
                .font(.title2.bold())
            SecureField("sk-...", text: $key)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            HStack {
                Spacer()
                Button("Save") {
                    do {
                        try Keychain.saveAPIKey(key)
                        dismiss()
                    } catch {
                        NSApplication.shared.presentError(error)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
