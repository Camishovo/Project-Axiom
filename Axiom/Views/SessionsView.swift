import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var gateway: GatewayManager
    
    var body: some View {
        NavigationStack {
            List {
                // Active sessions
                if !activeSessions.isEmpty {
                    Section("Active") {
                        ForEach(activeSessions) { session in
                            NavigationLink(destination: StreamingChatView(sessionKey: session.sessionKey)) {
                                SessionRow(session: session)
                            }
                        }
                    }
                }
                
                // Inactive sessions
                if !inactiveSessions.isEmpty {
                    Section("Recent") {
                        ForEach(inactiveSessions) { session in
                            NavigationLink(destination: StreamingChatView(sessionKey: session.sessionKey)) {
                                SessionRow(session: session)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .overlay {
                if gateway.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Sessions will appear when your agent is active")
                    )
                }
            }
            .refreshable {
                try? await gateway.listSessions()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: StreamingChatView(sessionKey: nil)) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
    
    private var activeSessions: [SessionInfo] {
        gateway.sessions.filter { $0.isActive }
            .sorted { $0.lastActivity > $1.lastActivity }
    }
    
    private var inactiveSessions: [SessionInfo] {
        gateway.sessions.filter { !$0.isActive }
            .sorted { $0.lastActivity > $1.lastActivity }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: SessionInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Channel badge
                if let channel = session.channel {
                    ChannelBadge(channel: channel)
                }
                
                Text(session.displayName)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // Active indicator
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(session.isActive ? .green : .gray)
            }
            
            // Stats row
            HStack(spacing: 12) {
                Label("\(session.messageCount)", systemImage: "bubble.left")
                Label(session.totalTokens.formatted(), systemImage: "number")
                if session.estimatedCost > 0 {
                    Label(String(format: "$%.2f", session.estimatedCost), systemImage: "dollarsign.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            // Last activity
            Text(session.lastActivity, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Channel Badge

struct ChannelBadge: View {
    let channel: String
    
    var body: some View {
        Text(channel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }
    
    private var badgeColor: Color {
        switch channel.lowercased() {
        case "telegram": return .blue
        case "discord": return .indigo
        case "whatsapp": return .green
        case "webchat": return .orange
        case "signal": return .cyan
        case "slack": return .purple
        default: return .secondary
        }
    }
}
