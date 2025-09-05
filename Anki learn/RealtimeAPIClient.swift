import Foundation

final class RealtimeAPIClient: NSObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioData = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var logHandler: ((String) -> Void)?

    private let apiKey: String
    private var instructions: String = ""
    private var prompt: String = ""

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }

    func generate(instructions: String, prompt: String, logHandler: @escaping (String) -> Void) async throws -> Data {
        self.instructions = instructions
        self.prompt = prompt
        self.audioData = Data()
        self.logHandler = logHandler

        log("Initializing connection...")
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

    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.logHandler?(message)
        }
    }

    // MARK: - WebSocket Message Sending

    private func sendSessionUpdate() async throws {
        log("Sending session.update...")
        let message: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "audio": [
                    "output": ["voice": "shimmer", "format": "mp3"]
                ]
            ]
        ]
        try await sendMessage(dictionary: message)
    }

    private func sendConversationItem(instructions: String, prompt: String) async throws {
        log("Sending conversation.item.create...")
        let fullPrompt = "\(instructions)\n\nTarget: \(prompt)"
        let message: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": fullPrompt]
                ]
            ]
        ]
        try await sendMessage(dictionary: message)
    }

    private func sendResponseCreate() async throws {
        log("Sending response.create...")
        let message: [String: Any] = ["type": "response.create"]
        try await sendMessage(dictionary: message)
    }

    private func sendConversation() {
        Task {
            do {
                try await self.sendConversationItem(instructions: self.instructions, prompt: self.prompt)
                try await self.sendResponseCreate()
            } catch {
                log("Failed to send conversation messages: \(error.localizedDescription)")
                self.continuation?.resume(throwing: error)
                self.closeConnection()
            }
        }
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
                self.log("Receive failed with error: \(error.localizedDescription)")
                self.continuation?.resume(throwing: error)
                self.closeConnection()
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleStringMessage(text)
                case .data:
                    self.log("Received unexpected binary data.")
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
        log("Received message: \(text)")
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            log("Failed to parse received message.")
            return
        }

        switch type {
        case "session.created":
            log("Session created. Sending conversation...")
            sendConversation()
        case "response.output_audio.delta":
            if let audioChunkB64 = json["data"] as? String,
               let audioChunk = Data(base64Encoded: audioChunkB64) {
                self.audioData.append(audioChunk)
            }
        case "response.completed":
            log("Response completed.")
            self.continuation?.resume(returning: self.audioData)
            self.closeConnection()
        case "error":
            let errorMessage = (json["message"] as? String) ?? "Unknown WebSocket error"
            log("Received server error: \(errorMessage)")
            let error = NSError(domain: "RealtimeAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            self.continuation?.resume(throwing: error)
            self.closeConnection()
        default:
            break
        }
    }

    // MARK: - Connection Lifecycle & Delegate

    private func closeConnection() {
        log("Closing connection.")
        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil
        self.continuation = nil
        self.logHandler = nil
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        log("Connection opened. Sending configuration...")
        Task {
            do {
                try await self.sendSessionUpdate()
            } catch {
                log("Failed to send session.update: \(error.localizedDescription)")
                self.continuation?.resume(throwing: error)
                self.closeConnection()
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "No reason provided"
        log("Connection closed unexpectedly. Code: \(closeCode.rawValue), Reason: \(reasonString)")
        if continuation != nil {
            let error = NSError(
                domain: "RealtimeAPIClient",
                code: Int(closeCode.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "WebSocket closed unexpectedly. Code: \(closeCode.rawValue), Reason: \(reasonString)"]
            )
            continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            log("Task failed with error: \(error.localizedDescription)")
            continuation?.resume(throwing: error)
            closeConnection()
        }
    }
}
