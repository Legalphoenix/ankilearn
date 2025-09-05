import SwiftUI
import UniformTypeIdentifiers

struct MnemonicsView: View {
    @State private var instructions: String = "You are a mnemonic creating agent. Your only role is to respond by creating a mnemonic that the user can use to aid in their recall of the target word. The target word has been provided to you."
    @State private var prompt: String = ""

    @State private var isGenerating = false
    @State private var statusMessage = "Idle"
    @State private var generatedAudioData: Data?
    @State private var logMessages: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mnemonic Generation (Debug)")
                .font(.title2.bold())

            Text("Instructions")
            TextEditor(text: $instructions)
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                .disabled(isGenerating)

            Text("Text Prompt")
            TextField("Enter a word or phrase to create a mnemonic for", text: $prompt)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(isGenerating)

            HStack(spacing: 12) {
                Button("Generate Mnemonic") {
                    generateMnemonic()
                }
                .disabled(isGenerating || prompt.isEmpty)

                if isGenerating {
                    ProgressView()
                }

                Button("Save As...") {
                    saveAudio()
                }
                .disabled(generatedAudioData == nil)

                Spacer()

                Button("Clear Logs") {
                    logMessages.removeAll()
                }
            }

            Text(statusMessage)
                .foregroundColor(.secondary)

            // Log Console
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(logMessages, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)) }
                }
                .padding(8)
            }
            .frame(minHeight: 100, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))


            Spacer()
        }
        .padding()
    }

    private func generateMnemonic() {
        guard let apiKey = Keychain.loadAPIKey(), !apiKey.isEmpty else {
            statusMessage = "Error: API key is not set. Please set it in the app settings."
            return
        }

        logMessages.removeAll()
        isGenerating = true
        statusMessage = "Generating..."
        generatedAudioData = nil

        Task {
            do {
                let client = RealtimeAPIClient(apiKey: apiKey)
                let data = try await client.generate(instructions: instructions, prompt: prompt) { logMessage in
                    DispatchQueue.main.async {
                        self.logMessages.append(logMessage)
                    }
                }

                await MainActor.run {
                    self.generatedAudioData = data
                    self.statusMessage = "Success! Audio generated (\(data.count) bytes). Ready to save."
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Error: \(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }

    private func saveAudio() {
        guard let audioData = generatedAudioData else {
            statusMessage = "Error: No audio data to save."
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [UTType.mp3]
        let sanitizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        savePanel.nameFieldStringValue = "\(sanitizedPrompt)_mnemonic.mp3"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try audioData.write(to: url)
                    DispatchQueue.main.async {
                        self.statusMessage = "Successfully saved to \(url.lastPathComponent)"
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.statusMessage = "Error saving file: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
