import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var gateway: GatewayManager
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Cards Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatusCard(
                            title: "Gateway",
                            value: connectionLabel,
                            icon: "antenna.radiowaves.left.and.right",
                            color: connectionColor
                        )
                        
                        StatusCard(
                            title: "Model",
                            value: gateway.gatewayStatus?.activeModel ?? "—",
                            icon: "cpu",
                            color: .blue
                        )
                        
                        StatusCard(
                            title: "Sessions",
                            value: "\(gateway.gatewayStatus?.activeSessions ?? gateway.sessions.count)",
                            icon: "list.bullet.rectangle",
                            color: .purple
                        )
                        
                        StatusCard(
                            title: "Today's Cost",
                            value: costLabel,
                            icon: "dollarsign.circle",
                            color: costColor
                        )
                    }
                    .padding(.horizontal)
                    
                    // Uptime
                    if let status = gateway.gatewayStatus {
                        InfoSection(title: "Uptime") {
                            Text(formatUptime(status.uptime))
                                .font(.system(.title2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Token Usage Breakdown
                    if let usage = gateway.gatewayStatus?.tokenUsage {
                        InfoSection(title: "Token Usage") {
                            HStack {
                                TokenStat(label: "Input", value: usage.input, color: .blue)
                                Spacer()
                                TokenStat(label: "Output", value: usage.output, color: .green)
                                Spacer()
                                TokenStat(label: "Total", value: usage.input + usage.output, color: .primary)
                            }
                        }
                    }
                    
                    // Active Sessions Preview
                    if !gateway.sessions.isEmpty {
                        InfoSection(title: "Active Sessions") {
                            VStack(spacing: 8) {
                                ForEach(gateway.sessions.prefix(5)) { session in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(session.displayName)
                                                .font(.subheadline.weight(.medium))
                                            Text("\(session.messageCount) msgs • \(session.totalTokens.formatted()) tokens")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Circle()
                                            .frame(width: 8, height: 8)
                                            .foregroundStyle(session.isActive ? .green : .gray)
                                    }
                                    .padding(.vertical, 2)
                                    
                                    if session.id != gateway.sessions.prefix(5).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    
                    // Nodes
                    if !gateway.nodes.isEmpty {
                        InfoSection(title: "Paired Nodes") {
                            VStack(spacing: 8) {
                                ForEach(gateway.nodes) { node in
                                    HStack {
                                        Image(systemName: node.platformIcon)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(node.name)
                                                .font(.subheadline.weight(.medium))
                                            Text(node.capabilities.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Circle()
                                            .frame(width: 8, height: 8)
                                            .foregroundStyle(node.isConnected ? .green : .gray)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Dashboard")
            .refreshable {
                try? await gateway.fetchGatewayStatus()
                try? await gateway.listSessions()
                try? await gateway.fetchNodes()
            }
        }
    }
    
    // MARK: - Computed
    
    private var connectionLabel: String {
        switch gateway.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .disconnected: return "Offline"
        }
    }
    
    private var connectionColor: Color {
        switch gateway.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        }
    }
    
    private var costLabel: String {
        let cost = gateway.gatewayStatus?.tokenUsage.estimatedCost ?? 0
        return String(format: "$%.2f", cost)
    }
    
    private var costColor: Color {
        let cost = gateway.gatewayStatus?.tokenUsage.estimatedCost ?? 0
        if cost > 10 { return .red }
        if cost > 5 { return .orange }
        return .green
    }
    
    private func formatUptime(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Components

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct TokenStat: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
