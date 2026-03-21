import Foundation
import Combine

/// Central manager for Gateway WebSocket connections.
/// Maintains dual connections: node (device capabilities) and operator (chat/sessions).
@MainActor
class GatewayManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var gatewayStatus: GatewayStatus?
    @Published var error: GatewayError?
    
    var isConnected: Bool {
        connectionState == .connected
    }
    
    // MARK: - Connections
    
    private var nodeConnection: WebSocketConnection?
    private var operatorConnection: WebSocketConnection?
    private var reconnectTask: Task<Void, Never>?
    private var config: GatewayConnectionConfig?
    
    // MARK: - Connect
    
    func connect(config: GatewayConnectionConfig) async {
        self.config = config
        connectionState = .connecting
        
        do {
            // Establish node connection (device capabilities)
            nodeConnection = WebSocketConnection(
                url: config.webSocketURL(role: .node),
                token: config.token
            )
            nodeConnection?.onMessage = { [weak self] message in
                await self?.handleNodeMessage(message)
            }
            nodeConnection?.onDisconnect = { [weak self] in
                await self?.handleDisconnect()
            }
            try await nodeConnection?.connect()
            
            // Establish operator connection (chat/sessions)
            operatorConnection = WebSocketConnection(
                url: config.webSocketURL(role: .operator),
                token: config.token
            )
            operatorConnection?.onMessage = { [weak self] message in
                await self?.handleOperatorMessage(message)
            }
            try await operatorConnection?.connect()
            
            // Authenticate both connections
            try await authenticate()
            
            // Register device capabilities
            try await registerNodeCapabilities()
            
            connectionState = .connected
            error = nil
            
        } catch let err as GatewayError {
            connectionState = .disconnected
            error = err
        } catch {
            connectionState = .disconnected
            self.error = .connectionFailed(error.localizedDescription)
        }
    }
    
    func disconnect() {
        reconnectTask?.cancel()
        nodeConnection?.disconnect()
        operatorConnection?.disconnect()
        connectionState = .disconnected
    }
    
    // MARK: - Chat
    
    func sendMessage(_ text: String, sessionKey: String? = nil) async throws {
        let payload: [String: Any] = [
            "method": "chat.send",
            "params": [
                "message": text,
                "sessionKey": sessionKey as Any
            ].compactMapValues { $0 }
        ]
        try await operatorConnection?.send(json: payload)
    }
    
    func fetchHistory(sessionKey: String, limit: Int = 50) async throws {
        let payload: [String: Any] = [
            "method": "chat.history",
            "params": [
                "sessionKey": sessionKey,
                "limit": limit
            ]
        ]
        try await operatorConnection?.send(json: payload)
    }
    
    // MARK: - Sessions
    
    func listSessions() async throws {
        let payload: [String: Any] = [
            "method": "sessions.list",
            "params": [:]
        ]
        try await operatorConnection?.send(json: payload)
    }
    
    // MARK: - Private
    
    private func authenticate() async throws {
        // Challenge-response auth handshake
        // Implementation depends on Gateway protocol version
    }
    
    private func registerNodeCapabilities() async throws {
        let capabilities: [String: Any] = [
            "method": "node.describe",
            "params": [
                "name": UIDevice.current.name,
                "platform": "ios",
                "capabilities": [
                    "canvas",
                    "camera",
                    "location",
                    "voice"
                ]
            ]
        ]
        try await nodeConnection?.send(json: capabilities)
    }
    
    private func handleNodeMessage(_ message: WebSocketMessage) async {
        // Handle node.invoke commands from the agent
        // (camera.capture, canvas.navigate, location.get, etc.)
    }
    
    private func handleOperatorMessage(_ message: WebSocketMessage) async {
        // Handle chat messages, session updates, status responses
    }
    
    private func handleDisconnect() async {
        guard connectionState == .connected else { return }
        connectionState = .reconnecting
        
        // Exponential backoff reconnect
        reconnectTask = Task {
            var delay: UInt64 = 1_000_000_000 // 1 second
            let maxDelay: UInt64 = 30_000_000_000 // 30 seconds
            
            while !Task.isCancelled {
                guard let config = self.config else { return }
                
                do {
                    try await Task.sleep(nanoseconds: delay)
                    await connect(config: config)
                    if connectionState == .connected { return }
                } catch {
                    // Task cancelled
                    return
                }
                
                delay = min(delay * 2, maxDelay)
            }
        }
    }
}

// MARK: - Types

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

enum GatewayError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case protocolError(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .authenticationFailed: return "Authentication failed"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .timeout: return "Connection timed out"
        }
    }
}

struct GatewayStatus {
    let uptime: TimeInterval
    let activeModel: String
    let activeSessions: Int
    let tokenUsage: TokenUsage
}

struct TokenUsage {
    let input: Int
    let output: Int
    let estimatedCost: Double
}
