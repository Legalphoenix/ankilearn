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

            var imageNames: [UUID: String] = [:]
            var audioNames: [UUID: String] = [:]

            for card in app.cards {
                if Task.isCancelled { break }

                let idx = String(format: "%04d", card.index)
                let imgName = "\(runId)_\(idx)_img.jpg"
                let sndName = "\(runId)_\(idx)_audio.\(app.audioFormat.rawValue)"

                // --- IMAGE ---
                do {
                    let prompt = PromptBuilder.scenePrompt(globalStyle: app.imageGlobalStyle,
                                                          phrase: card.phrase,
                                                          translation: card.translation)
                    app.progress.currentStatus = "Image \(card.index)/\(app.cards.count)"
                    let imgData = try await client.generateImage(prompt: prompt,
                                                                 size: app.imageSize,
                                                                 quality: app.imageQuality,
                                                                 format: "jpeg")
                    let imgURL = mediaDir.appendingPathComponent(imgName)
                    try imgData.write(to: imgURL)
                    imageNames[card.id] = imgName
                    await MainActor.run {
                        log.append("✓ Image \(card.index): \(imgName)")
                        app.progress.completed += 1
                    }
                } catch {
                    await MainActor.run {
                        log.append("✗ Image \(card.index) failed: \(error.localizedDescription)")
                        app.progress.completed += 1
                        app.progress.failed += 1
                    }
                }

                if Task.isCancelled { break }

                // --- AUDIO (phrase only by default) ---
                do {
                    let phrase = card.phrase
                    app.progress.currentStatus = "Audio \(card.index)/\(app.cards.count)"
                    let audioData = try await client.synthesize(input: phrase,
                                                                voice: app.ttsVoice,
                                                                format: app.audioFormat.rawValue,
                                                                model: "gpt-4o-mini-tts")
                    let audioURL = mediaDir.appendingPathComponent(sndName)
                    try audioData.write(to: audioURL)
                    audioNames[card.id] = sndName
                    await MainActor.run {
                        log.append("✓ Audio \(card.index): \(sndName)")
                        app.progress.completed += 1
                    }
                } catch {
                    await MainActor.run {
                        log.append("✗ Audio \(card.index) failed: \(error.localizedDescription)")
                        app.progress.completed += 1
                        app.progress.failed += 1
                    }
                }
            }

            // write TSV at the end
            do {
                try AnkiExporter.writeExport(cards: app.cards,
                                             imageNames: imageNames,
                                             audioNames: audioNames,
                                             to: folder)
                await MainActor.run { log.append("✓ Wrote deck.tsv") }
            } catch {
                await MainActor.run { log.append("✗ Writing deck.tsv failed: \(error.localizedDescription)") }
            }

            // copy to anki
            if app.copyToAnki, !app.selectedProfile.isEmpty {
                do {
                    let ankiMediaDir = AnkiProfile.collectionMedia(for: app.selectedProfile)
                    try MediaCopy.copyAll(from: mediaDir, to: ankiMediaDir)
                    await MainActor.run { log.append("✓ Copied media to Anki profile: \(app.selectedProfile)") }
                } catch {
                    await MainActor.run { log.append("✗ Copying to Anki failed: \(error.localizedDescription)") }
                }
            }

            await MainActor.run {
                app.progress.currentStatus = "Done."
                app.isBuilding = false
            }
        }
    }
}
