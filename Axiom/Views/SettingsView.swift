import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var gateway: GatewayManager
    @AppStorage("requireBiometrics") private var requireBiometrics = false
    @AppStorage("budgetAlertThreshold") private var budgetAlertThreshold = 5.0
    @AppStorage("enablePushNotifications") private var enablePushNotifications = true
    
    @State private var showDisconnectConfirm = false
    @State private var biometricType: BiometricType = .none
    @State private var biometricError: String?
    
    var body: some View {
        NavigationStack {
            Form {
                // Gateway Connection
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .frame(width: 8, height: 8)
                                .foregroundStyle(gateway.isConnected ? .green : .red)
                            Text(connectionLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if let config = gateway.activeConfig {
                        HStack {
                            Text("Host")
                            Spacer()
                            Text(config.host)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        
                        HStack {
                            Text("Port")
                            Spacer()
                            Text("\(config.port)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("TLS")
                            Spacer()
                            Image(systemName: config.useTLS ? "lock.fill" : "lock.open")
                                .foregroundStyle(config.useTLS ? .green : .orange)
                            Text(config.useTLS ? "Enabled" : "Disabled")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if let status = gateway.gatewayStatus {
                        HStack {
                            Text("Model")
                            Spacer()
                            Text(status.activeModel)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Uptime")
                            Spacer()
                            Text(formatUptime(status.uptime))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button("Disconnect", role: .destructive) {
                        showDisconnectConfirm = true
                    }
                    .disabled(!gateway.isConnected)
                    
                } header: {
                    Text("Gateway")
                } footer: {
                    if let error = gateway.error {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                    }
                }
                
                // Security
                Section {
                    Toggle(isOn: $requireBiometrics) {
                        HStack {
                            Image(systemName: biometricIcon)
                            Text(biometricLabel)
                        }
                    }
                    .onChange(of: requireBiometrics) { _, enabled in
                        if enabled { verifyBiometrics() }
                    }
                    
                    if let error = biometricError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Require authentication to open the app or view sensitive settings.")
                }
                
                // Notifications
                Section("Notifications") {
                    Toggle("Push Notifications", isOn: $enablePushNotifications)
                    
                    HStack {
                        Text("Budget Alert")
                        Spacer()
                        TextField("$", value: $budgetAlertThreshold, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                
                // Nodes
                if !gateway.nodes.isEmpty {
                    Section("Paired Nodes") {
                        ForEach(gateway.nodes) { node in
                            HStack {
                                Image(systemName: node.platformIcon)
                                    .foregroundStyle(.secondary)
                                
                                VStack(alignment: .leading) {
                                    Text(node.name)
                                    Text(node.capabilities.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Circle()
                                    .frame(width: 8, height: 8)
                                    .foregroundStyle(node.isConnected ? .green : .gray)
                            }
                        }
                    }
                }
                
                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("Phase 0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/Camishovo/Project-Axiom")!) {
                        HStack {
                            Text("GitHub")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://docs.openclaw.ai")!) {
                        HStack {
                            Text("OpenClaw Docs")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Disconnect from Gateway?",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    gateway.disconnect()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to reconnect to use the app.")
            }
            .onAppear { detectBiometricType() }
        }
    }
    
    // MARK: - Biometrics
    
    private var biometricIcon: String {
        switch biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock"
        }
    }
    
    private var biometricLabel: String {
        switch biometricType {
        case .faceID: return "Require Face ID"
        case .touchID: return "Require Touch ID"
        case .none: return "Biometric Auth"
        }
    }
    
    private func detectBiometricType() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID: biometricType = .faceID
            case .touchID: biometricType = .touchID
            default: biometricType = .none
            }
        } else {
            biometricType = .none
        }
    }
    
    private func verifyBiometrics() {
        let context = LAContext()
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Verify to enable biometric lock"
        ) { success, error in
            DispatchQueue.main.async {
                if !success {
                    requireBiometrics = false
                    biometricError = error?.localizedDescription ?? "Biometric verification failed"
                } else {
                    biometricError = nil
                }
            }
        }
    }
    
    private var connectionLabel: String {
        switch gateway.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .disconnected: return "Disconnected"
        }
    }
    
    private func formatUptime(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        return "\(hours)h \(minutes)m"
    }
}

enum BiometricType {
    case faceID, touchID, none
}
