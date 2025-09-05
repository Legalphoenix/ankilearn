import Foundation

/// Minimal Realtime API WebSocket client for one-shot text→audio mnemonics.
/// Notes:
/// - Uses `gpt-realtime` over WebSocket.
/// - Sends `session.update` to set session type and audio output voice.
/// - Sends `response.create` with instructions + a `Target: <word>` input.
/// - Accumulates `response.audio.delta` chunks (base64) into a single `Data` buffer.
/// - Finishes on `response.done` / `response.audio.done`.
/// Event shapes may evolve; adjust keys if OpenAI updates the API.
final class RealtimeClient {
    struct Config {
        var apiKey: String
        var model: String = "gpt-realtime"
        var baseURL: URL = URL(string: "wss://api.openai.com/v1/realtime")!
    }

    private let cfg: Config
    init(cfg: Config) { self.cfg = cfg }

    enum RealtimeError: Error, LocalizedError {
        case cannotCreateTask
        case serverError(String)
        case noAudio
        case timedOut
        case invalidMessage

        var errorDescription: String? {
            switch self {
            case .cannotCreateTask: return "Cannot create WebSocket task."
            case .serverError(let s): return "Realtime server error: \(s)"
            case .noAudio: return "No audio received from Realtime."
            case .timedOut: return "Realtime request timed out."
            case .invalidMessage: return "Unexpected Realtime message format."
            }
        }
    }

    /// Connects, requests an audio response, gathers audio, then closes.
    func generateMnemonicAudio(instructions: String,
                               targetWord: String,
                               voice: String,
                               logger: ((String) -> Void)? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: "\(cfg.baseURL.absoluteString)?model=\(cfg.model)")!)
        req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
        // Some deployments still expect this beta header; harmless if ignored.
        req.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        // No subprotocol required for native Authorization flows

        let session = URLSession(configuration: .default)
        // Use URLRequest variant so we can attach Authorization headers
        let task = session.webSocketTask(with: req)

        var audioData = Data()
        var isDone = false
        var sessionReady = false
        var userItemCreated = false

        func send(_ dict: [String: Any]) async throws {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            if let text = String(data: data, encoding: .utf8) {
                try await task.send(.string(text))
            } else {
                // Fallback: send binary if encoding fails
                try await task.send(.data(data))
            }
            if let type = dict["type"] as? String {
                logger?("→ send: \(type)")
            } else {
                logger?("→ send: (unknown)")
            }
        }

        var receiveError: Error?

        func receiveLoop() async {
            while !isDone {
                do {
                    let msg = try await task.receive()
                    switch msg {
                    case .data(let data):
                        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            do { try handleEvent(obj) }
                            catch {
                                receiveError = error
                                isDone = true
                                return
                            }
                        }
                    case .string(let str):
                        if let data = str.data(using: String.Encoding.utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            do { try handleEvent(obj) }
                            catch {
                                receiveError = error
                                isDone = true
                                return
                            }
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    // Socket error ends loop
                    receiveError = error
                    logger?("ws error: \(error.localizedDescription)")
                    isDone = true
                    break
                }
            }
        }

        func handleEvent(_ obj: [String: Any]) throws {
            guard let type = obj["type"] as? String else { return }
            logger?("← recv: \(type)")

            if type == "session.created" || type == "session.updated" {
                sessionReady = true
            }
            if type == "conversation.item.created" {
                userItemCreated = true
            }

            // Error handling
            if type == "error" || type == "response.error" {
                let errObj = (obj["error"] as? [String: Any]) ?? [:]
                let msg = errObj["message"] as? String
                    ?? obj["message"] as? String
                    ?? "Unknown error"
                let code = errObj["code"] as? String ?? ""
                if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
                   let text = String(data: data, encoding: .utf8) {
                    logger?("server error payload:\n\(text)")
                }
                if !msg.isEmpty { logger?("server error: \(msg) \(code)") }
                throw RealtimeError.serverError(msg)
            }

            // Gather audio chunks
            if type == "response.audio.delta" {
                if let b64 = obj["delta"] as? String, let chunk = Data(base64Encoded: b64) {
                    audioData.append(chunk)
                    logger?("audio += \(chunk.count) bytes (total \(audioData.count))")
                }
                return
            }

            // Completion signals
            if type == "response.done" || type == "response.audio.done" {
                isDone = true
                return
            }
        }

        // Start socket
        task.resume()
        logger?("ws started: \(cfg.baseURL.absoluteString)?model=\(cfg.model)")

        // Begin receiving immediately so we don't miss session.created
        let receiveTask = Task { await receiveLoop() }

        // 1) Wait for session.created from server
        do {
            var waited = 0
            while !sessionReady && waited < 100 { // ~20s
                try await Task.sleep(nanoseconds: 200_000_000)
                waited += 1
            }
        } catch { /* ignore */ }

        // 2) Configure session (instructions + voice + audio+text modalities)
        try await send([
            "type": "session.update",
            "session": [
                // Realtime expects modalities, and audio must be paired with text
                "modalities": ["audio", "text"],
                // Voice at top level
                "voice": voice,
                "instructions": instructions,
                // Valid streaming output encodings over WS: pcm16 | g711_ulaw | g711_alaw
                "output_audio_format": "pcm16"
            ]
        ])

        // Optionally wait briefly for session.updated ack (non-fatal)
        do {
            var waited = 0
            while !sessionReady && waited < 25 { // additional ~5s
                try await Task.sleep(nanoseconds: 200_000_000)
                waited += 1
            }
        } catch { /* ignore */ }

        // 2) Add user message to the conversation, then request an audio response
        let userText = "Target: \(targetWord)"
        try await send([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": userText]]
            ]
        ])

        // Optionally wait briefly for the ack to avoid racing
        do {
            var waited = 0
            while !userItemCreated && waited < 15 { // ~3s
                try await Task.sleep(nanoseconds: 200_000_000)
                waited += 1
            }
        } catch { /* ignore */ }

        try await send([ "type": "response.create" ])

        // 3) Receive until done or timeout (simple loop)
        let deadline = Date().addingTimeInterval(45)
        while !isDone && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if !isDone {
            receiveError = RealtimeError.timedOut
            isDone = true
            logger?("timeout after 45s")
        }
        _ = await receiveTask.value

        task.cancel(with: URLSessionWebSocketTask.CloseCode.normalClosure, reason: nil)

        if let err = receiveError { throw err }
        guard !audioData.isEmpty else { throw RealtimeError.noAudio }
        return audioData
    }
}
