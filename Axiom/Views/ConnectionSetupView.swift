import SwiftUI
import AVFoundation

struct ConnectionSetupView: View {
    @EnvironmentObject var gateway: GatewayManager
    @StateObject private var discovery = GatewayDiscovery()
    @State private var showQRScanner = false
    @State private var showManualSetup = false
    @State private var prefillHost = ""
    @State private var prefillPort = "18789"
    @State private var prefillTLS = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Logo
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)

                        Text("Project Axiom")
                            .font(.largeTitle.bold())

                        Text("Connect to your OpenClaw Gateway")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    // QR Code Scanner
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
                    .padding(.horizontal)

                    // Nearby Gateways
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Nearby Gateways")
                                .font(.headline)
                            Spacer()
                            if discovery.isScanning {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }

                        if discovery.discoveredGateways.isEmpty {
                            HStack {
                                if discovery.isScanning {
                                    Text("Scanning...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No gateways found")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(discovery.discoveredGateways) { gw in
                                    Button {
                                        prefillHost = gw.host
                                        prefillPort = "\(gw.port)"
                                        prefillTLS = gw.useTLS
                                        showManualSetup = true
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(gw.displayName)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                Text("\(gw.host):\(gw.port)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if gw.useTLS {
                                                Image(systemName: "lock.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.green)
                                            }
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }

                                    if gw.id != discovery.discoveredGateways.last?.id {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)

                    // Manual Entry
                    Button {
                        prefillHost = ""
                        prefillPort = "18789"
                        prefillTLS = false
                        showManualSetup = true
                    } label: {
                        Label("Manual Setup", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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

                    Spacer(minLength: 32)
                }
            }
            .onAppear { discovery.startScanning() }
            .onDisappear { discovery.stopScanning() }
            .sheet(isPresented: $showQRScanner) {
                QRCodeScannerView { config in
                    showQRScanner = false
                    Task { await gateway.connect(config: config) }
                }
            }
            .sheet(isPresented: $showManualSetup) {
                ManualSetupView(
                    initialHost: prefillHost,
                    initialPort: prefillPort,
                    initialTLS: prefillTLS
                ) { config in
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
    @State private var host: String
    @State private var port: String
    @State private var token = ""
    @State private var useTLS: Bool

    let onConnect: (GatewayConnectionConfig) -> Void

    init(initialHost: String = "", initialPort: String = "18788", initialTLS: Bool = false, onConnect: @escaping (GatewayConnectionConfig) -> Void) {
        _host = State(initialValue: initialHost)
        _port = State(initialValue: initialPort)
        _useTLS = State(initialValue: initialTLS)
        self.onConnect = onConnect
    }

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

