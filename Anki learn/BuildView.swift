import SwiftUI

struct BuildView: View {
    @EnvironmentObject var app: AppState
    @State private var log: [String] = []
    @State private var runningTask: Task<Void, Never>?
    @State private var deckLabel: String = ""
    @State private var runId: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("4) Build & Export")
                .font(.title2.bold())

            HStack {
                Button("Choose Export Folder…") { chooseFolder() }
                if let url = app.exportFolderURL {
                    Text(url.path).lineLimit(1).truncationMode(.middle)
                } else {
                    Text("No folder selected").foregroundColor(.secondary)
                }
                Spacer()
            }

            TextField("Deck Label (optional)", text: $deckLabel)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 250)

            HStack(spacing: 12) {
                Button(app.isBuilding ? "Stop" : "Start Build") {
                    if app.isBuilding {
                        runningTask?.cancel()
                        app.isBuilding = false
                    } else {
                        startBuild()
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(app.cards.isEmpty || app.exportFolderURL == nil)

                if app.isBuilding {
                    ProgressView(value: Double(app.progress.completed),
                                 total: Double(app.progress.total))
                        .frame(width: 240)
                    Text("\(app.progress.completed)/\(app.progress.total)  •  Failed: \(app.progress.failed)")
                        .foregroundColor(.secondary)
                }
            }

            Text(app.progress.currentStatus).foregroundColor(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(log, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)) }
                }
            }
            .frame(minHeight: 220)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

            Spacer()
        }
        .padding()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.begin { resp in
            if resp == .OK {
                app.exportFolderURL = panel.url
            }
        }
    }

    func makeRunId() -> String {
        func slug(_ s: String) -> String {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            return s.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .components(separatedBy: allowed.inverted).joined()
                .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        }
        let label = deckLabel.isEmpty ? "deck" : slug(deckLabel)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(label)-\(df.string(from: Date()))"
    }

    func startBuild() {
        runId = makeRunId()
        guard let folder = app.exportFolderURL else { return }
        guard let apiKey = Keychain.loadAPIKey() else {
            NSApplication.shared.presentError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Set API key (⌘,) first."]))
            return
        }

        app.isBuilding = true
        app.progress = .init(total: app.cards.count * 2, completed: 0, failed: 0, currentStatus: "Starting…")
        log.removeAll()

        runningTask = Task {
            let client = OpenAIClient(cfg: .init(apiKey: apiKey))
            let fm = FileManager.default
            let mediaDir = folder.appendingPathComponent("media", isDirectory: true)
            do { try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true) } catch {}

            // Result type for concurrent tasks
            struct CardResult {
                let cardId: UUID
                let cardIndex: Int
                let imageResult: Result<String, Error>
                let audioResult: Result<String, Error>
            }

            var imageNames: [UUID: String] = [:]
            var audioNames: [UUID: String] = [:]

            let chunkSize = 10 // Process 10 cards concurrently
            let cardChunks = app.cards.chunked(into: chunkSize)

            for (chunkIndex, chunk) in cardChunks.enumerated() {
                if Task.isCancelled { break }

                await MainActor.run {
                    app.progress.currentStatus = "Processing batch \(chunkIndex + 1)/\(cardChunks.count)..."
                }

                await withTaskGroup(of: CardResult.self) { group in
                    for card in chunk {
                        group.addTask {
                            // --- IMAGE ---
                            let imgName = "\(runId)_\(String(format: "%04d", card.index))_img.jpg"
                            let imageTaskResult: Result<String, Error> = await {
                                do {
                                    let prompt = PromptBuilder.scenePrompt(globalStyle: app.imageGlobalStyle, phrase: card.phrase, translation: card.translation)
                                    let imgData = try await retry(times: 3, delay: 2.0) {
                                        try await client.generateImage(prompt: prompt, size: app.imageSize, quality: app.imageQuality, format: "jpeg")
                                    }
                                    let imgURL = mediaDir.appendingPathComponent(imgName)
                                    try imgData.write(to: imgURL)
                                    return .success(imgName)
                                } catch {
                                    return .failure(error)
                                }
                            }()

                            // --- AUDIO ---
                            let sndName = "\(runId)_\(String(format: "%04d", card.index))_audio.\(app.audioFormat.rawValue)"
                            let audioTaskResult: Result<String, Error> = await {
                                do {
                                    let audioData = try await retry(times: 3, delay: 2.0) {
                                        try await client.synthesize(input: card.phrase, voice: app.ttsVoice, format: app.audioFormat.rawValue, model: "gpt-4o-mini-tts", instructions: app.audioGlobalStyle)
                                    }
                                    let audioURL = mediaDir.appendingPathComponent(sndName)
                                    try audioData.write(to: audioURL)
                                    return .success(sndName)
                                } catch {
                                    return .failure(error)
                                }
                            }()

                            return CardResult(cardId: card.id, cardIndex: card.index, imageResult: imageTaskResult, audioResult: audioTaskResult)
                        }
                    }

                    // Process results as they complete
                    for await result in group {
                        switch result.imageResult {
                        case .success(let filename):
                            imageNames[result.cardId] = filename
                            log.append("✓ Image \(result.cardIndex): \(filename)")
                        case .failure(let error):
                            log.append("✗ Image \(result.cardIndex) failed: \(error.localizedDescription)")
                            app.progress.failed += 1
                        }
                        app.progress.completed += 1

                        switch result.audioResult {
                        case .success(let filename):
                            audioNames[result.cardId] = filename
                            log.append("✓ Audio \(result.cardIndex): \(filename)")
                        case .failure(let error):
                            log.append("✗ Audio \(result.cardIndex) failed: \(error.localizedDescription)")
                            app.progress.failed += 1
                        }
                        app.progress.completed += 1
                    }
                }
            }

            // write TSV at the end
            if !Task.isCancelled {
                do {
                    let filename = try AnkiExporter.writeExport(cards: app.cards, imageNames: imageNames, audioNames: audioNames, to: folder, runId: runId)
                    await MainActor.run { log.append("✓ Wrote \(filename)") }
                } catch {
                    await MainActor.run { log.append("✗ Writing deck TSV failed: \(error.localizedDescription)") }
                }
            }

            // copy to anki
            if !Task.isCancelled && app.copyToAnki && !app.selectedProfile.isEmpty {
                do {
                    let ankiMediaDir = AnkiProfile.collectionMedia(for: app.selectedProfile)
                    try MediaCopy.copyAll(from: mediaDir, to: ankiMediaDir)
                    await MainActor.run { log.append("✓ Copied media to Anki profile: \(app.selectedProfile)") }
                } catch {
                    await MainActor.run { log.append("✗ Copying to Anki failed: \(error.localizedDescription)") }
                }
            }

            await MainActor.run {
                app.progress.currentStatus = Task.isCancelled ? "Cancelled." : "Done."
                app.isBuilding = false
            }
        }
    }
}
