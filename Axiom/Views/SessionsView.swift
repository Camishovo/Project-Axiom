import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var gateway: GatewayManager
    @State private var sessions: [SessionRecord] = []
    
    var body: some View {
        NavigationStack {
            List(sessions, id: \.sessionKey) { session in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(session.sessionKey)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        ConnectionBadge(isActive: true)
                    }
                    
                    HStack(spacing: 16) {
                        Label("\(session.messageCount)", systemImage: "bubble.left")
                        Label(String(format: "$%.2f", session.estimatedCost), systemImage: "dollarsign.circle")
                        Label("\(session.totalInputTokens + session.totalOutputTokens)", systemImage: "number")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    Text(session.lastActivity, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Sessions")
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Active Sessions",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Sessions will appear when your agent is active")
                    )
                }
            }
            .refreshable {
                try? await gateway.listSessions()
            }
        }
    }
}

struct ConnectionBadge: View {
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .frame(width: 6, height: 6)
                .foregroundStyle(isActive ? .green : .gray)
            Text(isActive ? "Active" : "Idle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
