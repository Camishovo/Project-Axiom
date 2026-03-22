import Foundation
import Combine

/// Handles real-time token streaming from the Gateway.
/// Accumulates tokens into complete messages and publishes updates.
@MainActor
class StreamingMessageHandler: ObservableObject {
    
    // MARK: - Published State
    
    /// Currently streaming message (nil if no active stream)
    @Published var activeStream: StreamingMessage?
    
    /// All completed messages for the current session
    @Published var messages: [ChatMessage] = []
    
    // MARK: - Private
    
    private var tokenBuffer = ""
    private var streamStartTime: Date?
    private var tokenCount = 0
    
    // MARK: - Stream Lifecycle
    
    /// Begin a new streaming response from the agent
    func beginStream(sessionKey: String, messageId: String? = nil) {
        let id = messageId ?? UUID().uuidString
        tokenBuffer = ""
        tokenCount = 0
        streamStartTime = Date()
        
        activeStream = StreamingMessage(
            id: id,
            sessionKey: sessionKey,
            content: "",
            tokenCount: 0,
            startTime: Date(),
            isComplete: false
        )
    }
    
    /// Append a token chunk to the active stream
    func appendToken(_ token: String) {
        guard activeStream != nil else { return }
        
        tokenBuffer += token
        tokenCount += 1
        
        activeStream?.content = tokenBuffer
        activeStream?.tokenCount = tokenCount
    }
    
    /// Complete the active stream and convert to a permanent message
    func completeStream() {
        guard let stream = activeStream else { return }
        
        let message = ChatMessage(
            id: stream.id,
            sessionKey: stream.sessionKey,
            role: "assistant",
            content: stream.content
        )
        message.tokenCount = stream.tokenCount
        
        messages.append(message)
        activeStream = nil
        tokenBuffer = ""
    }
    
    /// Cancel the active stream (error or user-initiated)
    func cancelStream() {
        // Keep partial content if there is any
        if let stream = activeStream, !stream.content.isEmpty {
            let message = ChatMessage(
                id: stream.id,
                sessionKey: stream.sessionKey,
                role: "assistant",
                content: stream.content + "\n\n⚠️ *Stream interrupted*"
            )
            messages.append(message)
        }
        
        activeStream = nil
        tokenBuffer = ""
    }
    
    // MARK: - WebSocket Message Handling
    
    /// Process an incoming WebSocket message related to streaming
    func handleWebSocketMessage(_ message: WebSocketMessage) {
        guard let method = message.method else { return }
        
        switch method {
        case "chat.stream.start":
            let sessionKey = message.params?["sessionKey"] as? String ?? "unknown"
            let messageId = message.params?["messageId"] as? String
            beginStream(sessionKey: sessionKey, messageId: messageId)
            
        case "chat.stream.token":
            if let token = message.params?["token"] as? String {
                appendToken(token)
            }
            
        case "chat.stream.end":
            completeStream()
            
        case "chat.stream.error":
            cancelStream()
            
        case "chat.message":
            // Non-streamed complete message
            if let content = message.params?["content"] as? String,
               let role = message.params?["role"] as? String,
               let sessionKey = message.params?["sessionKey"] as? String {
                let msg = ChatMessage(
                    id: message.params?["messageId"] as? String ?? UUID().uuidString,
                    sessionKey: sessionKey,
                    role: role,
                    content: content
                )
                messages.append(msg)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Helpers
    
    /// Tokens per second for the active stream
    var tokensPerSecond: Double {
        guard let stream = activeStream,
              let start = streamStartTime else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        return Double(stream.tokenCount) / elapsed
    }
    
    /// Clear all messages (session reset)
    func clearMessages() {
        messages.removeAll()
        activeStream = nil
        tokenBuffer = ""
    }
}

// MARK: - Streaming Message Model

struct StreamingMessage: Identifiable {
    let id: String
    let sessionKey: String
    var content: String
    var tokenCount: Int
    let startTime: Date
    var isComplete: Bool
}
