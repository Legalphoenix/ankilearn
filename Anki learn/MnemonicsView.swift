import SwiftUI
import AVFoundation

struct MnemonicsView: View {
    @EnvironmentObject var app: AppState
    @State private var isLoading = false
    @State private var player: AVAudioPlayer?
    @State private var lastError: String?
    @State private var debugEnabled = true
    @State private var debugLines: [String] = []
    @State private var lastAudioWav: Data? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mnemonics")
                .font(.title2.bold())

            // Include Mnemonics toggle moved to Build tab

            Group {
                Text("Instructions for the LLM")
                    .foregroundColor(.secondary)
                TextEditor(text: $app.mnemonicInstructions)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
            }

            Group {
                HStack {
                    Text("Realtime model:")
                    TextField("gpt-realtime", text: $app.realtimeModel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 220)
                    Spacer()
                }
                Text("Text prompt with target word (e.g., ‘Target: maison’)\nOnly the target word is required — the app will prefix ‘Target: ’ when sending.")
                    .foregroundColor(.secondary)
                HStack {
                    TextField("maison", text: $app.mnemonicPrompt)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit { Task { await testGenerate() } }
                    Button("Test Mnemonic") { Task { await testGenerate() } }
                        .disabled(isLoading || app.mnemonicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Replay") { replay() }
                        .disabled(isLoading || lastAudioWav == nil)
                }
            }

            if isLoading { ProgressView().padding(.vertical, 4) }
            if let err = lastError { Text(err).foregroundColor(.red) }

            Group {
                HStack {
                    Toggle("Debug logging", isOn: $debugEnabled)
                    Spacer()
                    Button("Clear") { debugLines.removeAll() }
                        .disabled(debugLines.isEmpty)
                }
                if debugEnabled {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(debugLines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(size: 11, design: .monospaced))
                            }
                        }
                    }
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                }
            }

            Spacer()
        }
        .padding()
    }

    @MainActor
    private func testGenerate() async {
        lastError = nil
        if debugEnabled { debugLines.removeAll() }
        guard let apiKey = Keychain.loadAPIKey() else {
            lastError = "Set API key (⌘,) first."
            return
        }
        let target = app.mnemonicPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let rt = RealtimeClient(cfg: .init(apiKey: apiKey, model: app.realtimeModel))
            let audio = try await rt.generateMnemonicAudio(
                instructions: app.mnemonicInstructions,
                targetWord: target,
                voice: app.ttsVoice,
                logger: { line in
                    guard debugEnabled else { return }
                    DispatchQueue.main.async { debugLines.append(line) }
                }
            )
            // Realtime WS returns raw PCM16 @ 24kHz mono; wrap in WAV for AVAudioPlayer
            let wav = AudioUtil.pcm16ToWav(audio)
            lastAudioWav = wav
            player = try AVAudioPlayer(data: wav)
            player?.play()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    private func replay() {
        if let p = player {
            p.currentTime = 0
            p.play()
            return
        }
        if let wav = lastAudioWav {
            do {
                player = try AVAudioPlayer(data: wav)
                player?.play()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}

// WAV wrapping moved to AudioUtil in Services.swift
