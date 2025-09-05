import Foundation

final class RealtimeAPIClient: NSObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioData = Data()
    private var continuation: CheckedContinuation<Data, Error>?

    private let apiKey: String
    private var instructions: String = ""
    private var prompt: String = ""

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }

    func generate(instructions: String, prompt: String) async throws -> Data {
        self.instructions = instructions
        self.prompt = prompt
        self.audioData = Data()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")

            let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
            self.webSocketTask = session.webSocketTask(with: request)
            self.receiveMessage() // Start listening before connect
            self.webSocketTask?.resume()
        }
    }

    // MARK: - WebSocket Message Sending

    private func sendSessionUpdate(instructions: String) async throws {
        let message: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "audio": [
                    "output": ["voice": "shimmer", "format": "mp3"]
                ],
                "instructions": instructions
            ]
        ]
        try await sendMessage(dictionary: message)
    }

    private func sendConversationItem(prompt: String) async throws {
        let message: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": "Target: \(prompt)"]
                ]
            ]
        ]
        try await sendMessage(dictionary: message)
    }

    private func sendResponseCreate() async throws {
        let message: [String: Any] = ["type": "response.create"]
        try await sendMessage(dictionary: message)
    }

    private func sendMessage(dictionary: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let message = URLSessionWebSocketTask.Message.string(String(data: data, encoding: .utf8)!)
        try await webSocketTask?.send(message)
    }

    // MARK: - WebSocket Message Receiving

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.continuation?.resume(throwing: error)
                self.closeConnection()
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleStringMessage(text)
                case .data:
                    break
                @unknown default:
                    break
                }
                if self.webSocketTask?.closeCode == .invalid { return }
                self.receiveMessage()
            }
        }
    }

    private func handleStringMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "response.output_audio.delta":
            if let audioChunkB64 = json["data"] as? String,
               let audioChunk = Data(base64Encoded: audioChunkB64) {
                self.audioData.append(audioChunk)
            }
        case "response.completed":
            self.continuation?.resume(returning: self.audioData)
            self.closeConnection()
        case "error":
            let errorMessage = (json["message"] as? String) ?? "Unknown WebSocket error"
            let error = NSError(domain: "RealtimeAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            self.continuation?.resume(throwing: error)
            self.closeConnection()
        default:
            break
        }
    }

    // MARK: - Connection Lifecycle & Delegate

    private func closeConnection() {
        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil
        self.continuation = nil
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task {
            do {
                try await self.sendSessionUpdate(instructions: self.instructions)
                try await self.sendConversationItem(prompt: self.prompt)
                try await self.sendResponseCreate()
            } catch {
                self.continuation?.resume(throwing: error)
                self.closeConnection()
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // Optional: handle closure, maybe resume with an error if unexpected
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
            closeConnection()
        }
    }
}
