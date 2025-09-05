import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var app: AppState
    @State private var droppedText: String = ""
    @State private var fileURL: URL?
    @State private var showOpenPanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1) Import Pairs")
                .font(.title2.bold())

            Text("Drop a UTF-8 text file with TAB-separated lines:  <phrase>\\t<translation>")
                .foregroundColor(.secondary)

            DropArea(droppedText: $droppedText, fileURL: $fileURL)
                .frame(height: 140)

            HStack {
                Button("Choose File…") {
                    openFile()
                }
                Spacer()
                Text("Parsed \(app.cards.count) cards")
                    .foregroundColor(.secondary)
            }

            if !app.cards.isEmpty {
                Table(app.cards) {
                    TableColumn("#") { Text("\($0.index)") }.width(40)
                    TableColumn("Phrase") { Text($0.phrase) }
                    TableColumn("Translation") { Text($0.translation) }
                }
                .frame(minHeight: 240)
            }

            if !app.savedLists.isEmpty {
                Text("Saved Lists")
                    .font(.title2.bold())
                    .padding(.top)

                List {
                    ForEach(app.savedLists) { list in
                        HStack {
                            Text(list.name)
                            Text(list.createdAt, style: .date)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Load") {
                                app.cards = Parser.parseTSV(list.content)
                            }
                            Button("Download") {
                                downloadList(list)
                            }
                            Button("Delete") {
                                app.savedLists.removeAll { $0.id == list.id }
                                app.saveLists()
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .onChange(of: droppedText) { newValue in
            if !newValue.isEmpty {
                app.cards = Parser.parseTSV(newValue)

                let listName: String
                if let url = fileURL {
                    listName = url.deletingPathExtension().lastPathComponent
                } else {
                    listName = "Pasted Text"
                }

                let newList = SavedList(name: listName, content: newValue, createdAt: Date())

                if !app.savedLists.contains(where: { $0.content == newList.content }) {
                    app.savedLists.append(newList)
                    app.saveLists()
                }
            }
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.plainText, .commaSeparatedText, .text]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                self.fileURL = url
                if let txt = try? String(contentsOf: url, encoding: .utf8) {
                    droppedText = txt
                }
            }
        }
    }

    func downloadList(_ list: SavedList) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        let safeName = list.name.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = safeName.isEmpty ? "list.txt" : "\(safeName).txt"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                try list.content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSApplication.shared.presentError(error)
            }
        }
    }
}

struct DropArea: View {
    @Binding var droppedText: String
    @Binding var fileURL: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundColor(.secondary)
            .overlay(
                Text("Drop TXT/TSV here")
                    .foregroundColor(.secondary)
            )
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let item = providers.first else { return false }
                _ = item.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    if let txt = try? String(contentsOf: url, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.fileURL = url
                            droppedText = txt
                        }
                    }
                }
                return true
            }
    }
}
