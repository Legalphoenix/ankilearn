import SwiftUI

struct Card: Identifiable, Hashable {
    let id: UUID
    var index: Int
    var phrase: String
    var translation: String
}

struct SavedList: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var content: String
    var createdAt: Date
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
    @Published var savedLists: [SavedList] = []

    // image global style/system instruction (user-editable)
    @Published var imageGlobalStyle: String =
    """
    Playful, clean illustration, bright colors, single clear focal point, \
    slight exaggeration for memorability, no text or captions, no watermarks.
    """
    {
        didSet { UserDefaults.standard.set(imageGlobalStyle, forKey: imageGlobalStyleKey) }
    }

    // image prompt template (user-editable). Supports variables:
    // {global_style}, {phrase}, {translation}
    @Published var imagePromptTemplate: String =
    """
    {global_style}
    Phrase: "{phrase}" (used to mean: "{translation}").
    Create a memorable illustrative scene that makes this phrase easy to recall.
    Keep a single clear focal point; no text or captions; no watermarks.
    """
    {
        didSet { UserDefaults.standard.set(imagePromptTemplate, forKey: imagePromptTemplateKey) }
    }

    // audio global style/system instruction (user-editable)
    @Published var audioGlobalStyle: String = """
    Language: French
    Accent/Affect: Warm, refined, and gently instructive, reminiscent of a friendly language instructor.
    Tone: Calm, encouraging, and articulate.
    Pacing: Slow and deliberate.
    Emotion: Cheerful, supportive, and pleasantly enthusiastic.
    Pronunciation: Clearly articulate terminology with gentle emphasis.
    Personality Affect: Friendly and approachable with a hint of sophistication; speak confidently and reassuringly.
    """

    // image size/quality
    @Published var imageSize: String = "1024x1024" // also: 1536x1024, 1024x1536
    @Published var imageQuality: String = "medium" // low|medium|high|auto

    // audio
    @Published var ttsVoice: String = "alloy"
    @Published var audioTestText: String = "Bonjour, faisons un test de voix."
    @Published var audioFormat: AudioFormat = .mp3
    @Published var synthesizeBackToo: Bool = false

    // mnemonics (Realtime)
    @Published var includeMnemonics: Bool = false
    @Published var mnemonicInstructions: String = """
    You are a mnemonic creating agent. Your only role is to respond by creating a mnemonic that the user can use to aid in their recall of the target word. The target word has been provided to you.
    """ {
        didSet {
            UserDefaults.standard.set(mnemonicInstructions, forKey: mnemonicInstructionsKey)
        }
    }
    @Published var mnemonicPrompt: String = ""
    @Published var realtimeModel: String = "gpt-realtime"

    // export location
    @Published var exportFolderURL: URL?

    // anki
    @AppStorage("ankiProfile") var selectedProfile: String = ""
    @AppStorage("copyToAnki") var copyToAnki: Bool = true

    // building
    @Published var includeImages: Bool = true
    @Published var includeAudio: Bool = true
    @Published var isBuilding = false
    @Published var progress = BuildProgress()

    // sheets
    @Published var showApiKeySheet = false
    @Published var showSettingsSheet = false

    // per-card overrides (optional future)
    // var overrides: [UUID: String] = [:]

    private let savedListsKey = "savedLists"
    private let imageGlobalStyleKey = "imageGlobalStyle"
    private let imagePromptTemplateKey = "imagePromptTemplate"
    private let mnemonicInstructionsKey = "mnemonicInstructions"

    func saveLists() {
        do {
            let data = try JSONEncoder().encode(savedLists)
            UserDefaults.standard.set(data, forKey: savedListsKey)
        } catch {
            print("Error saving lists: \(error)")
        }
    }

    func loadSavedLists() {
        guard let data = UserDefaults.standard.data(forKey: savedListsKey) else { return }
        do {
            savedLists = try JSONDecoder().decode([SavedList].self, from: data)
        } catch {
            print("Error loading lists: \(error)")
        }
    }

    init() {
        // Load persisted mnemonic instructions if present
        if let saved = UserDefaults.standard.string(forKey: mnemonicInstructionsKey), !saved.isEmpty {
            self.mnemonicInstructions = saved
        }
        if let saved = UserDefaults.standard.string(forKey: imageGlobalStyleKey), !saved.isEmpty {
            self.imageGlobalStyle = saved
        }
        if let saved = UserDefaults.standard.string(forKey: imagePromptTemplateKey), !saved.isEmpty {
            self.imagePromptTemplate = saved
        }
    }
}
