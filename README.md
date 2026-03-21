# Project Axiom

**The iOS experience OpenClaw deserves.**

A free, open-source, native SwiftUI companion app for OpenClaw that transforms the iPhone from a dumb terminal into an intelligent command center for your AI agent.

## What Is This?

Project Axiom connects to any OpenClaw Gateway over WebSocket, providing:

- **Native Chat** — Rich SwiftUI chat with streaming responses, markdown, and code highlighting
- **Agent Dashboard** — Status, sessions, cost tracking, and activity monitoring
- **Canvas Rendering** — First-class support for OpenClaw's agent-pushed interactive content
- **Push Notifications** — Your agent can reach you, not just respond
- **Device Capabilities** — Camera, location, voice exposed to your agent via node protocol

## Requirements

- iOS 17.0+
- An OpenClaw Gateway running somewhere (desktop, VPS, etc.)

## Building

```bash
# Clone the repo
git clone https://github.com/[org]/project-axiom.git
cd project-axiom

# Open in Xcode
open Axiom.xcodeproj
# or with SPM:
open Package.swift
```

## Architecture

Axiom operates as a node in the OpenClaw Gateway's WebSocket network with dual connections:

- **Node Connection** (`role: node`) — Registers device capabilities, handles `node.invoke` commands
- **Operator Connection** (`role: operator`) — Chat, session management, configuration RPC

## License

MIT

## Status

🚧 **Phase 0 — Foundation** — Active development
