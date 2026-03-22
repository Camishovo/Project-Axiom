# Contributing to Project Axiom

Axiom is an open-source project and we welcome contributions. Here's how to get started.

## Prerequisites

- Xcode 15.2+
- iOS 17.0+ simulator or device
- Swift 5.9+
- A running OpenClaw Gateway (for testing real connections)

## Getting Started

```bash
git clone https://github.com/Camishovo/Project-Axiom.git
cd Project-Axiom
open Axiom.xcodeproj
# or open Package.swift for SPM
```

Select an iOS 17+ simulator and hit Run. The app will launch into the connection setup screen.

## Project Structure

```
Axiom/
├── AxiomApp.swift              # App entry point, SwiftData container
├── ContentView.swift           # Root view with tab navigation
├── Core/
│   ├── GatewayManager.swift    # Central WebSocket connection manager (@MainActor)
│   ├── WebSocketConnection.swift   # URLSessionWebSocketTask wrapper (actor)
│   ├── DeviceIdentity.swift    # Ed25519 keypair, Keychain storage
│   └── KeychainManager.swift   # Generic Keychain helpers
├── Models/
│   └── DataModels.swift        # SwiftData models (GatewayConfig, ChatMessage, SessionRecord)
└── Views/
    ├── ConnectionSetupView.swift   # QR + manual setup
    ├── QRScannerView.swift         # AVFoundation QR scanner
    ├── ChatView.swift              # Main chat interface
    ├── StreamingChatView.swift     # Real-time streaming message display
    ├── DashboardView.swift         # Status overview
    ├── SessionsView.swift          # Session list
    └── SettingsView.swift          # App settings
```

## Architecture

Axiom uses a dual-connection architecture to the OpenClaw Gateway:

- **Node connection** (`role: node`) — Registers device capabilities (camera, canvas, location, voice). Receives `node.invoke` commands from the agent.
- **Operator connection** (`role: operator`) — Chat messages, session management, status updates.

Both connections use the same WebSocket protocol with Ed25519 challenge-response authentication (see `DeviceIdentity.swift`).

`GatewayManager` is the single source of truth for connection state. Views observe it via `@EnvironmentObject`.

## Protocol

OpenClaw Gateway uses a JSON WebSocket protocol. All messages are frames:
- **Request**: `{type:"req", id, method, params}`
- **Response**: `{type:"res", id, ok, payload|error}`
- **Event**: `{type:"event", event, payload}`

The handshake requires:
1. Wait for `connect.challenge` event from server
2. Sign nonce with Ed25519 private key
3. Send `connect` request with signed device identity

Full protocol spec: https://docs.openclaw.ai/gateway/protocol

## Development Guidelines

**No third-party dependencies.** Use only Apple frameworks: SwiftUI, SwiftData, CryptoKit, Network, AVFoundation, Speech.

**`@MainActor` on `GatewayManager`.** All UI-bound state must update on the main actor. Use `await MainActor.run {}` when updating from background tasks.

**`actor` on `WebSocketConnection`.** Protects mutable connection state from data races.

**Gate footer on PRs.** For any PR touching data operations, note whether it requires G2 approval (destructive operations).

## Branches

- `main` — stable, always buildable
- `feat/*` — feature branches, PR into main
- `fix/*` — bug fixes

## Pull Requests

1. Fork or branch from `main`
2. Keep PRs focused — one feature or fix per PR
3. Make sure it builds with no warnings before opening a PR
4. Add a short description of what changed and why

## Testing Against a Real Gateway

You'll need an OpenClaw Gateway running. The fastest way:

```bash
npm install -g openclaw
openclaw gateway start
```

Then scan the QR code shown in the gateway dashboard, or enter the host/port/token manually in the app.

## Questions

Open an issue or join the OpenClaw Discord: https://discord.com/invite/clawd
