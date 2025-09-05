import Foundation

// MARK: - OpenAI HTTP Client

final class OpenAIClient {
    struct Config {
        var apiKey: String
        var baseURL = URL(string: "https://api.openai.com")!
    }

    private let cfg: Config
    init(cfg: Config) { self.cfg = cfg }

    private func makeRequest(path: String, json: Data) -> URLRequest {
        var req = URLRequest(url: cfg.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = json
        return req
    }

    // MARK: Image Generation (gpt-image-1)
    struct ImageGenBody: Codable {
        let model: String = "gpt-image-1"
        let prompt: String
        let size: String        // "1024x1024" etc.
        let quality: String     // "low"|"medium"|"high"|"auto"
        let output_format: String // "jpeg"|"png"|"webp"
    }
    struct ImageGenResp: Codable {
        struct D: Codable { let b64_json: String }
        let data: [D]
    }

    func generateImage(prompt: String, size: String, quality: String, format: String) async throws -> Data {
        let body = ImageGenBody(prompt: prompt, size: size, quality: quality, output_format: format)
        let req = makeRequest(path: "/v1/images/generations", json: try JSONEncoder().encode(body))
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Self.makeHTTPError(data: data, fallback: "Image generation failed")
        }
        let decoded = try JSONDecoder().decode(ImageGenResp.self, from: data)
        guard let b64 = decoded.data.first?.b64_json, let bin = Data(base64Encoded: b64) else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed image response"])
        }
        return bin
    }

    // MARK: TTS (Audio API)
    struct TTSBody: Codable {
        let model: String       // "gpt-4o-mini-tts" or other
        let voice: String       // "alloy", "ash", ...
        let input: String
        let format: String      // "mp3"|"wav"|"opus"|"aac"|"flac"
        let instructions: String?
    }

    func synthesize(input: String, voice: String, format: String, model: String, instructions: String? = nil) async throws -> Data {
        let body = TTSBody(model: model, voice: voice, input: input, format: format, instructions: instructions)

        var bodyDict: [String: Any] = [
            "model": body.model,
            "voice": body.voice,
            "input": body.input,
            "format": body.format
        ]
        if let instructions = body.instructions, !instructions.isEmpty {
            bodyDict["instructions"] = instructions
        }

        let jsonData = try JSONSerialization.data(withJSONObject: bodyDict)
        let req = makeRequest(path: "/v1/audio/speech", json: jsonData)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Self.makeHTTPError(data: data, fallback: "TTS failed")
        }
        return data // raw audio bytes in chosen format
    }

    private static func makeHTTPError(data: Data, fallback: String) -> NSError {
        let str = String(data: data, encoding: .utf8) ?? ""
        return NSError(domain: "OpenAI", code: -1,
                       userInfo: [NSLocalizedDescriptionKey: "\(fallback): \(str.prefix(500))"])
    }
}

// MARK: - Parsing & Export

enum Parser {
    static func parseTSV(_ text: String) -> [Card] {
        let lines = text.split(whereSeparator: \.isNewline)
        var out: [Card] = []
        for (i, line) in lines.enumerated() {
            let cols = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 2 else { continue }
            let phrase = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(Card(id: UUID(), index: i + 1, phrase: phrase, translation: translation))
        }
        return out
    }
}

enum AnkiExporter {
    /// Writes folder:
    ///   <runId>.tsv
    ///   media/{image,audio files}
    static func writeExport(cards: [Card],
                            imageNames: [UUID: String],
                            audioNames: [UUID: String],
                            mnemonicNames: [UUID: String],
                            to folder: URL,
                            runId: String) throws -> String
    {
        let media = folder.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)

        var rows: [String] = []
        for c in cards {
            let imgName = imageNames[c.id] ?? ""
            let audName = audioNames[c.id] ?? ""
            let mneName = mnemonicNames[c.id] ?? ""

            let imgTag = imgName.isEmpty ? "" : "<img src=\"\(imgName)\">"
            let sndTag = audName.isEmpty ? "" : "[sound:\(audName)]"
            let mneTag = mneName.isEmpty ? "" : "[sound:\(mneName)]"

            rows.append("\(c.phrase)\t\(c.translation)\t\(imgTag)\t\(sndTag)\t\(mneTag)")
        }
        let tsv = rows.joined(separator: "\n")
        let tsvFilename = "\(runId).tsv"
        try tsv.write(to: folder.appendingPathComponent(tsvFilename), atomically: true, encoding: .utf8)
        return tsvFilename
    }
}

// MARK: - Anki Profile & Media Management

enum AnkiProfile {
    static func profilesDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Anki2")
    }

    static func availableProfiles() -> [String] {
        let fm = FileManager.default
        let baseDir = profilesDir()
        do {
            let allItemURLs = try fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])

            let profileDirs = allItemURLs.filter { itemURL in
                // Must be a directory
                guard (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                    return false
                }
                // Must not be addons
                if itemURL.lastPathComponent == "addons21" { return false }

                // Must contain a collection file
                let collectionURL = itemURL.appendingPathComponent("collection.anki2")
                return fm.fileExists(atPath: collectionURL.path)
            }

            return profileDirs.map { $0.lastPathComponent }
        } catch {
            return []
        }
    }

    static func collectionMedia(for profile: String) -> URL {
        profilesDir().appendingPathComponent(profile).appendingPathComponent("collection.media")
    }
}

enum MediaCopy {
    static func copyAll(from srcDir: URL, to dstDir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)
        for item in items {
            let dstURL = dstDir.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: dstURL.path) {
                try fm.removeItem(at: dstURL)
            }
            try fm.copyItem(at: item, to: dstURL)
        }
    }
}

// MARK: - Prompt Assembly

// MARK: - Audio Utilities

enum AudioUtil {
    static func pcm16ToWav(_ pcm: Data, sampleRate: UInt32 = 24_000, channels: UInt16 = 1) -> Data {
        var header = Data()
        let chunkSize: UInt32 = 36 + UInt32(pcm.count)
        let byteRate: UInt32 = sampleRate * UInt32(channels) * 2 // 16-bit = 2 bytes
        let blockAlign: UInt16 = channels * 2
        let bitsPerSample: UInt16 = 16

        header.append("RIFF".data(using: .ascii)!)
        header.append(chunkSize.littleEndianData)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(UInt32(16).littleEndianData)          // PCM fmt chunk size
        header.append(UInt16(1).littleEndianData)           // Audio format = 1 (PCM)
        header.append(channels.littleEndianData)
        header.append(sampleRate.littleEndianData)
        header.append(byteRate.littleEndianData)
        header.append(blockAlign.littleEndianData)
        header.append(bitsPerSample.littleEndianData)
        header.append("data".data(using: .ascii)!)
        header.append(UInt32(pcm.count).littleEndianData)
        return header + pcm
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data { withUnsafeBytes(of: self.littleEndian) { Data($0) } }
}

enum PromptBuilder {
    /// Renders the image prompt template by replacing variables.
    /// Supported tokens: {global_style}, {phrase}, {translation}
    static func renderImagePrompt(template: String, globalStyle: String, phrase: String, translation: String) -> String {
        var out = template
        out = out.replacingOccurrences(of: "{global_style}", with: globalStyle)
        out = out.replacingOccurrences(of: "{phrase}", with: phrase)
        out = out.replacingOccurrences(of: "{translation}", with: translation)
        return out
    }
}
