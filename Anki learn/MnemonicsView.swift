import SwiftUI
import UniformTypeIdentifiers

struct MnemonicsView: View {
    @State private var instructions: String = "You are a mnemonic creating agent. Your only role is to respond by creating a mnemonic that the user can use to aid in their recall of the target word. The target word has been provided to you."
    @State private var prompt: String = ""

    @State private var isGenerating = false
    @State private var statusMessage = "Idle"
    @State private var generatedAudioData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mnemonic Generation")
                .font(.title2.bold())

            Text("Instructions")
            TextEditor(text: $instructions)
                .frame(height: 150)
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
            }

            Text(statusMessage)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    private func generateMnemonic() {
        guard let apiKey = Keychain.loadAPIKey(), !apiKey.isEmpty else {
            statusMessage = "Error: API key is not set. Please set it in the app settings."
            return
        }

        isGenerating = true
        statusMessage = "Generating..."
        generatedAudioData = nil

        Task {
            do {
                let client = RealtimeAPIClient(apiKey: apiKey)
                let data = try await client.generate(instructions: instructions, prompt: prompt)

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
