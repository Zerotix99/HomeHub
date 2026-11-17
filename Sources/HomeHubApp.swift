import SwiftUI

@main
struct HomeHubApp: App {
    @StateObject private var client = HubClient()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(client)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject var client: HubClient
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                JellyControlView()
                    .tabItem {
                        Label("JellyControl", systemImage: "bolt.circle.fill")
                    }
                    .tag(0)

                DealRadarView()
                    .tabItem {
                        Label("Deal Radar", systemImage: "tag.fill")
                    }
                    .badge(client.dealState?.stats.activeDeals ?? 0)
                    .tag(1)

                SystemView()
                    .tabItem {
                        Label("System", systemImage: "slider.horizontal.3")
                    }
                    .tag(2)
            }
            .tint(.cyan)

            if let toast = client.toastMessage {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.45), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(99)
            }
        }
        .task {
            await client.resolveActiveHost()
            async let j: () = client.refreshJelly()
            async let d: () = client.refreshDealState()
            async let c: () = client.fetchDealConfig()
            async let a: () = client.checkAnisetteHealth()
            _ = await (j, d, c, a)
        }
    }
}
