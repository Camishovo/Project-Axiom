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
    @Published var sessions: [SessionInfo] = []
    @Published var nodes: [NodeInfo] = []
    @Published var activeConfig: GatewayConnectionConfig?
    
    var isConnected: Bool {
        connectionState == .connected
    }
    
    // MARK: - Connections
    
    private var nodeConnection: WebSocketConnection?
    private var operatorConnection: WebSocketConnection?
    private var reconnectTask: Task<Void, Never>?
    private var statusPollTask: Task<Void, Never>?
    private var config: GatewayConnectionConfig?
    
    // MARK: - Connect
    
    func connect(config: GatewayConnectionConfig) async {
        self.config = config
        self.activeConfig = config
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
            
            // Start polling for live status
            startStatusPolling()
            
        } catch let err as GatewayError {
            connectionState = .disconnected
            error = err
        } catch {
            connectionState = .disconnected
            self.error = .connectionFailed(error.localizedDescription)
        }
    }
    
    func disconnect() {
        stopStatusPolling()
        reconnectTask?.cancel()
        nodeConnection?.disconnect()
        operatorConnection?.disconnect()
        connectionState = .disconnected
        sessions = []
        gatewayStatus = nil
        activeConfig = nil
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
    
    // MARK: - Status
    
    func fetchGatewayStatus() async throws {
        let payload: [String: Any] = [
            "method": "gateway.status",
            "params": [:]
        ]
        try await operatorConnection?.send(json: payload)
    }
    
    func fetchNodes() async throws {
        let payload: [String: Any] = [
            "method": "nodes.list",
            "params": [:]
        ]
        try await operatorConnection?.send(json: payload)
    }
    
    /// Start polling for live status updates
    func startStatusPolling(interval: TimeInterval = 10) {
        statusPollTask?.cancel()
        statusPollTask = Task {
            while !Task.isCancelled && connectionState == .connected {
                try? await fetchGatewayStatus()
                try? await listSessions()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    func stopStatusPolling() {
        statusPollTask?.cancel()
        statusPollTask = nil
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
        guard let method = message.method else { return }
        let params = message.params ?? [:]
        
        switch method {
        case "gateway.status.response":
            gatewayStatus = GatewayStatus(
                uptime: params["uptime"] as? TimeInterval ?? 0,
                activeModel: params["model"] as? String ?? "unknown",
                activeSessions: params["activeSessions"] as? Int ?? 0,
                tokenUsage: TokenUsage(
                    input: (params["tokenUsage"] as? [String: Any])?["input"] as? Int ?? 0,
                    output: (params["tokenUsage"] as? [String: Any])?["output"] as? Int ?? 0,
                    estimatedCost: (params["tokenUsage"] as? [String: Any])?["estimatedCost"] as? Double ?? 0
                )
            )
            
        case "sessions.list.response":
            if let sessionData = params["sessions"] as? [[String: Any]] {
                sessions = sessionData.map { s in
                    SessionInfo(
                        sessionKey: s["sessionKey"] as? String ?? "",
                        channel: s["channel"] as? String,
                        sender: s["sender"] as? String,
                        messageCount: s["messageCount"] as? Int ?? 0,
                        lastActivity: Date(timeIntervalSince1970: s["lastActivity"] as? TimeInterval ?? 0),
                        inputTokens: s["inputTokens"] as? Int ?? 0,
                        outputTokens: s["outputTokens"] as? Int ?? 0,
                        estimatedCost: s["estimatedCost"] as? Double ?? 0,
                        isActive: s["isActive"] as? Bool ?? false
                    )
                }
            }
            
        case "nodes.list.response":
            if let nodeData = params["nodes"] as? [[String: Any]] {
                nodes = nodeData.map { n in
                    NodeInfo(
                        id: n["id"] as? String ?? "",
                        name: n["name"] as? String ?? "Unknown",
                        platform: n["platform"] as? String ?? "unknown",
                        isConnected: n["connected"] as? Bool ?? false,
                        capabilities: n["capabilities"] as? [String] ?? [],
                        lastSeen: Date(timeIntervalSince1970: n["lastSeen"] as? TimeInterval ?? 0)
                    )
                }
            }
            
        default:
            break
        }
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

struct SessionInfo: Identifiable {
    var id: String { sessionKey }
    let sessionKey: String
    let channel: String?
    let sender: String?
    let messageCount: Int
    let lastActivity: Date
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCost: Double
    let isActive: Bool
    
    var totalTokens: Int { inputTokens + outputTokens }
    var displayName: String { channel ?? sender ?? sessionKey }
}

struct NodeInfo: Identifiable {
    let id: String
    let name: String
    let platform: String
    let isConnected: Bool
    let capabilities: [String]
    let lastSeen: Date
    
    var platformIcon: String {
        switch platform {
        case "ios": return "iphone"
        case "macos": return "laptopcomputer"
        case "android": return "phone"
        default: return "desktopcomputer"
        }
    }
}
