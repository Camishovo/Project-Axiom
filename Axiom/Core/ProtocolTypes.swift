import Foundation

// MARK: - Frame envelope

/// Top-level discriminated union for all WebSocket frames.
enum ProtocolFrame {
    case request(RequestFrame)
    case response(ResponseFrame)
    case event(EventFrame)
}

extension ProtocolFrame: Decodable {
    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type)
        switch type_ {
        case "req":   self = .request(try RequestFrame(from: decoder))
        case "res":   self = .response(try ResponseFrame(from: decoder))
        case "event": self = .event(try EventFrame(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown frame type: \(type_)"
            )
        }
    }
}

// MARK: - Request / Response / Event frames

struct RequestFrame: Codable {
    let type: String        // "req"
    let id: String
    let method: String
    // params deliberately omitted — callers build Codable structs directly
}

struct ResponseFrame: Decodable {
    let type: String        // "res"
    let id: String
    let ok: Bool
    let payload: AnyCodable?
    let error: AnyCodable?
}

struct EventFrame: Decodable {
    let type: String        // "event"
    let event: String
    let payload: AnyCodable?
    let seq: Int?
    let stateVersion: Int?
}

// MARK: - Connect request

struct ConnectRequest: Encodable {
    let type = "req"
    let id: String
    let method = "connect"
    let params: ConnectParams
}

struct ConnectParams: Encodable {
    let minProtocol: Int
    let maxProtocol: Int
    let client: ClientInfo
    let role: String
    let scopes: [String]
    let caps: [String]
    let commands: [String]
    let permissions: [String: String]
    let auth: AuthInfo
    let locale: String
    let userAgent: String
    let device: DeviceInfo
}

struct ClientInfo: Encodable {
    let id: String
    let version: String
    let platform: String
    let mode: String
}

struct AuthInfo: Encodable {
    let token: String
}

struct DeviceInfo: Encodable {
    let id: String
    let publicKey: String
    let signature: String
    let signedAt: Int64
    let nonce: String
}

// MARK: - Hello-ok payload

struct HelloOkPayload: Decodable {
    let type: String        // "hello-ok"
    let `protocol`: Int
    let policy: PolicyInfo?
    let auth: AuthResult?
}

struct PolicyInfo: Decodable {
    let maxMessageLength: Int?
    let rateLimitRpm: Int?
}

struct AuthResult: Decodable {
    let deviceToken: String?
    let expiresAt: Int64?
}

// MARK: - Chat event payloads

struct ChatMessagePayload: Decodable {
    let sessionKey: String
    let role: String
    let content: String
    let id: String
    let timestamp: Double
}

struct ChatTokenPayload: Decodable {
    let sessionKey: String
    let token: String
    let messageId: String
}

struct ChatDonePayload: Decodable {
    let sessionKey: String
    let messageId: String
}

struct SessionsUpdatedPayload: Decodable {
    let sessions: [SessionPayload]
}

struct SessionPayload: Decodable {
    let sessionKey: String
    let channel: String?
    let sender: String?
    let messageCount: Int?
    let lastActivity: Double?
    let totalInputTokens: Int?
    let totalOutputTokens: Int?
    let estimatedCost: Double?
}

struct StatusUpdatePayload: Decodable {
    let uptime: Double?
    let activeModel: String?
    let activeSessions: Int?
    let tokenUsage: TokenUsagePayload?
}

struct TokenUsagePayload: Decodable {
    let input: Int?
    let output: Int?
    let estimatedCost: Double?
}

// MARK: - Challenge event payload

struct ChallengePayload: Decodable {
    let nonce: String
    let ts: Int64
}

// MARK: - AnyCodable (lightweight JSON value box)

/// Wraps arbitrary JSON so optional payload fields don't fail decoding.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)               { value = v; return }
        if let v = try? c.decode(Int.self)                { value = v; return }
        if let v = try? c.decode(Double.self)             { value = v; return }
        if let v = try? c.decode(String.self)             { value = v; return }
        if let v = try? c.decode([String: AnyCodable].self) { value = v; return }
        if let v = try? c.decode([AnyCodable].self)       { value = v; return }
        if c.decodeNil()                                  { value = NSNull(); return }
        throw DecodingError.typeMismatch(
            AnyCodable.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool:                   try c.encode(v)
        case let v as Int:                    try c.encode(v)
        case let v as Double:                 try c.encode(v)
        case let v as String:                 try c.encode(v)
        case let v as [String: AnyCodable]:   try c.encode(v)
        case let v as [AnyCodable]:           try c.encode(v)
        default:                              try c.encodeNil()
        }
    }

    /// Decode the payload into a typed struct.
    func decoded<T: Decodable>(as type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Signature payload builder

/// Builds the canonically sorted JSON string that must be signed for the handshake.
func buildSignaturePayload(
    deviceId: String,
    nonce: String,
    platform: String,
    publicKey: String,
    role: String,
    scopes: [String],
    token: String
) -> String {
    // Keys must be alphabetically sorted
    let dict: [(String, String)] = [
        ("deviceFamily", "mobile"),
        ("deviceId",     deviceId),
        ("nonce",        nonce),
        ("platform",     platform),
        ("publicKey",    publicKey),
        ("role",         role),
        ("scopes",       scopes.isEmpty ? "[]" : "[" + scopes.map { "\"\($0)\"" }.joined(separator: ",") + "]"),
        ("token",        token)
    ]
    let pairs = dict.map { "\"\($0.0)\":\($0.0 == "scopes" ? $0.1 : "\"\($0.1)\"")" }
    return "{" + pairs.joined(separator: ",") + "}"
}
