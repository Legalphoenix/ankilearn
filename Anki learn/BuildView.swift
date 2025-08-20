import SwiftUI

struct BuildView: View {
    @EnvironmentObject var app: AppState
    @State private var log: [String] = []
    @State private var runningTask: Task<Void, Never>?

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

    func startBuild() {
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
            let media = folder.appendingPathComponent("media", isDirectory: true)
            do { try fm.createDirectory(at: media, withIntermediateDirectories: true) } catch {}

            // helper to write a file if missing
            func writeIfAbsent(data: Data, to url: URL) throws {
                if !fm.fileExists(atPath: url.path) {
                    try data.write(to: url)
                }
            }

            for card in app.cards {
                if Task.isCancelled { break }

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
                    let imgURL = media.appendingPathComponent(card.imageFilename)
                    try writeIfAbsent(data: imgData, to: imgURL)
                    await MainActor.run {
                        log.append("✓ Image \(card.index): \(card.imageFilename)")
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
                    let audioURL = media.appendingPathComponent(card.audioFilename)
                    try writeIfAbsent(data: audioData, to: audioURL)
                    await MainActor.run {
                        log.append("✓ Audio \(card.index): \(card.audioFilename)")
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
                try AnkiExporter.writeExport(cards: app.cards, to: folder)
                await MainActor.run { log.append("✓ Wrote deck.tsv") }
            } catch {
                await MainActor.run { log.append("✗ Writing deck.tsv failed: \(error.localizedDescription)") }
            }

            await MainActor.run {
                app.progress.currentStatus = "Done."
                app.isBuilding = false
            }
        }
    }
}
