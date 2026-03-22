import SwiftUI

struct ChatView: View {
    @EnvironmentObject var gateway: GatewayManager
    let sessionKey: String?

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private var currentSessionKey: String { sessionKey ?? gateway.activeSessionKey ?? "default" }

    // Messages for this session, sorted by timestamp
    private var messages: [ChatMessage] {
        (gateway.messages[currentSessionKey] ?? [])
            .sorted { $0.timestamp < $1.timestamp }
    }

    // Show typing indicator if there are any streaming tokens for this session
    private var isAgentTyping: Bool {
        let sessionMessages = gateway.messages[currentSessionKey] ?? []
        let messageIds = Set(sessionMessages.map { $0.id })
        return gateway.streamingMessages.keys.contains(where: { messageIds.contains($0) })
            || (!gateway.streamingMessages.isEmpty && messages.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages, id: \.id) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming bubble — show accumulated tokens live
                        ForEach(Array(gateway.streamingMessages.keys.sorted()), id: \.self) { msgId in
                            if let text = gateway.streamingMessages[msgId], !text.isEmpty {
                                StreamingBubble(text: text)
                                    .id("streaming-\(msgId)")
                            }
                        }

                        if isAgentTyping && gateway.streamingMessages.isEmpty {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id ?? "typing", anchor: .bottom)
                    }
                }
                .onChange(of: gateway.streamingMessages.count) { _, _ in
                    withAnimation {
                        if let lastKey = gateway.streamingMessages.keys.sorted().last {
                            proxy.scrollTo("streaming-\(lastKey)", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 12) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || !gateway.isConnected)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(currentSessionKey)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            gateway.activeSessionKey = currentSessionKey
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        // Optimistically insert the user message locally
        let userMsg = ChatMessage(
            sessionKey: currentSessionKey,
            role: "user",
            content: text
        )
        var list = gateway.messages[currentSessionKey] ?? []
        list.append(userMsg)
        gateway.messages[currentSessionKey] = list

        Task {
            try? await gateway.sendMessage(text, sessionKey: currentSessionKey)
        }
    }
}

// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                if message.isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundStyle(.secondary)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(i) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
        .onAppear { animating = true }
    }
}
