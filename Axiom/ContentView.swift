import SwiftUI

struct ContentView: View {
    @EnvironmentObject var gateway: GatewayManager
    
    var body: some View {
        Group {
            if gateway.isConnected {
                MainTabView()
            } else {
                ConnectionSetupView()
            }
        }
        .animation(.easeInOut, value: gateway.isConnected)
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    var body: some View {
        TabView {
            ChatListView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
            
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent")
                }
            
            SessionsView()
                .tabItem {
                    Label("Sessions", systemImage: "list.bullet.rectangle")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
