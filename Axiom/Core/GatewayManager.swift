import Foundation
import Combine
import UIKit

/// Central manager for Gateway WebSocket connections.
/// Maintains dual connections: node (device capabilities) and operator (chat/sessions).
@MainActor
class GatewayManager: ObservableObject {

    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected
    @Published var gatewayStatus: GatewayStatus?
    @Published var error: GatewayError?
    @Published var activeConfig: GatewayConnectionConfig?

    // Chat & session state (event-driven)
    @Published var messages: [String: [ChatMessage]] = [:]        // keyed by sessionKey
    @Published var sessions: [SessionInfo] = []
    @Published var nodes: [NodeInfo] = []
    @Published var activeSessionKey: String?
    @Published var streamingMessages: [String: String] = [:]      // messageId -> accumulated tokens

    var isConnected: Bool {
        connectionState == .connected
    }

    // MARK: - Connections

    private var nodeConnection: WebSocketConnection?
    private var operatorConnection: WebSocketConnection?
    private var reconnectTask: Task<Void, Never>?
    private var statusPollTask: Task<Void, Never>?
    private var config: GatewayConnectionConfig?

    private let deviceIdentity = DeviceIdentity.load()
    private var helloOkReceived = false

    // MARK: - Connect

    func connect(config: GatewayConnectionConfig) async {
        self.config = config
        self.activeConfig = config
        connectionState = .connecting

        do {
            // Create connections
            nodeConnection = WebSocketConnection(
                url: config.webSocketURL(role: .node),
                token: config.token
            )
            operatorConnection = WebSocketConnection(
                url: config.webSocketURL(role: .operator),
                token: config.token
            )

            // Wire message handlers
            nodeConnection?.onMessage = { [weak self] message in
                await self?.handleNodeMessage(message)
            }
            nodeConnection?.onDisconnect = { [weak self] in
                await self?.handleDisconnect()
            }
            operatorConnection?.onMessage = { [weak self] message in
                await self?.handleOperatorMessage(message)
            }
            operatorConnection?.onDisconnect = { [weak self] in
                await self?.handleDisconnect()
            }

            // Open both sockets
            try await nodeConnection?.connect()
            try await operatorConnection?.connect()

            // Concurrently await challenges from both connections
            async let nodeNonce = nodeConnection!.waitForChallenge()
            async let operatorNonce = operatorConnection!.waitForChallenge()
            let (nNode, nOperator) = try await (nodeNonce, operatorNonce)

            // Build and send connect requests
            let nodeReq = buildConnectRequest(role: .node, nonce: nNode, token: config.token)
            let operatorReq = buildConnectRequest(role: .operator, nonce: nOperator, token: config.token)

            try await nodeConnection?.send(encodable: nodeReq)
            try await operatorConnection?.send(encodable: operatorReq)

            // Wait for hello-ok on operator connection
            try await waitForHelloOk(connection: operatorConnection!, timeout: 10)

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
        nodes = []
        gatewayStatus = nil
        activeConfig = nil
    }

    // MARK: - Chat

    func sendMessage(_ text: String, sessionKey: String? = nil) async throws {
        let key = sessionKey ?? activeSessionKey ?? "default"
        let req: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "chat.send",
            "params": [
                "message": text,
                "sessionKey": key
            ]
        ]
        try await operatorConnection?.send(json: req)
    }

    func fetchHistory(sessionKey: String, limit: Int = 50) async throws {
        let req: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "chat.history",
            "params": ["sessionKey": sessionKey, "limit": limit]
        ]
        try await operatorConnection?.send(json: req)
    }

    func listSessions() async throws {
        let req: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "sessions.list",
            "params": [:]
        ]
        try await operatorConnection?.send(json: req)
    }

    // MARK: - Status

    func fetchGatewayStatus() async throws {
        let req: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "gateway.status",
            "params": [:]
        ]
        try await operatorConnection?.send(json: req)
    }

    func fetchNodes() async throws {
        let req: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "nodes.list",
            "params": [:]
        ]
        try await operatorConnection?.send(json: req)
    }

    func startStatusPolling(interval: TimeInterval = 10) {
        statusPollTask?.cancel()
        statusPollTask = Task {
            while !Task.isCancelled && connectionState == .connected {
                try? await fetchGatewayStatus()
                try? await listSessions()
                try? await fetchNodes()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopStatusPolling() {
        statusPollTask?.cancel()
        statusPollTask = nil
    }

    // MARK: - Build connect request

    private func buildConnectRequest(role: ConnectionRole, nonce: String, token: String) -> ConnectRequest {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        let scopes: [String]
        let caps: [String]
        let commands: [String]
        let mode: String

        switch role {
        case .operator:
            scopes   = ["operator.read", "operator.write"]
            caps     = []
            commands = []
            mode     = "operator"
        case .node:
            scopes   = []
            caps     = ["camera", "canvas", "location", "voice"]
            commands = ["camera.snap", "canvas.navigate", "location.get"]
            mode     = "node"
        }

        let signaturePayload = buildSignaturePayload(
            deviceId:  deviceIdentity.id,
            nonce:     nonce,
            platform:  "ios",
            publicKey: deviceIdentity.publicKeyBase64,
            role:      role.rawValue,
            scopes:    scopes,
            token:     token
        )
        let signature = deviceIdentity.sign(payload: signaturePayload) ?? ""

        return ConnectRequest(
            id: UUID().uuidString,
            params: ConnectParams(
                minProtocol: 3,
                maxProtocol: 3,
                client: ClientInfo(id: "axiom-ios", version: "0.1.0", platform: "ios", mode: mode),
                role: role.rawValue,
                scopes: scopes,
                caps: caps,
                commands: commands,
                permissions: [:],
                auth: AuthInfo(token: token),
                locale: Locale.current.identifier,
                userAgent: "axiom-ios/0.1.0",
                device: DeviceInfo(
                    id: deviceIdentity.id,
                    publicKey: deviceIdentity.publicKeyBase64,
                    signature: signature,
                    signedAt: now,
                    nonce: nonce
                )
            )
        )
    }

    // MARK: - Wait for hello-ok

    private func waitForHelloOk(connection: WebSocketConnection, timeout: TimeInterval) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw GatewayError.timeout
            }
            group.addTask { [weak self] in
                guard let self else { return }
                while !self.helloOkReceived {
                    try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Message handlers

    private func handleNodeMessage(_ message: WebSocketMessage) async {
        // Handle node.invoke commands from the agent
    }

    private func handleOperatorMessage(_ message: WebSocketMessage) async {
        guard let type = message.type else { return }

        switch type {
        case "res":
            guard let ok = message.json["ok"] as? Bool, ok else { return }
            let payload = message.payload

            // hello-ok — handshake complete
            if let payloadType = payload?["type"] as? String, payloadType == "hello-ok" {
                helloOkReceived = true
                if let deviceToken = (payload?["auth"] as? [String: Any])?["deviceToken"] as? String {
                    try? KeychainManager.saveToken(deviceToken, for: "device-token")
                }
            } else {
                // Any successful res to our connect request counts as hello-ok
                helloOkReceived = true
            }

            // gateway.status response
            if let p = payload, let _ = p["uptime"] {
                handleGatewayStatusResponse(p)
            }

            // sessions.list response
            if let p = payload, let sessionData = p["sessions"] as? [[String: Any]] {
                handleSessionsListResponse(sessionData)
            }

            // nodes.list response
            if let p = payload, let nodeData = p["nodes"] as? [[String: Any]] {
                handleNodesListResponse(nodeData)
            }

        case "event":
            guard let event = message.event else { return }
            switch event {
            case "chat.message":     handleChatMessage(message)
            case "chat.token":       handleChatToken(message)
            case "chat.done":        handleChatDone(message)
            case "sessions.updated": handleSessionsUpdated(message)
            case "status.update":    handleStatusUpdate(message)
            default: break
            }

        default:
            break
        }
    }

    // MARK: - Response handlers (res frames)

    private func handleGatewayStatusResponse(_ p: [String: Any]) {
        let usage = p["tokenUsage"] as? [String: Any]
        gatewayStatus = GatewayStatus(
            uptime: p["uptime"] as? TimeInterval ?? 0,
            activeModel: p["model"] as? String ?? p["activeModel"] as? String ?? "unknown",
            activeSessions: p["activeSessions"] as? Int ?? 0,
            tokenUsage: TokenUsage(
                input: usage?["input"] as? Int ?? 0,
                output: usage?["output"] as? Int ?? 0,
                estimatedCost: usage?["estimatedCost"] as? Double ?? 0
            )
        )
    }

    private func handleSessionsListResponse(_ sessionData: [[String: Any]]) {
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

    private func handleNodesListResponse(_ nodeData: [[String: Any]]) {
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

    // MARK: - Event handlers (event frames)

    private func handleChatMessage(_ message: WebSocketMessage) {
        guard let p = message.payload,
              let sessionKey = p["sessionKey"] as? String,
              let role       = p["role"] as? String,
              let content    = p["content"] as? String,
              let id         = p["id"] as? String
        else { return }

        let ts = (p["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        let chatMsg = ChatMessage(id: id, sessionKey: sessionKey, role: role, content: content, timestamp: ts)

        var list = messages[sessionKey] ?? []
        if !list.contains(where: { $0.id == id }) {
            list.append(chatMsg)
            list.sort { $0.timestamp < $1.timestamp }
            messages[sessionKey] = list
        }
    }

    private func handleChatToken(_ message: WebSocketMessage) {
        guard let p = message.payload,
              let messageId = p["messageId"] as? String,
              let token     = p["token"] as? String
        else { return }
        streamingMessages[messageId, default: ""] += token
    }

    private func handleChatDone(_ message: WebSocketMessage) {
        guard let p = message.payload,
              let sessionKey = p["sessionKey"] as? String,
              let messageId  = p["messageId"] as? String,
              let accumulated = streamingMessages[messageId]
        else { return }

        streamingMessages.removeValue(forKey: messageId)
        let chatMsg = ChatMessage(
            id: messageId, sessionKey: sessionKey,
            role: "assistant", content: accumulated, timestamp: Date()
        )
        var list = messages[sessionKey] ?? []
        if let idx = list.firstIndex(where: { $0.id == messageId }) {
            list[idx] = chatMsg
        } else {
            list.append(chatMsg)
            list.sort { $0.timestamp < $1.timestamp }
        }
        messages[sessionKey] = list
    }

    private func handleSessionsUpdated(_ message: WebSocketMessage) {
        guard let p = message.payload,
              let rawSessions = p["sessions"] as? [[String: Any]]
        else { return }
        handleSessionsListResponse(rawSessions)
    }

    private func handleStatusUpdate(_ message: WebSocketMessage) {
        guard let p = message.payload else { return }
        handleGatewayStatusResponse(p)
    }

    // MARK: - Reconnect

    private func handleDisconnect() async {
        guard connectionState == .connected else { return }
        connectionState = .reconnecting
        helloOkReceived = false

        reconnectTask = Task {
            var delay: UInt64 = 1_000_000_000
            let maxDelay: UInt64 = 30_000_000_000
            while !Task.isCancelled {
                guard let config = self.config else { return }
                do {
                    try await Task.sleep(nanoseconds: delay)
                    await connect(config: config)
                    if connectionState == .connected { return }
                } catch { return }
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
        case .connectionFailed(let r): return "Connection failed: \(r)"
        case .authenticationFailed:   return "Authentication failed"
        case .protocolError(let m):   return "Protocol error: \(m)"
        case .timeout:                return "Connection timed out"
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
        case "ios":    return "iphone"
        case "macos":  return "laptopcomputer"
        case "android": return "phone"
        default:       return "desktopcomputer"
        }
    }
}
