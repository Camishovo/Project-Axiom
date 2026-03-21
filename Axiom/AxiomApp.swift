import SwiftUI
import SwiftData

@main
struct AxiomApp: App {
    @StateObject private var gatewayManager = GatewayManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gatewayManager)
        }
        .modelContainer(for: [
            GatewayConfig.self,
            ChatMessage.self,
            SessionRecord.self
        ])
    }
}
