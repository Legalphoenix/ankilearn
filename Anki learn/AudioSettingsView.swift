import SwiftUI
import AVFoundation

struct AudioSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var player: AVAudioPlayer?

    let voices = ["alloy","ash","ballad","coral","echo","fable","nova","onyx","sage","shimmer"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3) Audio Settings")
                .font(.title2.bold())

            HStack {
                Picker("Voice", selection: $app.ttsVoice) {
                    ForEach(voices, id: \.self) { Text($0) }
                }
                Picker("Format", selection: $app.audioFormat) {
                    ForEach(AudioFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Also synthesize translation (back)", isOn: $app.synthesizeBackToo)
                Spacer()
                Button("Test Voice") {
                    Task { await testVoice() }
                }
            }
            .padding(.bottom, 8)

            Text("Global instructions (prepended to every card). E.g., \"Speak in a cheerful, upbeat tone.\"")
                .foregroundColor(.secondary)

            TextEditor(text: $app.audioGlobalStyle)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

            Text("Tip: Keep MP3 for small file sizes and broad compatibility in Anki.")
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    func testVoice() async {
        do {
            guard let apiKey = Keychain.loadAPIKey() else { throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Set API key (⌘,) first."]) }
            let client = OpenAIClient(cfg: .init(apiKey: apiKey))
            let data = try await client.synthesize(input: "Bonjour, faisons un test de voix.",
                                                   voice: app.ttsVoice,
                                                   format: app.audioFormat.rawValue,
                                                   model: "gpt-4o-mini-tts",
                                                   instructions: app.audioGlobalStyle)
            try await MainActor.run {
                player = try AVAudioPlayer(data: data)
                player?.play()
            }
        } catch {
            NSApplication.shared.presentError(error)
        }
    }
}
