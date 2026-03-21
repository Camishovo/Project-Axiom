import SwiftUI
import AVFoundation

struct ConnectionSetupView: View {
    @EnvironmentObject var gateway: GatewayManager
    @State private var showQRScanner = false
    @State private var showManualSetup = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Logo
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                
                VStack(spacing: 8) {
                    Text("Project Axiom")
                        .font(.largeTitle.bold())
                    
                    Text("Connect to your OpenClaw Gateway")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Connection options
                VStack(spacing: 16) {
                    Button {
                        showQRScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.tint)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        showManualSetup = true
                    } label: {
                        Label("Manual Setup", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                
                // Connection status
                if case .connecting = gateway.connectionState {
                    ProgressView("Connecting...")
                        .padding()
                }
                
                if let error = gateway.error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
                
                Spacer()
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView { config in
                    showQRScanner = false
                    Task { await gateway.connect(config: config) }
                }
            }
            .sheet(isPresented: $showManualSetup) {
                ManualSetupView { config in
                    showManualSetup = false
                    Task { await gateway.connect(config: config) }
                }
            }
        }
    }
}

// MARK: - Manual Setup

struct ManualSetupView: View {
    @Environment(\.dismiss) var dismiss
    @State private var host = ""
    @State private var port = "18788"
    @State private var token = ""
    @State private var useTLS = false
    
    let onConnect: (GatewayConnectionConfig) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Gateway") {
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                    
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    
                    Toggle("Use TLS", isOn: $useTLS)
                }
                
                Section("Authentication") {
                    SecureField("Token", text: $token)
                }
                
                Section {
                    Button("Connect") {
                        let config = GatewayConnectionConfig(
                            host: host,
                            port: Int(port) ?? 18788,
                            token: token,
                            useTLS: useTLS
                        )
                        onConnect(config)
                    }
                    .disabled(host.isEmpty || token.isEmpty)
                }
            }
            .navigationTitle("Manual Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - QR Scanner (placeholder)

struct QRScannerView: View {
    let onScan: (GatewayConnectionConfig) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                // TODO: AVFoundation camera preview + QR code detection
                Text("QR Scanner")
                    .font(.title2)
                Text("Point camera at Gateway QR code")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
