import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var app: AppState
    @State private var droppedText: String = ""
    @State private var showOpenPanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1) Import Pairs")
                .font(.title2.bold())

            Text("Drop a UTF-8 text file with TAB-separated lines:  <phrase>\\t<translation>")
                .foregroundColor(.secondary)

            DropArea(droppedText: $droppedText)
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

            Spacer()
        }
        .padding()
        .onChange(of: droppedText) { newValue in
            if !newValue.isEmpty {
                app.cards = Parser.parseTSV(newValue)
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
                if let txt = try? String(contentsOf: url, encoding: .utf8) {
                    droppedText = txt
                }
            }
        }
    }
}

struct DropArea: View {
    @Binding var droppedText: String

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
                            droppedText = txt
                        }
                    }
                }
                return true
            }
    }
}
