import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var gateway: GatewayManager
    @AppStorage("requireBiometrics") private var requireBiometrics = false
    @AppStorage("budgetAlertThreshold") private var budgetAlertThreshold = 5.0
    @AppStorage("enablePushNotifications") private var enablePushNotifications = true
    
    var body: some View {
        NavigationStack {
            Form {
                // Gateway
                Section("Gateway") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(gateway.isConnected ? "Connected" : "Disconnected")
                            .foregroundStyle(gateway.isConnected ? .green : .red)
                    }
                    
                    Button("Disconnect", role: .destructive) {
                        gateway.disconnect()
                    }
                    .disabled(!gateway.isConnected)
                }
                
                // Security
                Section("Security") {
                    Toggle("Require Face ID / Touch ID", isOn: $requireBiometrics)
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
                
                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link("GitHub", destination: URL(string: "https://github.com/project-axiom")!)
                    Link("OpenClaw Docs", destination: URL(string: "https://docs.openclaw.ai")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
