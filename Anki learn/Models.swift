import Foundation

struct Card: Identifiable, Hashable {
    let id: UUID
    var index: Int
    var phrase: String
    var translation: String
}

enum AudioFormat: String, CaseIterable, Identifiable {
    case mp3, wav, opus, aac, flac
    var id: String { rawValue }
}

struct BuildProgress: Identifiable {
    let id = UUID()
    var total: Int = 0
    var completed: Int = 0
    var failed: Int = 0
    var currentStatus: String = ""
}

final class AppState: ObservableObject {
    // cards
    @Published var cards: [Card] = []

    // image global style/system instruction (user-editable)
    @Published var imageGlobalStyle: String =
    """
    Playful, clean illustration, bright colors, single clear focal point, \
    slight exaggeration for memorability, no text or captions, no watermarks.
    """

    // image size/quality
    @Published var imageSize: String = "1024x1024" // also: 1536x1024, 1024x1536
    @Published var imageQuality: String = "medium" // low|medium|high|auto

    // audio
    @Published var ttsVoice: String = "alloy"
    @Published var audioFormat: AudioFormat = .mp3
    @Published var synthesizeBackToo: Bool = false

    // export location
    @Published var exportFolderURL: URL?

    // anki
    @AppStorage("ankiProfile") var selectedProfile: String = ""
    @AppStorage("copyToAnki") var copyToAnki: Bool = true

    // building
    @Published var isBuilding = false
    @Published var progress = BuildProgress()

    // sheets
    @Published var showApiKeySheet = false
    @Published var showSettingsSheet = false

    // per-card overrides (optional future)
    // var overrides: [UUID: String] = [:]
}
