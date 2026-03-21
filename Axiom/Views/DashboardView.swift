import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var gateway: GatewayManager
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    // Connection Status
                    StatusCard(
                        title: "Gateway",
                        value: gateway.isConnected ? "Connected" : "Offline",
                        icon: "antenna.radiowaves.left.and.right",
                        color: gateway.isConnected ? .green : .red
                    )
                    
                    // Active Model
                    StatusCard(
                        title: "Model",
                        value: gateway.gatewayStatus?.activeModel ?? "—",
                        icon: "cpu",
                        color: .blue
                    )
                    
                    // Sessions
                    StatusCard(
                        title: "Sessions",
                        value: "\(gateway.gatewayStatus?.activeSessions ?? 0)",
                        icon: "list.bullet.rectangle",
                        color: .purple
                    )
                    
                    // Cost
                    StatusCard(
                        title: "Today's Cost",
                        value: String(format: "$%.2f", gateway.gatewayStatus?.tokenUsage.estimatedCost ?? 0),
                        icon: "dollarsign.circle",
                        color: .orange
                    )
                }
                .padding()
                
                // Uptime
                if let status = gateway.gatewayStatus {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Uptime")
                            .font(.headline)
                        Text(formatUptime(status.uptime))
                            .font(.title2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                
                // Token Usage
                if let usage = gateway.gatewayStatus?.tokenUsage {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Token Usage")
                            .font(.headline)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Input")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(usage.input.formatted())")
                                    .font(.title3.monospacedDigit())
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("Output")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(usage.output.formatted())")
                                    .font(.title3.monospacedDigit())
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Dashboard")
        }
    }
    
    private func formatUptime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Status Card

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
