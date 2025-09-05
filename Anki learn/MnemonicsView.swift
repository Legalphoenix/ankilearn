import SwiftUI
import AVFoundation

struct MnemonicsView: View {
    @EnvironmentObject var app: AppState
    @State private var isLoading = false
    @State private var isGeneratingImage = false
    @State private var player: AVAudioPlayer?
    @State private var lastError: String?
    @State private var debugEnabled = true
    @State private var debugLines: [String] = []
    @State private var lastAudioWav: Data? = nil
    @State private var lastText: String = ""
    @State private var previewImageData: Data?

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
                    Button("Generate Image from text") { Task { await generateImageFromText() } }
                        .disabled(isLoading || isGeneratingImage || lastText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if isLoading { ProgressView().padding(.vertical, 4) }
            if let err = lastError { Text(err).foregroundColor(.red) }

            if !lastText.isEmpty {
                Text("Mnemonic text (read-only)").foregroundColor(.secondary)
                HStack(alignment: .top) {
                    ScrollView {
                        Text(lastText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 80)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lastText, forType: .string)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
            }

            if let data = previewImageData, let img = NSImage(data: data) {
                Text("Preview: Image from mnemonic text")
                    .foregroundColor(.secondary)
                HStack {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 256, height: 256)
                    Spacer()
                }
            }

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
            let out = try await rt.generateMnemonic(
                instructions: app.mnemonicInstructions,
                targetWord: target,
                voice: app.ttsVoice,
                logger: { line in
                    guard debugEnabled else { return }
                    DispatchQueue.main.async { debugLines.append(line) }
                }
            )
            // Play audio
            let wav = AudioUtil.pcm16ToWav(out.audio)
            lastAudioWav = wav
            player = try AVAudioPlayer(data: wav)
            player?.play()
            // Save text
            lastText = out.text
            if debugEnabled { debugLines.append("Text: \(out.text)") }
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

    @MainActor
    private func generateImageFromText() async {
        guard !lastText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let apiKey = Keychain.loadAPIKey() else {
            lastError = "Set API key (⌘,) first."
            return
        }
        isGeneratingImage = true
        defer { isGeneratingImage = false }
        do {
            let client = OpenAIClient(cfg: .init(apiKey: apiKey))
            let prompt = PromptBuilder.renderMnemonicImagePrompt(template: app.mnemonicImagePromptTemplate,
                                                                 globalStyle: app.imageGlobalStyle,
                                                                 mnemonicText: lastText)
            let data = try await client.generateImage(prompt: prompt, size: app.imageSize, quality: app.imageQuality, format: "jpeg")
            previewImageData = data
        } catch {
            lastError = error.localizedDescription
        }
    }
}

// WAV wrapping moved to AudioUtil in Services.swift
