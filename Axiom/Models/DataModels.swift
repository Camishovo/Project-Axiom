import Foundation
import SwiftData

// MARK: - Gateway Config (persisted)

@Model
class GatewayConfig {
    var name: String
    var host: String
    var port: Int
    var useTLS: Bool
    var isActive: Bool
    var createdAt: Date
    var lastConnected: Date?
    
    // Token stored in Keychain, not SwiftData
    @Transient var token: String = ""
    
    init(name: String, host: String, port: Int, useTLS: Bool = false) {
        self.name = name
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.isActive = false
        self.createdAt = Date()
    }
    
    var connectionConfig: GatewayConnectionConfig {
        GatewayConnectionConfig(host: host, port: port, token: token, useTLS: useTLS)
    }
}

// MARK: - Chat Message

@Model
class ChatMessage {
    var id: String
    var sessionKey: String
    var role: String // "user", "assistant", "system"
    var content: String
    var timestamp: Date
    var isStreaming: Bool
    var tokenCount: Int?
    
    init(id: String = UUID().uuidString, sessionKey: String, role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.sessionKey = sessionKey
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = false
    }
}

// MARK: - Session Record

@Model
class SessionRecord {
    var sessionKey: String
    var channel: String?
    var sender: String?
    var messageCount: Int
    var lastActivity: Date
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var estimatedCost: Double
    
    init(sessionKey: String, channel: String? = nil, sender: String? = nil) {
        self.sessionKey = sessionKey
        self.channel = channel
        self.sender = sender
        self.messageCount = 0
        self.lastActivity = Date()
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.estimatedCost = 0
    }
}
