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
    
    // MARK: - Private
    
    private func listenForMessages() async {
        while isListening {
            do {
                guard let message = try await task?.receive() else { return }
                
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        await onMessage?(WebSocketMessage(raw: text, json: json))
                    }
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        await onMessage?(WebSocketMessage(raw: String(data: data, encoding: .utf8) ?? "", json: json))
                    }
                @unknown default:
                    break
                }
            } catch {
                if isListening {
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
    
    var method: String? {
        json["method"] as? String
    }
    
    var params: [String: Any]? {
        json["params"] as? [String: Any]
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
