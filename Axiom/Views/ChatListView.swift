import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var gateway: GatewayManager
    @State private var sessions: [SessionRecord] = []
    
    var body: some View {
        NavigationStack {
            List(sessions, id: \.sessionKey) { session in
                NavigationLink(destination: ChatView(sessionKey: session.sessionKey)) {
                    SessionRow(session: session)
                }
            }
            .navigationTitle("Chats")
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a conversation with your agent")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: ChatView(sessionKey: nil)) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.channel ?? "Main")
                    .font(.headline)
                Spacer()
                Text(session.lastActivity, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Text("\(session.messageCount) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if session.estimatedCost > 0 {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", session.estimatedCost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
