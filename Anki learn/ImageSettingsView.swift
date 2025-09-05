import SwiftUI

struct ImageSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var testPreviewData: Data?
    @State private var isLoading = false
    @State private var testIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2) Image Settings")
                .font(.title2.bold())

            Text("Global style/system prompt (used in template as {global_style}).")
                .foregroundColor(.secondary)

            TextEditor(text: $app.imageGlobalStyle)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

            Text("Image prompt template (supports {global_style}, {phrase}, {translation}).")
                .foregroundColor(.secondary)

            TextEditor(text: $app.imagePromptTemplate)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

            Text("Mnemonic image template (optional). Supports {mnemonic_text}, {global_style}. If empty, uses the mnemonic text directly.")
                .foregroundColor(.secondary)

            TextEditor(text: $app.mnemonicImagePromptTemplate)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

            HStack {
                Picker("Size", selection: $app.imageSize) {
                    Text("1024×1024").tag("1024x1024")
                    Text("1536×1024").tag("1536x1024")
                    Text("1024×1536").tag("1024x1536")
                }
                Picker("Quality", selection: $app.imageQuality) {
                    Text("low").tag("low")
                    Text("medium").tag("medium")
                    Text("high").tag("high")
                    Text("auto").tag("auto")
                }
                Spacer()
                Button("Test Render") { Task { await testRender() } }
                    .disabled(app.cards.isEmpty || isLoading)
            }

            if let data = testPreviewData, let img = NSImage(data: data) {
                HStack {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 256, height: 256)
                    Spacer()
                }
            }

            Spacer()
        }
        .padding()
    }

    func testRender() async {
        guard !app.cards.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let card = app.cards[min(testIndex, app.cards.count-1)]
        let prompt = PromptBuilder.renderImagePrompt(template: app.imagePromptTemplate,
                                                    globalStyle: app.imageGlobalStyle,
                                                    phrase: card.phrase,
                                                    translation: card.translation)
        do {
            guard let apiKey = Keychain.loadAPIKey() else { throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Set API key (⌘,) first."]) }
            let client = OpenAIClient(cfg: .init(apiKey: apiKey))
            let data = try await client.generateImage(prompt: prompt,
                                                      size: app.imageSize,
                                                      quality: app.imageQuality,
                                                      format: "jpeg")
            await MainActor.run { testPreviewData = data }
        } catch {
            await MainActor.run { testPreviewData = nil }
            NSApplication.shared.presentError(error)
        }
    }
}
