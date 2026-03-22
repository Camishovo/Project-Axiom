import SwiftUI
import AVFoundation

/// Full QR code scanner using AVFoundation camera.
/// Parses OpenClaw Gateway connection URLs from QR codes.
struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (GatewayConnectionConfig) -> Void
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }
    
    class Coordinator: NSObject, QRScannerDelegate {
        let onScan: (GatewayConnectionConfig) -> Void
        
        init(onScan: @escaping (GatewayConnectionConfig) -> Void) {
            self.onScan = onScan
        }
        
        func didScanQRCode(_ result: String) {
            guard let config = QRCodeParser.parse(result) else { return }
            onScan(config)
        }
    }
}

// MARK: - QR Scanner Delegate

protocol QRScannerDelegate: AnyObject {
    func didScanQRCode(_ result: String)
}

// MARK: - QR Scanner View Controller

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    
    weak var delegate: QRScannerDelegate?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
    
    private func setupCamera() {
        let session = AVCaptureSession()
        captureSession = session
        
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showCameraUnavailable()
            return
        }
        
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]
        
        // Preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
        
        // Add scanning overlay
        addScanOverlay()
        
        // Start capture
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    private func addScanOverlay() {
        let overlay = QRScanOverlay(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay)
    }
    
    private func showCameraUnavailable() {
        let label = UILabel()
        label.text = "Camera not available"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        
        hasScanned = true
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        captureSession?.stopRunning()
        delegate?.didScanQRCode(value)
    }
}

// MARK: - Scan Overlay (crosshair/frame visual)

class QRScanOverlay: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        let scanSize: CGFloat = min(rect.width, rect.height) * 0.65
        let scanRect = CGRect(
            x: (rect.width - scanSize) / 2,
            y: (rect.height - scanSize) / 2,
            width: scanSize,
            height: scanSize
        )
        
        // Dim outside scan area
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fill(rect)
        ctx.clear(scanRect)
        
        // Corner brackets
        let cornerLength: CGFloat = 30
        let lineWidth: CGFloat = 4
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // Top-left
            (CGPoint(x: scanRect.minX, y: scanRect.minY + cornerLength),
             CGPoint(x: scanRect.minX, y: scanRect.minY),
             CGPoint(x: scanRect.minX + cornerLength, y: scanRect.minY)),
            // Top-right
            (CGPoint(x: scanRect.maxX - cornerLength, y: scanRect.minY),
             CGPoint(x: scanRect.maxX, y: scanRect.minY),
             CGPoint(x: scanRect.maxX, y: scanRect.minY + cornerLength)),
            // Bottom-left
            (CGPoint(x: scanRect.minX, y: scanRect.maxY - cornerLength),
             CGPoint(x: scanRect.minX, y: scanRect.maxY),
             CGPoint(x: scanRect.minX + cornerLength, y: scanRect.maxY)),
            // Bottom-right
            (CGPoint(x: scanRect.maxX - cornerLength, y: scanRect.maxY),
             CGPoint(x: scanRect.maxX, y: scanRect.maxY),
             CGPoint(x: scanRect.maxX, y: scanRect.maxY - cornerLength)),
        ]
        
        for (start, corner, end) in corners {
            ctx.move(to: start)
            ctx.addLine(to: corner)
            ctx.addLine(to: end)
            ctx.strokePath()
        }
    }
}

// MARK: - QR Code Parser

/// Parses OpenClaw Gateway connection strings from QR codes.
/// Expected format: openclaw://<host>:<port>?token=<token>&tls=<0|1>
/// Fallback: JSON { "host": "...", "port": 18788, "token": "...", "tls": false }
enum QRCodeParser {
    
    static func parse(_ raw: String) -> GatewayConnectionConfig? {
        // Try URL scheme first
        if let config = parseURL(raw) { return config }
        // Try JSON
        if let config = parseJSON(raw) { return config }
        return nil
    }
    
    private static func parseURL(_ raw: String) -> GatewayConnectionConfig? {
        guard let url = URL(string: raw),
              url.scheme == "openclaw",
              let host = url.host,
              let port = url.port else { return nil }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
        let tls = components?.queryItems?.first(where: { $0.name == "tls" })?.value == "1"
        
        return GatewayConnectionConfig(host: host, port: port, token: token, useTLS: tls)
    }
    
    private static func parseJSON(_ raw: String) -> GatewayConnectionConfig? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = json["host"] as? String,
              let token = json["token"] as? String else { return nil }
        
        let port = json["port"] as? Int ?? 18788
        let tls = json["tls"] as? Bool ?? false
        
        return GatewayConnectionConfig(host: host, port: port, token: token, useTLS: tls)
    }
}
