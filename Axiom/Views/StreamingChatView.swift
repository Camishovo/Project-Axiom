import SwiftUI

/// Enhanced chat view with real-time token streaming support.
/// Replaces basic ChatView with streaming-aware message rendering.
struct StreamingChatView: View {
    @EnvironmentObject var gateway: GatewayManager
    @StateObject private var streamHandler = StreamingMessageHandler()
    let sessionKey: String?
    
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages + active stream
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Completed messages
                        ForEach(streamHandler.messages, id: \.id) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = message.content
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    
                                    Button {
                                        // Share sheet
                                        shareText(message.content)
                                    } label: {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                }
                        }
                        
                        // Active streaming message
                        if let stream = streamHandler.activeStream {
                            StreamingBubble(stream: stream, tokensPerSecond: streamHandler.tokensPerSecond)
                                .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: streamHandler.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: streamHandler.activeStream?.content) { _, _ in
                    scrollToBottom(proxy)
                }
            }
            
            Divider()
            
            // Input bar
            InputBar(
                text: $inputText,
                isFocused: $isInputFocused,
                isStreaming: streamHandler.activeStream != nil,
                onSend: sendMessage,
                onCancel: { streamHandler.cancelStream() }
            )
        }
        .navigationTitle(sessionKey ?? "New Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if streamHandler.activeStream != nil {
                    StreamingIndicator()
                }
            }
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let message = ChatMessage(
            sessionKey: sessionKey ?? "new",
            role: "user",
            content: text
        )
        streamHandler.messages.append(message)
        inputText = ""
        
        Task {
            try? await gateway.sendMessage(text, sessionKey: sessionKey)
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if streamHandler.activeStream != nil {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastId = streamHandler.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
    
    private func shareText(_ text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            root.present(activity, animated: true)
        }
    }
}

// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let stream: StreamingMessage
    let tokensPerSecond: Double
    
    @State private var cursorVisible = true
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Content with blinking cursor
                HStack(alignment: .bottom, spacing: 0) {
                    Text(stream.content)
                    
                    // Blinking cursor
                    Text("▊")
                        .foregroundStyle(.accentColor)
                        .opacity(cursorVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: cursorVisible)
                        .onAppear { cursorVisible = true }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                
                // Stream stats
                HStack(spacing: 8) {
                    Text("\(stream.tokenCount) tokens")
                    Text("•")
                    Text(String(format: "%.0f tok/s", tokensPerSecond))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            
            Spacer(minLength: 60)
        }
    }
}

// MARK: - Input Bar

struct InputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused(isFocused)
                .disabled(isStreaming)
            
            if isStreaming {
                // Stop button during streaming
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            } else {
                // Send button
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Streaming Indicator (nav bar)

struct StreamingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .frame(width: 8, height: 8)
                .foregroundStyle(.green)
                .scaleEffect(animating ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: animating)
            
            Text("Streaming")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { animating = true }
    }
}
