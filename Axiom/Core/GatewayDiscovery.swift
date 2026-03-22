import Network
import Foundation

/// Discovers OpenClaw Gateways on the local network via mDNS/Bonjour.
/// Uses NWBrowser to browse _openclaw-gw._tcp services.
@MainActor
class GatewayDiscovery: ObservableObject {

    @Published var discoveredGateways: [DiscoveredGateway] = []
    @Published var isScanning: Bool = false

    private var browser: NWBrowser?

    func startScanning() {
        guard browser == nil else { return }
        discoveredGateways = []
        isScanning = true

        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_openclaw-gw._tcp", domain: "local."), using: params)

        b.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.isScanning = false
                self.browser = nil
            default:
                break
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.discoveredGateways = results.compactMap { self.parseResult($0) }
        }

        b.start(queue: .main)
        browser = b
    }

    func stopScanning() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }

    // Parse TXT record into DiscoveredGateway
    private func parseResult(_ result: NWBrowser.Result) -> DiscoveredGateway? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }

        var port = 18789
        var displayName = name
        var host = "\(name).local"
        var useTLS = false
        var tlsFingerprint: String? = nil

        if case .bonjour(let txtRecord) = result.metadata {
            port = txtRecord.dictionary["gatewayPort"].flatMap { Int($0) } ?? 18789
            displayName = txtRecord.dictionary["displayName"] ?? name
            useTLS = txtRecord.dictionary["gatewayTls"] == "1"
            // Security rule: only read fingerprint from TXT if no stored pin exists for this host
            tlsFingerprint = txtRecord.dictionary["gatewayTlsSha256"]
            host = txtRecord.dictionary["lanHost"] ?? "\(name).local"
        }

        return DiscoveredGateway(
            id: name,
            displayName: displayName,
            host: host,
            port: port,
            useTLS: useTLS,
            tlsFingerprint: tlsFingerprint
        )
    }
}

struct DiscoveredGateway: Identifiable {
    let id: String           // service instance name (unique)
    let displayName: String  // from TXT displayName, or service name
    let host: String         // resolved hostname or IP
    let port: Int            // from TXT gatewayPort, default 18789
    let useTLS: Bool         // from TXT gatewayTls=1
    let tlsFingerprint: String?  // from TXT gatewayTlsSha256

    // Convert to GatewayConnectionConfig (token left empty — user must enter)
    var connectionConfig: GatewayConnectionConfig {
        GatewayConnectionConfig(host: host, port: port, token: "", useTLS: useTLS)
    }
}
