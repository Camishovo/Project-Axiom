import Foundation

/// Lightweight WebSocket wrapper using URLSessionWebSocketTask.
actor WebSocketConnection {

    private let url: URL
    private let token: String
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isListening = false

    var onMessage: ((WebSocketMessage) async -> Void)?
    var onDisconnect: (() async -> Void)?

    /// Set before calling connect(). Resolved once when connect.challenge arrives.
    private var challengeContinuation: CheckedContinuation<String, Error>?

    init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    func connect() async throws {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true

        session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        task = session?.webSocketTask(with: request)
        task?.resume()

        // Start listening for messages
        isListening = true
        Task { await listenForMessages() }
    }

    func disconnect() {
        isListening = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Handshake support

    /// Waits for the server-initiated connect.challenge event and returns the nonce.
    func waitForChallenge(timeout: TimeInterval = 10) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    // Store continuation — listenForMessages will resolve it
                    Task { await self.storeContinuation(continuation) }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw GatewayError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func storeContinuation(_ continuation: CheckedContinuation<String, Error>) {
        challengeContinuation = continuation
    }

    // MARK: - Send helpers

    func send(json payload: [String: Any]) async throws {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            throw GatewayError.protocolError("Failed to serialize message")
        }
        try await task?.send(.string(string))
    }

    func send(text: String) async throws {
        try await task?.send(.string(text))
    }

    /// Encodes an Encodable value and sends it as JSON text.
    func send<T: Encodable>(encodable: T) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(encodable)
        guard let string = String(data: data, encoding: .utf8) else {
            throw GatewayError.protocolError("Failed to encode message")
        }
        try await task?.send(.string(string))
    }

    // MARK: - Private

    private func listenForMessages() async {
        while isListening {
            do {
                guard let message = try await task?.receive() else { return }

                var text: String
                switch message {
                case .string(let s):
                    text = s
                case .data(let d):
                    text = String(data: d, encoding: .utf8) ?? ""
                @unknown default:
                    continue
                }

                guard let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                // Check for connect.challenge before routing to onMessage
                if json["type"] as? String == "event",
                   json["event"] as? String == "connect.challenge",
                   let payload = json["payload"] as? [String: Any],
                   let nonce = payload["nonce"] as? String {
                    if let continuation = challengeContinuation {
                        challengeContinuation = nil
                        continuation.resume(returning: nonce)
                    }
                    // Also pass to onMessage so it can be logged/observed
                }

                await onMessage?(WebSocketMessage(raw: text, json: json))

            } catch {
                if isListening {
                    // Fail any pending challenge continuation
                    if let continuation = challengeContinuation {
                        challengeContinuation = nil
                        continuation.resume(throwing: error)
                    }
                    await onDisconnect?()
                }
                return
            }
        }
    }
}

// MARK: - Types

struct WebSocketMessage {
    let raw: String
    let json: [String: Any]

    var type: String? { json["type"] as? String }
    var event: String? { json["event"] as? String }

    var method: String? {
        json["method"] as? String
    }

    var params: [String: Any]? {
        json["params"] as? [String: Any]
    }

    var payload: [String: Any]? {
        json["payload"] as? [String: Any]
    }
}

struct GatewayConnectionConfig: Codable {
    let host: String
    let port: Int
    let token: String
    let useTLS: Bool

    var baseURL: String {
        let scheme = useTLS ? "https" : "http"
        return "\(scheme)://\(host):\(port)"
    }

    func webSocketURL(role: ConnectionRole) -> URL {
        let scheme = useTLS ? "wss" : "ws"
        return URL(string: "\(scheme)://\(host):\(port)/ws?role=\(role.rawValue)")!
    }
}

enum ConnectionRole: String {
    case node
    case `operator`
}
