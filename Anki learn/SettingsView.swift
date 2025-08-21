import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var ankiProfiles: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title.bold())
                .padding(.bottom, 10)

            GroupBox(label: Text("Anki Integration").font(.headline)) {
                VStack(alignment: .leading, spacing: 15) {
                    Toggle("Copy media to Anki profile on build", isOn: $app.copyToAnki)

                    HStack {
                        Picker("Anki Profile:", selection: $app.selectedProfile) {
                            ForEach(ankiProfiles, id: \.self) { profile in
                                Text(profile).tag(profile)
                            }
                        }
                        .onAppear(perform: loadProfiles)
                        .disabled(!app.copyToAnki)

                        Button("Reload") {
                            loadProfiles()
                        }
                    }

                    Button("Reveal collection.media folder") {
                        revealMediaFolder()
                    }
                    .disabled(app.selectedProfile.isEmpty)
                }
                .padding(.top, 10)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 250)
    }

    private func loadProfiles() {
        ankiProfiles = AnkiProfile.availableProfiles()
        if !ankiProfiles.contains(app.selectedProfile) {
            app.selectedProfile = ankiProfiles.first ?? ""
        }
    }

    private func revealMediaFolder() {
        guard !app.selectedProfile.isEmpty else { return }
        let url = AnkiProfile.collectionMedia(for: app.selectedProfile)
        NSWorkspace.shared.open(url)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppState())
    }
}
